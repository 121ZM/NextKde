#include "ReferenceRenderer.h"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <chrono>
#include <algorithm>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

cv::Mat readImage(const fs::path &path, int mode)
{
    cv::Mat image = cv::imread(path.string(), mode);
    if (image.empty())
        throw std::runtime_error("failed to read " + path.string());
    return image;
}

void drawHeader(cv::Mat &frame, const std::string &title, int x)
{
    cv::putText(frame, title, {x + 18, 34}, cv::FONT_HERSHEY_SIMPLEX,
                0.65, cv::Scalar(255, 255, 255), 1, cv::LINE_AA);
}

int main(int argc, char **argv)
{
    if (argc != 6) {
        std::cerr << "usage: depth-orbit-compare IMAGE BACKGROUND MATTE INFLUENCE OUTPUT_DIR\n";
        return 2;
    }
    try {
        const cv::Mat image = readImage(argv[1], cv::IMREAD_COLOR);
        const cv::Mat background = readImage(argv[2], cv::IMREAD_COLOR);
        const cv::Mat matte = readImage(argv[3], cv::IMREAD_GRAYSCALE);
        const cv::Mat influence = readImage(argv[4], cv::IMREAD_GRAYSCALE);
        if (background.size() != matte.size() || background.size() != influence.size())
            throw std::runtime_error("layer assets must match each other");
        const fs::path outputDirectory = argv[5];
        fs::create_directories(outputDirectory);

        constexpr int sweepSteps = 22;
        std::vector<double> sweep;
        for (int i = 0; i < sweepSteps; ++i)
            sweep.push_back(-1.0 + 2.0 * i / (sweepSteps - 1));
        for (int i = sweepSteps - 2; i >= 1; --i)
            sweep.push_back(-1.0 + 2.0 * i / (sweepSteps - 1));

        const auto started = std::chrono::steady_clock::now();
        for (size_t index = 0; index < sweep.size(); ++index) {
            const double pointer = sweep[index];
            const cv::Mat current = DepthMeshPoc::renderLayeredShaderReference(
                image, background, matte, influence, pointer, 0.0, false);
            const cv::Mat stable = DepthMeshPoc::renderLayeredShaderReference(
                image, background, matte, influence, pointer, 0.0, true);
            cv::Mat currentSmall, stableSmall;
            cv::resize(current, currentSmall, {720, 405}, 0, 0, cv::INTER_AREA);
            cv::resize(stable, stableSmall, {720, 405}, 0, 0, cv::INTER_AREA);
            cv::Mat frame(455, 1440, CV_8UC3, cv::Scalar(24, 26, 29));
            drawHeader(frame, "CURRENT  Foreground 0.8-1.2% | Background 0.3%", 0);
            drawHeader(frame, "STABLE SUBJECT  Foreground 0.15-0.25% | Background 2.8%", 720);
            currentSmall.copyTo(frame(cv::Rect(0, 50, 720, 405)));
            stableSmall.copyTo(frame(cv::Rect(720, 50, 720, 405)));
            const int progressX = 14 + static_cast<int>(
                (frame.cols - 28) * index / std::max<size_t>(1, sweep.size() - 1));
            cv::line(frame, {14, 449}, {frame.cols - 14, 449},
                     cv::Scalar(82, 85, 90), 2, cv::LINE_AA);
            cv::circle(frame, {progressX, 449}, 4, cv::Scalar(90, 210, 255),
                       cv::FILLED, cv::LINE_AA);
            std::ostringstream name;
            name << "frame_" << std::setw(3) << std::setfill('0') << index << ".png";
            if (!cv::imwrite((outputDirectory / name.str()).string(), frame))
                throw std::runtime_error("failed to write animation frame");
        }
        const double seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        std::cout << "rendered " << sweep.size() << " A/B frames in "
                  << seconds << " seconds to " << outputDirectory << '\n';
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "orbit comparison failed: " << error.what() << '\n';
        return 1;
    }
}
