## A module registers a brush field that runs its own kernel,
## GLSL it hands the noise brush through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when, a clause a case: the banded field fixture's field reaches the
## door and the Texture row, a stroke through it paints its bands where its
## function says, read off the layer, and a field whose GLSL does not compile is
## refused with a line naming its file and line. A stroke through each shipped
## field runs the shipped kernel still, whose field read is the seam the bands
## go in at, and the suites of the three fields hold what it paints.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const BandsModuleScript = preload("res://tests/fixtures/banded-field/modules/banded-field-fixture/module.gd")

const CANVAS := Vector2i(256, 128)
const RADIUS := 10.0
## The stroke, left to right through the middle, a sample every
## [constant SAMPLE_STEP] pixels as a pen's would come.
const START := Vector2(40.0, 64.0)
const END := Vector2(216.0, 64.0)
const SAMPLE_STEP := 8.0
## How near a band's edge a texel's centre may sit and be passed over, in
## pixels, since the wash reads the field at the texel's nearest point.
const EDGE := 1.0

var _registries: SaRegistries = null
var _noise: SaModule = null
var _bands: SaModule = null
var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _noise = NoiseModuleScript.new()
    _noise.register(_registries.context.for_module(_noise.get_id()))
    _bands = BandsModuleScript.new()
    _bands.register(_registries.context.for_module(_bands.get_id()))
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.settings = _noise.settings
    _brush.surface = _surface
    _brush.stroke_seed = 5
    _brush.settings.color = Color(0.1, 0.2, 0.7, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.texture_drift = 0.0
    _brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null
    for module: SaModule in [_bands, _noise]:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _registries = null


## The banded field is on the door under its module, runs its own kernel kept
## under a name its module qualifies, and the Texture row lists it.
func test_the_banded_field_reaches_the_door_and_the_texture_row() -> void:
    var door := _registries.brush_fields
    var bands := door.field(NoiseFieldsScript.ENGINE, BandsModuleScript.FIELD_ID)
    assert_not_null(bands, "The door holds the banded field")
    if bands == null:
        return
    assert_eq(door.owner_of(bands), _bands.get_id(), "under the fixture module's name")
    assert_eq(bands.kernel, SaBrushFieldRegistry.OWN, "naming its own kernel")
    assert_eq(bands.include_name, "banded_field_fixture_fields/bands_field", "kept under a name its module qualifies")
    assert_true(
        GlobalShaderCompiler.source.has_virtual_include(bands.include_name), "and the import is kept while it is registered"
    )
    assert_true(NoiseFieldsScript.is_ours(bands), "The noise brush takes it as one of its own")
    assert_false(NoiseFieldsScript.OwnField.shader_for(bands).is_empty(), "and built a pass for it")
    assert_true(_texture_choices().has(BandsModuleScript.FIELD_ID), "The Texture row lists it: %s" % [_texture_choices()])
    _registries.context.for_module(_bands.get_id()).remove_all_registrations()
    assert_false(GlobalShaderCompiler.source.has_virtual_include(bands.include_name), "and the module's unload drops the import")


## Two modules' files of one name are two imports, and so are two files of one
## module in two folders.
func test_two_modules_fields_never_share_an_import() -> void:
    var first := SaBrushFieldRegistry.include_for("res://modules/one-module/fields/bands.gmacs")
    var second := SaBrushFieldRegistry.include_for("res://modules/another-module/fields/bands.gmacs")
    assert_eq(first, "one_module_fields/fields/bands", "A module's file is imported under the module's name")
    assert_true(first != second, "and another module's file of the same name under its own, %s" % second)
    var other := SaBrushFieldRegistry.include_for("res://modules/one-module/other/bands.gmacs")
    assert_true(first != other, "and so is a second folder's, %s" % other)


## A stroke through the bands paints the first half of each band and leaves
## the second bare, where `bands_field.gmacs` says, at the stroke's own offset.
func test_a_stroke_through_the_bands_paints_them_where_its_function_says() -> void:
    _brush.settings.texture_field = BandsModuleScript.FIELD_ID
    var ran := _stroke()
    var bands := _registries.brush_fields.field(NoiseFieldsScript.ENGINE, BandsModuleScript.FIELD_ID)
    assert_eq(ran, NoiseFieldsScript.OwnField.shader_for(bands), "The stroke ran the field's own pass")
    assert_eq(_brush.field_binding.values[5], BandsModuleScript.PERIOD, "with its period, a key the settings do not have")
    var offset := _brush.field_binding.values[3]
    var layer := _surface.easel.document.active_layer
    var images := {}
    var painted := 0
    var bare := 0
    var wrong: Array[String] = []
    for y: int in [int(START.y) - int(RADIUS / 2.0), int(START.y), int(START.y) + int(RADIUS / 2.0)]:
        for x in range(int(START.x + 2.0 * RADIUS), int(END.x - 2.0 * RADIUS)):
            var into := fposmod(x + 0.5 - START.x + offset, BandsModuleScript.PERIOD)
            var half := BandsModuleScript.PERIOD / 2.0
            if into < EDGE or absf(into - half) < EDGE or into > BandsModuleScript.PERIOD - EDGE:
                continue
            var paints := into < half
            var alpha := _alpha(layer, Vector2i(x, y), images)
            if paints:
                painted += 1
            else:
                bare += 1
            if (alpha > 0.5) != paints:
                wrong.append("(%d, %d) %.2f" % [x, y, alpha])
    assert_true(painted > 100 and bare > 100, "Both halves of the bands are read, %d to paint and %d bare" % [painted, bare])
    assert_true(wrong.is_empty(), "and every texel is as the function says, %d are not: %s" % [wrong.size(), wrong.slice(0, 8)])


## A field whose GLSL does not compile is refused at registration, and the
## sentence that says so names its file and the line the error is on.
func test_a_field_whose_kernel_does_not_compile_is_refused_with_its_file_and_line() -> void:
    var lines: Array[String] = []
    var announcing := SaProblems.announce
    SaProblems.announce = false
    # A sink is handed every line kept since the last one, and the suites run
    # before this one keep their own, so those are set aside and put back.
    var kept_faults := SaProblems.pending
    var kept_refusals := SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    var broken := BandsModuleScript.broken()
    var taken := _registries.context.for_module(_bands.get_id()).register_brush_field(broken)
    SaProblems.detach_sink()
    SaProblems.pending = kept_faults
    SaProblems.pending_refusals = kept_refusals
    SaProblems.announce = announcing
    assert_false(taken, "The door refuses the broken field")
    assert_null(_registries.brush_fields.field(NoiseFieldsScript.ENGINE, broken.id), "and does not hold it")
    assert_false(_texture_choices().has(broken.id), "so the Texture row does not list it")
    assert_false(GlobalShaderCompiler.source.has_virtual_include(broken.include_name), "and keeps no import of it")
    var said := ""
    for line in lines:
        if line.contains("is not registered"):
            said = line
    assert_true(said.contains("'%s'" % broken.id), "A sentence says the field is not registered: %s" % [lines])
    var at := "broken_field.gmacs:%d" % BandsModuleScript.BROKEN_LINE
    assert_true(said.contains(BandsModuleScript.BROKEN_PATH) and said.contains(at), "and names its file and %s: %s" % [at, said])
    assert_not_null(
        _registries.brush_fields.field(NoiseFieldsScript.ENGINE, BandsModuleScript.FIELD_ID), "The module's good field stays"
    )


## A stroke through each shipped field runs the shipped kernel, whose read of
## the field is the seam the bands go in at, over the shipped fields.
func test_a_stroke_through_each_shipped_field_runs_the_shipped_kernel() -> void:
    var shipped := GlobalShaderCompiler.resolve_shader_name(StateNoiseBrushScript.KERNEL)
    for field_id: String in [NoiseFieldsScript.GRAIN, NoiseFieldsScript.BRISTLE, NoiseFieldsScript.PICTURE]:
        _brush.settings.texture_field = field_id
        assert_eq(GlobalShaderCompiler.resolve_shader_name(_stroke()), shipped, "%s runs the shipped kernel" % field_id)
    var text := FileAccess.get_file_as_string(NoiseFieldsScript.OwnField.DAB_PATH).replace("\r\n", "\n")
    assert_eq(text.count(NoiseFieldsScript.OwnField.SEAM + "\n"), 1, "which imports its field read on one line")
    var seam := FileAccess.get_file_as_string("res://modules/sara-noise-brush-engine/field_kernel/noise_field_seam.gmacs")
    assert_true(seam.contains("return noise_field(along, across, half_width)"), "and that read is the shipped fields' own")


## Paints the stroke on a fresh surface and answers the shader it ran, read
## while it runs, since the lift puts the brush back on the shipped kernel.
func _stroke() -> String:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush.surface = _surface
    _brush.begin_stroke(START, 1.0)
    var at := START
    while at.x < END.x:
        at.x = minf(at.x + SAMPLE_STEP, END.x)
        _brush.add_sample(at, 1.0)
    var ran := _brush.compute.shader_name
    _brush.end_stroke()
    return ran


## The ids the noise brush's Texture row offers, read off its descriptor.
func _texture_choices() -> Array:
    var descriptor := _registries.tools.get_descriptor(NoiseModuleScript.TOOL_ID)
    for spec: SaOptionSpec in descriptor.options:
        if spec.key == NoiseFieldsScript.FIELD_KEY:
            return spec.choices.map(func(choice: Dictionary) -> Variant: return choice["id"])
    return []


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
