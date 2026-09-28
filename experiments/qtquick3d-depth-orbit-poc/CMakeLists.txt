cmake_minimum_required(VERSION 3.21)
project(qtquick3d_depth_orbit_poc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick Quick3D)
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

add_executable(qtquick3d-depth-orbit-poc
    main.cpp
    DepthMeshGeometry.cpp
    DepthMeshGeometry.h)
target_link_libraries(qtquick3d-depth-orbit-poc PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Quick3D ${OpenCV_LIBS})
target_compile_definitions(qtquick3d-depth-orbit-poc PRIVATE
    QTQUICK3D_ORBIT_QML_PATH="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
