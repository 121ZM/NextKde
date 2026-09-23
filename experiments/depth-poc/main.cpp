#include <onnxruntime_cxx_api.h>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <openssl/evp.h>

#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static constexpr const char *modelSha256 =
    "46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f";
static constexpr const char *contractVersion = "da2-vits-dynamic-aspect518-rgb-imagenet-cubic-uint16-v1";

static std::string toHex(const unsigned char *digest, unsigned int length)
{
    std::ostringstream out;
    for (unsigned int i = 0; i < length; ++i)
        out << std::hex << std::setfill('0') << std::setw(2) << static_cast<int>(digest[i]);
    return out.str();
}

static std::string sha256(const fs::path &path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file)
        throw std::runtime_error("cannot open for hashing: " + path.string());
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx || EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("cannot initialize SHA256");
    std::array<char, 1024 * 1024> buffer{};
    while (file) {
        file.read(buffer.data(), buffer.size());
        if (EVP_DigestUpdate(ctx, buffer.data(), static_cast<size_t>(file.gcount())) != 1) {
            EVP_MD_CTX_free(ctx);
            throw std::runtime_error("SHA256 update failed");
        }
    }
    if (!file.eof()) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("failed reading: " + path.string());
    }
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int length = 0;
    if (EVP_DigestFinal_ex(ctx, digest, &length) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("SHA256 finalization failed");
    }
    EVP_MD_CTX_free(ctx);
    return toHex(digest, length);
}

