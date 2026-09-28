import QtQuick
import QtQuick.Window
import QtQuick3D
import DepthOrbit 1.0

Window {
    id: root
    width: 1600
    height: 900
    visible: true
    color: "#15171a"
    title: "Qt Quick 3D depth orbit prototype"
    property vector2d pointer: Qt.vector2d(0, 0)
    property real focusDistance: depthGeometry.focusDistance
    readonly property real focusZ: -focusDistance
    readonly property real cameraRadius: focusDistance
    readonly property real imageZoom: 1.16
    readonly property real backgroundCoverage: imageZoom

    View3D {
        id: view
        anchors.fill: parent
        camera: camera
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: root.color
        }

        PerspectiveCamera {
            id: camera
            fieldOfView: 42
            fieldOfViewOrientation: PerspectiveCamera.Vertical
            clipNear: 0.01
            clipFar: 100
            position: Qt.vector3d(0, 0, 0)
            Component.onCompleted: lookAt(Qt.vector3d(0, 0, root.focusZ))
        }

        Model {
            id: sceneBackground
            visible: demoBackgroundUrl !== ""
            position: Qt.vector3d(0, 0, -depthGeometry.backgroundDistance)
            source: "#Rectangle"
            scale: Qt.vector3d(
                root.backgroundCoverage * 2.0 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) * 16 / 9 / 100,
                root.backgroundCoverage * 2.0 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) / 100, 1)
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                cullMode: Material.NoCulling
                diffuseMap: Texture {
                    source: demoBackgroundUrl
                    minFilter: Texture.Linear
                    magFilter: Texture.Linear
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                }
            }
        }

        Model {
            id: wallpaperMesh
            geometry: DepthMeshGeometry {
                id: depthGeometry
                depthPath: demoDepthUrl
                imageZoom: root.imageZoom
            }
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                cullMode: Material.NoCulling
                diffuseMap: Texture {
                    source: demoSourceUrl
                    minFilter: Texture.Linear
                    magFilter: Texture.Linear
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                }
            }
        }
    }

    function updateCamera() {
        const tilt = pointer.length() > 1 ? pointer.normalized() : pointer
        const yaw = tilt.x * Math.PI * 4 / 180
        const pitch = -tilt.y * Math.PI * 3 / 180
        const r = cameraRadius
        camera.position = Qt.vector3d(Math.sin(yaw) * Math.cos(pitch) * r,
            Math.sin(pitch) * r,
            focusZ + Math.cos(yaw) * Math.cos(pitch) * r)
        camera.lookAt(Qt.vector3d(0, 0, focusZ))
    }
    onPointerChanged: updateCamera()
    onFocusDistanceChanged: updateCamera()
}
