## A painter or a notebook brings a noise field of their own as
## one `.gmacs` file, and the brush editor offers it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when, a clause a case: a file dropped into the folder is listed in
## the Texture row, a stroke through it paints other than Grain does, and the
## file changed paints the changed field. A broken file is one problem line
## naming the file and the error, and the other fields stay. The door's
## `brush_field` step registers and replaces a field from text. A preset saved
## with the field and opened with the file gone opens with Grain and a notice.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const FolderScript = preload("res://modules/sara-noise-brush-engine/field_folder/noise_field_folder.gd")
const BrushFieldDriver = preload("res://harness/sa_brush_field_driver.gd")

const CANVAS := Vector2i(256, 128)
const RADIUS := 10.0
const START := Vector2(40.0, 64.0)
const END := Vector2(216.0, 64.0)
const SAMPLE_STEP := 8.0
## The painter's field, bands across the stroke every Period pixels of path,
## its header naming the row and the number.
const STRIPES := """# Field: Painter's stripes
# Number: Period, 2, 64, 12
#
# Bands across the stroke, the first half of each painting at any pressure.


def brush_field(float along, float across, float half_width, vec3 numbers, vec2 offset) -> vec2:
    float needed = fract((along + offset.x) / max(numbers.x, 2.0)) < 0.5 ? 0.0 : 1.0
    return vec2(needed, 1.0 - needed)
"""
## The same file saved again with a field that takes paint nowhere.
const NOTHING := """# Field: Painter's stripes


def brush_field(float along, float across, float half_width, vec3 numbers, vec2 offset) -> vec2:
    return vec2(1.0, 0.0)
"""
## A file whose function reads a name nothing declares, on its line 4.
const BROKEN := """# A broken field.


def brush_field(float along, float across, float half_width, vec3 numbers, vec2 offset) -> vec2:
    return vec2(missing_width, 0.0)
"""
const BROKEN_LINE := 5