static std::string sha256(const std::string &data)
{
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int length = 0;
    if (EVP_Digest(data.data(), data.size(), digest, &length, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("SHA256 failed");
    return toHex(digest, length);
}

static cv::Size modelSize(const cv::Size &source)
{
    const double scale = std::max(518.0 / source.width, 518.0 / source.height);
    const auto multipleOf14 = [](double value) {
        return std::max(518, static_cast<int>(std::lround(value / 14.0)) * 14);
    };
    return {multipleOf14(source.width * scale), multipleOf14(source.height * scale)};
}

static std::vector<float> preprocess(const cv::Mat &bgr, const cv::Size &target)
{
    cv::Mat rgb, resized, floating;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    cv::resize(rgb, resized, target, 0, 0, cv::INTER_CUBIC);
    resized.convertTo(floating, CV_32FC3, 1.0 / 255.0);

    constexpr float mean[] = {0.485f, 0.456f, 0.406f};
    constexpr float stddev[] = {0.229f, 0.224f, 0.225f};
    const auto planeSize = target.width * target.height;
    std::vector<float> tensor(3 * planeSize);
    for (int y = 0; y < target.height; ++y) {
        const auto *row = floating.ptr<cv::Vec3f>(y);
        for (int x = 0; x < target.width; ++x)
            for (int c = 0; c < 3; ++c)
                tensor[c * planeSize + y * target.width + x] = (row[x][c] - mean[c]) / stddev[c];
    }
    return tensor;
}

static cv::Mat infer(const fs::path &model, const cv::Mat &image)
{
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "depth-poc");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(4);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    Ort::Session session(env, model.c_str(), options);
    if (session.GetInputCount() != 1 || session.GetOutputCount() != 1)
        throw std::runtime_error("unexpected model input/output count");

    const auto inputType = session.GetInputTypeInfo(0);
    const auto inputInfo = inputType.GetTensorTypeAndShapeInfo();
    const auto inputShape = inputInfo.GetShape();
    if (inputInfo.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        inputShape != std::vector<int64_t>{-1, 3, -1, -1}) {
        std::ostringstream detail;
        detail << "model input does not match pinned contract: type="
               << inputInfo.GetElementType() << " shape=";
        for (auto dimension : inputShape)
            detail << dimension << ',';
        throw std::runtime_error(detail.str());
    }

    const auto target = modelSize(image.size());
    auto pixels = preprocess(image, target);
    const std::array<int64_t, 4> shape{1, 3, target.height, target.width};
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input = Ort::Value::CreateTensor<float>(memory, pixels.data(), pixels.size(),
                                                  shape.data(), shape.size());
    auto inputName = session.GetInputNameAllocated(0, Ort::AllocatorWithDefaultOptions{});
    auto outputName = session.GetOutputNameAllocated(0, Ort::AllocatorWithDefaultOptions{});
    const char *inputNames[] = {inputName.get()};
    const char *outputNames[] = {outputName.get()};
    auto outputs = session.Run(Ort::RunOptions{nullptr}, inputNames, &input, 1, outputNames, 1);
    const auto outputInfo = outputs[0].GetTensorTypeAndShapeInfo();
    if (outputInfo.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        outputInfo.GetShape() != std::vector<int64_t>{1, target.height, target.width})
        throw std::runtime_error("model output does not match pinned contract");

    cv::Mat raw(target.height, target.width, CV_32FC1, outputs[0].GetTensorMutableData<float>());
    cv::Mat enlarged;
    cv::resize(raw, enlarged, image.size(), 0, 0, cv::INTER_CUBIC);
    cv::Mat depth(image.size(), CV_16UC1);
    double minValue = std::numeric_limits<double>::infinity();
    double maxValue = -std::numeric_limits<double>::infinity();
    for (int y = 0; y < enlarged.rows; ++y) {
        const float *row = enlarged.ptr<float>(y);
        for (int x = 0; x < enlarged.cols; ++x) {
            if (!std::isfinite(row[x]))
                throw std::runtime_error("model produced non-finite depth");
            minValue = std::min(minValue, static_cast<double>(row[x]));
            maxValue = std::max(maxValue, static_cast<double>(row[x]));
        }
    }
    if (maxValue <= minValue)
        throw std::runtime_error("model produced constant depth");
    for (int y = 0; y < enlarged.rows; ++y) {
        const float *src = enlarged.ptr<float>(y);
        auto *dst = depth.ptr<uint16_t>(y);
        for (int x = 0; x < enlarged.cols; ++x) {
            const double normalized = (src[x] - minValue) / (maxValue - minValue);
            dst[x] = static_cast<uint16_t>(std::lround(normalized * 65535.0));
        }
    }
    std::cerr << "raw depth range after resize: " << minValue << " .. " << maxValue << '\n';
    return depth;
}

int main(int argc, char **argv)
{
    try {
        if (argc != 4)
            throw std::runtime_error("usage: depth-poc MODEL.onnx IMAGE CACHE_DIR");
        const fs::path model(argv[1]), imagePath(argv[2]), cacheRoot(argv[3]);
        if (sha256(model) != modelSha256)
            throw std::runtime_error("model SHA256 mismatch");
        const auto sourceHash = sha256(imagePath);
        const auto key = sha256(sourceHash + modelSha256 + contractVersion);
        const auto outputDir = cacheRoot / key;
        const auto outputPath = outputDir / "depth.png";
        if (fs::exists(outputPath)) {
            const cv::Mat cached = cv::imread(outputPath.string(), cv::IMREAD_UNCHANGED);
            if (!cached.empty() && cached.type() == CV_16UC1) {
                std::cout << "cache hit: " << outputPath << '\n';
                return 0;
            }
        }
        const cv::Mat image = cv::imread(imagePath.string(), cv::IMREAD_COLOR);
        if (image.empty())
            throw std::runtime_error("image is missing or unreadable");
        const cv::Mat depth = infer(model, image);
        fs::create_directories(outputDir);
        const auto tempPath = outputDir / "depth.tmp.png";
        if (!cv::imwrite(tempPath.string(), depth))
            throw std::runtime_error("failed to write depth PNG");
        fs::rename(tempPath, outputPath);
        std::ofstream metadata(outputDir / "metadata.json");
        metadata << "{\n  \"version\": 1,\n  \"model_sha256\": \"" << modelSha256
                 << "\",\n  \"contract\": \"" << contractVersion
                 << "\",\n  \"source_sha256\": \"" << sourceHash
                 << "\",\n  \"width\": " << image.cols
                 << ",\n  \"height\": " << image.rows << "\n}\n";
        std::cout << "generated: " << outputPath << " (" << image.cols << 'x'
                  << image.rows << ", 16-bit grayscale)\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "depth-poc: " << error.what() << '\n';
        return 1;
    }
}
