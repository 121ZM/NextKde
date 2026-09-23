#include <LiquidAI/SpatialAssetGenerator.h>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/geometry/2d.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr int maximumWidth = 2560;

QString toQString(const fs::path &path)
{
#ifdef Q_OS_WIN
    return QString::fromStdWString(path.native());
#else
    return QString::fromLocal8Bit(path.native().c_str());
#endif
}

cv::Mat decode(const fs::path &path, int flags)
{
    QFile file(toQString(path));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray encoded = file.readAll();
    if (encoded.isEmpty())
        return {};
    cv::Mat bytes(1, encoded.size(), CV_8UC1,
                  const_cast<char *>(encoded.constData()));
    return cv::imdecode(bytes, flags);
}

bool writePng(const fs::path &path, const cv::Mat &image)
{
    std::vector<uchar> encoded;
    if (!cv::imencode(".png", image, encoded,
                      {cv::IMWRITE_PNG_COMPRESSION, 3}))
        return false;
    QSaveFile file(toQString(path));
    return file.open(QIODevice::WriteOnly)
        && file.write(reinterpret_cast<const char *>(encoded.data()),
                      static_cast<qsizetype>(encoded.size()))
            == static_cast<qsizetype>(encoded.size())
        && file.commit();
}

bool writeMetadata(const fs::path &path, int width, int height)
{
    const QJsonObject object{
        {QStringLiteral("contract"),
         QString::fromLatin1(LiquidAI::SpatialAssetGenerator::contractVersion)},
        {QStringLiteral("width"), width},
        {QStringLiteral("height"), height},
        {QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
    };
    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Compact);
    QSaveFile file(toQString(path));
    return file.open(QIODevice::WriteOnly)
        && file.write(bytes) == bytes.size() && file.commit();
}

cv::Mat largestComponent(const cv::Mat &binary, double minimumFraction,
                         double maximumFraction)
{
    cv::Mat labels, stats, centroids;
    const int count = cv::connectedComponentsWithStats(binary, labels, stats,
                                                        centroids, 8);
    const double pixels = static_cast<double>(binary.total());
    int selected = 0;
    for (int index = 1; index < count; ++index) {
        const int area = stats.at<int>(index, cv::CC_STAT_AREA);
        if (area < pixels * minimumFraction || area > pixels * maximumFraction)
            continue;
        const int left = stats.at<int>(index, cv::CC_STAT_LEFT);
        const int top = stats.at<int>(index, cv::CC_STAT_TOP);
        const int right = left + stats.at<int>(index, cv::CC_STAT_WIDTH);
        const int bottom = top + stats.at<int>(index, cv::CC_STAT_HEIGHT);
        if (left < 2 || top < 2 || right > binary.cols - 2
            || bottom > binary.rows - 2)
            continue;
        if (!selected || area > stats.at<int>(selected, cv::CC_STAT_AREA))
            selected = index;
    }
    return selected ? labels == selected : cv::Mat{};
}

cv::Mat foregroundMask(const cv::Mat &photo, const cv::Mat &depth)
{
    cv::Mat candidate = depth > static_cast<ushort>(0.30 * 65535);
    candidate = largestComponent(candidate, 0.015, 0.55);
    if (candidate.empty())
        return {};

    const auto kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                                   cv::Size(21, 21));
    cv::Mat interior, vicinity;
    cv::erode(candidate, interior, kernel);
    cv::dilate(candidate, vicinity, kernel);
    cv::Mat labels(photo.size(), CV_8U, cv::Scalar(cv::GC_BGD));
    labels.setTo(cv::GC_PR_BGD, vicinity);
    labels.setTo(cv::GC_PR_FGD, candidate);
    labels.setTo(cv::GC_FGD, interior);
    cv::Mat backgroundModel, foregroundModel;
    cv::grabCut(photo, labels, cv::Rect(), backgroundModel, foregroundModel,
                4, cv::GC_INIT_WITH_MASK);
    cv::Mat binary = (labels == cv::GC_FGD) | (labels == cv::GC_PR_FGD);
    binary = largestComponent(binary, 0.015, 0.55);
    if (binary.empty())
        return {};
    cv::Mat overlap;
    cv::bitwise_and(binary, candidate, overlap);
    if (cv::countNonZero(overlap) < cv::countNonZero(candidate) * 0.65)
        return {};
    cv::morphologyEx(binary, binary, cv::MORPH_CLOSE,
                     cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(3, 3)));
    return binary;
}

