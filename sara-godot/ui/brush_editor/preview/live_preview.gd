## The brush editor's live preview strip: a rendered stroke, drawn again when its
## `SaPreviewCompressor` says so.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own, and it carries no provenance block: the stroke it draws is
## Sara's, and the idea of a live preview is all it shares with Krita's.
##
## Its own file rather than a block of `brush_editor_window.gd`, because the
## strip owns what it draws and how often. The rule for how often is
## `SaPreviewCompressor`'s, because the tip preview needs the same rule and a
## copy would be two rules.
class_name SaBrushPreviewStrip
extends TextureRect

## What the run has drawn, for a dump. The compressor's whole claim is a number,
## and a screenshot of a stroke cannot say how many times it was drawn.
var renders: int = 0

## The rule that decides when the strip draws. Read from outside for its
## `coalesced` and `pending`, which a dump and a test report.
var compressor: SaPreviewCompressor = null

var _tool_script: Script = null
var _settings: Resource = null


func _init() -> void:
    name = "LivePreviewImage"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    stretch_mode = TextureRect.STRETCH_SCALE
    compressor = SaPreviewCompressor.new(_render)
    add_child(compressor)


## What the strip draws from. The settings object is held rather than copied, so
## every later request reads whatever the painter has done to it since.
func bind_source(tool_script: Script, brush_settings: Resource) -> void:
    _tool_script = tool_script
    _settings = brush_settings


## Asks for a new stroke. Cheap to call from every signal that can change what
## the brush does.
func request() -> void:
    compressor.request()


## Draws the strip from the settings as they are now, whatever the compressor
## would have said. What a test and a scenario ask for.
func render_now() -> void:
    compressor.draw_now()


func _render() -> void:
    if _tool_script == null or _settings == null:
        return
    var image := SaPresetThumbs.render(_tool_script, _settings, SaPresetThumbs.PREVIEW_SIZE)
    if image != null:
        texture = ImageTexture.create_from_image(image)
        renders += 1
