#pragma once

#include <QQuick3DGeometry>
#include <QUrl>

class DepthMeshGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(QUrl depthPath READ depthPath WRITE setDepthPath NOTIFY depthPathChanged)
    Q_PROPERTY(float imageZoom READ imageZoom WRITE setImageZoom NOTIFY imageZoomChanged)
    Q_PROPERTY(float focusDistance READ focusDistance NOTIFY focusDistanceChanged)
    Q_PROPERTY(float backgroundDistance READ backgroundDistance NOTIFY backgroundDistanceChanged)

public:
    explicit DepthMeshGeometry(QQuick3DObject *parent = nullptr);
    QUrl depthPath() const { return m_depthPath; }
    float imageZoom() const { return m_imageZoom; }
    float focusDistance() const { return m_focusDistance; }
    float backgroundDistance() const { return m_backgroundDistance; }
    void setDepthPath(const QUrl &path);
    void setImageZoom(float zoom);

signals:
    void depthPathChanged();
    void imageZoomChanged();
    void focusDistanceChanged();
    void backgroundDistanceChanged();

private:
    void rebuild();
    QUrl m_depthPath;
    float m_imageZoom = 1.16f;
    float m_focusDistance = 2.5f;
    float m_backgroundDistance = 4.0f;
};
