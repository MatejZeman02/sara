## The Knee moves the picture smoothly past every value, 3
## included.
##
## A Knee crossing value 3 must not make the picture suddenly jump. The canvas material skipped the roll-off for a texel whose
## decoded peak stood at or under the Knee, while the operator brings anything
## past white down to it, so with the Knee above 1 a texel between white and the
## Knee reached the screen clipped channel by channel and flipped to rolled off
## the moment the Knee dropped under it. The Preferences preview is baked at a
## peak of 3, so the whole picture flipped at 3. This draws a texel at a peak of
## 2 through the canvas material on each side of it, the preview pair on each
## side of 3, and a colour under white at the default Knee.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The most two drawings either side of a Knee may differ by, in levels.
const TWO_STEPS := 2

## A stored colour whose decoded peak is 2.0 with the other two channels at a
## quarter and an eighth of it in light.
const HOT_LIGHT := Vector3(2.0, 0.5, 0.25)

## A colour under white, stored sRGB numbers.
const UNDER_WHITE := Color(0.8, 0.4, 0.2)

const VIEW_KEYS: Array[StringName] = [
    &"tonemap_highlights",
    &"tonemap_knee",
    &"tonemap_desaturation",
    &"gamut_mapping",
    &"display_exposure_enabled",
    &"display_exposure_stops",
    &"display_profile",
    &"shape_check",
]

var _saved := {}
var _canvas: SaCanvas = null


func before_each() -> void:
    var fresh := SaSettingsValues.new()
    for key: StringName in VIEW_KEYS:
        _saved[key] = SaSettings.get(key)
        SaSettings.set(key, fresh.get(key))
    fresh.free()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.ensure_easel()
    _canvas.sync_tonemap()


func after_each() -> void:
    if _canvas != null:
        _canvas.free()
    _canvas = null
    for key: StringName in VIEW_KEYS:
        SaSettings.set(key, _saved[key])


## Under either gamut mapping, since under clip a texel past white reaches the
## shortcut and under Oklab the gamut map sends it through the roll-off anyway.
func test_a_peak_of_2_reads_the_same_at_a_knee_of_1_9_and_of_2_1() -> void:
    for mapping: String in SaGamutMapping.MODES:
        SaSettings.gamut_mapping = mapping
        var stored := _encoded(HOT_LIGHT)
        var under := _texel_at(stored, 1.9)
        var over := _texel_at(stored, 2.1)
        var moved := _differ(under, over)
        assert_true(moved <= TWO_STEPS, "Under %s a peak of 2 reads %s at 1.9 and %s at 2.1" % [mapping, under, over])
        var operator := SaCurvePlot.rolled(stored, 2.1, SaSettings.tonemap_desaturation)
        var expected := Vector3i(operator.r8, operator.g8, operator.b8)
        assert_true(_differ(over, expected) <= TWO_STEPS, "At 2.1 the view is the operator's %s, read %s" % [expected, over])
        var clipped := _bytes_of(_encoded(HOT_LIGHT.clampf(0.0, 1.0)))
        var light := _decoded(over)
        var ratio := light.y / light.x
        var held := HOT_LIGHT.y / HOT_LIGHT.x
        var clipped_ratio := HOT_LIGHT.y / 1.0
        var nearer_held := absf(ratio - held) < absf(ratio - clipped_ratio)
        assert_true(nearer_held, "Green over red is %.3f, held %.3f, clipped %.3f" % [ratio, held, clipped_ratio])
        assert_true(_differ(over, clipped) > TWO_STEPS, "and the view is not the clipped %s" % clipped)


func test_the_preview_pair_reads_the_same_at_a_knee_of_2_99_and_of_3_01() -> void:
    for run_operator: bool in [true, false]:
        var under := _preview_at(run_operator, 2.99)
        var over := _preview_at(run_operator, 3.01)
        var worst := 0
        for y in under.get_height():
            for x in under.get_width():
                worst = maxi(worst, _differ(_pixel(under, x, y), _pixel(over, x, y)))
        var half := "operated" if run_operator else "plain"
        assert_true(worst <= TWO_STEPS, "The %s half moves by %d levels at the most from 2.99 to 3.01" % [half, worst])


func test_a_colour_under_white_at_the_default_knee_reaches_the_screen_unchanged() -> void:
    assert_eq(SaSettings.tonemap_knee, 1.0, "A fresh profile has a Knee of 1.0")
    var shown := _texel_at(UNDER_WHITE, 1.0)
    assert_eq(shown, _bytes_of(UNDER_WHITE), "%s is shown as stored" % UNDER_WHITE)


## The bytes of the one *stored* texel drawn through the canvas material at
## *knee*, with the roll-off on.
func _texel_at(stored: Color, knee: float) -> Vector3i:
    SaSettings.tonemap_highlights = true
    SaSettings.tonemap_knee = knee
    _canvas.sync_tonemap()
    var texture := SaTexture.new(Vector2i.ONE)
    var texels := PackedFloat32Array([stored.r, stored.g, stored.b, 1.0])
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    var output := Texture2DRD.new()
    output.texture_rd_rid = texture.rid
    var image := _drawn(output.get_rid(), _canvas.material.get_rid(), Vector2i.ONE)
    return _pixel(image, 0, 0)


## One half of the Preferences pair drawn texel for texel at *knee*: the shared
## picture, which a preview takes on entering the tree, through its own
## material, as the Display page draws it.
func _preview_at(run_operator: bool, knee: float) -> Image:
    var preview := SaGamutPreview.new(run_operator)
    preview.configure(knee, SaSettings.tonemap_desaturation)
    var image := _drawn(SaGamutPreview.picture().get_rid(), preview.material.get_rid(), SaGamutPreview.TEXELS)
    preview.free()
    return image


## The texture *texture* drawn one texel a pixel through the material
## *material* into an 8-bit viewport *size* across, and read back.
func _drawn(texture: RID, material: RID, size: Vector2i) -> Image:
    var viewport := _viewport(size)
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material)
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(size)), texture)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


func _viewport(size: Vector2i) -> SubViewport:
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    return viewport


static func _pixel(image: Image, x: int, y: int) -> Vector3i:
    var c := image.get_pixel(x, y)
    return Vector3i(c.r8, c.g8, c.b8)


## What an 8-bit screen shows of *stored* numbers at or under white.
static func _bytes_of(stored: Color) -> Vector3i:
    return Vector3i(stored.r8, stored.g8, stored.b8)


static func _differ(a: Vector3i, b: Vector3i) -> int:
    return maxi(absi(a.x - b.x), maxi(absi(a.y - b.y), absi(a.z - b.z)))


## *light* stored as the sRGB numbers a document holds.
static func _encoded(light: Vector3) -> Color:
    var curve := SaTransferFunction.srgb()
    return Color(curve.encode(light.x), curve.encode(light.y), curve.encode(light.z))


## Bytes on the screen decoded to light.
static func _decoded(bytes: Vector3i) -> Vector3:
    var c := Color8(bytes.x, bytes.y, bytes.z)
    return OkhsvConversions.srgb_transfer_function_inv(Vector3(c.r, c.g, c.b))
