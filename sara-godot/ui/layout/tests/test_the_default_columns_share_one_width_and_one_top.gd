## The default columns share one width and one top.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The left column's right edges must not differ (380, 370 and 452 were once
## measured), nor its tops (78, 90 and 80), nor the right column's left edges
## (1631 and 1600). The edges can differ through numbers in the files, such as
## a Brush Presets 310 wide beside Tool Options and Reference at 300, or through
## a docker's own minimum: the Reference's buttons stand in one row whose
## minimum must not be wider than the 300 its layout gives it, since a docker is
## never narrower than its column.
##
## The five files are the four shipped layouts and the one a fresh profile reads,
## all written for 1920 by 1080 and fitted to the window by `SaDockerLayoutFit`,
## so the numbers here are the files' and the fit is `test_the_default_layout_fits_the_screen.gd`'s.
## What the running app opens is `scenarios/the-default-columns-share-one-width-and-one-top.json`.
extends "res://tests/test_framework.gd"

## Where the left column stands and how wide it is, beside the Toolbox's 60.
const LEFT_X := 70
## The default layout (and the file a fresh profile reads) butts its left column
## against the Toolbox, so its edge is the Toolbox's 60 wide and no gap.
const BUTTED_LEFT_X := 60
## Where the right column stands, ending 10 short of 1920.
const RIGHT_X := 1600
## The one width both columns share, the Brush Presets' and the Layers', three of the presets' 72 pixel tiles and their margins.
const COLUMN_WIDTH := 310
## The one top: the Toolbox's, the row `MainDockers.below_bar` keeps every
## docker under while the bar's second row is on, as a fresh profile has it. A top
## of 78, the row under the one-row bar, would open every column a pixel lower
## than the files say.
const TOP := 79

## The dockers that stand in the left column in one layout or another. Every
## layout has Brush Presets at its head and the Minimap in the middle beside
## Info, except the default, whose Brush Presets stands under the Tool Options,
## which heads the column there.
const LEFT_COLUMN: Array[StringName] = [SaDockerIds.BRUSH_PRESETS, SaDockerIds.TOOL_OPTIONS, SaDockerIds.REFERENCE]
const RIGHT_COLUMN: Array[StringName] = [SaDockerIds.COLOR, SaDockerIds.LAYERS]
## Clip Studio Paint's layout keeps the Colour Picker at the
## foot of the left column, where its Color Wheel stands, and the Minimap over
## the Layers on the right, where its Navigator does.
const CLIP_STUDIO_LEFT: Array[StringName] = [
    SaDockerIds.BRUSH_PRESETS, SaDockerIds.TOOL_OPTIONS, SaDockerIds.REFERENCE, SaDockerIds.COLOR
]
const CLIP_STUDIO_RIGHT: Array[StringName] = [SaDockerIds.MINIMAP, SaDockerIds.LAYERS]

## The tops that must be one wherever they appear, and the two that open beside
## them in the middle of useful and full, whose 90 would read as a step down
## from the columns either side.
const FIRST_ROW: Array[StringName] = [
    SaDockerIds.TOOLBOX, SaDockerIds.BRUSH_PRESETS, SaDockerIds.COLOR, SaDockerIds.INFO, SaDockerIds.RECORDER
]


## The eight files, each read once.
func _files() -> Dictionary:
    var paths: Array[String] = [DockerLayoutStore.SHIPPED_DEFAULTS]
    for preset_name: String in SaDockerLayoutPresets.SHIPPED:
        paths.append(SaDockerLayoutPresets.SHIPPED_DIR.path_join(preset_name + ".cfg"))
    var out: Dictionary = {}
    for path: String in paths:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        out[path] = cfg
    assert_eq(out.size(), 9, "the eight shipped layouts and the one a fresh profile reads")
    return out


func _rect(cfg: ConfigFile, section: StringName) -> Rect2i:
    return Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))


## The dockers of *column* a file opens, in the order the column lists them.
func _open_in(cfg: ConfigFile, column: Array[StringName]) -> Array[StringName]:
    var out: Array[StringName] = []
    for section: StringName in column:
        if cfg.has_section(section) and bool(cfg.get_value(section, "visible", false)):
            out.append(section)
    return out


## Minimalistic opens nothing in the left column, which holds by having nothing
## in it, and the right column is open in all five.
func test_each_column_of_each_file_shares_one_edge_and_one_width() -> void:
    var files := _files()
    for path: String in files:
        var cfg: ConfigFile = files[path]
        assert_false(_open_in(cfg, _right_of(path)).is_empty(), "%s opens the right column" % path)
        var left_x := BUTTED_LEFT_X if _butts_its_dockers(path) else LEFT_X
        for pair: Array in [[_left_of(path), left_x], [_right_of(path), RIGHT_X]]:
            for section: StringName in _open_in(cfg, pair[0]):
                var rect := _rect(cfg, section)
                # Krita's and Photoshop's layouts stand the
                # left column's dockers in the right column, at its edge.
                var edges := [int(pair[1]), RIGHT_X] if pair[1] == left_x and _all_on_the_right(path) else [int(pair[1])]
                assert_true(edges.has(rect.position.x), "%s in %s stands at the column's edge" % [section, path])
                assert_eq(rect.size.x, COLUMN_WIDTH, "%s in %s is the column's width" % [section, path])


## Whether *path* is a file that stands its dockers edge to edge, the default.
static func _butts_its_dockers(path: String) -> bool:
    return path == DockerLayoutStore.SHIPPED_DEFAULTS or path.get_file() == "default.cfg"


## Whether *path* is one of the layouts that keep every docker but the
## Toolbox in the right column, as Krita, Photoshop and Procreate do.
static func _all_on_the_right(path: String) -> bool:
    return path.get_file() in ["krita.cfg", "photoshop.cfg", "procreate.cfg"]


