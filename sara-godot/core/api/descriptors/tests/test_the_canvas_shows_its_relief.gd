## The canvas shows its relief under a light.
##
## The view's shader lights the colour by the resolved normal. It is a canvas
## item shader and cannot be dispatched like a kernel, so the suite draws the
## easel's output through the canvas's own material into a viewport and reads
## the frame back, once lit and once not: where no layer has height the two are
## the same to the texel, and where the paint has a slope they are not, and
## which way they differ follows the light.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two cells wide, so one can hold height and the other none.
const SIZE := Vector2i(512, 256)

## A ramp of this many millimetres a pixel rising to the right, about a
## tenth of a millimetre over four pixels at the default 72 dpi, so the suite
## reads the smallest relief the light is tuned to show.
const RAMP_MM: float = 0.025

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _doc: SaDocument = null


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(SIZE)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    # On eight-bit steps, which the view's dither leaves where they are, so a flat texel through the material is the bare one.
    _doc.active_layer.fill(Color(77.0 / 255.0, 140.0 / 255.0, 0.8, 1.0))
    _easel.process_pending_composite()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = _easel
    _canvas.sync_tonemap()


func after_each() -> void:
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null
    _doc = null
    _registries = null
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


## A cell of height on the active layer, each texel what *height_of* answers
## for its canvas pixel, dirtied the way a dab dirties it, and composited.
func _raise(grid_pos: Vector2i, height_of: Callable) -> void:
    SaHeightOps.new(_doc).gain(_doc.active_layer)
    var texture := _doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            var pixel := grid_pos * SaLayer.CHUNK_SIZE + Vector2i(x, y)
            bytes.encode_half((y * texture.size.x + x) * 2, float(height_of.call(pixel)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])
    _easel.process_pending_composite()
    _canvas.view_changed()


func _ramp(pixel: Vector2i) -> float:
    return float(pixel.x) * RAMP_MM


## The easel's output drawn one texel a pixel into a viewport, through the
## canvas's material when *lit*, and through no material at all otherwise,
## which is the picture the view drew before it had a shader.
func _frame(through_material: bool) -> Image:
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = _easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    if through_material:
        RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The texels whose colour differs between two frames.
static func _differing(a: Image, b: Image) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    for y in a.get_height():
        for x in a.get_width():
            if a.get_pixel(x, y) != b.get_pixel(x, y):
                found.append(Vector2i(x, y))
    return found


func test_the_settings_hold_what_the_rows_can_set() -> void:
    assert_true(SaSettings.show_relief, "Show Impasto is on by default, so height shows as soon as it is painted")
    SaSettings.relief_light_angle = 405.0
    assert_almost_eq(SaSettings.relief_light_angle, 45.0, 0.0001, "The light's bearing goes round")
    SaSettings.relief_strength = 100.0
    assert_almost_eq(SaSettings.relief_strength, SaSettings.MAX_RELIEF_STRENGTH, 0.0001, "and the strength has a top")
    SaSettings.relief_strength = -1.0
    assert_almost_eq(SaSettings.relief_strength, 0.0, 0.0001, "and a floor, where the paint is drawn flat")


func test_the_view_menu_row_is_the_setting() -> void:
    var registry := _registries.view_transforms
    var row := registry.get_descriptor(&"show_relief")
    assert_not_null(row, "The View menu has a Show Impasto row")
    if row == null:
        return
    assert_eq(row.kind, SaViewTransformDescriptor.Kind.TOGGLE, "and it is a toggle")
    assert_true(registry.is_enabled(&"show_relief"), "which reads the setting")
    registry.set_enabled(&"show_relief", false)
    assert_false(SaSettings.show_relief, "and writes it")


func test_nothing_is_bound_until_a_layer_carries_height() -> void:
    var mat := _canvas.material as ShaderMaterial
    assert_false(mat.get_shader_parameter("relief_enabled"), "No height, so the relief is not read")
    _raise(Vector2i.ZERO, _ramp)
    assert_true(mat.get_shader_parameter("relief_enabled"), "Height binds the relief")
    assert_not_null(mat.get_shader_parameter("relief_texture"), "and its texture")
    SaSettings.show_relief = false
    assert_false(mat.get_shader_parameter("relief_enabled"), "The toggle takes it off")
    SaSettings.show_relief = true
    assert_true(mat.get_shader_parameter("relief_enabled"), "and puts it back")


## The light is the document's, so moving it relights the view
## and moving Preferences' does not.
func test_the_light_follows_its_bearing() -> void:
    var mat := _canvas.material as ShaderMaterial
    _doc.relief_light.angle = 90.0
    var toward: Vector3 = mat.get_shader_parameter("relief_light")
    assert_true(toward.x > 0.5, "A light at 90 degrees stands to the right")
    assert_almost_eq(toward.y, 0.0, 0.0001, "neither up nor down")
    assert_true(toward.z > 0.5, "and above the canvas")
    _doc.relief_light.strength = 2.5
    assert_almost_eq(float(mat.get_shader_parameter("relief_strength")), 2.5, 0.0001, "The strength reaches the shader")
    SaSettings.relief_light_angle = 270.0
    SaSettings.relief_strength = 7.0
    _canvas.sync_tonemap()
    toward = mat.get_shader_parameter("relief_light")
    assert_true(toward.x > 0.5, "Preferences' light leaves the open document's where it stands")
    assert_almost_eq(float(mat.get_shader_parameter("relief_strength")), 2.5, 0.0001, "and its strength as well")


## The case that matters: where no layer has height the view is unchanged to
## the texel, with Show Impasto on.
func test_a_document_without_height_draws_as_it_did_to_the_texel() -> void:
    _canvas.view_changed()
    var lit := _frame(true)
    var bare := _frame(false)
    assert_eq(_differing(lit, bare).size(), 0, "With no height anywhere the material changes no texel")


func test_a_texel_with_no_slope_beside_one_with_height_is_unchanged() -> void:
    _raise(Vector2i.ZERO, _ramp)
    var lit := _frame(true)
    var bare := _frame(false)
    var relief := GlobalShaderCompiler.get_rd().texture_get_data(_easel.relief.texture.rid, 0)
    var flat_changed := 0
    var sloped := 0
    for at in _differing(lit, bare):
        var normal := SaFieldSpec.decode_texel(relief, _easel.relief.texture.format, at.y * SIZE.x + at.x)
        if normal.r == 0.0 and normal.g == 0.0:
            flat_changed += 1
        else:
            sloped += 1
    assert_eq(flat_changed, 0, "No texel whose surface is flat changes, the cell without height included")
    assert_true(sloped > 200 * 200, "and the ramp's cell is lit, %d texels of it" % sloped)
    var far := Vector2i(400, 128)
    assert_eq(lit.get_pixelv(far), bare.get_pixelv(far), "A texel of the cell with no height is the bare picture's")


## A ramp rising to the right faces the left. Lit from the upper left it is
## brighter than the bare paint, and lit from the lower right it is darker.
func test_the_slope_is_lit_from_where_the_light_stands() -> void:
    _raise(Vector2i.ZERO, _ramp)
    var at := Vector2i(128, 128)
    var bare := _frame(false).get_pixelv(at)
    var towards := _frame(true).get_pixelv(at)
    _doc.relief_light.angle = 135.0
    var away := _frame(true).get_pixelv(at)
    assert_true(towards.get_luminance() > bare.get_luminance(), "A face turned to the light is brighter")
    assert_true(away.get_luminance() < bare.get_luminance(), "and one turned away is darker")
    _doc.relief_light.strength = 0.0
    assert_eq(_frame(true).get_pixelv(at), bare, "A strength of nought draws the paint flat")
