#include "DepthMeshGeometry.h"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <QVector3D>
#include <vector>

namespace {
constexpr int columns = 321;
constexpr int rows = 181;
constexpr double farDistance = 3.3;
constexpr double depthSpan = 1.3;
constexpr double foregroundDepthScale = 0.55;
constexpr double backgroundDepthScale = 1.45;
constexpr double fovDegrees = 42.0;
constexpr double edgeCutoff = 0.22;

struct Vertex {
    float x;
    float y;
    float z;
    float u;
    float v;
};

cv::Mat cropAndResize(const cv::Mat &input)
{
    constexpr double aspect = 16.0 / 9.0;
    const double sourceAspect = static_cast<double>(input.cols) / input.rows;
    cv::Rect crop(0, 0, input.cols, input.rows);
    if (sourceAspect > aspect) {
        crop.width = static_cast<int>(std::lround(input.rows * aspect));
        crop.x = (input.cols - crop.width) / 2;
    } else {
        crop.height = static_cast<int>(std::lround(input.cols / aspect));
        crop.y = (input.rows - crop.height) / 2;
    }
    cv::Mat resized;
    cv::resize(input(crop), resized, {columns, rows}, 0, 0, cv::INTER_LINEAR);
    return resized;
}
} // namespace

DepthMeshGeometry::DepthMeshGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    setStride(sizeof(Vertex));
    setPrimitiveType(PrimitiveType::Triangles);
    addAttribute(Attribute::PositionSemantic, offsetof(Vertex, x), Attribute::F32Type);
    addAttribute(Attribute::TexCoord0Semantic, offsetof(Vertex, u), Attribute::F32Type);
}

void DepthMeshGeometry::setDepthPath(const QUrl &path)
{
    if (m_depthPath == path)
        return;
    m_depthPath = path;
    emit depthPathChanged();
    rebuild();
}

void DepthMeshGeometry::setImageZoom(float zoom)
{
    const float bounded = std::clamp(zoom, 1.0f, 1.5f);
    if (std::abs(m_imageZoom - bounded) < 1e-5f)
        return;
    m_imageZoom = bounded;
    emit imageZoomChanged();
    rebuild();
}

void DepthMeshGeometry::rebuild()
{
    if (!m_depthPath.isLocalFile())
        return;
    const cv::Mat rawDepth = cv::imread(m_depthPath.toLocalFile().toStdString(),
                                         cv::IMREAD_UNCHANGED);
    if (rawDepth.empty() || rawDepth.type() != CV_16UC1)
        return;
    const cv::Mat depth = cropAndResize(rawDepth);

    const float pivotDepth = depth.at<std::uint16_t>(rows / 2, columns / 2)
        / 65535.0f;
    const double pivotDistance = farDistance - pivotDepth * depthSpan;
    const auto distanceAtDepth = [pivotDepth, pivotDistance](double value) {
        if (value >= pivotDepth)
            return pivotDistance - (value - pivotDepth) * depthSpan
                * foregroundDepthScale;
        return pivotDistance + (pivotDepth - value) * depthSpan
            * backgroundDepthScale;
    };
    const float newFocusDistance = static_cast<float>(pivotDistance);
    if (std::abs(m_focusDistance - newFocusDistance) > 1e-5f) {
        m_focusDistance = newFocusDistance;
        emit focusDistanceChanged();
    }

    const double tangent = std::tan(fovDegrees * CV_PI / 360.0);
    constexpr double aspect = 16.0 / 9.0;
    std::array<Vertex, columns * rows> vertices{};
    std::array<double, columns * rows> normalizedDepths{};
    double maximumDistance = 0.0;
    float minX = std::numeric_limits<float>::max();
    float minY = minX;
    float minZ = minX;
    float maxX = std::numeric_limits<float>::lowest();
    float maxY = maxX;
    float maxZ = maxX;
    for (int y = 0; y < rows; ++y) {
        const double v = static_cast<double>(y) / (rows - 1);
        for (int x = 0; x < columns; ++x) {
            const double u = static_cast<double>(x) / (columns - 1);
            const int sampleX = std::clamp(static_cast<int>(std::lround(
                u * (columns - 1))), 0, columns - 1);
            const int sampleY = std::clamp(static_cast<int>(std::lround(
                v * (rows - 1))), 0, rows - 1);
            const double relativeDepth = depth.at<std::uint16_t>(sampleY, sampleX)
                / 65535.0;
            normalizedDepths[static_cast<size_t>(y) * columns + x]
                = relativeDepth;
            const double z = distanceAtDepth(relativeDepth);
            maximumDistance = std::max(maximumDistance, z);
            const double ndcX = (u * 2.0 - 1.0) * m_imageZoom;
            const double ndcY = (1.0 - v * 2.0) * m_imageZoom;
            Vertex &vertex = vertices[static_cast<size_t>(y) * columns + x];
            vertex.x = static_cast<float>(ndcX * z * tangent * aspect);
            vertex.y = static_cast<float>(ndcY * z * tangent);
            vertex.z = static_cast<float>(-z);
            vertex.u = static_cast<float>(u);
            vertex.v = static_cast<float>(1.0 - v);
            minX = std::min(minX, vertex.x);
            minY = std::min(minY, vertex.y);
            minZ = std::min(minZ, vertex.z);
            maxX = std::max(maxX, vertex.x);
            maxY = std::max(maxY, vertex.y);
            maxZ = std::max(maxZ, vertex.z);
        }
    }

    std::vector<Vertex> triangles;
    triangles.reserve(static_cast<size_t>(columns - 1) * (rows - 1) * 6);
    auto appendTriangle = [&](int a, int b, int c) {
        const int ia = a;
        const int ib = b;
        const int ic = c;
        const double da = normalizedDepths[ia];
        const double db = normalizedDepths[ib];
        const double dc = normalizedDepths[ic];
        if (std::max({da, db, dc}) - std::min({da, db, dc}) > edgeCutoff)
            return;
        triangles.push_back(vertices[ia]);
        triangles.push_back(vertices[ib]);
        triangles.push_back(vertices[ic]);
    };
    for (int y = 0; y + 1 < rows; ++y) {
        for (int x = 0; x + 1 < columns; ++x) {
            const int tl = y * columns + x;
            const int tr = tl + 1;
            const int bl = tl + columns;
            const int br = bl + 1;
            appendTriangle(tl, bl, tr);
            appendTriangle(tr, bl, br);
        }
    }

    QByteArray vertexData(reinterpret_cast<const char *>(triangles.data()),
                          static_cast<qsizetype>(triangles.size() * sizeof(Vertex)));
    setVertexData(vertexData);
    setBounds(QVector3D(minX, minY, minZ), QVector3D(maxX, maxY, maxZ));
    const float newBackgroundDistance = static_cast<float>(maximumDistance + 0.25);
    if (std::abs(m_backgroundDistance - newBackgroundDistance) > 1e-5f) {
        m_backgroundDistance = newBackgroundDistance;
        emit backgroundDistanceChanged();
    }
    update();
}
