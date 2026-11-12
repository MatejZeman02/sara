# The JPEG XL codec for Sara's save, as a GDExtension, with libjxl built into
# it, so a platform ships one library and nothing beside it.
#
#   scripts/fetch_libjxl.sh LIBJXL
#   cmake -S . -B BUILD -DGODOT_CPP=DIR -DLIBJXL=LIBJXL -DCMAKE_BUILD_TYPE=Release
#   cmake --build BUILD --config Release -j 4
#
# GODOT_CPP is a checkout of godot-cpp that has the API of Godot 4.7.
# LIBJXL is the patched libjxl source made by scripts/fetch_libjxl.sh. The
# library lands in OUTPUT_DIR, bin beside sara_jxl.gdextension unless asked
# otherwise.
cmake_minimum_required(VERSION 3.17)
project(sara-jxl LANGUAGES C CXX)

set(GODOT_CPP "" CACHE PATH "godot-cpp checkout")
set(LIBJXL "" CACHE PATH "the libjxl source of scripts/fetch_libjxl.sh")
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin" CACHE PATH "where the library lands")
set(GODOTCPP_API_VERSION 4.7 CACHE STRING "")
add_subdirectory(${GODOT_CPP} godot-cpp)

# libjxl static and position independent, with its bundled highway, brotli
# and skcms, and only the library itself.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
foreach(off TOOLS BENCHMARK EXAMPLES MANPAGES DOXYGEN SJPEG JPEGLI JPEGLI_LIBJPEG OPENEXR JNI PLUGINS VIEWERS FUZZERS DEVTOOLS)
    set(JPEGXL_ENABLE_${off} OFF CACHE BOOL "" FORCE)
endforeach()
# Lean effort 8 (results/jxl-pool-half.md on the main branch): effort 8 takes
# effort 7's grouping, table search and colour transforms, fixed in the build
# rather than read from the environment. The other lean settings are options
# SaJxl::encode_for_save sets.
add_compile_definitions([[JXL_E7_FIXED="cluster,ans,rct"]])
add_subdirectory(${LIBJXL} libjxl EXCLUDE_FROM_ALL)

add_library(sara-jxl SHARED src/sa_jxl.cpp src/register_types.cpp)
target_link_libraries(sara-jxl PRIVATE godot-cpp jxl)
# Keep libjxl's and brotli's symbols inside the library on Linux, where a
# static library's symbols would otherwise be exported and could meet the
# brotli Godot carries for its fonts. A Windows DLL exports none of them.
target_link_options(sara-jxl PRIVATE $<$<PLATFORM_ID:Linux>:LINKER:--exclude-libs,ALL>)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
# The generator expression keeps a multi-configuration generator, Visual
# Studio's, from adding a folder of its own per configuration.
set_target_properties(sara-jxl PROPERTIES
    CXX_STANDARD 17
    CXX_VISIBILITY_PRESET hidden
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    OUTPUT_NAME "sara-jxl${GODOTCPP_SUFFIX}")

# The library is named to Godot only once it is built: sara_jxl.gdextension is
# written at every build, listing what bin/ holds, and is not in the
# repository. A target of its own rather than a step after the link, so a build
# with nothing to relink writes it too.
add_custom_target(sara-jxl-gdextension ALL
    COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/write_gdextension.cmake
    VERBATIM)
add_dependencies(sara-jxl-gdextension sara-jxl)
