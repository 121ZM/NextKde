#pragma once

#include <opencv2/core.hpp>

namespace DepthMeshPoc {

cv::Mat renderDepthShaderReference(const cv::Mat &image,
                                   const cv::Mat &depth16,
                                   double pointerX, double pointerY);

cv::Mat renderLayeredShaderReference(const cv::Mat &image,
                                     const cv::Mat &background,
                                     const cv::Mat &matte,
                                     const cv::Mat &influence,
                                     double pointerX, double pointerY,
                                     bool stableForeground = false);

} // namespace DepthMeshPoc
