#include <LiquidAI/ModelManager.h>

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QEventLoop>

#include <limits>

namespace {

QString modelCacheDirectory()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/liquid-shell/models");
}

std::filesystem::path toPath(const QString &path)
{
#ifdef _WIN32
    return std::filesystem::path(path.toStdWString());
#else
    return std::filesystem::path(path.toLocal8Bit().constData());
#endif
}

bool hashFile(const QString &path, QByteArray *digest)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        const QByteArray chunk = file.read(1024 * 1024);
        if (chunk.isEmpty() && file.error() != QFileDevice::NoError)
            return false;
        hash.addData(chunk);
    }
    *digest = hash.result().toHex();
    return true;
}

bool ensureVerifiedModel(const QString &fileName, const char *expectedSha256,
                         const char *downloadUrl, std::filesystem::path *path,
                         std::string *error, int timeoutMs)
{
    const QString directory = modelCacheDirectory();
    if (directory.isEmpty() || !QDir().mkpath(directory)) {
        *error = "无法创建模型缓存目录";
        return false;
    }
    const QString destination = directory + QLatin1Char('/') + fileName;
    QByteArray digest;
    if (QFileInfo(destination).isFile() && hashFile(destination, &digest)
        && digest == QByteArray(expectedSha256)) {
        *path = toPath(destination);
        return true;
    }

    QFile::remove(destination);
    QNetworkAccessManager network;
    QNetworkRequest request{QUrl(QString::fromLatin1(downloadUrl))};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = network.get(request);
    QSaveFile output(destination + QStringLiteral(".download"));
    if (!output.open(QIODevice::WriteOnly)) {
        reply->abort();
        reply->deleteLater();
        *error = "无法创建模型临时文件";
        return false;
    }

    constexpr qint64 maximumModelBytes = 200LL * 1024 * 1024;
    bool tooLarge = false;
    QObject::connect(reply, &QIODevice::readyRead, reply, [&] {
        const QByteArray chunk = reply->readAll();
        if (output.size() + chunk.size() > maximumModelBytes) {
            tooLarge = true;
            reply->abort();
            return;
        }
        if (output.write(chunk) != chunk.size())
            reply->abort();
    });
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(timeoutMs);
    QObject::connect(&timeout, &QTimer::timeout, reply, &QNetworkReply::abort);
    timeout.start();
    loop.exec();

    const QByteArray tail = reply->readAll();
    if (!tail.isEmpty() && output.size() + tail.size() <= maximumModelBytes)
        output.write(tail);
    const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto networkError = reply->error();
    const QString networkMessage = reply->errorString();
    reply->deleteLater();
    if (tooLarge || output.size() > maximumModelBytes) {
        output.cancelWriting();
        *error = "模型文件超过大小上限";
        return false;
    }
    if (networkError != QNetworkReply::NoError || status < 200 || status >= 300) {
        output.cancelWriting();
        *error = "模型下载失败：" + networkMessage.toStdString();
        return false;
    }
    if (!output.commit() || !hashFile(destination + QStringLiteral(".download"), &digest)
        || digest != QByteArray(expectedSha256)) {
        QFile::remove(destination + QStringLiteral(".download"));
        *error = "模型 SHA256 校验失败";
        return false;
    }
    if (!QFile::rename(destination + QStringLiteral(".download"), destination)) {
        QFile::remove(destination + QStringLiteral(".download"));
        *error = "无法安装已校验的模型";
        return false;
    }
    *path = toPath(destination);
    return true;
}

} // namespace

namespace LiquidAI {

bool ModelManager::ensureDepthAnythingV2Small(std::filesystem::path *path,
                                             std::string *error) const
{
    return ensureVerifiedModel(QStringLiteral("depth-anything-v2-small-vits.onnx"),
                               modelSha256, modelUrl, path, error, 180000);
}

bool ModelManager::ensureForegroundIsNet(std::filesystem::path *path,
                                         std::string *error) const
{
    return ensureVerifiedModel(QStringLiteral("isnet-general-use.onnx"),
                               foregroundModelSha256, foregroundModelUrl,
                               path, error, 60000);
}

} // namespace LiquidAI
