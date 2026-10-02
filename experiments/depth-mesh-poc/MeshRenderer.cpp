#include "MeshRenderer.h"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/photo.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <vector>

namespace DepthMeshPoc {
namespace {

constexpr int frameWidth = 1600;
constexpr int frameHeight = 900;
constexpr int meshStep = 2;
constexpr double verticalFovDegrees = 42.0;
constexpr double orbitYawDegrees = 2.0;
constexpr double orbitPitchDegrees = 1.6;
constexpr double depthSpan = 1.3;
constexpr double farDistance = 3.3;
constexpr double edgeCutoff = 0.23;
constexpr double overscan = 0.04;

struct Vec3 {
    double x;
    double y;
    double z;
};

Vec3 operator+(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
Vec3 operator-(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
Vec3 operator*(Vec3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
double dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
Vec3 cross(Vec3 a, Vec3 b)
{
    return {a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x};
}
Vec3 normalize(Vec3 v)
{
    const double length = std::sqrt(dot(v, v));
    return length > 1e-9 ? v * (1.0 / length) : Vec3{0, 0, 1};
}

struct Vertex {
    double x = 0;
    double y = 0;
    double z = 0;
    double u = 0;
    double v = 0;
    float depth = 0;
};

struct ProjectedVertex {
    double x;
    double y;
    double z;
    double u;
    double v;
};

cv::Mat cropAndResize(const cv::Mat &input, int interpolation)
{
    const double targetAspect = static_cast<double>(frameWidth) / frameHeight;
    const double aspect = static_cast<double>(input.cols) / input.rows;
    cv::Rect crop(0, 0, input.cols, input.rows);
    if (aspect > targetAspect) {
        crop.width = static_cast<int>(std::lround(input.rows * targetAspect));
        crop.x = (input.cols - crop.width) / 2;
    } else {
        crop.height = static_cast<int>(std::lround(input.cols / targetAspect));
        crop.y = (input.rows - crop.height) / 2;
    }
    cv::Mat result;
    cv::resize(input(crop), result, {frameWidth, frameHeight}, 0, 0,
               interpolation);
    return result;
}

cv::Vec3b bilinearColor(const cv::Mat &image, double u, double v)
{
    const double px = std::clamp(u * (image.cols - 1), 0.0,
                                 static_cast<double>(image.cols - 1));
    const double py = std::clamp(v * (image.rows - 1), 0.0,
                                 static_cast<double>(image.rows - 1));
    const int x0 = static_cast<int>(px);
    const int y0 = static_cast<int>(py);
    const int x1 = std::min(x0 + 1, image.cols - 1);
    const int y1 = std::min(y0 + 1, image.rows - 1);
    const double fx = px - x0;
    const double fy = py - y0;
    const auto c00 = image.at<cv::Vec3b>(y0, x0);
    const auto c10 = image.at<cv::Vec3b>(y0, x1);
    const auto c01 = image.at<cv::Vec3b>(y1, x0);
    const auto c11 = image.at<cv::Vec3b>(y1, x1);
    cv::Vec3b result;
    for (int channel = 0; channel < 3; ++channel) {
        const double top = c00[channel] * (1 - fx) + c10[channel] * fx;
        const double bottom = c01[channel] * (1 - fx) + c11[channel] * fx;
        result[channel] = cv::saturate_cast<uchar>(top * (1 - fy) + bottom * fy);
    }
    return result;
}

void rasterizeTriangle(const cv::Mat &texture,
                       const std::array<ProjectedVertex, 3> &vertices,
                       cv::Mat &colorBuffer, cv::Mat &zBuffer)
{
    const auto &a = vertices[0];
    const auto &b = vertices[1];
    const auto &c = vertices[2];
    const double area = (b.x - a.x) * (c.y - a.y)
        - (b.y - a.y) * (c.x - a.x);
    if (std::abs(area) < 1e-6)
        return;
    const int left = std::max(0, static_cast<int>(std::floor(
        std::min({a.x, b.x, c.x}))));
    const int right = std::min(colorBuffer.cols - 1, static_cast<int>(std::ceil(
        std::max({a.x, b.x, c.x}))));
    const int top = std::max(0, static_cast<int>(std::floor(
        std::min({a.y, b.y, c.y}))));
    const int bottom = std::min(colorBuffer.rows - 1, static_cast<int>(std::ceil(
        std::max({a.y, b.y, c.y}))));
    if (left > right || top > bottom)
        return;

    const double inverseArea = 1.0 / area;
    for (int y = top; y <= bottom; ++y) {
        auto *zRow = zBuffer.ptr<float>(y);
        auto *colorRow = colorBuffer.ptr<cv::Vec3b>(y);
        for (int x = left; x <= right; ++x) {
            const double px = x + 0.5;
            const double py = y + 0.5;
            const double wa = ((b.x - px) * (c.y - py)
                               - (b.y - py) * (c.x - px)) * inverseArea;
            const double wb = ((c.x - px) * (a.y - py)
                               - (c.y - py) * (a.x - px)) * inverseArea;
            const double wc = 1.0 - wa - wb;
            if (wa < -1e-5 || wb < -1e-5 || wc < -1e-5)
                continue;
            const double inverseZ = wa / a.z + wb / b.z + wc / c.z;
            if (inverseZ <= 0)
                continue;
            const float z = static_cast<float>(1.0 / inverseZ);
            if (z >= zRow[x])
                continue;
            const double u = (wa * a.u / a.z + wb * b.u / b.z
                              + wc * c.u / c.z) / inverseZ;
            const double v = (wa * a.v / a.z + wb * b.v / b.z
                              + wc * c.v / c.z) / inverseZ;
            zRow[x] = z;
            colorRow[x] = bilinearColor(texture, u, v);
        }
    }
}

} // namespace

RenderResult MeshRenderer::render(const cv::Mat &image,
                                  const cv::Mat &depth16,
                                  double pointerX, double pointerY) const
{
    RenderResult result;
    const auto started = std::chrono::steady_clock::now();
    if (image.empty() || depth16.empty() || image.size() != depth16.size()
        || depth16.type() != CV_16UC1)
        return result;

    cv::Mat photo = cropAndResize(image, cv::INTER_AREA);
    cv::Mat depth16Crop = cropAndResize(depth16, cv::INTER_AREA);
    cv::Mat depth;
    depth16Crop.convertTo(depth, CV_32F, 1.0 / 65535.0);
    cv::Mat filteredDepth;
    cv::bilateralFilter(depth, filteredDepth, 7, 0.08, 3.0);
    depth = std::move(filteredDepth);

    const double pointerLength = std::max(1.0, std::hypot(pointerX, pointerY));
    pointerX /= pointerLength;
    pointerY /= pointerLength;
    const double yaw = pointerX * orbitYawDegrees * CV_PI / 180.0;
    const double pitch = -pointerY * orbitPitchDegrees * CV_PI / 180.0;

    const double focusDepth = depth.at<float>(frameHeight / 2, frameWidth / 2);
    const double focusZ = farDistance - focusDepth * depthSpan;
    const Vec3 focus{0, 0, focusZ};
    const double orbitRadius = focusZ;
    const Vec3 eye{
        std::sin(yaw) * std::cos(pitch) * orbitRadius,
        std::sin(pitch) * orbitRadius,
        focusZ - std::cos(yaw) * std::cos(pitch) * orbitRadius,
    };
    const Vec3 forward = normalize(focus - eye);
    const Vec3 right = normalize(cross({0, 1, 0}, forward));
    const Vec3 cameraUp = normalize(cross(forward, right));

    const int canvasWidth = static_cast<int>(std::lround(
        frameWidth * (1.0 + 2.0 * overscan)));
    const int canvasHeight = static_cast<int>(std::lround(
        frameHeight * (1.0 + 2.0 * overscan)));
    const double focalLength = frameHeight
        / (2.0 * std::tan(verticalFovDegrees * CV_PI / 360.0));
    const double halfFovTangent = std::tan(verticalFovDegrees * CV_PI / 360.0);

    const int columns = (frameWidth + meshStep - 1) / meshStep + 1;
    const int rows = (frameHeight + meshStep - 1) / meshStep + 1;
    std::vector<Vertex> sourceVertices(static_cast<size_t>(columns) * rows);
    std::vector<ProjectedVertex> projected(sourceVertices.size());
    for (int row = 0; row < rows; ++row) {
        const int py = std::min(row * meshStep, frameHeight - 1);
        const double v = static_cast<double>(py) / (frameHeight - 1);
        const double ndcY = 1.0 - 2.0 * v;
        for (int column = 0; column < columns; ++column) {
            const int px = std::min(column * meshStep, frameWidth - 1);
            const double u = static_cast<double>(px) / (frameWidth - 1);
            const double ndcX = 2.0 * u - 1.0;
            const float relativeDepth = depth.at<float>(py, px);
            const double z = farDistance - relativeDepth * depthSpan;
            const Vec3 point{
                ndcX * z * halfFovTangent * frameWidth / frameHeight,
                ndcY * z * halfFovTangent,
                z,
            };
            const Vec3 relative = point - eye;
            const double cameraX = dot(relative, right);
            const double cameraY = dot(relative, cameraUp);
            const double cameraZ = dot(relative, forward);
            const double screenX = canvasWidth * 0.5
                + focalLength * cameraX / cameraZ;
            const double screenY = canvasHeight * 0.5
                - focalLength * cameraY / cameraZ;
            const size_t index = static_cast<size_t>(row) * columns + column;
            sourceVertices[index] = {point.x, point.y, point.z, u, v,
                                     relativeDepth};
            projected[index] = {screenX, screenY, cameraZ, u, v};
        }
    }

    cv::Mat canvas(canvasHeight, canvasWidth, CV_8UC3, cv::Scalar(0, 0, 0));
    cv::Mat zBuffer(canvasHeight, canvasWidth, CV_32F,
                    cv::Scalar(std::numeric_limits<float>::max()));
    auto emitTriangle = [&](size_t a, size_t b, size_t c) {
        const float low = std::min({sourceVertices[a].depth,
                                    sourceVertices[b].depth,
                                    sourceVertices[c].depth});
        const float high = std::max({sourceVertices[a].depth,
                                     sourceVertices[b].depth,
                                     sourceVertices[c].depth});
        if (high - low > edgeCutoff)
            return;
        rasterizeTriangle(photo, {projected[a], projected[b], projected[c]},
                          canvas, zBuffer);
    };
    for (int row = 0; row + 1 < rows; ++row) {
        for (int column = 0; column + 1 < columns; ++column) {
            const size_t topLeft = static_cast<size_t>(row) * columns + column;
            const size_t topRight = topLeft + 1;
            const size_t bottomLeft = topLeft + columns;
            const size_t bottomRight = bottomLeft + 1;
            emitTriangle(topLeft, bottomLeft, topRight);
            emitTriangle(topRight, bottomLeft, bottomRight);
        }
    }

    const int cropX = (canvasWidth - frameWidth) / 2;
    const int cropY = (canvasHeight - frameHeight) / 2;
    cv::Mat visibleColor = canvas(cv::Rect(cropX, cropY, frameWidth, frameHeight)).clone();
    cv::Mat visibleDepth = zBuffer(cv::Rect(cropX, cropY, frameWidth, frameHeight));
    cv::Mat holes = visibleDepth >= std::numeric_limits<float>::max() * 0.5f;
    const int holeCount = cv::countNonZero(holes);
    if (holeCount > 0) {
        cv::inpaint(visibleColor, holes, visibleColor, 4.0, cv::INPAINT_TELEA);
    }
    result.frame = std::move(visibleColor);
    result.filledPixels = frameWidth * frameHeight - holeCount;
    result.elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - started);
    return result;
}

} // namespace DepthMeshPoc
