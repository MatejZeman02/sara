## The Edit menu fills and clears a selection and names its chords.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Delete cleared the selected pixels and Alt+Backspace filled them, and the
## Edit menu said neither, and a copy took the active layer only. The menu now
## lists the two fills, the clear and Copy Merged, each with its chord, and
## Copy Merged holds the picture as the canvas shows it through the selection.
## What a screenshot cannot show is here: the chord each row draws, that each
## press is one history step, and that the merged copy is the composite under
## the mask, texel for texel.
extends "res://tests/test_framework.gd"

## Real chunks, a real composite and a readback of both.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks side by side, so a selection over the seam is copied from both.
const CANVAS := Vector2i(512, 256)

## The selection, an ellipse over the seam, so its edge is a curve the mask
## draws rather than a rectangle the bounds alone would give.
const AREA := Rect2i(180, 30, 160, 190)

## A bar of the lower layer and a half-covering square of the upper one, which
## overlap inside the selection.
const BAR := Rect2i(150, 90, 220, 60)
const SQUARE := Rect2i(240, 60, 80, 120)
const RED := Color(0.9, 0.1, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 0.5)

## The rows the menu offers, item id -> [words, command, chord].
const ROWS := {
    SaEditMenu.ID_COPY_MERGED: ["Copy Merged", &"edit_copy_merged", "Ctrl+Shift+C"],
    SaEditMenu.ID_FILL_FOREGROUND: ["Fill with Foreground Colour", &"fill_foreground", "Alt+Backspace"],
    SaEditMenu.ID_FILL_BACKGROUND: ["Fill with Background Colour", &"fill_background", "Alt+Delete"],
    SaEditMenu.ID_CLEAR: ["Clear", &"layer_clear", "Backspace"],
}

var _surface: SaSurface = null
var _canvas: SaCanvas = null
var _registries: SaRegistries = null
var _table: SaShortcutCommands = null
var _bar: TopMenuBar = null
var _menu: SaMenu = null
var _pair: Array = []


## A bar bound the way main binds it, the skeleton's fills, the app's commands
## and the shortcut table's clipboard over one canvas.
func before_each() -> void:
    _shared().clear()
    _surface = Fixtures.make_surface(CANVAS)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _table = SaShortcutCommands.new(Callable(), func() -> SaCanvas: return _canvas, Callable(), null)
    _table.register_into(_registries.commands)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    _menu = _bar.menu("Edit")
    _pair = [SaColors.foreground, SaColors.background]
    SaColors.foreground = RED
    SaColors.background = Color(0.2, 0.8, 0.3, 1.0)


func after_each() -> void:
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
    _bar.free()
    _canvas.free()
    Fixtures.teardown(_surface)
    _table = null
    _registries = null


func test_the_four_rows_are_listed_with_their_chords() -> void:
    _menu.populate()
    var report := {}
    for entry: Dictionary in _menu.popup.row_report():
        report[entry["id"]] = entry
    for item_id: int in ROWS:
        var row: Array = ROWS[item_id]
        var entry: Dictionary = report.get(String(SaMenu.key(item_id)), {})
        assert_eq(entry.get("label", ""), row[0], "Edit has a %s row" % row[0])
        assert_eq(_menu.command_at(item_id), row[1], "which runs %s" % row[1])
        assert_eq(entry.get("hint", ""), row[2], "and draws %s beside it" % row[2])
        assert_eq(_registries.commands.chord_text(row[1], 1), row[2], "the key the router answers on")
        var tooltip := _menu.popup.label_button(SaMenu.key(item_id)).tooltip_text
        assert_false(tooltip.is_empty(), "and says what it does on hover")
    var others := SaShortcutStore.conflicts("Ctrl+Shift+C", &"edit_copy_merged")
    assert_true(others.is_empty(), "No other command answers Ctrl+Shift+C: %s" % [others])
    var clear := _registries.commands.get_descriptor(&"layer_clear")
    assert_eq(clear.menu_label(), "Clear Layer", "The clear keeps its own words for every other row it is on")
    assert_true(_registries.commands.chord_text(&"layer_clear").contains("Delete"), "and answers Delete as well as Backspace")


