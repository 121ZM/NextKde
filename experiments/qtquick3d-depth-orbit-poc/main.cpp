#include "DepthMeshGeometry.h"

#include <QDir>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <QVector2D>

#include <cmath>
#include <iostream>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 5) {
        std::cerr << "usage: qtquick3d-depth-orbit-poc IMAGE DEPTH16 BACKGROUND OUTPUT_DIR\n";
        return 2;
    }
    qmlRegisterType<DepthMeshGeometry>("DepthOrbit", 1, 0, "DepthMeshGeometry");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [](const QList<QQmlError> &warnings) {
        for (const auto &warning : warnings)
            std::cerr << warning.toString().toStdString() << '\n';
    });
    auto *context = engine.rootContext();
    context->setContextProperty("demoSourceUrl",
                                QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    context->setContextProperty("demoDepthUrl",
                                QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])));
    context->setContextProperty("demoBackgroundUrl",
        QString::fromLocal8Bit(argv[3]) == "-" ? QString()
            : QUrl::fromLocalFile(QString::fromLocal8Bit(argv[3])).toString());
    const QString outputDirectory = QDir::cleanPath(QString::fromLocal8Bit(argv[4]));
    QDir().mkpath(outputDirectory);
    engine.rootContext()->setContextProperty("demoOutputDirectory", outputDirectory);
    engine.load(QUrl::fromLocalFile(QStringLiteral(QTQUICK3D_ORBIT_QML_PATH)));
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window)
        return 1;

    QElapsedTimer elapsed;
    elapsed.start();
    int frames = 0;
    QObject::connect(window, &QQuickWindow::frameSwapped, &app,
                     [&frames] { ++frames; });
    QTimer animation;
    animation.setInterval(16);
    QObject::connect(&animation, &QTimer::timeout, window, [window, &elapsed] {
        const float seconds = elapsed.elapsed() / 1000.0f;
        window->setProperty("pointer", QVariant::fromValue(QVector2D(
            std::sin(seconds * 1.1f), std::sin(seconds * 0.73f) * 0.55f)));
    });
    animation.start();
    QTimer::singleShot(2500, window, [window, &animation, &frames,
                                       outputDirectory] {
        animation.stop();
        const int measuredFrames = frames;
        const double fps = measuredFrames / 2.5;
        const QVector2D poses[] = {QVector2D(-1.0f, 0.0f),
                                   QVector2D(0.0f, 0.0f),
                                   QVector2D(1.0f, 0.0f)};
        const QStringList names{QStringLiteral("left"),
                                QStringLiteral("center"),
                                QStringLiteral("right")};
        auto capture = std::make_shared<std::function<void(int)>>();
        *capture = [window, poses, names, outputDirectory, fps, measuredFrames,
                    capture](int index) {
            if (index >= 3) {
                std::cout << "Qt Quick 3D frames: " << measuredFrames
                          << " in 2.5 s (" << fps << " fps)\n"
                          << "wrote rendered poses to "
                          << outputDirectory.toStdString() << '\n';
                QCoreApplication::quit();
                return;
            }
            window->setProperty("pointer", QVariant::fromValue(poses[index]));
            QTimer::singleShot(250, window, [window, names, outputDirectory,
                                             capture, index] {
                const QString path = QDir(outputDirectory).filePath(
                    names[index] + QStringLiteral(".png"));
                const QImage frame = window->grabWindow();
                if (!frame.save(path))
                    std::cerr << "failed to save " << path.toStdString() << '\n';
                (*capture)(index + 1);
            });
        };
        (*capture)(0);
    });
    return app.exec();
}
