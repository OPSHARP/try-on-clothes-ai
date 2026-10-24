# CMake configuration for API Key Provider native library
cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project("api_key_provider")

# Create the shared library
add_library(
    api_key_provider
    SHARED
    api_key_provider.cpp
)

# Include headers
target_include_directories(
    api_key_provider
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Link required libraries
target_link_libraries(
    api_key_provider
    android
    log
)

# Use C++17
set_target_properties(
    api_key_provider
    PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# 16KB page size alignment for Android 15 & 16 (API 35/36) Google Play requirement
target_link_options(
    api_key_provider
    PRIVATE
    "-Wl,-z,max-page-size=16384"
)
