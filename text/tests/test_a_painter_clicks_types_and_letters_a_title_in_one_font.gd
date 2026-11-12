## A painter clicks with the Text tool, types a title, commits it, and the
## title is a text layer of one history step, drawn over its glyphs and
## nowhere else, that a file keeps as it was set where its font is missing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The keys go through the shortcut router as a keyboard's do, so a letter that
## picks a tool is shown to type instead while a block is edited. The click is
## the tool's own press at a document point, the method its input handler
## calls with the pointer's place.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const StateText = preload("res://modules/sara-base-modules/text/edit/state_text.gd")
const Door = preload("res://modules/sara-base-modules/text/door/sa_text_door.gd")
const INTER_WOFF2 = "res://modules/sara-base-modules/text/tests/fixtures/inter-variable-latin.woff2"

const SIZE := Vector2i(1024, 512)
const TITLE := "Sea Fog"
## Where the title's first baseline starts.
const AT := Vector2(120.5, 200.25)
const EM := 96.0
## The least alpha a display shows, half of an eight bit step.
const SHOWN := 0.5 / 255.0
static var scratch: String = SaDataRoot.path("test_a_painter_clicks_types_and_letters_a_title.sad")
static var scratch_font: String = SaDataRoot.path("test_a_painter_clicks_types_scratch_font.woff2")

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.get_document()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _surface.easel, func() -> Array: return [_surface])
    _registries.register_builtins()
    _modules.clear()
    for path: String in ["stamp-brush", "base", "text"]:
        var module: SaModule = load("res://modules/sara-base-modules/%s/module.gd" % path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _surface.tool_machine = _machine
    _machine.set_active_tool(&"text")
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)


func after_each() -> void:
    _router.free()
    for i in range(_modules.size() - 1, -1, -1):
        _modules[i].unregister(_registries.context)
    _modules.clear()
    _surface.tool_machine = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _registries = null
    Fonts.forget("Inter")
    for path: String in [scratch, scratch + "1", scratch + ".saving", scratch_font]:
        var real := ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(real):
            DirAccess.remove_absolute(real)


func _tool() -> StateText:
    return _machine.active_tool as StateText


## A press and a release of *keycode* typing *character*, through the router
## as the main window hands it a key.
func _press(keycode: Key, character: String = "", ctrl: bool = false, shift: bool = false) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = keycode
        event.physical_keycode = keycode
        event.unicode = character.unicode_at(0) if not character.is_empty() else 0
        event.ctrl_pressed = ctrl
        event.shift_pressed = shift
        event.pressed = pressed
        _router.handle_viewport_input(event, null)


## *said* typed a key at a time, a capital with Shift held.
func _type(said: String) -> void:
    for character in said:
        if character == " ":
            _press(KEY_SPACE, " ")
        elif character == "\n":
            _press(KEY_ENTER)
        else:
            var code := OS.find_keycode_from_string(character.to_upper())
            _press(code, character, false, character != character.to_lower())


func _text_layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer.layer_type == &"text":
            found.append(layer)
    return found


## Every chunk of *layer* read back, by place, each drawn first if it owes it.
static func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos).rid, 0)
    return out


## The box of every texel of *layer* with paint a display could show, in
## document pixels. Coverage summed in floats leaves a residue of a few
## millionths beside a closed outline, which the half store can keep.
static func _inked(layer: SaLayer) -> Rect2i:
    var box := Rect2i()
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                if SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).a > SHOWN:
                    var at := Rect2i(grid_pos * SaChunk.SIZE + Vector2i(x, y), Vector2i.ONE)
                    box = at if box.size == Vector2i.ZERO else box.merge(at)
    return box


