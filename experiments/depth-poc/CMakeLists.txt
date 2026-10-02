cmake_minimum_required(VERSION 3.21)
project(depth_poc LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)
find_package(OpenSSL REQUIRED COMPONENTS Crypto)

set(ORT_ROOT "" CACHE PATH "Extracted ONNX Runtime C++ release directory")
if(NOT EXISTS "${ORT_ROOT}/include/onnxruntime_cxx_api.h")
    message(FATAL_ERROR "Set ORT_ROOT to an extracted ONNX Runtime release")
endif()

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${ORT_ROOT}/lib/libonnxruntime.so"
    INTERFACE_INCLUDE_DIRECTORIES "${ORT_ROOT}/include")

add_executable(depth-poc main.cpp)
target_link_libraries(depth-poc PRIVATE onnxruntime ${OpenCV_LIBS} OpenSSL::Crypto)
set_target_properties(depth-poc PROPERTIES BUILD_RPATH "${ORT_ROOT}/lib")