## Each of the three is one step, inside the selection and nowhere else, and
## one undo takes it back.
func test_each_fill_and_the_clear_is_one_history_step() -> void:
    var doc := _surface.easel.document
    doc.selection.select_rect(AREA)
    var inside := AREA.get_center()
    var outside := Vector2i(20, 20)
    for item_id: int in [SaEditMenu.ID_FILL_FOREGROUND, SaEditMenu.ID_FILL_BACKGROUND, SaEditMenu.ID_CLEAR]:
        var words: String = ROWS[item_id][0]
        _menu.populate()
        var before := doc.undo_redo.get_history_count()
        var was := _layer_texel(doc.active_layer, inside)
        assert_true(_menu.popup.press_row(SaMenu.key(item_id)), "%s takes a press" % words)
        assert_eq(doc.undo_redo.get_history_count(), before + 1, "%s is one history step" % words)
        var now := _layer_texel(doc.active_layer, inside)
        match item_id:
            SaEditMenu.ID_FILL_FOREGROUND:
                assert_almost_eq(now.r, RED.r, 1e-3, "the selection holds the foreground")
            SaEditMenu.ID_FILL_BACKGROUND:
                assert_almost_eq(now.g, SaColors.background.g, 1e-3, "the selection holds the background")
            SaEditMenu.ID_CLEAR:
                assert_almost_eq(now.a, 0.0, 1e-6, "the selection is empty")
        assert_almost_eq(_layer_texel(doc.active_layer, outside).a, 0.0, 1e-6, "and nothing outside it changed")
        assert_true(doc.undo(), "%s undoes in one press" % words)
        assert_almost_eq(_layer_texel(doc.active_layer, inside).a, was.a, 1e-6, "back to what it was")
        assert_true(doc.redo(), "and comes again")


## The copy is the easel's output under the selection's mask, every texel the
## ellipse's box reaches: the colour as composited, the alpha scaled by the mask.
func test_copy_merged_is_the_composite_under_the_mask() -> void:
    var doc := _surface.easel.document
    _paint_two_layers(doc)
    doc.selection.select_ellipse(AREA)
    _menu.populate()
    assert_true(_menu.popup.press_row(SaMenu.key(SaEditMenu.ID_COPY_MERGED)), "Copy Merged takes a press")
    var clipboard := _shared()
    assert_eq(clipboard.chunks.size(), 2, "the two chunks the ellipse reaches")
    assert_eq(clipboard.bounds, doc.selection.bounds, "over the selection's box")
    assert_true(clipboard.space.matches(doc.color_space), "in the document's colours")

    var output := _surface.easel.output
    var picture := _bytes(output)
    var wrong := 0
    var compared := 0
    for grid_pos: Vector2i in clipboard.chunks:
        var copied := _bytes(clipboard.chunks[grid_pos].albedo())
        var mask_texture := doc.selection.texture_for(grid_pos)
        var mask := _bytes(mask_texture)
        var box := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE)).intersection(doc.selection.bounds)
        for y in range(box.position.y, box.end.y):
            for x in range(box.position.x, box.end.x):
                var local := Vector2i(x, y) - grid_pos * SaChunk.SIZE
                var shown := SaFieldSpec.decode_texel(picture, output.format, y * output.size.x + x)
                var coverage := SaFieldSpec.decode_texel(mask, mask_texture.format, local.y * mask_texture.size.x + local.x).r
                var held := SaFieldSpec.decode_texel(copied, output.format, local.y * SaChunk.SIZE + local.x)
                compared += 1
                if absf(held.a - shown.a * coverage) > 1e-4:
                    wrong += 1
                elif coverage > 0.0 and not _same_colour(Color(held, 1.0), Color(shown, 1.0)):
                    wrong += 1
    assert_true(compared > 20000, "the whole box is compared: %d texels" % compared)
    assert_eq(wrong, 0, "and every one is the composite under the mask")

    var overlap := Vector2i(280, 120)
    var took := _copied_texel(clipboard, overlap)
    assert_true(
        not _same_colour(took, RED) and not _same_colour(took, BLUE),
        "where the two layers overlap the copy holds their blend, not one layer"
    )
    assert_almost_eq(
        _copied_texel(clipboard, Vector2i(AREA.position.x + 2, AREA.position.y + 2)).a,
        0.0,
        1e-6,
        "outside the curve it holds nothing"
    )


