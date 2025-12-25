cmake_minimum_required(VERSION 3.10)
project(nativehttp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(nativehttp SHARED native_http.cpp)

find_library(log-lib log)
find_library(android-lib android)

# Link to libdl for dlopen/dlsym at runtime
find_library(dl-lib dl)
if(NOT dl-lib)
  # On some NDKs, dl is part of libc; still link target
  set(dl-lib dl)
endif()

# Add libcurl headers (per-ABI) that we vendor into the repo under third_party/curl/include/<abi>/include
# Use CMAKE_CURRENT_SOURCE_DIR to anchor at android/app/src/main/cpp
set(CURL_LOCAL_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include/${ANDROID_ABI}/include")
if(EXISTS "${CURL_LOCAL_INCLUDE}")
  target_include_directories(nativehttp PRIVATE "${CURL_LOCAL_INCLUDE}")
else()
  message(WARNING "libcurl include path not found: ${CURL_LOCAL_INCLUDE}")
endif()

# Export JNI symbols
target_link_libraries(nativehttp ${log-lib} ${android-lib} ${dl-lib})
