import QtQuick
import QtQuick.Window

Window {
    id: root
    width: 1600
    height: 900
    visible: true
    color: "#181a1d"
    title: "GPU depth orbit prototype"
    property vector2d pointer: Qt.vector2d(0, 0)

    Image {
        id: sourceImage
        source: demoSourceUrl
        visible: false
        asynchronous: false
        cache: false
    }
    Image {
        id: depthImage
        source: demoDepthUrl
        visible: false
        asynchronous: false
        cache: false
    }

    ShaderEffect {
        anchors.fill: parent
        mesh: Qt.size(320, 180)
        cullMode: ShaderEffect.NoCulling
        property variant source: sourceImage
        property variant depthMap: depthImage
        property vector2d pointer: root.pointer
        property vector2d viewSize: Qt.vector2d(width, height)
        property real depthSpan: 1.3
        property real farDistance: 3.3
        property real orbitYaw: 4.0
        property real orbitPitch: 3.0
        vertexShader: Qt.resolvedUrl("shaders/depth_orbit.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/depth_orbit.frag.qsb")
    }
}
