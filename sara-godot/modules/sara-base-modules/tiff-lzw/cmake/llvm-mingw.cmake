# Builds the Windows library on Linux with llvm-mingw
# (https://github.com/mstorsjo/llvm-mingw), whose bin folder must be on PATH.
# Everything links statically, the C++ runtime included, so the library needs
# no DLL beside it.
#
#   PATH=LLVM_MINGW/bin:$PATH cmake -S . -B BUILD \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/llvm-mingw.cmake ...
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-static")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
