## A module ships its own generator kernel for a generated layer type.
##
## The fixture under `tests/fixtures/noise-ground` registers a noise ground
## whose `generate` and `raise_tooth` are its own `.gmacs`, whose view is its
## own canvas shader, and whose parameters carry two no built-in has, `octaves`
## and `seed`. The suite makes a layer of it through the door every type takes,
## reads its kernel's texels against the grain worked out here on the CPU,
## changes the seed and finds the texels move, saves and opens the document and
## finds the type and the seed again, and reads the height its tooth asks the
## module's `raise_tooth` for.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const FIXTURE_MODULE = preload("res://tests/fixtures/noise-ground/modules/noise-ground-fixture/module.gd")

## What the GPU's single precision may leave between its grain and the one
## worked out here in double precision. The lattice is hashed in integers on
## both sides, so only the smoothing and the octaves'
## sum differ, by parts in a million, and the colour's own storage rounds
## more. A wrong seed or octave count moves a texel by a tenth or more.
const NEAR: float = 0.02
## The places the suite reads, spread over two chunks and away from both
## edges, in document pixels.
const PLACES: Array[Vector2i] = [Vector2i(3, 5), Vector2i(100, 17), Vector2i(255, 200), Vector2i(300, 41), Vector2i(470, 222)]

static var scratch: String = SaDataRoot.path("test_c4_noise_ground.sad")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    FIXTURE_MODULE.new().register(_registries.context.for_module(FIXTURE_MODULE.ID))
    _easel = _new_easel()
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null
    _remove_scratch()


func _new_easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(_registries.blend_modes)
    easel.process_pending_composite()
    return easel


func _remove_scratch() -> void:
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


## A noise ground added the way the Layers docker's add list adds one, under
## the active layer, which stays the active one.
func _add_ground() -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(FIXTURE_MODULE.TYPE, _registries.layer_types)
    _doc.set_active_layer(paint)
    _composite()
    return ground