## The left column of *path*, Clip Studio Paint's own or the one the others share.
static func _left_of(path: String) -> Array[StringName]:
    return CLIP_STUDIO_LEFT if path.get_file() == "clip_studio.cfg" else LEFT_COLUMN


## The right column of *path*, as [method _left_of] reads the left.
static func _right_of(path: String) -> Array[StringName]:
    return CLIP_STUDIO_RIGHT if path.get_file() == "clip_studio.cfg" else RIGHT_COLUMN


## The right column ends where it did, 10 short of the right edge, so the width
## it gained went to the left and the Layers docker did not move.
func test_the_right_column_ends_10_short_of_the_edge_it_was_written_for() -> void:
    var files := _files()
    for path: String in files:
        var cfg: ConfigFile = files[path]
        for section: StringName in _open_in(cfg, _right_of(path)):
            assert_eq(_rect(cfg, section).end.x, 1910, "%s in %s ends at 1910" % [section, path])


## Whether *cfg* stands its Brush Presets below an open Tool Options, which is
## where the default keeps it instead of in the first row.
func _under_the_tool_options(cfg: ConfigFile) -> bool:
    if not cfg.has_section(SaDockerIds.TOOL_OPTIONS) or not bool(cfg.get_value(SaDockerIds.TOOL_OPTIONS, "visible", false)):
        return false
    return _rect(cfg, SaDockerIds.TOOL_OPTIONS).end.y <= _rect(cfg, SaDockerIds.BRUSH_PRESETS).position.y


## Whether *cfg* opens the Minimap at the right column's x, above the Colour
## Picker, which is where the default and Useful put it.
func _minimap_heads_the_right_column(cfg: ConfigFile) -> bool:
    if not cfg.has_section(SaDockerIds.MINIMAP) or not cfg.has_section(SaDockerIds.COLOR):
        return false
    if not bool(cfg.get_value(SaDockerIds.MINIMAP, "visible", false)):
        return false
    var minimap := _rect(cfg, SaDockerIds.MINIMAP)
    return minimap.position.x == RIGHT_X and minimap.end.y <= _rect(cfg, SaDockerIds.COLOR).position.y


func test_the_first_row_and_each_columns_head_share_one_top() -> void:
    var files := _files()
    for path: String in files:
        var cfg: ConfigFile = files[path]
        for section: StringName in FIRST_ROW:
            # The default keeps its Brush Presets under the Tool Options, at the
            # column's foot rather than its head, and opens it there. A file that puts it anywhere else
            # still answers for the one top.
            var kept_below := section == SaDockerIds.BRUSH_PRESETS and _under_the_tool_options(cfg)
            # Krita's and Photoshop's stand it under the Colour Picker, open or
            # closed, so the right column's head answers for the top there.
            kept_below = kept_below or (section == SaDockerIds.BRUSH_PRESETS and _all_on_the_right(path))
            # Clip Studio Paint's stands the Colour Picker at the left column's
            # foot, so the Brush Presets at its head answers for the top there.
            kept_below = kept_below or (section == SaDockerIds.COLOR and path.get_file() == "clip_studio.cfg")
            # The Minimap heads the right column in the default and Useful, 180
            # tall, so the Colour Picker stands under it and the Minimap answers
            # for the top there.
            kept_below = kept_below or (section == SaDockerIds.COLOR and _minimap_heads_the_right_column(cfg))
            if cfg.has_section(section) and not kept_below:
                assert_eq(_rect(cfg, section).position.y, TOP, "%s in %s is at the one top" % [section, path])
        for column: Array[StringName] in [_left_of(path), _right_of(path)]:
            var open := _open_in(cfg, column)
            if column == LEFT_COLUMN and _all_on_the_right(path):
                open.append_array(_open_in(cfg, RIGHT_COLUMN))
            if column == _right_of(path) and _minimap_heads_the_right_column(cfg):
                open.append(SaDockerIds.MINIMAP)
            if open.is_empty():
                continue
            var head := _rect(cfg, open[0]).position.y
            for section: StringName in open:
                head = mini(head, _rect(cfg, section).position.y)
            assert_eq(head, TOP, "the column of %s in %s starts at the one top" % [column, path])


## Nothing the columns gained reaches another docker, the hidden ones included,
## since the Window menu shows a hidden docker where its file puts it.
func test_the_wider_columns_cover_no_other_docker() -> void:
    var files := _files()
    for path: String in files:
        var cfg: ConfigFile = files[path]
        var sections: Array[String] = []
        for section: String in cfg.get_sections():
            if not section.begins_with("_"):
                sections.append(section)
        for i in sections.size():
            for j in range(i + 1, sections.size()):
                var a := _rect(cfg, sections[i])
                var b := _rect(cfg, sections[j])
                assert_false(a.intersects(b), "%s and %s overlap in %s" % [sections[i], sections[j], path])


## The Reference's buttons wrap rather than set the docker's floor, so the
## column's width is the one the docker opens at.
func test_the_references_minimum_fits_the_column_at_scale_1() -> void:
    assert_eq(SaSettings.ui_scale, 1.0, "measured at scale 1")
    var host := Node.new()
    var docker := ReferenceDocker.new()
    host.add_child(docker)
    var row := docker.find_child("ButtonRow", true, false)
    assert_true(row.get_parent() is ReferenceTabs, "the buttons share the tabs' row as icons")
    var wanted := DockerWindow.column_min_width(docker)
    assert_true(wanted > 0, "the docker has a column to measure")
    assert_true(wanted <= COLUMN_WIDTH, "the Reference's column wants %d, inside the %d of the column" % [wanted, COLUMN_WIDTH])
    host.free()
