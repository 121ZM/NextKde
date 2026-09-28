#pragma once

#include <opencv2/core.hpp>

#include <chrono>

namespace DepthMeshPoc {

struct RenderResult {
    cv::Mat frame;
    std::chrono::microseconds elapsed{};
    int filledPixels = 0;
};

class MeshRenderer final {
public:
    RenderResult render(const cv::Mat &image, const cv::Mat &depth16,
                        double pointerX, double pointerY) const;
};

} // namespace DepthMeshPoc
