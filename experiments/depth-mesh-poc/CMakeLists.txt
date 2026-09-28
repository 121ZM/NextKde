cmake_minimum_required(VERSION 3.21)
project(depth_mesh_poc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs photo)

add_executable(depth-mesh-poc
    main.cpp
    MeshRenderer.cpp
    ReferenceRenderer.cpp
)
target_link_libraries(depth-mesh-poc PRIVATE ${OpenCV_LIBS})

add_executable(depth-orbit-compare
    orbit_compare.cpp
    ReferenceRenderer.cpp
)
target_link_libraries(depth-orbit-compare PRIVATE ${OpenCV_LIBS})
