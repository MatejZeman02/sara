## The Krita layout opens the Tool Options docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter coming from Krita looks for Tool Options at once and presses
## backslash for it. Krita's own
## default workspace opens one, so the layout that copies that workspace opens
## it too. The file is read here as written for 1920 by 1080, and the fit to
## every other window is `test_a_shipped_layout_fits_its_columns_to_the_window_at_any_ui_scale.gd`'s.
## What the running app opens is `scenarios/the-krita-layout-opens-the-tool-options-docker.json`.
extends "res://tests/test_framework.gd"

const KRITA := "res://layouts/krita.cfg"
const WRITTEN_FOR := Rect2i(0, 79, 1920, 1001)
const LAYERS_FLOOR := 272
const BRUSH_PRESETS_HEIGHT := 300


func _krita() -> ConfigFile:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(KRITA), OK, "the Krita layout reads")
    return cfg


## The sections the file opens.
static func _open(cfg: ConfigFile) -> Array[String]:
    var out: Array[String] = []
    for section: String in cfg.get_sections():
        if not section.begins_with("_") and bool(cfg.get_value(section, "visible", false)):
            out.append(section)
    return out


static func _rect(cfg: ConfigFile, section: String) -> Rect2i:
    return Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))


func test_the_krita_layout_opens_tool_options() -> void:
    assert_true(_open(_krita()).has(String(SaDockerIds.TOOL_OPTIONS)), "Tool Options is among the Krita layout's open dockers")


func test_tool_options_stands_whole_in_the_window_and_over_no_other_open_docker() -> void:
    var cfg := _krita()
    var tool_options := _rect(cfg, String(SaDockerIds.TOOL_OPTIONS))
    assert_true(WRITTEN_FOR.encloses(tool_options), "Tool Options stands whole inside 1920 by 1080 under the bar")
    for section: String in _open(cfg):
        if section != String(SaDockerIds.TOOL_OPTIONS):
            assert_false(tool_options.intersects(_rect(cfg, section)), "Tool Options lies over no part of %s" % section)


func test_the_right_column_keeps_what_the_brush_presets_and_the_layers_need() -> void:
    var cfg := _krita()
    assert_true(_rect(cfg, String(SaDockerIds.BRUSH_PRESETS)).size.y >= BRUSH_PRESETS_HEIGHT, "Brush Presets keeps its 300")
    assert_true(_rect(cfg, String(SaDockerIds.LAYERS)).size.y >= LAYERS_FLOOR, "Layers keeps its 272 floor")
