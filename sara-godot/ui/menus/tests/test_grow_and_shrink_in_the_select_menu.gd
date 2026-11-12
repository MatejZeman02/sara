## Grow and Shrink in the Select menu. A wand selection that
## stops at the opaque core of a soft stroke had no way out to its fringe but a
## higher tolerance or painting in Quick Mask. Grow moves the edge out by the
## radius, Shrink moves it back in, and a shrink past the middle leaves no
## selection. Each is one undo step under its own name, and each row is lit
## only with a selection to reshape, the way Feather's and Border's are.
##
## Every mask is read back from VRAM. The running app is
## `scenarios/grow-and-shrink-in-the-select-menu.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)

## A rectangle over the crossing of four chunks, so every pass reads a
## neighbour across a seam.
const ACROSS := Rect2i(230, 230, 60, 60)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _host: Node = null
var _bar: TopMenuBar = null
var _canvas: SaCanvas = null
var _table: SaShortcutCommands = null
var _kept_embedding: bool = true


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.get_document()


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    _table = null
    if _host != null:
        _host.free()
        _host = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _registries = null
    _doc = null


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func _title() -> String:
    return _doc.undo_redo.get_current_action_name()


func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


## Every chunk of the mask as its bytes, read back, so two masks compare whole.
func _mask() -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture := (_doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## Grow as the menu runs it once its dialog is answered: one change under the
## title the Undo History docker lists.
func _grow(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.GROW_TITLE, SaSelectionFilters.grow.bind(selection, radius, _doc.canvas_size))


func _shrink(radius: int) -> void:
    var selection := _doc.selection
    selection.change(SaSelection.SHRINK_TITLE, SaSelectionFilters.shrink.bind(selection, radius, _doc.canvas_size))


## One soft red dab, hardness 0, so its alpha falls off from the centre to
## nothing over its radius. What a wand at its default tolerance stops short of.
func _soft_dab(pos: Vector2, radius: float) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, radius, 0.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


func test_grow_moves_the_edge_out_by_the_radius_across_the_seams() -> void:
    _doc.selection.select_rect(ACROSS)
    var steps := _steps()
    _grow(4)
    assert_eq(_steps(), steps + 1, "Grow is one step")
    assert_eq(_title(), SaSelection.GROW_TITLE, "listed as %s" % SaSelection.GROW_TITLE)
    assert_eq(_doc.selection.bounds, ACROSS.grow(4), "the box moved out by 4 on every side")
    for at: Vector2i in [Vector2i(226, 260), Vector2i(293, 260), Vector2i(260, 226), Vector2i(260, 293)]:
        assert_eq(_coverage(at.x, at.y), 1.0, "%s, 4 px past the old edge, is selected" % at)
    for at: Vector2i in [Vector2i(225, 260), Vector2i(294, 260), Vector2i(260, 225), Vector2i(260, 294)]:
        assert_eq(_coverage(at.x, at.y), 0.0, "%s, 5 px past it, is not" % at)
    assert_eq(_coverage(226, 226), 1.0, "and the window is square, so the corner stays square")


func test_shrink_after_grow_gives_the_rectangle_back_texel_for_texel() -> void:
    _doc.selection.select_rect(ACROSS)
    var before := _mask()
    _grow(4)
    var steps := _steps()
    _shrink(4)
    assert_eq(_steps(), steps + 1, "Shrink is one step")
    assert_eq(_title(), SaSelection.SHRINK_TITLE, "listed as %s" % SaSelection.SHRINK_TITLE)
    assert_eq(_doc.selection.bounds, ACROSS, "the box is the rectangle's again")
    assert_eq(_mask(), before, "and so is every texel of the four chunks")


func test_undo_puts_the_mask_back_and_redo_grows_it_again() -> void:
    _doc.selection.select_rect(ACROSS)
    var before := _mask()
    _grow(6)
    var grown := _mask()
    _doc.undo()
    assert_eq(_doc.selection.bounds, ACROSS, "Undo puts the box back")
    assert_eq(_mask(), before, "and the mask as it was")
    _doc.redo()
    assert_eq(_doc.selection.bounds, ACROSS.grow(6), "Redo grows it again")
    assert_eq(_mask(), grown, "to the same mask")


## The row's acceptance case: a soft stroke clicked with the wand
## at its default tolerance, grown by 4 and shrunk by 4.
func test_a_wand_selection_on_a_soft_stroke_grows_to_its_fringe_and_back() -> void:
    _soft_dab(Vector2(300, 300), 40.0)
    _machine.set_active_tool(&"wand")
    _machine.active_tool.sample_merged = false
    _machine.active_tool.flood(Vector2i(300, 300))
    var core := _doc.selection.bounds
    assert_true(core.size.x > 0 and core.size.x < 80, "the wand stops inside the soft dab, %s" % core)
    var fringe := Vector2i(core.position.x - 2, 300)
    assert_eq(_coverage(fringe.x, fringe.y), 0.0, "and leaves its fringe out")
    _grow(4)
    assert_eq(_doc.selection.bounds, core.grow(4), "Grow 4 makes the box 8 px larger in each axis")
    assert_true(_coverage(fringe.x, fringe.y) > 0.0, "and takes in the fringe")
    _shrink(4)
    assert_eq(_doc.selection.bounds, core, "Shrink 4 brings the box back")
    assert_eq(_coverage(fringe.x, fringe.y), 0.0, "and the fringe goes out again")


func test_a_shrink_by_less_than_half_leaves_the_middle() -> void:
    _doc.selection.select_rect(Rect2i(100, 100, 6, 6))
    _shrink(2)
    assert_true(_doc.selection.active, "Shrinking 6 px by 2 leaves a selection")
    assert_eq(_doc.selection.bounds, Rect2i(102, 102, 2, 2), "2 px square in the middle")


func test_a_shrink_past_the_middle_leaves_no_selection_in_one_step() -> void:
    _doc.selection.select_rect(Rect2i(100, 100, 6, 6))
    var steps := _steps()
    _shrink(4)
    assert_false(_doc.selection.active, "Shrinking 6 px by 4 leaves no selection")
    assert_true(_doc.selection.chunks.is_empty(), "and no chunk")
    assert_eq(_steps(), steps + 1, "in one step")
    assert_eq(_title(), SaSelection.SHRINK_TITLE, "listed as Shrink rather than Deselect")
    _doc.undo()
    assert_true(_doc.selection.active, "Undo brings the selection back")
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 6, 6), "as it was")


