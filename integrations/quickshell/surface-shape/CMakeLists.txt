cmake_minimum_required(VERSION 3.21)

# The protocol shim below is a C source, and KOS is a C++-only project.  CMake
# will happily accept a ".c" file into a target whose language is not enabled,
# then quietly never build it: the plugin links, the wl_interface stays
# undefined, and dlopen reports "undefined symbol" only at run time.  Enabling C
# here -- in the directory that owns the source, not in the root project -- is
# what makes the shim real.
enable_language(C)

find_package(ECM REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
find_package(WaylandScanner REQUIRED)
find_package(Wayland REQUIRED COMPONENTS Client)
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui GuiPrivate Qml Quick WaylandClient)

set(protocol_sources)
ecm_add_wayland_client_protocol(protocol_sources
    PROTOCOL "${CMAKE_SOURCE_DIR}/protocols/kos-surface-shape-v1.xml"
    BASENAME kos-surface-shape-v1)

add_library(kos_surface_shape MODULE
    cursoroverride.cpp
    surfaceshape.cpp
    surfaceshapeplugin.cpp
    ${protocol_sources}
)
target_link_libraries(kos_surface_shape PRIVATE
    Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::Qml Qt6::Quick
    Qt6::WaylandClient Wayland::Client)
set_target_properties(kos_surface_shape PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Kos/SurfaceShape")

configure_file(qmldir "${CMAKE_BINARY_DIR}/qml/Kos/SurfaceShape/qmldir" COPYONLY)

# KDE_INSTALL_QMLDIR resolves to <prefix>/lib/qml, which is not a path Qt
# searches: QT_INSTALL_QML is <prefix>/lib/qt6/qml, and every module on the
# system -- KWin's own org/kde/kwin included -- lives there. Installing into
# lib/qml would leave the module unreachable unless every launcher exported
# QML2_IMPORT_PATH, so the shell would fail on the installed path while the
# source tree (which kosctl points at the build dir) kept working.
install(TARGETS kos_surface_shape
    DESTINATION ${QT6_INSTALL_QML}/Kos/SurfaceShape
    COMPONENT kwin_plugins)
install(FILES qmldir
    DESTINATION ${QT6_INSTALL_QML}/Kos/SurfaceShape
    COMPONENT kwin_plugins)
