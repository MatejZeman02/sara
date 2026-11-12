## Layer via Copy and Layer via
## Cut put what the selection covers of the active layer on a new layer above
## it, in place, as one step, and leave the clipboard as it was. With nothing
## selected Ctrl+J duplicates the layer, as Photoshop's does, and Layer via
## Cut is dimmed.
##
## Every pixel of every chunk the selection reaches is read back and held to
## the selection's own mask, because a copy through the wrong mask lands
## plausible red in the middle and wrong pixels only at the edge.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## An ellipse across the four chunks' seams of a 512 canvas.
const OVAL := Rect2i(120, 90, 260, 300)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _doc.active_layer.fill(RED)


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    _registries = null
    _doc = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _texels(texture: SaTexture) -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


func _layers() -> Array[SaLayer]:
    return SaLayerOps.new(_doc).layers()


## J with Ctrl, and Shift when *shift*, as a keyboard sends it.
func _press_j(shift: bool) -> bool:
    var event := InputEventKey.new()
    event.keycode = KEY_J
    event.physical_keycode = KEY_J
    event.ctrl_pressed = true
    event.shift_pressed = shift
    event.pressed = true
    return _registries.commands.try_handle_input(event)


## How many texels of *layer* differ from the source's red times the
## selection's coverage, over every chunk the selection reaches. *taken* is
## true for the new layer, which holds the red where the selection is, and
## false for the source after a cut, which holds it where it is not.
func _wrong_texels(layer: SaLayer, taken: bool) -> int:
    var wrong := 0
    for grid_pos: Vector2i in SaLayer.grid_positions(_doc.canvas_size):
        var mask := _doc.selection.texture_for(grid_pos)
        var field := layer.get_field(grid_pos)
        if mask == null:
            continue
        var coverage := _texels(mask)
        var got := _texels(field) if field != null else []
        for i in coverage.size():
            var want := coverage[i].r if taken else 1.0 - coverage[i].r
            var alpha: float = got[i].a if not got.is_empty() else 0.0
            if absf(alpha - want) > 1e-3 or (want > 0.0 and absf(got[i].r - 1.0) > 1e-3):
                wrong += 1
    return wrong


## The clipboard the open documents share, the run's owner's, as main's is in
## the app.
func _shared() -> SaClipboard:
    return SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard


func test_layer_via_copy_takes_exactly_the_ellipse_and_leaves_the_clipboard() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 64, 64))
    _shared().copy(_doc, _doc.active_layer)
    var held := _shared().chunks.duplicate()
    var held_bounds := _shared().bounds
    _doc.selection.select_ellipse(OVAL)
    var source := _doc.active_layer
    var before := _layers().size()
    var steps := _doc.history.step_count()

    assert_true(_press_j(false), "Ctrl+J runs Layer via Copy")

    var made := _doc.active_layer
    assert_eq(_layers().size(), before + 1, "One layer more")
    assert_true(made != source, "and the new one is active")
    assert_eq(made.get_index(), source.get_index() + 1, "right above its source")
    assert_eq(str(made.name), "%s copy" % source.name, "named after it")
    assert_eq(made.chunks.size(), 4, "in the four chunks the ellipse reaches")
    assert_eq(_wrong_texels(made, true), 0, "It holds the ellipse's pixels and nothing else")
    for grid_pos: Vector2i in source.chunks:
        for color: Color in _texels(source.get_field(grid_pos)):
            if absf(color.a - 1.0) > 1e-4:
                assert_true(false, "The source changed at chunk %s" % grid_pos)
                break
    assert_eq(_shared().bounds, held_bounds, "The clipboard is where Copy left it")
    assert_eq(_shared().chunks, held, "holding the chunks it held")
    assert_eq(_doc.history.step_count(), steps + 1, "One step")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_layers().size(), before, "taking the new layer away in one")
    assert_eq(_doc.active_layer, source, "and the source is active again")