## The canvas edge counts as unselected on all four sides, on a canvas whose
## last chunks reach past it, where Select All leaves ones beyond the edge.
func test_select_all_shrinks_away_from_every_edge_of_the_canvas() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(Vector2i(500, 300))
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.get_document()
    _doc.selection.select_all(_doc.canvas_size)
    _shrink(4)
    assert_eq(_doc.selection.bounds, Rect2i(4, 4, 492, 292), "4 px in from each of the four edges")
    assert_eq(_coverage(495, 150), 1.0, "the last column kept is selected")
    assert_eq(_coverage(496, 150), 0.0, "and the one after it is not, as on the left")
    assert_eq(_coverage(3, 150), 0.0, "where the first four columns went")
    assert_eq(_coverage(250, 296), 0.0, "and the bottom, across the canvas's short last chunk")


func test_with_nothing_selected_both_do_nothing() -> void:
    var steps := _steps()
    _grow(4)
    _shrink(4)
    assert_false(_doc.selection.active, "No selection stays no selection")
    assert_eq(_steps(), steps, "and nothing is recorded")


## A bar whose Select menu reaches the tree, so the menu builds its dialogs
## under the popup's host the way it does in the app, bound to commands that
## act on this suite's document the way main binds them.
func _open_bar() -> SaSelectMenu:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S38TestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _table = SaShortcutCommands.new(Callable(), func() -> SaCanvas: return _canvas, Callable(), null)
    _table.register_into(_registries.commands)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    return _bar.menu("Select") as SaSelectMenu


func _dimmed(menu: SaSelectMenu, item_id: int) -> bool:
    menu.populate()
    return menu.popup.is_disabled(SaMenu.key(item_id))


func test_the_rows_are_lit_only_with_a_selection_to_reshape() -> void:
    var menu := _open_bar()
    assert_true(_dimmed(menu, SaSelectMenu.ID_GROW), "Grow is dimmed with nothing selected")
    assert_true(_dimmed(menu, SaSelectMenu.ID_SHRINK), "and so is Shrink")
    _doc.selection.select_rect(ACROSS)
    assert_false(_dimmed(menu, SaSelectMenu.ID_GROW), "Grow is lit once there is a selection")
    assert_false(_dimmed(menu, SaSelectMenu.ID_SHRINK), "and so is Shrink")


func test_each_dialog_is_a_window_of_its_own_name() -> void:
    var menu := _open_bar()
    for which: StringName in [&"grow", &"shrink"]:
        menu.open_radius_dialog(which)
        var word := String(SaSelectMenu.RADIUS_WORDS[which])
        var dialog := _host.find_child(word + "Dialog", true, false) as SaRadiusDialog
        assert_not_null(dialog, "%s opens a window of its own name" % word)
        if dialog == null:
            continue
        assert_eq(dialog.title, word, "titled %s" % word)
        assert_eq(dialog.radius(), SaSelectMenu.DEFAULT_RADII[which], "at its own radius")
        var hint := dialog.find_child("HintLabel", true, false) as Label
        assert_true(hint.visible and hint.text.contains("by this many pixels"), "saying the edge moves: '%s'" % hint.text)
        dialog.hide()
