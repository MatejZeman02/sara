## The undo list names an alpha-locked stroke and Clear Layer
## rightly.
##
## The `layers` sweep painted with the alpha lock on and read Erase Stroke in
## the Undo docker, pressed Backspace and read Fill Layer, and saw a Ground
## Colour row come from opening a paper's colour swatch and closing it. A
## stroke that paints straight into the layer was named for that route, which
## an alpha-locked stroke shares with a build-up eraser. The clear was the fill
## it is underneath. And the swatch hands back the stored colour through the
## display colour and back, which under Oklab moves it in its last digit.
##
## Each case reads the name of the newest step, the last row the Undo docker
## draws, and the strokes go through the stamp brush's own press and lift, so
## the name is the one the engine's commit leaves and not one a suite gave it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The strokes are real dabs on a real chunk.
const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)
## Where every stroke presses, inside the painted chunk.
const AT := Vector2(128.0, 128.0)
## What the layer holds before a stroke, so an eraser and an alpha-locked
## stroke both have paint to change.
const PAINT := Color(0.2, 0.4, 0.8, 1.0)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _pair: Array = []


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _surface.easel.compositor.set_registry(_registries.blend_modes)
    _doc.active_layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _pair = [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color(1.0, 0.0, 0.0, 1.0)


func after_each() -> void:
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null


## A stamp brush in *painting_mode*, build-up by default as the Paint preset
## ships it.
func _brush(painting_mode: StampSettingsScript.PaintingMode = StampSettingsScript.PaintingMode.BUILD_UP) -> StateBrushScript:
    var brush := StateBrushScript.new()
    brush.surface = _surface
    brush.settings.radius = 0.1
    brush.settings.opacity_by_pressure = false
    brush.settings.painting_mode = painting_mode
    return brush


## A press, one motion and a lift at [constant AT], the way a mouse clicks,
## and the name of the one step it left.
func _click(brush: StateBrushScript) -> String:
    (_surface.view as Fixtures.FakeView).mouse_position = AT
    var steps := _doc.history.step_count()
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    brush.handle_input(motion)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)
    assert_eq(_doc.history.step_count(), steps + 1, "The stroke is one step")
    return _doc.undo_redo.get_current_action_name()


## A key as a keyboard sends it, through the command registry's own dispatch,
## which is where the main window hands a key the canvas did not take.
func _press(chord: String) -> bool:
    var parsed := SaShortcutStore.parse_chord(chord)
    var event := InputEventKey.new()
    event.keycode = parsed.keycode
    event.physical_keycode = parsed.keycode
    event.key_label = parsed.keycode
    event.alt_pressed = parsed.alt_pressed
    event.pressed = true
    return _registries.commands.try_handle_input(event)


func test_a_stroke_on_an_alpha_locked_layer_is_a_brush_stroke() -> void:
    _doc.active_layer.alpha_locked = true
    assert_true(SaStrokeRoute.decide(false, true, false).direct, "An alpha-locked build-up stroke paints straight in")
    assert_eq(_click(_brush()), "Brush Stroke", "and is named for what the painter did, not for that route")


func test_a_stroke_on_an_alpha_locked_layer_in_wash_is_a_brush_stroke_too() -> void:
    _doc.active_layer.alpha_locked = true
    assert_eq(_click(_brush(StampSettingsScript.PaintingMode.WASH)), "Brush Stroke", "Through the buffer it was already")


func test_a_plain_stroke_is_a_brush_stroke() -> void:
    assert_eq(_click(_brush()), "Brush Stroke", "Nothing locked and nothing erasing")


## The Erase toggle leaves the brush's own mode at Normal, so only the engine
## knows the stroke erases, and its commit is what says so.
func test_the_erase_toggle_on_a_build_up_brush_is_still_an_erase_stroke() -> void:
    var brush := _brush()
    brush.eraser_toggled = true
    assert_eq(brush.settings.blend_mode, SaLayer.BLEND_MODE.NORMAL, "The toggle leaves the mode where it was")
    assert_true(SaStrokeRoute.decide(true, false, false).direct, "A build-up eraser paints straight in")
    assert_eq(_click(brush), "Erase Stroke", "and is still an Erase Stroke")


func test_a_build_up_brush_whose_mode_is_erase_is_an_erase_stroke() -> void:
    var brush := _brush()
    brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    assert_eq(_click(brush), "Erase Stroke", "The eraser preset's own mode")


