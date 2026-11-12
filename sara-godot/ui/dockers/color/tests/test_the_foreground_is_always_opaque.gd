## The foreground and the background are opaque, whatever route a colour came
## by.
##
## An eyedropper pick across a
## soft edge (alpha 0.57) and an eight digit hex such as `#e8431c80` left an
## alpha in the foreground that the swatch showed as a checker blend and no
## slider showed, while the stroke laid the colour at full alpha. The store
## drops the alpha in its setters, its bus listener, the recent list and the
## load, the eyedropper drops it before it announces a pick, and the hex field
## refuses four and eight digits like any other bad code. The same pick on the
## running app is `scenarios/the-foreground-s-alpha-is-shown-or-dropped.json`.
##
## Under `ui` rather than beside the store, because the hex field is the
## picker's and a suite under `core` may not name a `ui` class. The eyedropper
## half needs a RenderingDevice and says so when there is none, so the rest
## runs on every machine.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## Where a store of the suite's own writes, so the painter's `colors.cfg` is
## never touched.
static var scratch_path: String = SaDataRoot.path("test_s52_colors.cfg")

## A soft edge's colour, the sweep's alpha.
const EDGE := Color(0.91, 0.26, 0.11, 0.57)
## The colour the picker shows before a hex code is typed.
const SHOWN := Color(0.2, 0.6, 0.9, 1.0)

var _heard: Array[Color] = []
var _kept_path: String
var _kept_recent: Array[Color] = []
var _kept_foreground: Color


## The eyedropper with a pointer the suite moves, since the tool samples where
## the pointer is rather than where an event says.
class ScriptedPointer:
    extends "res://modules/sara-base-modules/base/tools/state_eyedropper.gd"

    var at := Vector2(100, 100)

    func get_document_mouse_position() -> Vector2:
        return at


func before_each() -> void:
    _heard.clear()
    _kept_path = SaColors.path
    _kept_recent = SaColors.recent.duplicate()
    _kept_foreground = SaColors.foreground
    SaColors.path = scratch_path
    EventBus.color_picked.connect(_on_heard)


func after_each() -> void:
    EventBus.color_picked.disconnect(_on_heard)
    SaColors.recent.clear()
    SaColors.recent.append_array(_kept_recent)
    SaColors.foreground = _kept_foreground
    SaColors.path = _kept_path
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


func test_the_setters_keep_the_colour_and_drop_its_alpha() -> void:
    var store := _store()
    var backgrounds: Array[Color] = []
    var on_background := func(color: Color) -> void: backgrounds.append(color)
    EventBus.background_color_changed.connect(on_background)

    store.foreground = EDGE
    store.background = Color(0.1, 0.2, 0.3, 0.25)
    # The same colour at another alpha is the same colour now, so not a change.
    store.foreground = Color(EDGE, 0.8)

    EventBus.background_color_changed.disconnect(on_background)
    assert_eq(store.foreground, Color(EDGE, 1.0), "The foreground keeps the colour and drops the alpha")
    assert_eq(store.background, Color(0.1, 0.2, 0.3, 1.0), "and so does the background")
    assert_eq(_heard, [Color(EDGE, 1.0)], "The bus hears the foreground once, opaque")
    assert_eq(backgrounds, [Color(0.1, 0.2, 0.3, 1.0)], "and the background likewise")
    store.free()


## Hard rule 5: the alpha goes and the channels stay, above 1.0 and below 0.0
## included.
func test_a_channel_out_of_range_survives_the_alpha_going() -> void:
    var store := _store()
    store.foreground = Color(2.5, 1.0, -0.4, 0.5)
    assert_eq(store.foreground, Color(2.5, 1.0, -0.4, 1.0), "Only the alpha changed, got %s" % store.foreground)
    store.free()


## The Reference docker and the harness announce on the bus rather than through
## the setter, and the store follows them without an echo, opaque.
func test_a_pick_announced_on_the_bus_is_kept_opaque_without_an_echo() -> void:
    var store := _store()
    store._ready()
    EventBus.color_picked.emit(EDGE)
    assert_eq(store.foreground, Color(EDGE, 1.0), "The store keeps the pick opaque")
    assert_eq(_heard, [EDGE], "and announces nothing of its own")
    store.free()


