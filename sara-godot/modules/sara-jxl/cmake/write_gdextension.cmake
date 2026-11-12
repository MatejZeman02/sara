# Writes sara_jxl.gdextension, the file Godot loads the module by, naming only
# the libraries bin/ holds. It is written by the build and never committed:
# Godot names an extension it found in every later run, and one whose library
# is missing prints three errors at each launch, so a checkout that never built
# the module, or a platform it was not built for, must not have a file that
# names one. With the file absent Godot loads nothing, and the module's
# module.gd registers nothing and says nothing.
#
#   cmake -DMODULE_DIR=DIR -P cmake/write_gdextension.cmake
set(libraries "")
foreach(platform linux windows)
    if(platform STREQUAL linux)
        set(file "libsara-jxl.linux.template_release.x86_64.so")
    else()
        set(file "libsara-jxl.windows.template_release.x86_64.dll")
    endif()
    if(EXISTS "${MODULE_DIR}/bin/${file}")
        string(APPEND libraries "${platform}.x86_64 = \"bin/${file}\"\n")
    endif()
endforeach()
set(target "${MODULE_DIR}/sara_jxl.gdextension")
if(libraries STREQUAL "")
    file(REMOVE "${target}")
    return()
endif()
set(text "[configuration]\n\nentry_symbol = \"sara_jxl_init\"\ncompatibility_minimum = \"4.7\"\n\n[libraries]\n\n${libraries}")
# Rewritten only when it changes, so a build that adds nothing leaves Godot's
# import of the file alone.
if(EXISTS "${target}")
    file(READ "${target}" held)
    if(held STREQUAL text)
        return()
    endif()
endif()
file(WRITE "${target}" "${text}")