## Such a press is refused with a line and makes no step,
## so the list gains nothing to name.
func test_an_eraser_on_an_alpha_locked_layer_adds_no_step() -> void:
    _doc.active_layer.alpha_locked = true
    var brush := _brush()
    brush.eraser_toggled = true
    var steps := _doc.history.step_count()
    (_surface.view as Fixtures.FakeView).mouse_position = AT
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    assert_false(brush.is_drawing, "The press opened no stroke")
    assert_eq(_doc.history.step_count(), steps, "and the list gained no step")


## A wash eraser goes through the buffer, whose commit called every stroke a
## Brush Stroke, so it was the one eraser the list misnamed the other way.
func test_a_wash_eraser_is_an_erase_stroke() -> void:
    var brush := _brush(StampSettingsScript.PaintingMode.WASH)
    brush.eraser_toggled = true
    assert_eq(_click(brush), "Erase Stroke", "Through the buffer as well")


## The document's own door names a stroke by the modes it is handed, for a
## caller that commits without an engine.
func test_begin_stroke_reads_erase_from_either_mode() -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.ERASE)
    assert_true(_doc.stroke_transaction.erasing, "The brush's own mode")
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL, SaLayer.BLEND_MODE.ERASE)
    assert_true(_doc.stroke_transaction.erasing, "The buffer's")
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL, SaLayer.BLEND_MODE.ALPHA_LOCK)
    assert_false(_doc.stroke_transaction.erasing, "and an alpha-locked wash is neither")
    _doc.stroke_transaction.reset()
    assert_false(_doc.stroke_transaction.erasing, "A reset clears it")


func test_backspace_is_clear_layer() -> void:
    var steps := _doc.history.step_count()
    assert_true(_press("Backspace"), "Backspace reaches the clear")
    assert_false(_doc.active_layer.chunks.has(Vector2i.ZERO), "which empties the layer")
    assert_eq(_doc.history.step_count(), steps + 1, "in one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Clear Layer", "called Clear Layer")
    assert_true(_doc.undo(), "Its undo")
    assert_true(_doc.active_layer.chunks.has(Vector2i.ZERO), "gives the paint back")


func test_the_foreground_fill_is_still_fill_layer() -> void:
    assert_true(_press("Alt+Backspace"), "Alt and Backspace reach the fill")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Fill Layer", "called Fill Layer")


## A document laid on a paper in Oklab, as File > New lays one, with the
## paper active.
func _paper_in_oklab() -> SaLayer:
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, SaColorSpace.oklab(), SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    var paper := _doc.get_node("Background") as SaLayer
    assert_true(paper != null and paper.is_generated(), "The ground is a generated layer called Background")
    return paper


## What the running app wrote when the swatch's popup was closed by Escape on
## a white Oklab paper: the colour it held, with the last digit moved.
func test_a_colour_a_digit_away_adds_no_ground_colour_row() -> void:
    var paper := _paper_in_oklab()
    paper.generator_params[SaGeneratedLayer.PARAM_COLOR] = Color(1.0, 0.0, 5.9604645e-08, 1.0)
    var steps := _doc.history.step_count()
    var nudged := Color(1.0, -2.9802322e-08, 1.1920929e-07, 1.0)
    SaGeneratedLayer.set_color(_doc, paper, SaGeneratedLayer.PARAM_COLOR, nudged, "Ground Colour")
    assert_eq(_doc.history.step_count(), steps, "The same colour a digit away is no step")


func test_the_swatchs_round_trip_adds_no_ground_colour_row() -> void:
    var paper := _paper_in_oklab()
    var space := _doc.color_space
    var steps := _doc.history.step_count()
    for key: String in [SaGeneratedLayer.PARAM_COLOR, SaGeneratedLayer.PARAM_SECOND]:
        var held: Color = paper.generator_params.get(key, paper.generator_params[SaGeneratedLayer.PARAM_COLOR])
        var handed_back := space.from_display(space.to_display(held))
        SaGeneratedLayer.set_color(_doc, paper, key, handed_back, "Ground Colour")
    assert_eq(_doc.history.step_count(), steps, "What the swatch shows, handed back, is no step")


func test_a_changed_ground_colour_is_still_one_step() -> void:
    var paper := _paper_in_oklab()
    var space := _doc.color_space
    var steps := _doc.history.step_count()
    var held: Color = paper.generator_params[SaGeneratedLayer.PARAM_COLOR]
    var changed := space.from_display(Color(0.9, 0.8, 0.6))
    SaGeneratedLayer.set_color(_doc, paper, SaGeneratedLayer.PARAM_COLOR, changed, "Ground Colour")
    assert_eq(_doc.history.step_count(), steps + 1, "A colour that changed is one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Ground Colour", "called Ground Colour")
    assert_true(_doc.undo(), "and its undo")
    assert_eq(paper.generator_params[SaGeneratedLayer.PARAM_COLOR], held, "gives the colour back")
