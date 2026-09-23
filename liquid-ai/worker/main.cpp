#include <LiquidAI/DepthGenerator.h>

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <filesystem>
#include <iostream>
#include <string>

#ifdef Q_OS_LINUX
#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

constexpr std::size_t maximumRequestBytes = 64 * 1024;

std::filesystem::path pathFromQString(const QString &value)
{
#ifdef Q_OS_WIN
    return std::filesystem::path(value.toStdWString());
#else
    return std::filesystem::path(value.toLocal8Bit().constData());
#endif
}

QString pathToQString(const std::filesystem::path &path)
{
#ifdef Q_OS_WIN
    return QString::fromStdWString(path.native());
#else
    return QString::fromLocal8Bit(path.native().c_str());
#endif
}

QByteArray errorResponse(const QString &requestId, const QString &code,
                         const QString &message, bool retryable)
{
    return QJsonDocument(QJsonObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("ok"), false},
        {QStringLiteral("error"), QJsonObject{
            {QStringLiteral("code"), code},
            {QStringLiteral("message"), message},
            {QStringLiteral("retryable"), retryable},
        }},
    }).toJson(QJsonDocument::Compact);
}

QByteArray handleRequest(const QByteArray &line, LiquidAI::DepthGenerator &generator)
{
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return errorResponse({}, QStringLiteral("invalid-worker-request"),
                             QStringLiteral("AI worker 请求格式无效"), false);

    const QJsonObject request = document.object();
    const QString requestId = request.value(QStringLiteral("requestId")).toString();
    if (request.value(QStringLiteral("version")).toInt() != 1
        || request.value(QStringLiteral("operation")).toString()
            != QStringLiteral("depth.generate")) {
        return errorResponse(requestId, QStringLiteral("unsupported-worker-request"),
                             QStringLiteral("AI worker 不支持此请求"), false);
    }

    const QString imagePath = request.value(QStringLiteral("imagePath")).toString();
    if (imagePath.isEmpty() || imagePath.size() > 32768)
        return errorResponse(requestId, QStringLiteral("invalid-image-path"),
                             QStringLiteral("图片路径无效"), false);

    const auto result = generator.generate(pathFromQString(imagePath));
    if (!result.success) {
        return errorResponse(requestId, QStringLiteral("depth-generation-failed"),
                             QString::fromStdString(result.error), false);
    }

    return QJsonDocument(QJsonObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("ok"), true},
        {QStringLiteral("result"), QJsonObject{
            {QStringLiteral("depthPath"), pathToQString(result.depthPath)},
            {QStringLiteral("width"), result.width},
            {QStringLiteral("height"), result.height},
            {QStringLiteral("cached"), result.cached},
            {QStringLiteral("model"), QStringLiteral("depth-anything-v2-small-vits-onnx-v1")},
            {QStringLiteral("contract"),
             QString::fromLatin1(LiquidAI::DepthGenerator::contractVersion)},
        }},
    }).toJson(QJsonDocument::Compact);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
#ifdef Q_OS_LINUX
    // If the machine is under memory pressure, prefer reclaiming this
    // optional worker over the platform daemon that owns desktop controls.
    setpriority(PRIO_PROCESS, 0, 10);
    const int oomScore = open("/proc/self/oom_score_adj", O_WRONLY | O_CLOEXEC);
    if (oomScore >= 0) {
        constexpr char value[] = "500";
        (void)write(oomScore, value, sizeof(value) - 1);
        close(oomScore);
    }
#endif
    LiquidAI::DepthGenerator generator;

    std::string line;
    line.reserve(maximumRequestBytes);
    bool oversized = false;
    char character = 0;
    while (std::cin.get(character)) {
        if (character != '\n') {
            if (line.size() < maximumRequestBytes)
                line.push_back(character);
            else
                oversized = true;
            continue;
        }

        const QByteArray response = oversized
            ? errorResponse({}, QStringLiteral("worker-request-too-large"),
                            QStringLiteral("AI worker 请求超过大小限制"), false)
            : handleRequest(QByteArray::fromStdString(line), generator);
        std::cout.write(response.constData(), response.size());
        std::cout.put('\n');
        std::cout.flush();
        line.clear();
        oversized = false;
    }
    return 0;
}