## Paste puts the merged copy down as one layer, and that layer alone shows
## inside the selection what every layer showed together.
func test_copy_merged_then_paste_is_one_layer_of_every_visible_layer() -> void:
    var doc := _surface.easel.document
    _paint_two_layers(doc)
    doc.selection.select_rect(AREA)
    _menu.populate()
    assert_true(_menu.popup.press_row(SaMenu.key(SaEditMenu.ID_COPY_MERGED)), "Copy Merged takes a press")
    var before := _bytes(_surface.easel.output)
    var count := SaLayerOps.new(doc).layers().size()
    _menu.populate()
    assert_true(_menu.popup.press_row(SaMenu.key(SaEditMenu.ID_PASTE)), "Paste takes a press")
    var layers := SaLayerOps.new(doc).layers()
    assert_eq(layers.size(), count + 1, "one layer more")
    var pasted := doc.active_layer
    assert_eq(pasted.name, "Pasted Layer", "the pasted one, active")

    for layer: SaLayer in layers:
        layer.visible = layer == pasted
    # The fold caches what is visible, so a change of it is read again first.
    doc.update_caches()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    var after := _bytes(_surface.easel.output)
    var output := _surface.easel.output
    var wrong := 0
    for y in range(AREA.position.y, AREA.end.y):
        for x in range(AREA.position.x, AREA.end.x):
            var index := y * output.size.x + x
            if not _same_colour(
                SaFieldSpec.decode_texel(after, output.format, index), SaFieldSpec.decode_texel(before, output.format, index)
            ):
                wrong += 1
    assert_eq(wrong, 0, "the pasted layer alone is the picture inside the selection")
    var outside := SaFieldSpec.decode_texel(after, output.format, 10 * output.size.x + 10)
    assert_almost_eq(outside.a, 0.0, 1e-6, "and holds nothing outside it")


## With nothing selected the copy is the whole picture, and a locked active
## layer, which refuses a fill, does not stop a copy of what the canvas shows.
func test_nothing_selected_or_a_locked_layer_copies_the_whole_picture() -> void:
    var doc := _surface.easel.document
    _paint_two_layers(doc)
    doc.active_layer.is_locked = true
    var before := doc.undo_redo.get_history_count()
    _menu.populate()
    _menu.popup.press_row(SaMenu.key(SaEditMenu.ID_FILL_FOREGROUND))
    assert_eq(doc.undo_redo.get_history_count(), before, "a locked layer takes no fill")
    assert_true(_menu.popup.press_row(SaMenu.key(SaEditMenu.ID_COPY_MERGED)), "Copy Merged takes a press")
    assert_eq(_shared().bounds, Rect2i(Vector2i.ZERO, CANVAS), "the whole canvas")
    assert_eq(_shared().chunks.size(), 2, "every chunk of it")
    assert_almost_eq(_copied_texel(_shared(), Vector2i(10, 10)).a, 1.0, 1e-4, "the ground and all")
    assert_eq(doc.undo_redo.get_history_count(), before, "and a copy is no step")


## A red bar on the paint layer and a half-covering blue square on a layer
## above it, over the grey ground, each laid through a selection and the
## selection dropped again.
func _paint_two_layers(doc: SaDocument) -> void:
    doc.selection.select_rect(BAR)
    doc.fill_layer(RED)
    SaLayerOps.new(doc).add()
    doc.selection.select_rect(SQUARE)
    doc.fill_layer(BLUE)
    doc.selection.deselect()


func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func _same_colour(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4 and absf(a.a - b.a) < 1e-4


## The texel of *layer* at the document pixel *at*, transparent where the
## layer holds no chunk.
func _layer_texel(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(_bytes(texture), texture.format, local.y * texture.size.x + local.x)


## The clipboard's texel at the document pixel *at*.
func _copied_texel(clipboard: SaClipboard, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var chunk: SaChunk = clipboard.chunks.get(grid)
    if chunk == null:
        return Color.TRANSPARENT
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(_bytes(chunk.albedo()), chunk.albedo().format, local.y * chunk.pixel_size() + local.x)


## The clipboard the open documents share, the run's owner's, as main's is in
## the app. Asked for in `before_each`, which makes the owner when the run has
## none, so the commands find it.
func _shared() -> SaClipboard:
    return SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard
