#include "MeshRenderer.h"
#include "ReferenceRenderer.h"

#include <opencv2/imgcodecs.hpp>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

struct View {
    const char *name;
    double x;
    double y;
};

const std::vector<View> views{
    {"left", -1.0, 0.0},
    {"center", 0.0, 0.0},
    {"right", 1.0, 0.0},
    {"top-left", -1.0, -1.0},
    {"bottom-right", 1.0, 1.0},
};

void requireWrite(const fs::path &path, const cv::Mat &image)
{
    if (image.empty() || !cv::imwrite(path.string(), image))
        throw std::runtime_error("failed to write " + path.string());
}

cv::Mat readImage(const fs::path &path, int mode)
{
    cv::Mat image = cv::imread(path.string(), mode);
    if (image.empty())
        throw std::runtime_error("failed to read " + path.string());
    return image;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 7) {
        std::cerr << "usage: depth-mesh-poc IMAGE DEPTH16 OUTPUT_DIR "
                     "[BACKGROUND MATTE INFLUENCE]\n";
        return 2;
    }
    try {
        const fs::path imagePath = argv[1];
        const cv::Mat image = readImage(imagePath, cv::IMREAD_COLOR);
        const cv::Mat depth = readImage(argv[2], cv::IMREAD_UNCHANGED);
        if (depth.type() != CV_16UC1 || image.size() != depth.size())
            throw std::runtime_error("expected matching image and 16-bit depth map");

        const bool hasLayers = argc == 7;
        cv::Mat background, matte, influence;
        if (hasLayers) {
            background = readImage(argv[4], cv::IMREAD_COLOR);
            matte = readImage(argv[5], cv::IMREAD_GRAYSCALE);
            influence = readImage(argv[6], cv::IMREAD_GRAYSCALE);
            if (background.size() != matte.size()
                || background.size() != influence.size())
                throw std::runtime_error("layer assets must match each other");
        }

        const fs::path outputDirectory = argv[3];
        fs::create_directories(outputDirectory);
        std::ofstream metrics(outputDirectory / "metrics.csv");
        metrics << "view,renderer,milliseconds,mesh_coverage_percent\n";
        metrics << std::fixed << std::setprecision(2);
        DepthMeshPoc::MeshRenderer meshRenderer;
        for (const auto &view : views) {
            const auto baselineStart = std::chrono::steady_clock::now();
            const cv::Mat baseline = hasLayers
                ? DepthMeshPoc::renderLayeredShaderReference(
                      image, background, matte, influence, view.x, view.y, false)
                : DepthMeshPoc::renderDepthShaderReference(
                      image, depth, view.x, view.y);
            const auto baselineTime = std::chrono::duration_cast<
                std::chrono::microseconds>(std::chrono::steady_clock::now()
                                           - baselineStart);
            requireWrite(outputDirectory / (std::string("baseline-")
                                              + view.name + ".jpg"), baseline);
            metrics << view.name << ",current-reference," << baselineTime.count() / 1000.0
                    << ",100.00\n";

            if (hasLayers) {
                const cv::Mat stableForeground =
                    DepthMeshPoc::renderLayeredShaderReference(
                        image, background, matte, influence,
                        view.x, view.y, true);
                requireWrite(outputDirectory / (std::string("stable-")
                    + view.name + ".jpg"), stableForeground);
                metrics << view.name << ",stable-foreground-reference,"
                        << baselineTime.count() / 1000.0 << ",100.00\n";
            }

            const auto mesh = meshRenderer.render(image, depth, view.x, view.y);
            if (mesh.frame.empty())
                throw std::runtime_error("mesh renderer returned an empty frame");
            requireWrite(outputDirectory / (std::string("mesh-")
                                              + view.name + ".jpg"), mesh.frame);
            const double coverage = 100.0 * mesh.filledPixels
                / (mesh.frame.cols * mesh.frame.rows);
            metrics << view.name << ",depth-mesh," << mesh.elapsed.count() / 1000.0
                    << "," << coverage << "\n";
            std::cout << view.name << ": reference=" << baselineTime.count() / 1000.0
                      << " ms, mesh=" << mesh.elapsed.count() / 1000.0
                      << " ms, coverage=" << coverage << "%\n";
        }
        std::cout << "wrote offline comparison to " << outputDirectory << '\n';
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "depth mesh preview failed: " << error.what() << '\n';
        return 1;
    }
}
