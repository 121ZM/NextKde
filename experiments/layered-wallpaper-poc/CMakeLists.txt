cmake_minimum_required(VERSION 3.21)
project(layered_wallpaper_poc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

add_executable(layered-wallpaper-poc main.cpp)
target_link_libraries(layered-wallpaper-poc PRIVATE ${OpenCV_LIBS})
