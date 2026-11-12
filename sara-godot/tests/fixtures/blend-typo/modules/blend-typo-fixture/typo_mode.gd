## The descriptor the registry turns down: its kernel name is one letter away
## from the one `typo_mode.gmacs` declares.
##
## A plain script read through `preload` rather than a `class_name`, for the
## reason the box blur's kernel files give: a new class name resolves only once
## an editor has rescanned the project, and a fixture is read by a scenario run
## that never does.
##
## SPDX-License-Identifier: GPL-3.0-or-later

## The id a `.sad` would carry and the name the fixture's own module answers to.
const ID: StringName = &"blend_typo_fixture"

## This module's shader, qualified by the folder that owns it. `SaShaderIndex`
## reads a shader's owner off the directory, so this string and the folder name
## have to agree, and `sa_shader_index.gd`'s `resolve_shader_name` says what a
## bare name would cost.
const SHADER: String = "blend-typo-fixture/typo_mode"

## `hard_mix` is what the shader declares. This is the typo.
const KERNEL: String = "hardmix"


static func descriptor() -> SaBlendModeDescriptor:
    var mode := SaBlendModeDescriptor.create(ID, KERNEL, SHADER)
    mode.display_name = "Blend Typo"
    return mode
