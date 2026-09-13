cmake_minimum_required(VERSION 3.20)
project(x4_barrel_orientation_probe LANGUAGES CXX)

if(NOT X4NATIVE_SDK)
    message(FATAL_ERROR "Set X4NATIVE_SDK to the local X4Native sdk directory")
endif()

add_library(x4_barrel_orientation_probe SHARED probe.cpp)
target_compile_features(x4_barrel_orientation_probe PRIVATE cxx_std_17)
target_include_directories(x4_barrel_orientation_probe PRIVATE "${X4NATIVE_SDK}")
target_link_libraries(x4_barrel_orientation_probe PRIVATE bcrypt)
set_target_properties(x4_barrel_orientation_probe PROPERTIES PREFIX "")