func test_a_used_colour_joins_the_recent_row_opaque() -> void:
    var store := _store()
    store.note_used(EDGE)
    store.note_used(Color(EDGE, 0.2))
    assert_eq(store.recent, [Color(EDGE, 1.0)], "One opaque entry, the second use the same colour")
    store.free()


## A `colors.cfg` written before the store dropped the alpha comes back opaque,
## the pair and both lists.
func test_a_saved_alpha_loads_opaque() -> void:
    var config := ConfigFile.new()
    config.set_value("pair", "foreground", EDGE)
    config.set_value("pair", "background", Color(1.0, 1.0, 1.0, 0.4))
    config.set_value("lists", "swatches", [Color(0.1, 0.5, 0.2, 0.3)])
    config.set_value("lists", "recent", [Color(0.7, 0.1, 0.6, 0.5)])
    assert_eq(config.save(scratch_path), OK, "The scratch file is written")

    var store := SaColorStore.new()
    store.load_from(scratch_path)
    assert_eq(store.foreground, Color(EDGE, 1.0), "The foreground loads opaque")
    assert_eq(store.background, Color.WHITE, "and the background")
    assert_eq(store.swatches, [Color(0.1, 0.5, 0.2, 1.0)], "and the swatches")
    assert_eq(store.recent, [Color(0.7, 0.1, 0.6, 1.0)], "and the recent list")
    store.free()


## The sweep's pick: a soft edge, at one texel and averaged over nine. The pick
## is the edge's colour un-premultiplied, opaque on the bus, in the store and
## in the recent row.
func test_the_eyedropper_on_a_soft_edge_picks_its_colour_opaque() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("the eyedropper reads the canvas back, which needs a RenderingDevice")
        return
    for side: int in [1, 9]:
        _heard.clear()
        var surface := Fixtures.make_surface(Vector2i(256, 256))
        var doc := surface.get_document()
        var chunk := doc.active_layer.get_or_create_chunk(Vector2i.ZERO)
        chunk.field(SaFieldSpec.ALBEDO).clear(doc.color_space.from_display(EDGE))
        var eyedropper := ScriptedPointer.new()
        eyedropper.surface = surface
        eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER
        eyedropper.sample_size = side

        eyedropper.handle_input(_button(true))
        eyedropper.handle_input(_button(false))

        assert_eq(_heard.size(), 1, "At %d, the click picks once" % side)
        if _heard.size() == 1:
            var picked := _heard[0]
            assert_eq(picked.a, 1.0, "At %d, the pick is opaque on the bus, got %s" % [side, picked])
            assert_true(_near(picked, EDGE), "and is the edge's colour, not a darkened one, got %s" % picked)
        assert_eq(SaColors.foreground.a, 1.0, "At %d, the foreground is opaque" % side)
        assert_eq(SaColors.recent[0].a, 1.0, "and so is the recent row's first chip")
        doc.free()
        surface.easel.free()


func test_the_hex_field_refuses_eight_and_four_digits() -> void:
    for code: String in ["#e8431c80", "e8431c80", "#e84c"]:
        var picker := _picker()
        var changed: Array[Color] = []
        picker.color_changed.connect(func(c: Color) -> void: changed.append(c))
        picker.hex_input.text = code
        picker.hex_input.text_submitted.emit(code)
        assert_eq(picker.hex_input.text, "#" + SHOWN.to_html(false), "%s puts the shown colour back in the field" % code)
        assert_eq(picker.color, SHOWN, "and the foreground does not move")
        assert_true(changed.is_empty(), "and nothing reaches the brush")
        picker.get_parent().free()


func test_the_hex_field_still_takes_six_digits_and_three() -> void:
    for code: String in ["#e8431c", "e43"]:
        var picker := _picker()
        picker.hex_input.text = code
        picker.hex_input.text_submitted.emit(code)
        var want := Color.html("#" + code.trim_prefix("#"))
        assert_true(picker.color.is_equal_approx(want), "%s is taken, got %s" % [code, picker.color])
        assert_eq(picker.color.a, 1.0, "opaque")
        picker.get_parent().free()


func _store() -> SaColorStore:
    var store := SaColorStore.new()
    store.path = scratch_path
    return store


func _picker() -> SaColorPicker:
    var picker := SaColorPickerScript.new()
    var holder := Control.new()
    holder.add_child(picker)
    picker.color = SHOWN
    return picker


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _on_heard(color: Color) -> void:
    _heard.append(color)