func test_a_title_typed_and_committed_is_one_step_a_layer_over_its_glyphs_and_undo_takes_it_away() -> void:
    var steps := _doc.history.position()
    var layers := _doc.get_child_count()
    _tool().font_size = EM
    _tool().press(AT)
    assert_true(_tool().editing(), "A click on empty canvas starts a block")
    _type(TITLE)
    assert_eq(_tool()._text, TITLE, "The keys type the title")
    assert_eq(_doc.history.position(), steps, "and nothing is recorded while it is typed")
    _press(KEY_ENTER, "", true)
    assert_false(_tool().editing(), "Ctrl+Enter commits it")
    assert_eq(_doc.history.position(), steps + 1, "as one history step")
    assert_eq(_doc.get_child_count(), layers + 1, "which added one layer")

    var made := _text_layers()
    assert_eq(made.size(), 1, "a text layer")
    var layer := made[0]
    var recipe := layer.recipe as Recipe
    assert_eq(String(layer.name), TITLE, "named by its words")
    assert_eq(recipe.text, TITLE, "holding the title")
    assert_eq(recipe.family, Fonts.DEFAULT_FAMILY, "in the Font row's family")
    assert_eq(recipe.runs.size(), TITLE.replace(" ", "").length(), "with a glyph for every letter")
    var said := recipe.report()
    assert_eq([said["text"], said["lines"], said["glyphs"]], [TITLE, 1, recipe.runs.size()], "which its report says")
    assert_eq((said["fonts"] as Array)[0]["glyphs"], recipe.runs.size(), "every glyph from its own family, none a fallback")
    var bounds := recipe.bounds()
    assert_true(bounds.size.x > EM * 2.0 and bounds.size.y > EM * 0.5, "whose box is a title's, %s" % bounds)
    for grid_pos: Vector2i in layer.chunks:
        var square := Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        assert_true(square.intersects(bounds), "Chunk %s lies under the glyphs" % grid_pos)
    var squares_under := 0
    for gy in range(floori(bounds.position.y / 256.0), floori((bounds.end.y - 1) / 256.0) + 1):
        for gx in range(floori(bounds.position.x / 256.0), floori((bounds.end.x - 1) / 256.0) + 1):
            squares_under += 1
            assert_true(layer.chunks.has(Vector2i(gx, gy)), "and the square %s under them has its chunk" % Vector2i(gx, gy))
    assert_eq(layer.chunks.size(), squares_under, "so the chunks are those and no others")
    var inked := _inked(layer)
    assert_true(inked.size.x > 0, "The glyphs are drawn")
    assert_true(bounds.encloses(inked), "and no paint lies outside their box, %s inside %s" % [inked, bounds])
    assert_true(inked.position.x <= int(AT.x) + 12 and inked.end.y >= int(AT.y) - 2, "starting at the click, %s" % inked)

    _doc.undo()
    assert_eq(_text_layers().size(), 0, "Undo leaves no text layer")
    assert_eq(_doc.get_child_count(), layers, "and the stack as it was")
    _doc.redo()
    assert_eq(_text_layers().size(), 1, "and redo brings it back")


func test_every_letter_a_tool_answers_is_typed_and_leaves_the_tool_in_hand() -> void:
    var shortcuts := PackedStringArray()
    for descriptor: SaToolDescriptor in _registries.tools.list_descriptors():
        if String(descriptor.activate_action).is_empty() or not InputMap.has_action(descriptor.activate_action):
            continue
        for event in InputMap.action_get_events(descriptor.activate_action):
            var key := event as InputEventKey
            if key == null or key.get_modifiers_mask() != 0:
                continue
            var named := OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
            if named.length() == 1 and not named.to_lower() in shortcuts:
                shortcuts.append(named.to_lower())
    assert_true(shortcuts.size() >= 5, "The tools answer single letters, %s" % ", ".join(shortcuts))
    var typed := "".join(shortcuts) + " " + "abcdefghijklmnopqrstuvwxyz"
    _tool().press(AT)
    _type(typed)
    assert_eq(_tool()._text, typed, "Every one of them is typed, Space among them")
    assert_eq(_machine.active_tool_name, &"text", "and the Text tool is still in hand")
    _press(KEY_ESCAPE)
    assert_false(_tool().editing(), "Escape commits the block")
    assert_eq((_text_layers()[0].recipe as Recipe).text, typed, "with everything typed in it")
    _press(KEY_B, "b")
    assert_eq(_machine.active_tool_name, &"brush", "Once it is committed, B picks the brush again")


func test_a_file_opened_without_its_font_draws_the_same_pixels_from_the_stored_outlines() -> void:
    DirAccess.copy_absolute(ProjectSettings.globalize_path(INTER_WOFF2), ProjectSettings.globalize_path(scratch_font))
    assert_eq(Fonts.load_file(scratch_font), "Inter", "A font file of the painter's own loads")
    _tool().press(AT)
    _tool().type_text("Fog\nLine")
    var recipe := _doc.active_layer.recipe as Recipe
    recipe.set_block(recipe.text, "Inter", EM, recipe.paint, recipe.origin)
    _tool().commit()
    var layer := _text_layers()[0]
    var painted := _bytes(layer)
    assert_eq(recipe.fonts[0].get("family", ""), "Inter", "The block names its font")
    assert_eq(String(recipe.fonts[0].get("sha256", "")).length(), 64, "with the hash of its bytes")
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")

    Fonts.forget("Inter")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_font))
    assert_false(Fonts.has_family("Inter"), "The font's file is out of reach")
    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and the file opened")
    var back := opened.get_document().get_node(NodePath(String(layer.name))) as SaLayer
    assert_not_null(back, "with the text layer")
    _registries.layer_types.rebind([back])
    var kept := back.recipe as Recipe
    assert_not_null(kept, "which is a text layer again")
    assert_true(kept.missing, "that knows its font is missing")
    assert_true(kept.report()["missing"], "and says so to the state dump")
    assert_eq(kept.text, "Fog\nLine", "keeps what it says")
    var drawn := _bytes(back)
    assert_eq(_sorted(drawn.keys()), _sorted(painted.keys()), "and draws the same chunks")
    for grid_pos: Vector2i in painted:
        assert_true(drawn[grid_pos] == painted[grid_pos], "with the same bytes in %s" % grid_pos)
    opened.get_document().free()
    Fixtures.teardown(opened)


