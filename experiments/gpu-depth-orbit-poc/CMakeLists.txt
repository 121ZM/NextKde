cmake_minimum_required(VERSION 3.21)
project(gpu_depth_orbit_poc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
find_program(QSB_EXECUTABLE qsb HINTS /usr/lib/qt6/bin REQUIRED)

set(SHADER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shaders)
foreach(STAGE vert frag)
    add_custom_command(
        OUTPUT ${SHADER_DIR}/depth_orbit.${STAGE}.qsb
        COMMAND ${QSB_EXECUTABLE} --qt6
                -o ${SHADER_DIR}/depth_orbit.${STAGE}.qsb
                ${SHADER_DIR}/depth_orbit.${STAGE}
        DEPENDS ${SHADER_DIR}/depth_orbit.${STAGE}
        VERBATIM)
endforeach()
add_custom_target(gpu-depth-orbit-shaders DEPENDS
    ${SHADER_DIR}/depth_orbit.vert.qsb
    ${SHADER_DIR}/depth_orbit.frag.qsb)

add_executable(gpu-depth-orbit-poc main.cpp)
add_dependencies(gpu-depth-orbit-poc gpu-depth-orbit-shaders)
target_link_libraries(gpu-depth-orbit-poc PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
target_compile_definitions(gpu-depth-orbit-poc PRIVATE
    GPU_DEPTH_ORBIT_QML_PATH="${CMAKE_CURRENT_SOURCE_DIR}/Main.qml")