func test_layer_via_cut_moves_the_pixels_and_one_undo_puts_them_back() -> void:
    _shared().clear()
    _doc.selection.select_ellipse(OVAL)
    var source := _doc.active_layer
    var before := _layers().size()
    var steps := _doc.history.step_count()

    assert_true(_press_j(true), "Ctrl+Shift+J runs Layer via Cut")

    var made := _doc.active_layer
    assert_eq(_layers().size(), before + 1, "One layer more")
    assert_eq(str(made.name), "%s copy" % source.name, "named after its source")
    assert_eq(_wrong_texels(made, true), 0, "The new layer holds the ellipse")
    assert_eq(_wrong_texels(source, false), 0, "and the source holds everything but it")
    assert_true(_shared().is_empty(), "The clipboard, empty before, is empty still")
    assert_eq(_doc.history.step_count(), steps + 1, "One step")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_layers().size(), before, "The new layer is gone")
    for grid_pos: Vector2i in source.chunks:
        for color: Color in _texels(source.get_field(grid_pos)):
            if absf(color.a - 1.0) > 1e-4:
                assert_true(false, "The cut stayed in chunk %s after the undo" % grid_pos)
                break
    assert_true(_doc.redo(), "and a redo")
    assert_eq(_wrong_texels(_doc.active_layer, true), 0, "brings the new layer back")
    assert_eq(_wrong_texels(source, false), 0, "and the hole")


func test_ctrl_j_with_nothing_selected_duplicates_and_cut_is_dimmed() -> void:
    var source := _doc.active_layer
    var before := _layers().size()

    assert_false(_registries.commands.get_descriptor(&"layer_via_cut").is_enabled(), "Layer via Cut is dimmed")
    assert_true(_registries.commands.get_descriptor(&"layer_via_copy").is_enabled(), "Layer via Copy is not")
    assert_false(_press_j(true), "Ctrl+Shift+J does nothing")
    assert_eq(_layers().size(), before, "and adds no layer")

    assert_true(_press_j(false), "Ctrl+J runs")
    assert_eq(_layers().size(), before + 1, "and adds a layer")
    assert_eq(str(_doc.active_layer.name), "%s Copy" % source.name, "which is Duplicate Layer's copy")
    assert_eq(_doc.active_layer.chunks.size(), source.chunks.size(), "of the whole layer")


func test_the_right_click_menu_offers_both_only_while_a_selection_stands() -> void:
    var listed := func() -> Array[StringName]:
        var ids: Array[StringName] = []
        for descriptor: SaCommandDescriptor in _registries.commands.list_context_commands():
            ids.append(descriptor.id)
        return ids
    assert_false(listed.call().has(&"layer_via_copy"), "With nothing selected Layer via Copy is not offered")
    assert_false(listed.call().has(&"layer_via_cut"), "nor Layer via Cut")
    _doc.selection.select_ellipse(OVAL)
    assert_true(listed.call().has(&"layer_via_copy"), "With a selection Layer via Copy is")
    assert_true(listed.call().has(&"layer_via_cut"), "and Layer via Cut")


func test_the_two_tables_place_the_chords_as_photoshop_and_krita_do() -> void:
    assert_eq(_registries.commands.chord_text(&"layer_via_copy"), "Ctrl+J", "Sara's own Ctrl+J is Layer via Copy")
    assert_eq(_registries.commands.chord_text(&"layer_via_cut"), "Ctrl+Shift+J", "and Ctrl+Shift+J Layer via Cut")
    var krita := SaShortcutStore.load_profile("Krita")
    assert_eq(krita.get("layer_duplicate", []), ["Ctrl+J"], "Krita keeps Ctrl+J on the duplicate")
    assert_eq(krita.get("layer_via_copy", []), ["Ctrl+Alt+J"], "and copies on Ctrl+Alt+J")
    assert_eq(krita.get("layer_via_cut", []), ["Ctrl+Shift+J"], "and cuts on Ctrl+Shift+J")
    var photoshop := SaShortcutStore.load_profile("Photoshop")
    assert_eq(photoshop.get("layer_via_copy", []), ["Ctrl+J"], "Photoshop copies on Ctrl+J")
    assert_eq(photoshop.get("layer_via_cut", []), ["Ctrl+Shift+J"], "and cuts on Ctrl+Shift+J")


func test_a_selection_over_no_paint_makes_no_layer_and_says_so() -> void:
    SaLayerOps.new(_doc).add()
    _doc.selection.select_ellipse(OVAL)
    var before := _layers().size()
    var steps := _doc.history.step_count()

    _registries.commands.execute(&"layer_via_copy")
    assert_eq(_layers().size(), before, "A layer with no paint gives no layer")
    assert_eq(_doc.history.step_count(), steps, "and no step")
