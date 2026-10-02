#include <QDir>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QImage>
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
    if (argc != 4) {
        std::cerr << "usage: gpu-depth-orbit-poc IMAGE DEPTH16 OUTPUT_DIR\n";
        return 2;
    }

    const QUrl qmlUrl = QUrl::fromLocalFile(
        QStringLiteral(GPU_DEPTH_ORBIT_QML_PATH));
    const QString outputDirectory = QDir::cleanPath(QString::fromLocal8Bit(argv[3]));
    QDir().mkpath(outputDirectory);

    QQmlApplicationEngine engine;
    auto *context = engine.rootContext();
    context->setContextProperty("demoSourceUrl",
                                QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    context->setContextProperty("demoDepthUrl",
                                QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])));
    context->setContextProperty("demoOutputDirectory", outputDirectory);
    engine.load(qmlUrl);
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
        const QVector2D pointer(std::sin(seconds * 1.1f),
                                std::sin(seconds * 0.73f) * 0.55f);
        window->setProperty("pointer", QVariant::fromValue(pointer));
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
                std::cout << "GPU window frames: " << measuredFrames
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
