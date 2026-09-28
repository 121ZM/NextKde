#include "ReferenceRenderer.h"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>

namespace DepthMeshPoc {
namespace {

constexpr int frameWidth = 1600;
constexpr int frameHeight = 900;
constexpr float crop = 0.90f;

cv::Mat cropAndResize(const cv::Mat &input, int interpolation)
{
    const double targetAspect = static_cast<double>(frameWidth) / frameHeight;
    const double aspect = static_cast<double>(input.cols) / input.rows;
    cv::Rect cropRect(0, 0, input.cols, input.rows);
    if (aspect > targetAspect) {
        cropRect.width = static_cast<int>(std::lround(input.rows * targetAspect));
        cropRect.x = (input.cols - cropRect.width) / 2;
    } else {
        cropRect.height = static_cast<int>(std::lround(input.cols / targetAspect));
        cropRect.y = (input.rows - cropRect.height) / 2;
    }
    cv::Mat output;
    cv::resize(input(cropRect), output, {frameWidth, frameHeight}, 0, 0,
               interpolation);
    return output;
}

cv::Vec2f normalizedPointer(double x, double y)
{
    const double length = std::max(1.0, std::hypot(x, y));
    return {static_cast<float>(x / length), static_cast<float>(y / length)};
}

void makeMaps(cv::Mat &mapX, cv::Mat &mapY, cv::Mat &baseX, cv::Mat &baseY,
              const cv::Vec2f &tilt, float perspective)
{
    mapX.create(frameHeight, frameWidth, CV_32F);
    mapY.create(frameHeight, frameWidth, CV_32F);
    baseX.create(frameHeight, frameWidth, CV_32F);
    baseY.create(frameHeight, frameWidth, CV_32F);
    for (int y = 0; y < frameHeight; ++y) {
        auto *mx = mapX.ptr<float>(y);
        auto *my = mapY.ptr<float>(y);
        auto *bx = baseX.ptr<float>(y);
        auto *by = baseY.ptr<float>(y);
        const float cy = (y + 0.5f) / frameHeight - 0.5f;
        for (int x = 0; x < frameWidth; ++x) {
            const float cx = (x + 0.5f) / frameWidth - 0.5f;
            const float denominator = 1.0f
                + (tilt[0] * cx + tilt[1] * cy) * perspective;
            const float u = 0.5f + cx / denominator * crop;
            const float v = 0.5f + cy / denominator * crop;
            bx[x] = std::clamp((0.5f + cx * crop) * frameWidth,
                               0.0f, static_cast<float>(frameWidth - 1));
            by[x] = std::clamp((0.5f + cy * crop) * frameHeight,
                               0.0f, static_cast<float>(frameHeight - 1));
            mx[x] = u * frameWidth;
            my[x] = v * frameHeight;
        }
    }
}

} // namespace

cv::Mat renderDepthShaderReference(const cv::Mat &image,
                                   const cv::Mat &depth16,
                                   double pointerX, double pointerY)
{
    const cv::Mat photo = cropAndResize(image, cv::INTER_AREA);
    cv::Mat depth = cropAndResize(depth16, cv::INTER_AREA);
    depth.convertTo(depth, CV_32F, 1.0 / 65535.0);
    const auto tilt = normalizedPointer(pointerX, pointerY);
    cv::Mat sourceX, sourceY, baseX, baseY;
    makeMaps(sourceX, sourceY, baseX, baseY, tilt, 0.11f);

    cv::Mat baseDepth, movedDepth;
    cv::remap(depth, baseDepth, baseX, baseY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    cv::Mat movedX = sourceX.clone();
    cv::Mat movedY = sourceY.clone();
    for (int y = 0; y < frameHeight; ++y) {
        auto *mx = movedX.ptr<float>(y);
        auto *my = movedY.ptr<float>(y);
        const auto *depthRow = baseDepth.ptr<float>(y);
        for (int x = 0; x < frameWidth; ++x) {
            const float delta = (depthRow[x] - baseDepth.at<float>(
                frameHeight / 2, frameWidth / 2)) * 0.022f;
            mx[x] += tilt[0] * delta * frameWidth;
            my[x] += tilt[1] * delta * frameHeight;
        }
    }
    cv::remap(depth, movedDepth, movedX, movedY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    cv::Mat sampled;
    cv::remap(photo, sampled, movedX, movedY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    for (int y = 0; y < frameHeight; ++y) {
        const auto *depthRow = baseDepth.ptr<float>(y);
        const auto *movedRow = movedDepth.ptr<float>(y);
        auto *mapX = movedX.ptr<float>(y);
        auto *mapY = movedY.ptr<float>(y);
        for (int x = 0; x < frameWidth; ++x) {
            const float continuity = 1.0f - std::clamp(
                (std::abs(movedRow[x] - depthRow[x]) - 0.04f) / 0.12f,
                0.0f, 1.0f);
            const float delta = (depthRow[x] - baseDepth.at<float>(
                frameHeight / 2, frameWidth / 2)) * 0.022f * continuity;
            mapX[x] = std::clamp(baseX.at<float>(y, x)
                                     + tilt[0] * delta * frameWidth,
                                 0.0f, static_cast<float>(frameWidth - 1));
            mapY[x] = std::clamp(baseY.at<float>(y, x)
                                     + tilt[1] * delta * frameHeight,
                                 0.0f, static_cast<float>(frameHeight - 1));
        }
    }
    cv::remap(photo, sampled, movedX, movedY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    return sampled;
}

cv::Mat renderLayeredShaderReference(const cv::Mat &image,
                                     const cv::Mat &background,
                                     const cv::Mat &matte,
                                     const cv::Mat &influence,
                                     double pointerX, double pointerY,
                                     bool stableForeground)
{
    const cv::Mat photo = cropAndResize(image, cv::INTER_AREA);
    const cv::Mat back = cropAndResize(background, cv::INTER_AREA);
    const cv::Mat alpha = cropAndResize(matte, cv::INTER_AREA);
    const cv::Mat near = cropAndResize(influence, cv::INTER_AREA);
    const auto tilt = normalizedPointer(pointerX, pointerY);
    cv::Mat backX, backY, ignoredX, ignoredY;
    cv::Mat frontX, frontY, baseX, baseY;
    makeMaps(backX, backY, ignoredX, ignoredY, tilt,
             stableForeground ? 0.04f : 0.065f);
    makeMaps(frontX, frontY, baseX, baseY, tilt,
             stableForeground ? 0.01f : 0.13f);
    cv::Mat centerX(frameHeight, frameWidth, CV_32F);
    cv::Mat centerY(frameHeight, frameWidth, CV_32F);
    for (int y = 0; y < frameHeight; ++y) {
        auto *cx = centerX.ptr<float>(y);
        auto *cy = centerY.ptr<float>(y);
        for (int x = 0; x < frameWidth; ++x) {
            cx[x] = (0.5f + ((x + 0.5f) / frameWidth - 0.5f) * crop)
                * frameWidth;
            cy[x] = (0.5f + ((y + 0.5f) / frameHeight - 0.5f) * crop)
                * frameHeight;
        }
    }
    cv::Mat sampledNear;
    cv::remap(near, sampledNear, centerX, centerY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    for (int y = 0; y < frameHeight; ++y) {
        auto *bx = backX.ptr<float>(y);
        auto *by = backY.ptr<float>(y);
        auto *fx = frontX.ptr<float>(y);
        auto *fy = frontY.ptr<float>(y);
        const auto *nearRow = sampledNear.ptr<uchar>(y);
        const float cy = (y + 0.5f) / frameHeight - 0.5f;
        for (int x = 0; x < frameWidth; ++x) {
            const float cx = (x + 0.5f) / frameWidth - 0.5f;
            const float backgroundTravel = stableForeground ? 0.012f : 0.003f;
            const float foregroundTravel = stableForeground
                ? 0.0005f + 0.00025f * nearRow[x] / 255.0f
                : 0.008f + 0.004f * nearRow[x] / 255.0f;
            bx[x] = std::clamp(bx[x] - tilt[0] * backgroundTravel * frameWidth,
                               0.0f, static_cast<float>(frameWidth - 1));
            by[x] = std::clamp(by[x] - tilt[1] * backgroundTravel * frameHeight,
                               0.0f, static_cast<float>(frameHeight - 1));
            fx[x] = std::clamp(fx[x] + tilt[0] * foregroundTravel * frameWidth,
                               0.0f, static_cast<float>(frameWidth - 1));
            fy[x] = std::clamp(fy[x] + tilt[1] * foregroundTravel * frameHeight,
                               0.0f, static_cast<float>(frameHeight - 1));
        }
        (void)cy;
    }
    cv::Mat bgSample, fgSample, alphaSample;
    cv::remap(back, bgSample, backX, backY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    cv::remap(photo, fgSample, frontX, frontY, cv::INTER_LINEAR,
              cv::BORDER_REPLICATE);
    cv::remap(alpha, alphaSample, frontX, frontY, cv::INTER_LINEAR,
              cv::BORDER_CONSTANT);
    cv::Mat alphaFloat;
    alphaSample.convertTo(alphaFloat, CV_32F, 1.0 / 255.0);
    cv::Mat alpha3;
    cv::cvtColor(alphaFloat, alpha3, cv::COLOR_GRAY2BGR);
    cv::Mat bgFloat, fgFloat;
    bgSample.convertTo(bgFloat, CV_32FC3, 1.0 / 255.0);
    fgSample.convertTo(fgFloat, CV_32FC3, 1.0 / 255.0);
    cv::Mat resultFloat = fgFloat.mul(alpha3)
        + bgFloat.mul(cv::Scalar::all(1.0) - alpha3);
    cv::Mat result;
    resultFloat.convertTo(result, CV_8UC3, 255.0);
    return result;
}

} // namespace DepthMeshPoc
