#include "surfaceshape.h"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class SurfaceShapePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<SurfaceShape>(uri, 1, 0, "SurfaceShape");
    }
};

#include "surfaceshapeplugin.moc"
