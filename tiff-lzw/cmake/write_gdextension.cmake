# Writes sara_tiff_lzw.gdextension, the file Godot loads the library by, naming
# only the libraries bin/ holds. It is written by the build and never
# committed, because Godot prints errors at each launch for an extension whose
# library is missing. With the file absent Godot loads nothing, and
# SaTiffUnpacker unpacks LZW in its GDScript.
#
#   cmake -DMODULE_DIR=DIR -P cmake/write_gdextension.cmake
set(libraries "")
foreach(platform linux windows)
    if(platform STREQUAL linux)
        set(file "libsara-tiff-lzw.linux.template_release.x86_64.so")
    else()
        set(file "libsara-tiff-lzw.windows.template_release.x86_64.dll")
    endif()
    if(EXISTS "${MODULE_DIR}/bin/${file}")
        string(APPEND libraries "${platform}.x86_64 = \"bin/${file}\"\n")
    endif()
endforeach()
set(target "${MODULE_DIR}/sara_tiff_lzw.gdextension")
if(libraries STREQUAL "")
    file(REMOVE "${target}")
    return()
endif()
set(text "[configuration]\n\nentry_symbol = \"sara_tiff_lzw_init\"\ncompatibility_minimum = \"4.7\"\n\n[libraries]\n\n${libraries}")
# Rewritten only when it changes, so a build that adds nothing leaves Godot's
# import of the file alone.
if(EXISTS "${target}")
    file(READ "${target}" held)
    if(held STREQUAL text)
        return()
    endif()
endif()
file(WRITE "${target}" "${text}")