func _composite() -> void:
    _easel.request_full_composite()
    _easel.process_pending_composite()


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## What *ground*'s kernel writes at *place*, through the compositor's door the
## export takes, over the chunk that holds it.
func _generated(easel: SaEasel, ground: SaLayer, place: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := place / SaLayer.CHUNK_SIZE
    var side := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
    var format: int = ground.schema[0].format
    var texture := easel.compositor.generate_chunk(
        ground, Vector2(grid * SaLayer.CHUNK_SIZE), Rect2i(Vector2i.ZERO, side), format
    )
    return _texel(texture, place - grid * SaLayer.CHUNK_SIZE)


## The fixture's grain, `noise_ground.gmacs` worked out here: *octaves* of
## `libs/noise.gmacs`'s value noise, the lattice moved by *shift*, the seed.
static func _grain(at: Vector2, octaves: float, shift: float) -> float:
    var total := 0.0
    var amplitude := 0.5
    var reached := 0.0
    var p := at + Vector2(shift * 17.0, shift * 31.0)
    for i in clampi(int(octaves), 1, 8):
        total += amplitude * _value_noise(p)
        reached += amplitude
        amplitude *= 0.5
        p *= 2.0
    return total / reached


static func _value_noise(p: Vector2) -> float:
    var floored := p.floor()
    var cell := Vector2i(floored)
    var f := p - floored
    var s := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
    var a := _hash(cell)
    var b := _hash(cell + Vector2i(1, 0))
    var c := _hash(cell + Vector2i(0, 1))
    var d := _hash(cell + Vector2i(1, 1))
    return lerpf(lerpf(a, b, s.x), lerpf(c, d, s.x), s.y)


## `libs/lattice_hash.gmacs`'s `sa_lattice_hash` at a z of nought, in 32-bit
## arithmetic kept by masking GDScript's 64-bit integers.
static func _hash(corner: Vector2i) -> float:
    var h := _lowbias32(0)
    h = _lowbias32((h + corner.y) & 0xFFFFFFFF)
    h = _lowbias32((h + corner.x) & 0xFFFFFFFF)
    return float(h >> 8) / 16777216.0


static func _lowbias32(x: int) -> int:
    x = (x ^ (x >> 16)) & 0xFFFFFFFF
    x = (x * 0x7feb352d) & 0xFFFFFFFF
    x = x ^ (x >> 15)
    x = (x * 0x846ca68b) & 0xFFFFFFFF
    return x ^ (x >> 16)


## The grain of *ground* at *place*, by its own parameters.
func _grain_of(ground: SaLayer, place: Vector2i) -> float:
    var params := ground.generator_params
    var scale := SaTyped.float_at(params, SaGeneratedLayer.PARAM_SCALE, 1.0)
    var octaves := SaTyped.float_at(params, FIXTURE_MODULE.PARAM_OCTAVES, 0.0)
    var shift := SaTyped.float_at(params, FIXTURE_MODULE.PARAM_SEED, 0.0)
    return _grain(Vector2(place) / maxf(scale, 1.0), octaves, shift)


## The colour *ground*'s function says belongs at *place*: its two colours,
## mixed by the grain there.
func _expected(ground: SaLayer, place: Vector2i) -> Color:
    var first: Color = ground.generator_params[SaGeneratedLayer.PARAM_COLOR]
    var second: Color = ground.generator_params[SaGeneratedLayer.PARAM_SECOND]
    return first.lerp(second, _grain_of(ground, place))


func _near(got: Color, wanted: Color) -> bool:
    return absf(got.r - wanted.r) < NEAR and absf(got.g - wanted.g) < NEAR and absf(got.b - wanted.b) < NEAR


func test_the_module_registers_a_type_on_a_kernel_of_its_own() -> void:
    var descriptor := _registries.layer_types.get_descriptor(FIXTURE_MODULE.TYPE)
    assert_not_null(descriptor, "The module's type is registered")
    if descriptor == null:
        return
    assert_eq(descriptor.owner_module, FIXTURE_MODULE.ID, "under the module's id")
    assert_eq(descriptor.generator, "noise-ground-fixture/noise_ground", "on a generator qualified by the module")
    assert_true(GlobalShaderCompiler.get_kernel_index(descriptor.generator, "generate") >= 0, "whose generate is compiled")
    assert_true(GlobalShaderCompiler.get_kernel_index(descriptor.generator, "raise_tooth") >= 0, "and its raise_tooth")
    assert_true(ResourceLoader.exists(descriptor.generator_view), "with a view shader that is there")
    assert_true(SaGeneratedLayer.answers_height(descriptor), "and a tooth among its defaults, so it answers a height")
    var ground := _add_ground()
    assert_true(ground.is_generated(), "A layer of it evaluates the kernel")
    assert_eq(ground.chunks.size(), 0, "and stores nothing")
    var values := SaGeneratedLayer.params_of(ground, Vector2.ZERO, Rect2i(0, 0, 8, 8))
    assert_true(values.has("octaves") and values.has("seed"), "The kernel is handed the module's own two by name")


func test_the_kernel_paints_the_grain_its_function_says() -> void:
    var ground := _add_ground()
    var shades: Array[float] = []
    for place: Vector2i in PLACES:
        var got := _generated(_easel, ground, place)
        var wanted := _expected(ground, place)
        shades.append(got.r)
        assert_true(_near(got, wanted), "At %s the kernel writes %s, the grain's %s" % [place, got, wanted])
    assert_true(shades.max() - shades.min() > 0.1, "and the grain varies from place to place")
    var shown := _texel(_easel.output, PLACES[1])
    assert_true(_near(shown, _generated(_easel, ground, PLACES[1])), "The composite shows the kernel's texel")


func test_a_parameter_the_module_adds_reaches_its_kernel() -> void:
    var ground := _add_ground()
    var before: Array[Color] = []
    for place: Vector2i in PLACES:
        before.append(_generated(_easel, ground, place))
    var shown := _texel(_easel.output, PLACES[2])
    SaGeneratedLayer.set_param(_doc, ground, FIXTURE_MODULE.PARAM_SEED, 3.0, "Noise Seed")
    _composite()
    var moved := 0
    for i in PLACES.size():
        var got := _generated(_easel, ground, PLACES[i])
        if not _near(got, before[i]):
            moved += 1
        assert_true(_near(got, _expected(ground, PLACES[i])), "At %s the texel is the grain at seed 3" % PLACES[i])
    assert_true(moved >= PLACES.size() - 1, "A new seed moves the texels, %d of %d" % [moved, PLACES.size()])
    assert_false(_near(_texel(_easel.output, PLACES[2]), shown), "and the composite shows it")
    SaGeneratedLayer.set_param(_doc, ground, FIXTURE_MODULE.PARAM_OCTAVES, 1.0, "Noise Octaves")
    assert_true(_near(_generated(_easel, ground, PLACES[3]), _expected(ground, PLACES[3])), "One octave is one octave")
    _doc.undo()
    _doc.undo()
    assert_eq(SaTyped.float_at(ground.generator_params, FIXTURE_MODULE.PARAM_SEED, -1.0), 0.0, "Two undos give the seed back")
    assert_true(_near(_generated(_easel, ground, PLACES[0]), before[0]), "and the texels with it")


func test_the_layer_and_its_parameters_come_back_from_a_sad() -> void:
    var ground := _add_ground()
    SaGeneratedLayer.set_param(_doc, ground, FIXTURE_MODULE.PARAM_SEED, 2.0, "Noise Seed")
    SaGeneratedLayer.set_param(_doc, ground, FIXTURE_MODULE.PARAM_OCTAVES, 3.0, "Noise Octaves")
    var saved := _generated(_easel, ground, PLACES[3])
    _remove_scratch()
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")

    var loaded := _new_easel()
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and opened")
    var back := loaded.document.get_node_or_null(NodePath(str(ground.name))) as SaLayer
    assert_not_null(back, "The noise ground is there")
    if back == null:
        loaded.free()
        return
    assert_eq(back.layer_type, FIXTURE_MODULE.TYPE, "with the module's type")
    assert_almost_eq(SaTyped.float_at(back.generator_params, FIXTURE_MODULE.PARAM_SEED, -1.0), 2.0, 0.0001, "its seed")
    assert_almost_eq(SaTyped.float_at(back.generator_params, FIXTURE_MODULE.PARAM_OCTAVES, -1.0), 3.0, 0.0001, "its octaves")
    assert_eq(back.chunks.size(), 0, "and no chunk")
    _registries.layer_types.rebind([back])
    assert_eq(back.generator, "noise-ground-fixture/noise_ground", "Rebinding puts the module's kernel back")
    assert_true(_near(_generated(loaded, back, PLACES[3]), saved), "which paints what it painted before the save")
    loaded.free()


func test_its_tooth_is_a_height_its_own_raise_tooth_answers() -> void:
    var ground := _add_ground()
    var heights := _easel.relief.heights
    assert_not_null(heights, "A noise ground with a tooth resolves a height with no paint on it")
    if heights == null:
        return
    var tooth := SaGeneratedLayer.tooth_of(ground)
    assert_almost_eq(tooth, 0.2, 0.0001, "The tooth is the module's default")
    for place: Vector2i in PLACES:
        var height := _texel(heights, place).r
        assert_almost_eq(
            height, tooth * _grain_of(ground, place), tooth * NEAR, "The height at %s is the tooth times the grain" % place
        )
