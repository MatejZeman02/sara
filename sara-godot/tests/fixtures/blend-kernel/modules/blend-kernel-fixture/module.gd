## A module whose one registration is a blend mode with a kernel of its own,
## `kept_hard_mix.gmacs` beside this file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Hard Mix proved this door while it was a module, and became one of the
## skeleton's modes once it had. This fixture keeps the door proven: a mode
## whose shader is not `composite` is resolved in the module's own file and
## composited by it. In a root of its own so no scenario loading
## `res://tests/fixtures/modules` gains a blend mode it did not ask for. The id
## is the directory name, because the shader index files the kernel under it.
extends SaModule

## The id a layer would carry.
const MODE_ID: StringName = &"kept_hard_mix"

## The module's shader, qualified by the folder that owns it, which
## `SaShaderIndex` reads off the directory.
const SHADER: String = "blend-kernel-fixture/kept_hard_mix"

const KERNEL: String = "kept_hard_mix"


func get_id() -> StringName:
    return &"blend-kernel-fixture"


func get_name() -> String:
    return "Blend Kernel Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_blend_mode(descriptor())


## The mode as a module declares it: a display-referred formula filed under
## Contrast, after the skeleton's Hard Mix.
static func descriptor() -> SaBlendModeDescriptor:
    var mode := SaBlendModeDescriptor.create(MODE_ID, KERNEL, SHADER)
    mode.display_name = "Kept Hard Mix"
    mode.domain = SaBlendModeDescriptor.Domain.DISPLAY_REFERRED
    mode.category = &"contrast"
    mode.sort_order = 96
    return mode
