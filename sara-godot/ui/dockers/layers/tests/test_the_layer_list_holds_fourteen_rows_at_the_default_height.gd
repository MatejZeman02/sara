## The layer list holds fourteen rows at the default height.
##
## At the default 310 by 400 the
## Background row would be cut in half and a scroll bar would come at seven rows if
## the blend dropdown, the Opacity slider and the actions took 125 pixels under
## the list. The dropdown and the slider stand on a row
## each above the list, and the default layout gives the
## docker the height down to the Reference's bottom edge, which the Colour Picker's blank strip under its
## pair paid for.
##
## The rows are measured the way the docker's column lays them out: the list is
## the one child of the column that expands, so it gets the docker's height less
## the grip's corner and every other child's minimum. The running app read the
## same 434 for the list at 581 tall, in
## `scenarios/the-layer-list-holds-fourteen-rows-at-the-default-height.json`.
extends "res://tests/test_framework.gd"

## The rows carry a thumbnail each, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The two files a fresh profile and Dockers > Layouts > default read.
const LAYOUT_FILES: Array[String] = ["res://docker_layout_default.cfg", "res://layouts/default.cfg"]

## Twelve added to the Layer 1 and the Background a new document holds.
const ROWS := 14

var _restore_visible: Dictionary = {}
var _restore_order: Array = []


func before_each() -> void:
    _restore_order = SaSettings.get_layout_order(SaDockerIds.LAYERS).duplicate()
    for element: String in ["Blend Mode", "Opacity"]:
        _restore_visible[element] = SaSettings.get_element_visible(SaDockerIds.LAYERS, element)


func after_each() -> void:
    for element: String in _restore_visible:
        SaSettings.set_element_visible(SaDockerIds.LAYERS, element, bool(_restore_visible[element]))
    SaSettings.set_layout_order(SaDockerIds.LAYERS, _restore_order)


## A docker over a document of `ROWS` layers with the skeleton's blend modes
## bound, so the dropdown reads the mode a new layer has. The canvas holds the
## docker and the easel, and freeing it frees all three.
func _docker(layers: int = ROWS) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var ops := SaLayerOps.new(canvas.easel.document)
    for i in layers - 2:
        ops.add()
    var docker := LayersDocker.new()
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(Fixtures.make_registries().blend_modes)
    docker.sync_layer_list()
    return docker


## The column of the two rows, read through the dropdown it holds.
func _shared_row(docker: LayersDocker) -> VBoxContainer:
    return docker.blend_mode_opt.get_parent().get_parent() as VBoxContainer


## The Layers docker's rectangle in *path*.
func _layers_rect(path: String) -> Rect2i:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(path), OK, "%s loads" % path)
    return Rect2i(cfg.get_value("LayersDocker", "position", Vector2i.ZERO), cfg.get_value("LayersDocker", "size", Vector2i.ZERO))


func test_the_dropdown_and_the_slider_stand_on_rows_of_their_own_dropdown_first() -> void:
    var docker := _docker(2)
    var row := _shared_row(docker)
    assert_not_null(row, "the dropdown's box is a line of a column")
    assert_true(docker.opacity_slider.get_parent().get_parent() == row, "and the slider's box the next line of the same one")
    assert_true(row.get_parent() == docker.item_list.get_parent(), "a part of the docker's column, beside the list")
    var blend_box := docker.blend_mode_opt.get_parent() as Control
    var opacity_box := docker.opacity_slider.get_parent() as Control
    assert_true(blend_box.get_index() < opacity_box.get_index(), "the dropdown above and the slider under it")
    docker.target_canvas.free()


