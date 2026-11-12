## The JPEG XL module: registers the codec `jxl`, which a save asks for by name
## through the door's `codecs`, and never names the library itself.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The library is `SaJxl`, the GDExtension of this folder, which Godot loads by
## `sara_jxl.gdextension` before any script runs. When the class is not there
## the module registers nothing, so Sara saves and opens as it does without it.
## The module itself says nothing either way. The loader does: when the list
## names a library for this platform and Godot did not load it, an install that
## left the file behind or a build that dropped it, the start shows one problem
## naming the module and the file. A platform the build wrote no line for,
## Android among them, or a checkout that never built the library and so has
## no list, is silent. It is called through `ClassDB` by name for the same
## reason: a script that named the class would not parse without the library.
extends SaModule

## What a save asks for the codec by.
const CODEC := &"jxl"
## The GDExtension class, asked for by name.
const LIBRARY := &"SaJxl"


func get_id() -> StringName:
    return &"jpeg_xl"


func get_name() -> String:
    return "JPEG XL"


func register(ctx: SaContext) -> void:
    if not ClassDB.class_exists(LIBRARY):
        return
    ctx.codecs.register(CODEC, _encode, _decode)


## One field of one chunk coded lossless at the save's setting, which
## `encode_for_save` fixes, never `encode`'s own arguments.
static func _encode(texels: PackedByteArray, width: int, height: int, channels: int, bytes_per_channel: int) -> PackedByteArray:
    return ClassDB.class_call_static(LIBRARY, &"encode_for_save", texels, width, height, channels, bytes_per_channel)


## The texels of *stream*, or an empty array when it is not that picture.
static func _decode(stream: PackedByteArray, width: int, height: int, channels: int, bytes_per_channel: int) -> PackedByteArray:
    return ClassDB.class_call_static(LIBRARY, &"decode", stream, width, height, channels, bytes_per_channel)
