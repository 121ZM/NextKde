#include <opencv2/core.hpp>
#include <opencv2/geometry/2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr int kWorkWidth = 1920;
constexpr int kPreviewWidth = 1920;
constexpr int kPreviewHeight = 1080;

enum class Profile { Raccoon, IronMan };

struct Motion {
    double background;
    double foreground;
    double nearBoost;
    double margin;
};

cv::Mat resizedToWidth(const cv::Mat &image, int width)
{
    cv::Mat result;
    const int height = std::max(1, static_cast<int>(std::lround(
        static_cast<double>(image.rows) * width / image.cols)));
    cv::resize(image, result, cv::Size(width, height), 0, 0, cv::INTER_AREA);
    return result;
}

cv::Mat subjectMask(const cv::Mat &photo, const cv::Mat &depth,
                    Profile profile)
{
    const int width = photo.cols;
    const int height = photo.rows;
    cv::Mat depthFloat;
    depth.convertTo(depthFloat, CV_32F, 1.0 / 65535.0);
    cv::GaussianBlur(depthFloat, depthFloat, cv::Size(), 1.2);

    // These seeds deliberately describe one of the two proof images. They are
    // not a general foreground segmentation contract.
    cv::Mat labels(photo.size(), CV_8U, cv::Scalar(cv::GC_BGD));
    const cv::Rect candidate = profile == Profile::Raccoon
        ? cv::Rect(static_cast<int>(width * 0.38),
                   static_cast<int>(height * 0.08),
                   static_cast<int>(width * 0.60),
                   static_cast<int>(height * 0.86))
        : cv::Rect(static_cast<int>(width * 0.31),
                   static_cast<int>(height * 0.15),
                   static_cast<int>(width * 0.54),
                   static_cast<int>(height * 0.79));
    for (int y = candidate.y; y < candidate.br().y; ++y) {
        const auto *color = photo.ptr<cv::Vec3b>(y);
        const auto *relativeDepth = depthFloat.ptr<float>(y);
        auto *label = labels.ptr<uchar>(y);
        for (int x = candidate.x; x < candidate.br().x; ++x) {
            const float nx = static_cast<float>(x) / width;
            const float ny = static_cast<float>(y) / height;
            const float core = profile == Profile::Raccoon
                ? std::pow((nx - 0.65f) / 0.12f, 2)
                    + std::pow((ny - 0.47f) / 0.27f, 2)
                : std::pow((nx - 0.56f) / 0.11f, 2)
                    + std::pow((ny - 0.50f) / 0.21f, 2);
            const bool greenGrass = profile == Profile::Raccoon && ny > 0.61f
                && color[x][1] > color[x][2] * 1.18f
                && color[x][1] > color[x][0] * 1.07f;
            if (greenGrass)
                label[x] = cv::GC_BGD;
            else if (core < 1.0f && relativeDepth[x]
                     > (profile == Profile::Raccoon ? 0.24f : 0.35f))
                label[x] = cv::GC_FGD;
            else if (relativeDepth[x]
                     > (profile == Profile::Raccoon ? 0.32f : 0.27f))
                label[x] = cv::GC_PR_FGD;
            else
                label[x] = cv::GC_PR_BGD;
        }
    }

    cv::Mat backgroundModel, foregroundModel;
    cv::grabCut(photo, labels, cv::Rect(), backgroundModel, foregroundModel,
                5, cv::GC_INIT_WITH_MASK);

    cv::Mat binary = (labels == cv::GC_FGD) | (labels == cv::GC_PR_FGD);
    cv::Mat componentLabels, stats, centroids;
    const int count = cv::connectedComponentsWithStats(binary, componentLabels,
                                                        stats, centroids, 8);
    const int centerX = static_cast<int>(width * (profile == Profile::Raccoon
                                                     ? 0.65 : 0.56));
    const int centerY = static_cast<int>(height * (profile == Profile::Raccoon
                                                      ? 0.47 : 0.50));
    int subjectComponent = componentLabels.at<int>(centerY, centerX);
    if (subjectComponent == 0) {
        int biggest = 0;
        for (int i = 1; i < count; ++i) {
            if (stats.at<int>(i, cv::CC_STAT_AREA)
                > stats.at<int>(biggest, cv::CC_STAT_AREA))
                biggest = i;
        }
        subjectComponent = biggest;
    }
    if (subjectComponent == 0)
        throw std::runtime_error("foreground seed did not yield a component");

    binary = componentLabels == subjectComponent;
    cv::morphologyEx(binary, binary, cv::MORPH_CLOSE,
                     cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(3, 3)));
    cv::Mat holeLabels, holeStats, holeCentroids;
    cv::Mat inverse = 255 - binary;
    const int holeCount = cv::connectedComponentsWithStats(
        inverse, holeLabels, holeStats, holeCentroids, 8);
    for (int label = 1; label < holeCount; ++label) {
        const bool touchesBorder = holeStats.at<int>(label, cv::CC_STAT_LEFT) == 0
            || holeStats.at<int>(label, cv::CC_STAT_TOP) == 0
            || holeStats.at<int>(label, cv::CC_STAT_LEFT)
                   + holeStats.at<int>(label, cv::CC_STAT_WIDTH) == width
            || holeStats.at<int>(label, cv::CC_STAT_TOP)
                   + holeStats.at<int>(label, cv::CC_STAT_HEIGHT) == height;
        if (!touchesBorder && holeStats.at<int>(label, cv::CC_STAT_AREA) < 2500)
            binary.setTo(255, holeLabels == label);
    }
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
            if (hiddenRow[x] == 0)
                nearest.at(labelRow[x]) = cv::Point(x, y);
        }
    }
    cv::Mat filled = photo.clone();
    for (int y = 0; y < photo.rows; ++y) {
        const auto *hiddenRow = hidden.ptr<uchar>(y);
        const auto *labelRow = labels.ptr<int>(y);
        auto *filledRow = filled.ptr<cv::Vec3b>(y);
        for (int x = 0; x < photo.cols; ++x) {
            if (hiddenRow[x] != 0) {
                const cv::Point point = nearest.at(labelRow[x]);
                if (point.x >= 0)
                    filledRow[x] = photo.at<cv::Vec3b>(point);
            }
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

cv::Mat centerCrop(const cv::Mat &image, cv::Size target)
{
    const double targetAspect = static_cast<double>(target.width) / target.height;
    const double imageAspect = static_cast<double>(image.cols) / image.rows;
    cv::Rect crop(0, 0, image.cols, image.rows);
    if (imageAspect > targetAspect) {
        crop.width = static_cast<int>(std::lround(image.rows * targetAspect));
        crop.x = (image.cols - crop.width) / 2;
    } else {
        crop.height = static_cast<int>(std::lround(image.cols / targetAspect));
        crop.y = (image.rows - crop.height) / 2;
    }
    cv::Mat output;
    cv::resize(image(crop), output, target, 0, 0, cv::INTER_LINEAR);
    return output;
}

cv::Mat shifted(const cv::Mat &image, double dx, double dy)
{
    cv::Mat output;
    const cv::Matx23d matrix(1, 0, dx, 0, 1, dy);
    cv::warpAffine(image, output, matrix, image.size(), cv::INTER_LINEAR,
                   cv::BORDER_REFLECT_101);
    return output;
}

cv::Mat grassOcclusionMask(const cv::Mat &photo)
{
    cv::Mat alpha(photo.size(), CV_8U, cv::Scalar(0));
    for (int y = 0; y < photo.rows; ++y) {
        const double vertical = std::clamp(
            (static_cast<double>(y) / photo.rows - 0.66) / 0.18, 0.0, 1.0);
        if (vertical <= 0)
            continue;
        const auto *color = photo.ptr<cv::Vec3b>(y);
        auto *mask = alpha.ptr<uchar>(y);
        for (int x = 0; x < photo.cols; ++x) {
            const double green = color[x][1];
            const double red = color[x][2];
            const double blue = color[x][0];
            const double chroma = std::min(green - red + 5,
                                            green - blue - 5);
            const double strength = std::clamp(chroma / 18.0, 0.0, 1.0);
            mask[x] = static_cast<uchar>(std::lround(
                255.0 * vertical * strength));
        }
    }
    cv::GaussianBlur(alpha, alpha, cv::Size(), 0.8);
    return alpha;
}

cv::Mat nearHandMask(const cv::Mat &depth, const cv::Mat &subject)
{
    cv::Mat hand(depth.size(), CV_8U, cv::Scalar(0));
    const int left = static_cast<int>(depth.cols * 0.60);
    const int top = static_cast<int>(depth.rows * 0.12);
    const int bottom = static_cast<int>(depth.rows * 0.58);
    for (int y = top; y < bottom; ++y) {
        const auto *depthRow = depth.ptr<ushort>(y);
        const auto *subjectRow = subject.ptr<uchar>(y);
        auto *handRow = hand.ptr<uchar>(y);
        for (int x = left; x < depth.cols; ++x) {
            if (subjectRow[x] && depthRow[x] > 0.70 * 65535)
                handRow[x] = 255;
        }
    }
    cv::morphologyEx(hand, hand, cv::MORPH_CLOSE,
                     cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(5, 5)));
    cv::Mat componentLabels, stats, centroids;
    const int count = cv::connectedComponentsWithStats(
        hand, componentLabels, stats, centroids, 8);
    int biggest = 0;
    for (int index = 1; index < count; ++index) {
        if (!biggest || stats.at<int>(index, cv::CC_STAT_AREA)
            > stats.at<int>(biggest, cv::CC_STAT_AREA))
            biggest = index;
    }
    if (!biggest || stats.at<int>(biggest, cv::CC_STAT_AREA) < 1000)
        throw std::runtime_error("near hand mask is missing");
    return componentLabels == biggest;
}

cv::Mat renderFrame(const cv::Mat &background, const cv::Mat &foreground,
                    const cv::Mat &alpha, const cv::Mat &handInfluence,
                    const cv::Mat &grassAlpha,
                    double position, const Motion &motion)
{
    const cv::Size target(kPreviewWidth, kPreviewHeight);
    // Reserve the same border at every position. The near layer travels much
    // farther than the background, so the difference reads as depth.
    const double margin = motion.margin;
    const auto zoomedSize = cv::Size(
        static_cast<int>(std::lround(target.width / (1.0 - 2 * margin))),
        static_cast<int>(std::lround(target.height / (1.0 - 2 * margin))));
    const cv::Mat back = centerCrop(background, zoomedSize);
    const cv::Mat front = centerCrop(foreground, zoomedSize);
    const cv::Mat matte = centerCrop(alpha, zoomedSize);
    const cv::Mat influence = centerCrop(handInfluence, zoomedSize);
    const cv::Mat grassMatte = centerCrop(grassAlpha, zoomedSize);
    const cv::Rect viewport((zoomedSize.width - target.width) / 2,
                            (zoomedSize.height - target.height) / 2,
                            target.width, target.height);
    const cv::Mat backMoved = shifted(back, position * target.width * motion.background,
                                     position * target.height * motion.background)(viewport);
    cv::Mat frontMoved, alphaMoved;
    if (motion.nearBoost > 0) {
        // A smooth displacement field moves the whole hand as one piece while
        // distributing the small extra shift through the wrist and shoulder.
        cv::Mat mapX(target, CV_32F), mapY(target, CV_32F);
        for (int y = 0; y < target.height; ++y) {
            auto *sourceX = mapX.ptr<float>(y);
            auto *sourceY = mapY.ptr<float>(y);
            const auto *weightRow = influence.ptr<uchar>(y + viewport.y);
            for (int x = 0; x < target.width; ++x) {
                const double weight = weightRow[x + viewport.x] / 255.0;
                const double travel = motion.foreground
                    + motion.nearBoost * weight;
                sourceX[x] = static_cast<float>(x + viewport.x
                    - position * target.width * travel);
                sourceY[x] = static_cast<float>(y + viewport.y
                    - position * target.height * travel);
            }
        }
        cv::remap(front, frontMoved, mapX, mapY, cv::INTER_LINEAR,
                  cv::BORDER_REFLECT_101);
        cv::remap(matte, alphaMoved, mapX, mapY, cv::INTER_LINEAR,
                  cv::BORDER_CONSTANT, cv::Scalar(0));
    } else {
        frontMoved = shifted(front,
            position * target.width * motion.foreground,
            position * target.height * motion.foreground)(viewport);
        alphaMoved = shifted(matte,
            position * target.width * motion.foreground,
            position * target.height * motion.foreground)(viewport);
    }
    const cv::Mat grassMoved = shifted(front, position * target.width * motion.background,
                                      position * target.height * motion.background)(viewport);
    const cv::Mat grassAlphaMoved = shifted(grassMatte,
                                           position * target.width * motion.background,
                                           position * target.height * motion.background)(viewport);

    cv::Mat backFloat, frontFloat, alphaFloat;
    backMoved.convertTo(backFloat, CV_32FC3, 1.0 / 255.0);
    frontMoved.convertTo(frontFloat, CV_32FC3, 1.0 / 255.0);
    alphaMoved.convertTo(alphaFloat, CV_32F, 1.0 / 255.0);
    cv::Mat alpha3;
    cv::cvtColor(alphaFloat, alpha3, cv::COLOR_GRAY2BGR);
    cv::Mat result = frontFloat.mul(alpha3)
                   + backFloat.mul(cv::Scalar::all(1.0) - alpha3);
    cv::Mat grassFloat, grassAlphaFloat, grassAlpha3;
    grassMoved.convertTo(grassFloat, CV_32FC3, 1.0 / 255.0);
    grassAlphaMoved.convertTo(grassAlphaFloat, CV_32F, 1.0 / 255.0);
    cv::cvtColor(grassAlphaFloat, grassAlpha3, cv::COLOR_GRAY2BGR);
    result = grassFloat.mul(grassAlpha3)
             + result.mul(cv::Scalar::all(1.0) - grassAlpha3);
    result.convertTo(result, CV_8UC3, 255.0);
    return result;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc == 7 && std::string(argv[1]) == "assets") {
        try {
            const cv::Mat original = cv::imread(argv[2], cv::IMREAD_COLOR);
            const cv::Mat originalBackground = cv::imread(argv[3], cv::IMREAD_COLOR);
            const cv::Mat originalMatte = cv::imread(argv[4], cv::IMREAD_GRAYSCALE);
            const cv::Mat originalInfluence = cv::imread(argv[5], cv::IMREAD_GRAYSCALE);
            if (original.empty() || originalBackground.empty()
                || originalMatte.empty() || originalInfluence.empty()
                || originalBackground.size() != originalMatte.size()
                || originalBackground.size() != originalInfluence.size())
                throw std::runtime_error("cached scene assets are incomplete");
            const cv::Mat photo = resizedToWidth(original, kWorkWidth);
            const cv::Mat background = resizedToWidth(originalBackground, kWorkWidth);
            const cv::Mat matte = resizedToWidth(originalMatte, kWorkWidth);
            const cv::Mat influence = resizedToWidth(originalInfluence, kWorkWidth);
            const cv::Mat noOcclusion(photo.size(), CV_8UC1, cv::Scalar(0));
            const Motion motion{-0.005, 0.020, 0.010, 0.050};
            const fs::path outputDirectory = argv[6];
            fs::create_directories(outputDirectory);
            for (const auto &frame : {std::pair{"left", -1.0},
                                      std::pair{"center", 0.0},
                                      std::pair{"right", 1.0}}) {
                const cv::Mat preview = renderFrame(background, photo, matte,
                    influence, noOcclusion, frame.second, motion);
                cv::imwrite((outputDirectory / (std::string(frame.first)
                            + ".jpg")).string(), preview,
                            {cv::IMWRITE_JPEG_QUALITY, 92});
            }
            std::cout << "wrote cached scene preview to " << outputDirectory << '\n';
            return 0;
        } catch (const std::exception &error) {
            std::cerr << "cached scene preview failed: " << error.what() << '\n';
            return 1;
        }
    }
    if (argc != 5 || (std::string(argv[1]) != "raccoon"
                      && std::string(argv[1]) != "ironman")) {
        std::cerr << "usage: layered-wallpaper-poc raccoon|ironman IMAGE DEPTH_PNG OUTPUT_DIR\n"
                     "       layered-wallpaper-poc assets IMAGE BACKGROUND MATTE INFLUENCE OUTPUT_DIR\n";
        return 2;
    }
    try {
        const Profile profile = std::string(argv[1]) == "raccoon"
            ? Profile::Raccoon : Profile::IronMan;
        const Motion motion = profile == Profile::Raccoon
            ? Motion{0.003, 0.020, 0.0, 0.035}
            : Motion{-0.005, 0.020, 0.010, 0.050};
        const cv::Mat original = cv::imread(argv[2], cv::IMREAD_COLOR);
        const cv::Mat originalDepth = cv::imread(argv[3], cv::IMREAD_UNCHANGED);
        if (original.empty() || originalDepth.empty()
            || originalDepth.type() != CV_16UC1
            || original.size() != originalDepth.size())
            throw std::runtime_error("image and 16-bit depth must share dimensions");

        const fs::path outputDirectory = argv[4];
        fs::create_directories(outputDirectory);
        const cv::Mat photo = resizedToWidth(original, kWorkWidth);
        const cv::Mat depth = resizedToWidth(originalDepth, kWorkWidth);
        const cv::Mat mask = subjectMask(photo, depth, profile);
        cv::Mat alpha;
        cv::GaussianBlur(mask, alpha, cv::Size(), 1.1);
        const cv::Mat handMask = profile == Profile::IronMan
            ? nearHandMask(depth, mask)
            : cv::Mat(photo.size(), CV_8U, cv::Scalar(0));
        cv::Mat handInfluence;
        cv::dilate(handMask, handInfluence,
                   cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                             cv::Size(101, 101)));
        cv::GaussianBlur(handInfluence, handInfluence, cv::Size(), 25.0);
        const cv::Mat grassAlpha = profile == Profile::Raccoon
            ? grassOcclusionMask(photo)
            : cv::Mat(photo.size(), CV_8U, cv::Scalar(0));

        // Only a strip behind the moving silhouette is exposed. Extend nearby
        // colors inward and soften the boundary to avoid duplicate objects.
        const cv::Mat background = extendedBackground(photo, mask);

        cv::Mat foreground;
        cv::cvtColor(photo, foreground, cv::COLOR_BGR2BGRA);
        cv::insertChannel(alpha, foreground, 3);
        cv::imwrite((outputDirectory / "foreground.png").string(), foreground);
        cv::imwrite((outputDirectory / "background.png").string(), background);
        cv::imwrite((outputDirectory / "mask.png").string(), mask);
        cv::imwrite((outputDirectory / "hand-mask.png").string(), handMask);
        cv::imwrite((outputDirectory / "hand-influence.png").string(), handInfluence);
        cv::imwrite((outputDirectory / "grass-mask.png").string(), grassAlpha);

        for (const auto &frame : {std::pair{"left", -1.0},
                                  std::pair{"center", 0.0},
                                  std::pair{"right", 1.0}}) {
            const cv::Mat preview = renderFrame(background, photo, alpha,
                                                handInfluence, grassAlpha,
                                                frame.second, motion);
            cv::imwrite((outputDirectory / (std::string(frame.first)
                                            + ".jpg")).string(), preview,
                        {cv::IMWRITE_JPEG_QUALITY, 92});
        }
        const fs::path framesDirectory = outputDirectory / "frames";
        fs::create_directories(framesDirectory);
        constexpr int frameCount = 72;
        for (int index = 0; index < frameCount; ++index) {
            const double phase = 2.0 * CV_PI * index / frameCount;
            const double position = -std::cos(phase);
            const cv::Mat frame = renderFrame(background, photo, alpha,
                                              handInfluence, grassAlpha, position,
                                              motion);
            const std::string name = cv::format("frame_%03d.jpg", index);
            cv::imwrite((framesDirectory / name).string(), frame,
                        {cv::IMWRITE_JPEG_QUALITY, 88});
        }
        std::cout << "wrote layered sample to " << outputDirectory << '\n';
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "layered sample failed: " << error.what() << '\n';
        return 1;
    }
}