## At the column's width the dropdown names its mode whole and the slider shows
## its number whole. At half each both were cut in the running app, to
## "Normal (O" and "Opacity: 100" with an ellipsis, when the two shared a row.
## Each has the column's whole width on a row of its own now.
##
## Measured in the font each face draws in rather than laid out, because a
## container off the tree sorts nothing and a button off it shapes no text.
func test_at_the_columns_width_the_mode_and_the_number_read_whole() -> void:
    var docker := _docker(2)
    var blend_box := docker.blend_mode_opt.get_parent() as Control
    var width := float(_layers_rect(LAYOUT_FILES[0]).size.x - 2 * SaUI.px(SaUI.BASE_MARGIN))
    var dropdown_share := width
    var slider_share := width

    var dropdown := docker.blend_mode_opt
    var font := dropdown.get_theme_font("font")
    var font_size := dropdown.get_theme_font_size("font_size")
    # "Blend" stands in front of the dropdown inside its share, at a
    # row label's size, so the mode has the share less the word and its gap.
    var label_size := maxi(1, int(roundf(float(font_size) * LayersDocker.LABEL_FONT_SCALE)))
    var label := font.get_string_size(tr("Blend"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_size).x
    dropdown_share -= label + blend_box.get_theme_constant("separation")
    var face := dropdown.get_theme_stylebox("normal")
    var arrow := dropdown.get_theme_icon("arrow", "OptionButton")
    var frame := face.get_margin(SIDE_LEFT) + face.get_margin(SIDE_RIGHT)
    frame += arrow.get_width() + dropdown.get_theme_constant("h_separation")
    # Oklab is the space a fresh profile's document opens in, and the suite's
    # easel opens in another.
    for text: String in ["Normal (Oklab)", dropdown.text]:
        var wants := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x + frame
        assert_true(wants <= dropdown_share, "'%s' wants %.0f and has %.0f" % [text, wants, dropdown_share])

    var slider := docker.opacity_slider
    var number := slider.text_width() + float(SaUI.px(FactorSlider.TEXT_PADDING))
    assert_true(number <= slider_share, "the slider's number wants %.0f and has %.0f" % [number, slider_share])
    assert_false(slider.prefix.contains("Opacity"), "the word is not on the face")
    assert_true(slider.tooltip_text.begins_with("Opacity"), "it opens the tooltip instead")
    docker.target_canvas.free()


func test_hiding_either_leaves_the_other_on_the_row() -> void:
    var docker := _docker(2)
    var row := _shared_row(docker)
    var blend_box := docker.blend_mode_opt.get_parent() as Control
    var opacity_box := docker.opacity_slider.get_parent() as Control

    SaSettings.set_element_visible(SaDockerIds.LAYERS, "Blend Mode", false)
    docker.apply_layout_settings()
    assert_false(blend_box.visible, "Blend Mode hidden hides the dropdown")
    assert_true(opacity_box.visible and opacity_box.get_parent() == row, "and leaves the slider on the row")
    assert_true(row.visible, "which stays")

    SaSettings.set_element_visible(SaDockerIds.LAYERS, "Blend Mode", true)
    SaSettings.set_element_visible(SaDockerIds.LAYERS, "Opacity", false)
    docker.apply_layout_settings()
    assert_false(opacity_box.visible, "Opacity hidden hides the slider")
    assert_true(blend_box.visible and blend_box.get_parent() == row, "and leaves the dropdown on the row")
    assert_true(row.visible, "which stays")

    SaSettings.set_element_visible(SaDockerIds.LAYERS, "Blend Mode", false)
    docker.apply_layout_settings()
    assert_false(row.visible, "with both hidden the row costs the list nothing")
    docker.target_canvas.free()


## Each is still an element of its own in the order, and the row stands where
## the first of the two stands.
func test_the_row_stands_where_the_first_of_the_two_stands() -> void:
    var docker := _docker(2)
    var row := _shared_row(docker)
    var column := row.get_parent()

    docker.apply_layout_settings()
    assert_eq(row.get_index(), docker.item_list.get_index() - 1, "the default order puts the two above the list")

    var order := ["Drag Handle", "Resizer", "Opacity", "Layer List", "Actions", "Blend Mode"]
    SaSettings.set_layout_order(SaDockerIds.LAYERS, order)
    docker.apply_layout_settings()
    assert_eq(row.get_index(), 0, "Opacity first puts the row above the list")
    assert_eq(docker.item_list.get_index(), 1, "the list under it")
    assert_eq(docker.actions.get_index(), 2, "and the actions under that, the row not placed twice")
    # Three: a ground's rows open in a panel of their own, out of the column.
    assert_eq(column.get_child_count(), 3, "the column holds the list, the row and the actions")

    order = ["Drag Handle", "Resizer", "Layer List", "Actions", "Blend Mode", "Opacity"]
    SaSettings.set_layout_order(SaDockerIds.LAYERS, order)
    docker.apply_layout_settings()
    assert_eq(row.get_index(), 2, "Blend Mode after the actions puts the row under them")
    docker.target_canvas.free()


## Both files hold one rectangle, and it ends on the Reference's bottom edge,
## the left column's, so both columns end on one line.
func test_both_layout_files_grow_the_docker_to_the_bottom() -> void:
    var rects: Array[Rect2i] = []
    for path: String in LAYOUT_FILES:
        rects.append(_layers_rect(path))
    assert_eq(rects[0], rects[1], "the two files hold one Layers rectangle")
    var cfg := ConfigFile.new()
    cfg.load(LAYOUT_FILES[0])
    var left_column := Rect2i(cfg.get_value("ReferenceDocker", "position"), cfg.get_value("ReferenceDocker", "size"))
    assert_true(rects[0].end.y >= left_column.end.y, "the Layers docker ends no higher than the Reference, closed")
    assert_true(rects[0].end.y <= 1080, "on the 1920 by 1080 host the file is written for")


func test_fourteen_rows_show_at_the_default_size_with_no_scroll_bar() -> void:
    var docker := _docker()
    assert_eq(docker.item_list.row_count(), ROWS, "the docker draws a row a layer")
    docker.reserve_grip_corner()
    var height := _layers_rect(LAYOUT_FILES[0]).size.y
    var column := docker.content_column()
    var room := float(height) + column.offset_bottom - column.get_combined_minimum_size().y
    var rows: float = docker.item_list.vbox.get_combined_minimum_size().y
    assert_true(rows <= room, "%d rows want %.0f and the list has %.0f at %d tall" % [ROWS, rows, room, height])
    docker.target_canvas.free()
