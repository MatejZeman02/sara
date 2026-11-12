# Text layers, the first milestone of the text spec: point text in one font.
#
# **This file is the folder's registration**, through the door a third party
# uses: the text layer as a drawn type whose recipe is `sa_text_recipe.gd`, the
# Text tool with its Font and Size rows, and the door's `text` and `font` steps
# as three roles the harness asks for by name, so the harness names no module.
#
# Every script is reached by a path beside this file and not by a class name,
# since a class name is global and a copy of this folder would clash with it.
#
# SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const Recipe := preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const StateText := preload("res://modules/sara-base-modules/text/edit/state_text.gd")
const Session := preload("res://modules/sara-base-modules/text/edit/sa_text_session.gd")
const Fonts := preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")
const Door := preload("res://modules/sara-base-modules/text/door/sa_text_door.gd")

const TOOL := &"text"
const ICON := "res://modules/sara-base-modules/text/icons/text.svg"


func get_id() -> StringName:
    return &"text"


func get_name() -> String:
    return "Text"


func register(ctx: SaContext) -> void:
    ctx.register_layer_type(descriptor())
    var tool := SaToolDescriptor.create(TOOL, StateText)
    tool.display_name = "Text"
    tool.icon_name = ICON
    tool.category = &"paint"
    tool.cursor_shape = Control.CURSOR_IBEAM
    tool.activate_action = &"tool_text"
    tool.options = options()
    ctx.register_tool(tool)
    ctx.register_role(&"text_step", Door)
    ctx.register_role(&"font_step", Door)
    ctx.register_role(&"text_edit_step", Door)


## The text layer as Add Layer and a `.sad` know it, a drawn layer whose
## pixels are its block's glyphs.
static func descriptor() -> SaLayerTypeDescriptor:
    var made := SaLayerTypeDescriptor.drawn_layer(Session.TYPE, Recipe)
    made.display_name = "Text"
    made.icon_name = ICON
    made.hint = "Letters drawn from their outlines, typed with the Text tool and sharp at any size."
    return made


## The Text tool's two rows: the family a new block is set in, one of the
## three Sara ships, and its size in pixels an em. Both reach the block in hand
## as they move.
static func options() -> Array[SaOptionSpec]:
    var ids: Array = []
    for i in Fonts.SHIPPED.size():
        ids.append(i)
    var font := (
        SaOptionSpec
        . make_enum(
            &"text_font",
            "Font",
            ids,
            Fonts.SHIPPED.keys(),
            {
                "on_tool": true,
                "panel_also": true,
                "property": ^"font_choice",
                "width": 132,
                "tooltip": "The family the text is set in.",
            }
        )
    )
    var size := (
        SaOptionSpec
        . make_float(
            &"text_size",
            "Size",
            4.0,
            2000.0,
            1.0,
            {
                "on_tool": true,
                "panel_also": true,
                "property": ^"font_size",
                "soft_max": 400.0,
                "logarithmic": true,
                "decimals": 0,
                "trim_trailing_zeros": true,
                "tooltip": "The size of an em in document pixels.",
            }
        )
    )
    return [font, size]
