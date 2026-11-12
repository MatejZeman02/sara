## Affect all is the adjustment layer's own, so it reaches the
## whole picture from inside a group.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter on 2026-10-16: "'Affect all' should be encoded into the filter,
## not done by position. I wanna have a global effect inside the group, and I
## cannot. I want the effect to be turned off when I hide the group."
##
## The picture, three chunks across over the grey background: Below over the
## left chunk at the top level, an isolated group holding Member over the
## middle chunk and an Invert adjustment layer above it, and Above over the
## right chunk at the top level over the group. Every layer is opaque, so a
## texel inverted reads one minus its colour, and the grey reads itself either
## way, which is why the background shows: a chunk nothing draws over keeps
## what the canvas last held there in a suite's walk.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 256)
const LEFT := Vector2i(0, 0)
const MIDDLE := Vector2i(1, 0)
const RIGHT := Vector2i(2, 0)
const BELOW := Color(0.125, 0.625, 0.25, 1.0)
const MEMBER := Color(0.75, 0.25, 0.375, 1.0)
const ABOVE := Color(0.25, 0.375, 0.875, 1.0)
const TOLERANCE := 1.0e-4
## A texel of each chunk the suite reads, away from the edges.
const AT := Vector2i(100, 120)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _types: SaLayerTypeRegistry = null
var _below: SaLayer = null
var _member: SaLayer = null
var _invert: SaLayer = null
var _group: SaLayer = null
var _above: SaLayer = null


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _below = _doc.get_node("Layer 1") as SaLayer
    _below.name = "Below"
    _below.get_or_create_chunk(LEFT).clear(BELOW)
    _doc.set_active_layer(_below)
    _member = ops.add()
    _member.name = "Member"
    _member.get_or_create_chunk(MIDDLE).clear(MEMBER)
    _group = ops.group_layers([_member])
    ops.set_isolated(_group, true)
    _doc.set_active_layer(_member)
    _invert = SaFilterConversion.new(_doc).add_holding(Bench.INVERT, {}, _types, "Invert", true)
    _doc.set_active_layer(_group)
    _above = ops.add()
    _above.name = "Above"
    _above.get_or_create_chunk(RIGHT).clear(ABOVE)
    _doc.set_active_layer(_below)
    _doc.history.reset()
    _doc.undo_redo.clear_history()
    SaProblems.announce = false


func after_each() -> void:
    SaProblems.announce = true
    _easel.free()
    _easel = null
    _doc = null
    _types = null


func _show() -> void:
    _doc.invalidate_chunks([LEFT, MIDDLE, RIGHT])
    Bench.composite(_easel)


## The composite's texel in the chunk at *grid_pos*.
func _shown(grid_pos: Vector2i) -> Color:
    return Bench.texel(_easel.output, grid_pos * SaLayer.CHUNK_SIZE + AT)


static func _inverted(color: Color) -> Color:
    return Color(1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a)


