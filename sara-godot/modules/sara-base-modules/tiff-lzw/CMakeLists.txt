# The LZW unpacker of SaTiffUnpacker and the sample passes of SaTiffReader as a
# GDExtension, the TIFF reader's native half, with no library but godot-cpp.
#
#   cmake -S . -B BUILD -DGODOT_CPP=DIR -DCMAKE_BUILD_TYPE=Release
#   cmake --build BUILD --config Release -j 4
#
# GODOT_CPP is a checkout of godot-cpp that has the API of Godot 4.7. The
# library lands in OUTPUT_DIR, bin beside sara_tiff_lzw.gdextension unless asked
# otherwise. packaging/build.sh of sara-skeleton runs this for Linux and, with
# cmake/llvm-mingw.cmake, for Windows.
cmake_minimum_required(VERSION 3.17)
project(sara-tiff-lzw LANGUAGES C CXX)

set(GODOT_CPP "" CACHE PATH "godot-cpp checkout")
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin" CACHE PATH "where the library lands")
set(GODOTCPP_API_VERSION 4.7 CACHE STRING "")
add_subdirectory(${GODOT_CPP} godot-cpp)

add_library(sara-tiff-lzw SHARED src/sa_tiff_lzw.cpp src/sa_tiff_samples.cpp src/register_types.cpp)
target_link_libraries(sara-tiff-lzw PRIVATE godot-cpp)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(sara-tiff-lzw PROPERTIES
    CXX_STANDARD 17
    CXX_VISIBILITY_PRESET hidden
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    OUTPUT_NAME "sara-tiff-lzw${GODOTCPP_SUFFIX}")

# The library is named to Godot only once it is built, as sara-jxl's is:
# sara_tiff_lzw.gdextension is written at every build, listing what bin/ holds,
# and is not in the repository.
add_custom_target(sara-tiff-lzw-gdextension ALL
    COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/write_gdextension.cmake
    VERBATIM)
add_dependencies(sara-tiff-lzw-gdextension sara-tiff-lzw)
