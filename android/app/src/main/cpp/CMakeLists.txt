cmake_minimum_required(VERSION 3.22.1)

# whisper.cpp is far too slow unoptimized, so always build it as Release,
# including for `flutter run` debug builds.
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)

project(breeze_whisper C CXX)

include(FetchContent)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
if(ANDROID_ABI STREQUAL "arm64-v8a")
  # Dot-product and fp16 instructions (ARMv8.2, phones from ~2018 on) make
  # quantized models several times faster.
  set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()

FetchContent_Declare(
  whisper
  GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
  GIT_TAG v1.9.5
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(whisper)

add_library(breeze_whisper SHARED breeze_whisper.cpp)
target_link_libraries(breeze_whisper PRIVATE whisper)
if(ANDROID)
  target_link_libraries(breeze_whisper PRIVATE log)
endif()
