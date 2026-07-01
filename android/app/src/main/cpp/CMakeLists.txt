cmake_minimum_required(VERSION 3.22.1)

project(tgchat)

# 优先使用项目根目录下的 llama_cpp 目录（setup 脚本下载位置）
set(LLAMA_ROOT "${CMAKE_SOURCE_DIR}/../../../../../llama_cpp" CACHE PATH "llama.cpp root")

find_library(
    LLAMA_LIB
    llama
    PATHS
        "${LLAMA_ROOT}"
        "${CMAKE_SOURCE_DIR}/../jniLibs/arm64-v8a"
    NO_DEFAULT_PATH
)

find_file(
    LLAMA_HEADER
    llama.h
    PATHS
        "${LLAMA_ROOT}/include"
        "${LLAMA_ROOT}"
    NO_DEFAULT_PATH
)

if(NOT LLAMA_LIB)
    message(FATAL_ERROR "libllama.so not found. Run setup_env.ps1 to download llama.cpp Android binaries.")
endif()

if(NOT LLAMA_HEADER)
    message(FATAL_ERROR "llama.h not found. Run setup_env.ps1 to download llama.cpp headers.")
endif()

get_filename_component(LLAMA_INCLUDE_DIR "${LLAMA_HEADER}" DIRECTORY)

add_library(tgchat SHARED tgchat.cpp)

target_include_directories(tgchat PRIVATE ${LLAMA_INCLUDE_DIR})

target_link_libraries(tgchat ${LLAMA_LIB} log)