func test_a_click_on_a_title_edits_it_as_one_step_and_an_empty_block_leaves_nothing() -> void:
    _tool().press(AT)
    _type("Tide")
    _press(KEY_ESCAPE)
    var steps := _doc.history.position()
    var layer := _text_layers()[0]
    var before := _bytes(layer)
    _tool().press(AT + Vector2(EM * 0.6, -EM * 0.3))
    assert_true(_tool().editing(), "A click on the letters edits them")
    assert_eq(_doc.active_layer, layer, "on their own layer")
    _press(KEY_END)
    _type("s")
    _tool().press(Vector2(900.0, 480.0))
    assert_false(_tool().editing(), "A click outside commits")
    assert_eq((layer.recipe as Recipe).text, "Tides", "the edit")
    assert_eq(_doc.history.position(), steps + 1, "as one Edit Text step")
    assert_eq(_text_layers().size(), 1, "on the same layer")
    _doc.undo()
    assert_eq((layer.recipe as Recipe).text, "Tide", "Undo takes the edit back")
    assert_true(_bytes(layer) == before, "and the pixels with it")

    var layers := _doc.get_child_count()
    _tool().press(Vector2(600.0, 400.0))
    _press(KEY_ESCAPE)
    assert_eq(_doc.get_child_count(), layers, "A block committed empty leaves no layer")
    assert_eq(_doc.history.position(), steps, "and no step")


func test_the_door_puts_the_caret_by_index_and_the_rows_follow_the_block_opened() -> void:
    _tool().font_choice = 1
    _tool().press(AT)
    _type("Tide")
    _press(KEY_ESCAPE)
    _tool().font_choice = 2
    _tool().font_size = 30.0
    var layer := _text_layers()[0]
    var said := Door.text_edit_step(_doc, {"layer": String(layer.name), "caret": 2}, _machine)
    assert_true(said.begins_with("SaCapture: text {"), "The step opens the layer, %s" % said)
    var set_at := (layer.recipe as Recipe).size
    assert_true(set_at != 30.0, "The block was set at its own size, %.1f" % set_at)
    assert_eq([_tool().family(), _tool().font_size], ["Comic Neue", set_at], "and the rows turn to its family and size")
    _type("x")
    _press(KEY_ESCAPE)
    assert_eq((layer.recipe as Recipe).text, "Tixde", "A key types at the caret the step put")
    assert_eq((layer.recipe as Recipe).family, "Comic Neue", "in the family the block was set in")
    var refused := Door.text_edit_step(_doc, {"caret": 1}, _machine)
    assert_true(refused.contains("refused"), "With no block in hand and no layer named it refuses, %s" % refused)


func test_the_caret_walks_through_mixed_directions_and_lines() -> void:
    _tool().press(AT)
    _tool().type_text("abc אבג\nxyz")
    assert_eq(_tool()._caret, 11, "The caret stands after what was typed")
    var below := (_doc.active_layer.recipe as Recipe).laid_out().caret_at(11).position.x
    _press(KEY_UP)
    var above := (_doc.active_layer.recipe as Recipe).laid_out().caret_at(_tool()._caret).position.x
    assert_true(_tool()._caret <= 7, "Up takes it to the line above, %d" % _tool()._caret)
    assert_true(absf(above - below) < EM * 0.4, "at the place nearest its own, %.1f under %.1f" % [above, below])
    _press(KEY_HOME)
    assert_eq(_tool()._caret, 0, "Home to the line's start")
    _press(KEY_RIGHT)
    _press(KEY_RIGHT)
    assert_eq(_tool()._caret, 2, "Right steps a grapheme")
    _press(KEY_BACKSPACE)
    assert_eq(_tool()._text, "ac אבג\nxyz", "Backspace takes the one before it")
    _press(KEY_DELETE)
    assert_eq(_tool()._text, "a אבג\nxyz", "Delete the one after")
    var recipe := _doc.active_layer.recipe as Recipe
    var layout := recipe.laid_out()
    var left := layout.caret_at(3).position.x
    var right := layout.caret_at(5).position.x
    assert_true(absf(left - right) > 1.0, "Carets inside the Hebrew run stand apart, %.1f and %.1f" % [left, right])
    assert_true(layout.caret_at(7).position.y > layout.caret_at(0).position.y, "and the second line's below the first")
    _tool().commit()


static func _sorted(positions: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    out.assign(positions)
    out.sort()
    return out