var _registries: SaRegistries = null
var _noise: SaModule = null
var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _written: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _written = PackedStringArray()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _noise = NoiseModuleScript.new()
    _noise.register(_registries.context.for_module(_noise.get_id()))
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.settings = _noise.settings
    _brush.surface = _surface
    _brush.stroke_seed = 5
    _brush.settings.color = Color(0.1, 0.2, 0.7, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.texture_drift = 0.0
    _brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null
    for path in _written:
        DirAccess.remove_absolute(path)
    _noise.unregister(_registries.context)
    _registries.context.for_module(_noise.get_id()).remove_all_registrations()
    _registries = null


## A file dropped in is listed after the shipped three with its header's label
## and number, paints other than Grain, and paints the changed field once saved
## again, with the old one replaced rather than kept beside it.
func test_a_dropped_file_is_listed_paints_and_paints_again_when_it_changes() -> void:
    var grain := _alphas(NoiseFieldsScript.GRAIN)
    _drop("stripes", STRIPES)
    _registries.brush_fields.reread_asked.emit(NoiseFieldsScript.ENGINE)
    var choices := _texture_choices()
    assert_eq(choices, ["grain", "bristle", "picture", "stripes"], "The Texture row lists the file after the shipped three")
    var stripes := _field("stripes")
    assert_not_null(stripes, "The door holds the file's field")
    if stripes == null:
        return
    assert_eq(stripes.label, "Painter's stripes", "under the header's label")
    var key := FolderScript.number_key("stripes", 0)
    assert_eq(stripes.numbers[0], key, "its first number under a key of its own")
    assert_eq(float(_noise.settings.get(key)), 12.0, "which reads the header's default")
    var period := _row(key)
    assert_true(period != null and period.label == "Period" and period.max_value == 64.0, "and the Texture page has its row")
    var striped := _alphas("stripes")
    var painted := striped.count(true)
    assert_true(painted > 100 and striped.count(false) > 100, "The stripes paint half the stroke, %d texels" % painted)
    assert_true(_differ(grain, striped) > 100, "and paint other than Grain does, %d texels apart" % _differ(grain, striped))
    _noise.settings.set(key, 40.0)
    assert_eq(stripes.number(_noise.settings, 0), 40.0, "A moved Period is the number the kernel is handed")
    _drop("stripes", NOTHING)
    var after := _alphas("stripes")
    assert_eq(after.count(true), 0, "The file saved again paints the new field at the next stroke, none at all")
    var now := _field("stripes")
    assert_true(now != null and now != stripes, "through a new field in the old one's place")
    assert_eq(_texture_choices().count("stripes"), 1, "listed once")


## A file that does not compile is one sentence naming the file and its
## line, and leaves the other fields.
func test_a_broken_file_is_one_problem_line_and_leaves_the_others() -> void:
    _drop("stripes", STRIPES)
    _drop("broken", BROKEN)
    var lines := _problems(func() -> void: _registries.brush_fields.reread_asked.emit(NoiseFieldsScript.ENGINE))
    var path := _path("broken")
    # The compiler logs its own lines for any kernel that fails, and the door's
    # sentence is the one that says what became of the file.
    var naming := lines.filter(func(line: String) -> bool: return line.contains(path) and line.contains("is not registered"))
    assert_eq(naming.size(), 1, "One sentence names the broken file: %s" % [lines])
    var said: String = naming[0] if not naming.is_empty() else ""
    assert_true(
        said.contains(path) and said.contains("ERROR") and said.contains(":%d" % BROKEN_LINE),
        "with its error and line: %s" % said
    )
    assert_true(
        _texture_choices().has("stripes") and not _texture_choices().has("broken"),
        "The other field stays: %s" % [_texture_choices()]
    )
    var again := _problems(func() -> void: _registries.brush_fields.reread_asked.emit(NoiseFieldsScript.ENGINE))
    assert_true(
        again.filter(func(line: String) -> bool: return line.contains("broken")).is_empty(),
        "and an unchanged file is not tried again"
    )


## The door's step writes the text into the folder and registers it, answers
## the compiler's line for a broken one, and a stroke paints the field it made.
func test_the_door_step_registers_and_replaces_a_field_from_text() -> void:
    var said := BrushFieldDriver.run(_registries.brush_fields, {"name": "notebook_stripes", "source": STRIPES})
    _written.append(_path("notebook_stripes"))
    assert_true(bool(said.get("ok")), "The step takes the text: %s" % [said])
    assert_eq(said.get("field"), "notebook_stripes", "under the name it was given")
    assert_true(_texture_choices().has("notebook_stripes"), "and the Texture row lists it")
    assert_true(_alphas("notebook_stripes").count(true) > 100, "A stroke paints through it")
    var refused := BrushFieldDriver.write(_registries.brush_fields, {"name": "notebook_stripes", "source": BROKEN})
    assert_false(bool(refused.get("ok")), "A broken function is refused")
    var error := String(refused.get("error", ""))
    assert_true(error.contains("ERROR") and error.contains(":%d" % BROKEN_LINE), "with the compiler's line: %s" % error)
    var again := BrushFieldDriver.write(_registries.brush_fields, {"name": "notebook_stripes", "source": NOTHING})
    assert_true(bool(again.get("ok")), "and the fixed one takes again: %s" % [again])
    assert_eq(_alphas("notebook_stripes").count(true), 0, "painting the fixed function")
    var unnamed := BrushFieldDriver.write(_registries.brush_fields, {"name": "../stripes", "source": STRIPES})
    assert_false(bool(unnamed.get("ok")), "A name that is not a plain word is refused before anything is written")


## A preset saved with the painter's field and opened with the file gone opens
## with Grain and a notice naming the file.
func test_a_preset_whose_field_file_is_gone_opens_with_grain_and_a_notice() -> void:
    _drop("stripes", STRIPES)
    _registries.brush_fields.reread_asked.emit(NoiseFieldsScript.ENGINE)
    var store := SaPresetStore.new()
    store.dir = SaDataRoot.path("test-presets")
    DirAccess.make_dir_recursive_absolute(store.dir)
    _noise.settings.texture_field = "stripes"
    assert_eq(_noise.settings.texture_field, "stripes", "The brush paints through the painter's field")
    var stored := store.save_preset("Stripes", _noise.settings)
    assert_false(stored.is_empty(), "and a preset saves it")
    _noise.settings.texture_field = NoiseFieldsScript.BRISTLE
    DirAccess.remove_absolute(_path("stripes"))
    _registries.brush_fields.reread_asked.emit(NoiseFieldsScript.ENGINE)
    assert_null(_field("stripes"), "The file gone, its field is gone")
    var notices: Array[String] = []
    var hear := func(text: String) -> void: notices.append(text)
    EventBus.paint_refused.connect(hear)
    var applied := store.apply_preset(stored, _noise.settings)
    EventBus.paint_refused.disconnect(hear)
    store.delete_preset(stored)
    DirAccess.remove_absolute(store.dir)
    assert_true(applied, "The preset opens")
    assert_eq(_noise.settings.texture_field, NoiseFieldsScript.GRAIN, "with Grain")
    assert_eq(notices.size(), 1, "and one notice: %s" % [notices])
    assert_true(not notices.is_empty() and notices[0].contains(_path("stripes")), "naming the missing file: %s" % [notices])


## Writes *text* as the folder's file called *stem*, kept for the clean-up.
func _drop(stem: String, text: String) -> void:
    var path := _path(stem)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()
    if not _written.has(path):
        _written.append(path)


func _path(stem: String) -> String:
    return SaBrushFieldRegistry.folder_for(NoiseFieldsScript.ENGINE).path_join(stem + ".gmacs")


func _field(field_id: String) -> SaBrushFieldRegistry.Field:
    return _registries.brush_fields.field(NoiseFieldsScript.ENGINE, field_id)


## Every problem line *act* gives, the lines kept before it set aside.
func _problems(act: Callable) -> Array[String]:
    var lines: Array[String] = []
    var announcing := SaProblems.announce
    SaProblems.announce = false
    var kept_faults := SaProblems.pending
    var kept_refusals := SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    act.call()
    SaProblems.detach_sink()
    SaProblems.pending = kept_faults
    SaProblems.pending_refusals = kept_refusals
    SaProblems.announce = announcing
    return lines


## The ids the noise brush's Texture row offers, read off its descriptor.
func _texture_choices() -> Array:
    var spec := _row(NoiseFieldsScript.FIELD_KEY)
    return spec.choices.map(func(choice: Dictionary) -> Variant: return choice["id"]) if spec != null else []


func _row(key: StringName) -> SaOptionSpec:
    var descriptor := _registries.tools.get_descriptor(NoiseModuleScript.TOOL_ID)
    for spec: SaOptionSpec in descriptor.options:
        if spec.key == key:
            return spec
    return null


## Paints the stroke through *field_id* on a fresh surface and answers, for
## each texel along three lines through it, whether it took paint.
func _alphas(field_id: String) -> Array[bool]:
    _brush.settings.texture_field = field_id
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush.surface = _surface
    _brush.begin_stroke(START, 1.0)
    var at := START
    while at.x < END.x:
        at.x = minf(at.x + SAMPLE_STEP, END.x)
        _brush.add_sample(at, 0.6)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var out: Array[bool] = []
    for y: int in [int(START.y) - int(RADIUS / 2.0), int(START.y), int(START.y) + int(RADIUS / 2.0)]:
        for x in range(int(START.x + 2.0 * RADIUS), int(END.x - 2.0 * RADIUS)):
            out.append(_alpha(layer, Vector2i(x, y), images) > 0.5)
    return out


static func _differ(a: Array[bool], b: Array[bool]) -> int:
    var count := 0
    for index in mini(a.size(), b.size()):
        if a[index] != b[index]:
            count += 1
    return count


func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            @warning_ignore("static_called_on_instance")
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0