static func _apart(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _reads(grid_pos: Vector2i, want: Color, what: String) -> void:
    var got := _shown(grid_pos)
    assert_true(_apart(got, want) <= TOLERANCE, "%s: %s against %s" % [what, got, want])


## The three chunks read Below, Member and Above, each inverted or not as
## *inverted* says, the grey in Member's place when *member* is false.
func _picture(inverted: Array[bool], member: bool = true) -> void:
    _show()
    var colours := [BELOW, MEMBER if member else SaDocument.BACKGROUND_GREY, ABOVE]
    var names := ["Below", "Member", "Above"]
    for i in 3:
        var want: Color = colours[i]
        if inverted[i]:
            want = _inverted(want)
        var word := "inverted" if inverted[i] else "as painted"
        _reads([LEFT, MIDDLE, RIGHT][i], want, "%s reads %s" % [names[i], word])


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func test_the_picture_is_as_the_header_says() -> void:
    assert_true(_invert != null and _invert.is_adjustment(), "The Invert layer is an adjustment layer")
    assert_true(_invert.affects_all, "with Affect all on")
    assert_eq(SaLayerStack.parent_of(_invert), _group, "inside the group")
    assert_true(SaLayerStack.isolates(_group), "which is isolated")
    assert_true(_above.get_index() > _group.get_index(), "with Above over the group")


## The first requirement: every visible texel inverted, none with the group
## hidden, and only the group's member with the property off.
func test_it_reaches_the_whole_picture_and_hides_with_its_group() -> void:
    _picture([true, true, true])
    SaLayerOps.new(_doc).set_visible(_group, false)
    _picture([false, false, false], false)
    SaLayerOps.new(_doc).set_visible(_group, true)
    _picture([true, true, true])
    assert_true(SaBackdropLayer.affect_all(_doc, _invert, false), "The property turns off")
    _picture([false, true, false])


## With the Invert layer itself picked, the active tier draws it, and the
## picture is the same.
func test_picked_it_reaches_the_whole_picture_still() -> void:
    _doc.set_active_layer(_invert)
    _picture([true, true, true])
    _doc.set_active_layer(_above)
    _picture([true, true, true])


## The group's opacity multiplies into the layer's own, as a pass-through
## group's does: at half, every texel is halfway to its inverse.
func test_the_group_s_opacity_multiplies_in() -> void:
    SaLayerOps.new(_doc).set_opacity(_group, 0.5)
    _show()
    var got := _shown(RIGHT)
    var want := ABOVE.lerp(_inverted(ABOVE), 0.5)
    assert_true(_apart(got, want) <= 1.0e-3, "Above is halfway to its inverse: %s against %s" % [got, want])


func test_a_flatten_reads_as_the_canvas() -> void:
    _show()
    var before := _bytes(_easel.output)
    assert_true(SaLayerOps.new(_doc).flatten(), "The flatten runs")
    _show()
    for grid_pos: Vector2i in [LEFT, MIDDLE, RIGHT]:
        var want := Bench.texel(_easel.output, grid_pos * SaLayer.CHUNK_SIZE + AT)
        var held: Color = SaFieldSpec.decode_texel(before, _easel.output.format, _index(grid_pos))
        assert_true(_apart(want, held) <= TOLERANCE, "The flattened %s reads as the canvas did" % grid_pos)
    assert_true(_doc.undo(), "One step")
    assert_eq(_invert.get_parent(), _doc, "whose undo brings the layer back")
    _picture([true, true, true])


## A merge of the visible layers takes the group and the lifted layer with it
## and leaves the picture as it was. It refused any group as locked until this
## unit, since `SaLayer.is_locked` answers true for every group.
func test_a_merge_of_the_visible_layers_reads_as_the_canvas() -> void:
    _show()
    var before: Array[Color] = []
    for grid_pos: Vector2i in [LEFT, MIDDLE, RIGHT]:
        before.append(_shown(grid_pos))
    assert_true(SaMergeVisible.new(_doc).merge(), "The merge runs")
    assert_null(_invert.get_parent(), "and takes the lifted layer out")
    _show()
    var i := 0
    for grid_pos: Vector2i in [LEFT, MIDDLE, RIGHT]:
        var got := _shown(grid_pos)
        var said := "The merged %s reads as the canvas: %s against %s" % [grid_pos, got, before[i]]
        assert_true(_apart(got, before[i]) <= TOLERANCE, said)
        i += 1
    assert_true(_doc.undo(), "One step")
    assert_eq(SaLayerStack.parent_of(_invert), _group, "whose undo brings the layer back into its group")
    _picture([true, true, true])


func test_an_export_reads_as_the_canvas() -> void:
    _show()
    var path := ProjectSettings.globalize_path(SaDataRoot.path("export.exr"))
    assert_eq(SaExport.export_exr(_easel, path), OK, "The export is written")
    var image := Image.load_from_file(path)
    DirAccess.remove_absolute(path)
    assert_not_null(image, "and reads back")
    if image == null:
        return
    for grid_pos: Vector2i in [LEFT, MIDDLE, RIGHT]:
        var at := grid_pos * SaLayer.CHUNK_SIZE + AT
        var got := image.get_pixelv(at)
        # The export is linear sRGB, and the canvas holds the document's
        # encoded sRGB.
        var want := _shown(grid_pos).srgb_to_linear()
        assert_true(_apart(got, want) <= 1.0e-3, "The exported %s reads as the canvas: %s against %s" % [grid_pos, got, want])


func test_a_save_keeps_it_and_a_file_without_it_reads_it_off() -> void:
    var path := ProjectSettings.globalize_path(SaDataRoot.path("affect_all.sad"))
    assert_eq(SaExport.save_sad(_doc, path), OK, "It saves")
    var loaded := Bench.easel(SIZE)
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    var reopened := loaded.document.get_node_or_null("Invert") as SaLayer
    assert_true(reopened != null and reopened.affects_all, "with Affect all on")
    loaded.free()
    var entry := SaSadLayerEntry.write(_invert, PackedByteArray(), GlobalShaderCompiler.get_rd())
    assert_true(entry.get("affects_all", false), "The entry carries the key")
    entry.erase("affects_all")
    var read := SaSadLayerEntry.layer_from(entry)
    assert_false(read.affects_all, "and an entry without it reads it off")
    read.free()
    var plain := SaSadLayerEntry.write(_below, PackedByteArray(), GlobalShaderCompiler.get_rd())
    assert_false(plain.has("affects_all"), "A layer with it off writes no key")
    DirAccess.remove_absolute(path)


func test_the_toggle_is_one_step_each_way() -> void:
    var steps := _doc.undo_redo.get_history_count()
    assert_true(SaBackdropLayer.affect_all(_doc, _invert, false), "The toggle turns it off")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_false(SaBackdropLayer.affect_all(_doc, _invert, false), "and turning it off again is nothing")
    assert_false(SaBackdropLayer.affect_all(_doc, _below, true), "nor is a paint layer")
    assert_true(_doc.undo(), "Undo")
    assert_true(_invert.affects_all, "puts it back on")
    _picture([true, true, true])
    assert_true(_doc.redo(), "Redo")
    assert_false(_invert.affects_all, "takes it off again")
    _picture([false, true, false])


## The settings window's check, on the layer's own record.
func test_the_settings_window_s_check_toggles_it() -> void:
    var window := SaFilterEditWindow.new()
    window.watch(_easel.compositor.filter_chain.registry)
    window.open(_invert.filters[0], _doc)
    assert_not_null(window.affect_all, "The window shows an Affect all check")
    if window.affect_all != null:
        assert_true(window.affect_all.button_pressed, "ticked as the layer is")
        window.affect_all.button_pressed = false
        assert_false(_invert.affects_all, "and unticking it turns the property off")
        assert_true(_doc.undo(), "as one step")
        assert_true(_invert.affects_all, "which undoes")
    var record := SaFilterOps.new(_doc).attach(_member, Bench.INVERT)
    window.open(record, _doc)
    assert_null(window.affect_all, "A record on a paint layer shows none")
    window.free()


## The Filter dialog's Layer way with Affect all puts the layer above the
## active one in that layer's group, with the property on.
func test_the_dialog_s_layer_way_makes_the_layer_in_place() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "U170TestHost"
    EventBus.add_child(host)
    var registry := _easel.compositor.filter_chain.registry
    var filter := SaBrightnessContrastFilter.new()
    var key := SaFilterRegistry.key_for(&"sara-base-modules", filter)
    registry.register(filter, &"sara-base-modules")
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.layer_types = _types
    window.watch(registry)
    host.add_child(window)
    _doc.set_active_layer(_member)
    assert_true(registry.invoke(key), "The Filter menu's door opens Brightness/Contrast")
    SaFilterDialogWindow.capture(tree, {"widget": "brightness", "value": 30.0})
    SaFilterDialogWindow.capture(tree, {"affect_all": true})
    SaFilterDialogWindow.capture(tree, {"way": "layer"})
    window.dialog.flush_rerun()
    window.apply_filter()
    var made := _doc.active_layer
    assert_true(made != _member and made.is_adjustment(), "Apply makes an adjustment layer")
    assert_eq(made.get_index(), _member.get_index() + 1, "just above the active layer")
    assert_eq(SaLayerStack.parent_of(made), _group, "in the active layer's group")
    assert_true(made.affects_all, "with Affect all on")
    SaSettings.filter_way = "bake"
    SaSettings.filter_affect_all = false
    window.free()
    canvas.free()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding


func _index(grid_pos: Vector2i) -> int:
    var at := grid_pos * SaLayer.CHUNK_SIZE + AT
    return at.y * _easel.output.size.x + at.x
