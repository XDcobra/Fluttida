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

# Add libcurl headers from a stable vendored include location.
# We keep compatibility with previous layouts but avoid hard dependency on ABI-specific copies.
set(CURL_INCLUDE_CANDIDATES
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include/common/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include/arm64-v8a/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include/armeabi-v7a/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/curl/include/x86_64/include"
)

set(CURL_LOCAL_INCLUDE "")
foreach(_curl_include ${CURL_INCLUDE_CANDIDATES})
  if(EXISTS "${_curl_include}/curl/curl.h")
    set(CURL_LOCAL_INCLUDE "${_curl_include}")
    break()
  endif()
endforeach()

if(NOT CURL_LOCAL_INCLUDE STREQUAL "")
  target_include_directories(nativehttp PRIVATE "${CURL_LOCAL_INCLUDE}")
else()
  message(FATAL_ERROR "No vendored libcurl headers found under third_party/curl/include")
endif()

# Export JNI symbols
target_link_libraries(nativehttp ${log-lib} ${android-lib} ${dl-lib})