cv::Mat extendedBackground(const cv::Mat &photo, const cv::Mat &subject)
{
    cv::Mat hidden;
    cv::dilate(subject, hidden,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                         cv::Size(41, 41)));
    cv::Mat distance, labels;
    cv::distanceTransform(hidden, distance, labels, cv::DIST_L2,
                          5, cv::DIST_LABEL_PIXEL);
    double minimum, maximum;
    cv::minMaxLoc(labels, &minimum, &maximum);
    std::vector<cv::Point> nearest(static_cast<size_t>(maximum) + 1,
                                   cv::Point(-1, -1));
    for (int y = 0; y < photo.rows; ++y) {
        const auto *hiddenRow = hidden.ptr<uchar>(y);
        const auto *labelRow = labels.ptr<int>(y);
        for (int x = 0; x < photo.cols; ++x) {
            if (!hiddenRow[x])
                nearest.at(labelRow[x]) = cv::Point(x, y);
        }
    }
    cv::Mat filled = photo.clone();
    for (int y = 0; y < photo.rows; ++y) {
        const auto *hiddenRow = hidden.ptr<uchar>(y);
        const auto *labelRow = labels.ptr<int>(y);
        auto *row = filled.ptr<cv::Vec3b>(y);
        for (int x = 0; x < photo.cols; ++x) {
            if (!hiddenRow[x])
                continue;
            const cv::Point point = nearest.at(labelRow[x]);
            if (point.x >= 0)
                row[x] = photo.at<cv::Vec3b>(point);
        }
    }
    cv::Mat softened, softMask;
    cv::GaussianBlur(filled, softened, cv::Size(), 18.0);
    cv::GaussianBlur(hidden, softMask, cv::Size(), 12.0);
    cv::Mat originalFloat, softenedFloat, alphaFloat, alpha3;
    photo.convertTo(originalFloat, CV_32FC3, 1.0 / 255.0);
    softened.convertTo(softenedFloat, CV_32FC3, 1.0 / 255.0);
    softMask.convertTo(alphaFloat, CV_32F, 1.0 / 255.0);
    cv::cvtColor(alphaFloat, alpha3, cv::COLOR_GRAY2BGR);
    cv::Mat blended = softenedFloat.mul(alpha3)
        + originalFloat.mul(cv::Scalar::all(1.0) - alpha3);
    blended.convertTo(blended, CV_8UC3, 255.0);
    return blended;
}

cv::Mat handInfluence(const cv::Mat &depth, const cv::Mat &subject)
{
    cv::Mat near = depth > static_cast<ushort>(0.82 * 65535);
    cv::bitwise_and(near, subject, near);
    near = largestComponent(near, 0.001, 0.30);
    if (near.empty())
        return cv::Mat(depth.size(), CV_8UC1, cv::Scalar(0));
    cv::dilate(near, near,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                         cv::Size(101, 101)));
    cv::GaussianBlur(near, near, cv::Size(), 25.0);
    return near;
}

} // namespace

namespace LiquidAI {

SpatialAssetResult SpatialAssetGenerator::generate(const fs::path &imagePath,
                                                    const fs::path &depthPath) const
{
    SpatialAssetResult result;
    try {
        const fs::path directory = depthPath.parent_path() / "spatial-v2";
        result.backgroundPath = directory / "background.png";
        result.mattePath = directory / "matte.png";
        result.influencePath = directory / "influence.png";
        const fs::path metadataPath = directory / "metadata.json";

        const cv::Mat source = decode(imagePath, cv::IMREAD_COLOR);
        const cv::Mat sourceDepth = decode(depthPath, cv::IMREAD_UNCHANGED);
        if (source.empty() || sourceDepth.type() != CV_16UC1
            || source.size() != sourceDepth.size()) {
            result.error = "空间素材输入不匹配";
            return result;
        }
        const int width = std::min(source.cols, maximumWidth);
        const int height = std::max(1, static_cast<int>(std::lround(
            static_cast<double>(source.rows) * width / source.cols)));
        if (height > 4096) {
            result.error = "空间素材图片长宽比超出范围";
            return result;
        }

        QFile metadataFile(toQString(metadataPath));
        if (metadataFile.open(QIODevice::ReadOnly)) {
            const QJsonObject metadata = QJsonDocument::fromJson(
                metadataFile.readAll()).object();
            if (metadata.value(QStringLiteral("contract")).toString()
                    == QString::fromLatin1(contractVersion)
                && metadata.value(QStringLiteral("width")).toInt() == width
                && metadata.value(QStringLiteral("height")).toInt() == height
                && decode(result.backgroundPath, cv::IMREAD_COLOR).size()
                    == cv::Size(width, height)
                && decode(result.mattePath, cv::IMREAD_GRAYSCALE).size()
                    == cv::Size(width, height)
                && decode(result.influencePath, cv::IMREAD_GRAYSCALE).size()
                    == cv::Size(width, height)) {
                result.success = true;
                result.cached = true;
                return result;
            }
        }

        cv::Mat photo, depth;
        if (source.cols > width) {
            cv::resize(source, photo, cv::Size(width, height), 0, 0, cv::INTER_AREA);
            cv::resize(sourceDepth, depth, cv::Size(width, height), 0, 0,
                       cv::INTER_AREA);
        } else {
            photo = source;
            depth = sourceDepth;
        }
        const cv::Mat mask = foregroundMask(photo, depth);
        if (mask.empty()) {
            result.error = "未找到适合分层的独立前景";
            return result;
        }
        cv::Mat alpha;
        cv::GaussianBlur(mask, alpha, cv::Size(), 1.1);
        const cv::Mat background = extendedBackground(photo, mask);
        const cv::Mat influence = handInfluence(depth, mask);
        if (!QDir().mkpath(toQString(directory))
            || !writePng(result.backgroundPath, background)
            || !writePng(result.mattePath, alpha)
            || !writePng(result.influencePath, influence)
            || !writeMetadata(metadataPath, width, height)) {
            result.error = "无法写入空间壁纸缓存";
            return result;
        }
        result.success = true;
        return result;
    } catch (const cv::Exception &exception) {
        result.error = exception.what();
        return result;
    } catch (const std::exception &exception) {
        result.error = exception.what();
        return result;
    }
}

} // namespace LiquidAI
