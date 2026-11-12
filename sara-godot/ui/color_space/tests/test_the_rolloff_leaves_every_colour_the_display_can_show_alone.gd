## The highlight rolloff leaves every colour the display can
## show alone.
##
## On the test image the rolloff must not desaturate every colour. The
## desaturation should slowly start happening only from some range, staying true
## to the original colours as much as possible. The knee moved to white and
## the chroma loss to Khronos PBR Neutral's measure, so this draws the view the
## way a painter sees it, the canvas's own material over stored numbers into an
## 8-bit viewport, and reads it back: the whole cube on a grid with the rolloff
## on and off, a colour well past white, a colour a hair past it, a profile
## before the change and after it, and the two twins of the operator, the export
## kernel and the plot, against the view colour by colour.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Steps of a channel across the cube, so 17 values per channel from 0 to 1.
const STEPS := 16
const SIDE := STEPS + 1

## One 8-bit step, in levels.
const ONE_STEP := 1

## The colours past the cube the suite reads, stored sRGB numbers. The
## first two are the reported ones, then a hair past white and a primary well past it on each
## side of the hue circle, blue among them for its fold.
const PAST_WHITE: Array[Color] = [
    Color(4.0, 1.0, 0.5),
    Color(1.0, 0.25, 0.125),
    Color(1.01, 1.01, 1.01),
    Color(1.01, 0.0, 0.0),
    Color(1.0, 1.0, 1.0),
    Color(1.0, 0.0, 0.0),
    Color(2.0, 0.25, 0.0),
    Color(1.25, 0.0, 0.0),
    Color(1.5, 0.0, 0.0),
    Color(2.0, 0.0, 0.0),
    Color(3.0, 0.0, 0.0),
    Color(0.25, 1.5, 0.1),
    Color(0.0, 1.01, 0.0),
    Color(0.0, 0.0, 1.01),
    Color(0.0, 0.0, 1.25),
    Color(0.0, 0.0, 2.0),
    Color(0.3, 0.2, 2.0),
    Color(1.5, 0.1, 1.5),
    Color(0.1, 1.2, 1.4),
    Color(0.0, 0.0, 1.06),
    Color(0.0, 0.0, 1.1),
    Color(0.0, 0.0, 1.15),
    Color(1.12, 1.12, 0.0),
    Color(1.16, 1.16, 0.0),
]

## Steps of a channel across a face of the cube at white, so 9 values a channel
## and 217 colours with one channel at 1.
const FACE_STEPS := 8

## How many steps of 1/200 a colour on a face at white is walked up from 1.0,
## so to a stored 1.5.
const RAMP_STEPS := 100
const RAMP_STEP := 1.0 / 200.0

## The most one step of the walk may move a colour, in levels. The sRGB curve
## is steep just above black, so a dark channel a colour gives up its chroma
## to rises by three levels a step at the most. Blue's fold moved it 38.
const RAMP_MOST := 4

## The stored reds the shader's tuning table reads the chroma of.
const TABLE_REDS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

## The profile a build before the knee moved wrote, and the version it wrote it under.
const BEFORE_B25 := 20

const SCRATCH := "test_rolloff_profile.cfg"

## Every preference the view reads that a suite before this one may have moved,
## put back to a fresh profile's value for each case and to what it was after.
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
var _saved_path := ""
var _canvas: SaCanvas = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
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
    SaSettings.settings_path = _saved_path
    for key: StringName in VIEW_KEYS:
        SaSettings.set(key, _saved[key])
    var scratch := ProjectSettings.globalize_path(SaDataRoot.path(SCRATCH))
    if FileAccess.file_exists(scratch):
        DirAccess.remove_absolute(scratch)


## Every step of 1/16 per channel inside the cube, with the rolloff on and off
## at the default knee and desaturation: the same picture within one step.
func test_every_colour_inside_the_cube_is_shown_the_same_with_the_rolloff_on() -> void:
    assert_true(SaSettings.tonemap_highlights, "A fresh profile has the rolloff on")
    var grid := _grid()
    var on := _view(grid, true)
    var off := _view(grid, false)
    var worst := 0
    var worst_at := Color()
    var moved := 0
    for i in grid.size():
        var a := _bytes(on, i)
        var b := _bytes(off, i)
        var differ := maxi(absi(a.x - b.x), maxi(absi(a.y - b.y), absi(a.z - b.z)))
        if differ > 0:
            moved += 1
        if differ > worst:
            worst = differ
            worst_at = grid[i]
    assert_eq(grid.size(), SIDE * SIDE * SIDE, "The grid is every step of 1/%d per channel" % STEPS)
    assert_true(worst <= ONE_STEP, "%d of %d colours moved, the most %d levels at %s" % [moved, grid.size(), worst, worst_at])
    print("    %d of %d colours inside the cube moved with the rolloff on, the most by %d" % [moved, grid.size(), worst])


## A stored (4.0, 1.0, 0.5), far past white, keeps the hue its decoded light has
## to within a degree and is fainter than the colour it is four times of.
func test_a_colour_far_past_white_keeps_its_hue_and_gives_up_chroma() -> void:
    var shown := _view(PAST_WHITE, true)
    var hot := _lab(_bytes(shown, 0))
    var plain := _lab(_bytes(shown, 1))
    var source := SaOklab.from_linear_srgb(_decoded(PAST_WHITE[0]))
    var turned := absf(rad_to_deg(angle_difference(_hue(source), _hue(hot))))
    assert_true(
        turned <= 1.0,
        (
            "A stored 4, 1, 0.5 turns %.2f degrees, %.2f against its own %.2f"
            % [turned, rad_to_deg(_hue(hot)), rad_to_deg(_hue(source))]
        )
    )
    assert_true(
        _chroma(hot) < _chroma(plain),
        "with chroma %.4f, under the %.4f of a stored 1, 0.25, 0.125" % [_chroma(hot), _chroma(plain)]
    )


## A stored 1.01 differs from a stored 1.0 by too little to see, grey and red
## alike, because the loss grows from nothing at white.
func test_a_hair_past_white_is_shown_as_white_is() -> void:
    var shown := _view(PAST_WHITE, true)
    for pair: Array in [[2, 4], [3, 5]]:
        var hair := _bytes(shown, pair[0])
        var at := _bytes(shown, pair[1])
        var differ := maxi(absi(hair.x - at.x), maxi(absi(hair.y - at.y), absi(hair.z - at.z)))
        assert_true(
            differ <= ONE_STEP, "A stored %s shows as %s beside %s for %s" % [PAST_WHITE[pair[0]], hair, at, PAST_WHITE[pair[1]]]
        )


## Every colour on a face of the cube at white, walked up from a stored 1.0 to
## 1.5 in steps of 1/200, gives up its chroma a little at a time. Blue and
## yellow were the colours that did not: the rolloff's step to white carried
## them a hair out of the cube, where the gamut map's first exit is across the
## fold, and a stored blue of 1.06 was drawn (0, 49, 232) one step after
## (0, 11, 255).
func test_a_colour_on_the_cubes_face_gives_up_its_chroma_without_a_jump() -> void:
    var faces: Array[Color] = []
    for b in FACE_STEPS + 1:
        for g in FACE_STEPS + 1:
            for r in FACE_STEPS + 1:
                if maxi(r, maxi(g, b)) == FACE_STEPS:
                    faces.append(Color(float(r) / FACE_STEPS, float(g) / FACE_STEPS, float(b) / FACE_STEPS))
    var walked: Array[Color] = []
    for face in faces:
        for step in RAMP_STEPS + 1:
            var scale := 1.0 + step * RAMP_STEP
            walked.append(Color(face.r * scale, face.g * scale, face.b * scale))
    var shown := _view(walked, true)
    var worst := [0, Color(), Color()]
    for i in walked.size():
        if i % (RAMP_STEPS + 1) == 0:
            continue
        var was := _bytes(shown, i - 1)
        var now := _bytes(shown, i)
        var moved := maxi(absi(now.x - was.x), maxi(absi(now.y - was.y), absi(now.z - was.z)))
        if moved > int(worst[0]):
            worst = [moved, walked[i - 1], walked[i]]
    assert_eq(faces.size(), 217, "The faces at white hold every step of 1/%d" % FACE_STEPS)
    assert_true(worst[0] <= RAMP_MOST, "A step from %s to %s moved the colour by %d levels" % [worst[1], worst[2], worst[0]])
    var said := "    %d colours on the faces at white walked to 1.5, the most a step of 1/200 moved one is %d levels"
    print(said % [faces.size(), worst[0]])


## A fresh profile has the rolloff on and the knee at white.
func test_a_fresh_profile_rolls_off_from_white() -> void:
    var fresh := SaSettingsValues.new()
    assert_true(fresh.tonemap_highlights, "A fresh profile has the rolloff on")
    assert_almost_eq(fresh.tonemap_knee, 1.0, 0.0, "and the knee at white")
    fresh.free()
    var mat := _canvas.material as ShaderMaterial
    assert_true(mat.get_shader_parameter("tonemap_enabled"), "and the view hears it")
    assert_almost_eq(mat.get_shader_parameter("knee"), 1.0, 0.0, "with the knee")


## A profile written before the change, on the old default knee with the
## switch off, reads back at a knee of 1.0 and on.
func test_a_profile_from_before_reads_back_at_white_and_on() -> void:
    _load_profile(BEFORE_B25, 0.5, false)
    assert_almost_eq(SaSettings.tonemap_knee, 1.0, 1e-6, "The old default knee reads as the new one")
    assert_true(SaSettings.tonemap_highlights, "and the switch that was off is on")


## A knee the painter chose is kept, and so is a switch turned off after the
## migration, which a profile of this version holds.
func test_a_chosen_knee_and_a_switch_turned_off_since_are_kept() -> void:
    _load_profile(BEFORE_B25, 0.7, false)
    assert_almost_eq(SaSettings.tonemap_knee, 0.7, 1e-6, "A knee the painter moved stays where it was moved")
    assert_true(SaSettings.tonemap_highlights, "while the switch turns on, once")
    _load_profile(SaSettingsMigrations.SETTINGS_VERSION, 0.5, false)
    assert_false(SaSettings.tonemap_highlights, "A switch turned off after the migration stays off")
    assert_almost_eq(SaSettings.tonemap_knee, 0.5, 1e-6, "and a knee of 0.5 chosen since stays 0.5")


## The export kernel gives the view's bytes, and so does the plot's own
## transcription, for every colour the cases above read.
func test_the_export_and_the_plot_give_the_views_numbers() -> void:
    var colours := _grid()
    colours.append_array(PAST_WHITE)
    var shown := _view(colours, true)
    var exported := _exported(colours)
    var knee := SaSettings.tonemap_knee
    var desat := SaSettings.tonemap_desaturation
    var export_worst := [0, Color()]
    var plot_worst := [0, Color()]
    for i in colours.size():
        var view := _bytes(shown, i)
        var place := _place(i, exported.get_width())
        var out := exported.get_pixel(place.x, place.y)
        _note_worst(export_worst, view, Vector3i(out.r8, out.g8, out.b8), colours[i])
        var plotted := SaCurvePlot.rolled(colours[i], knee, desat)
        _note_worst(plot_worst, view, Vector3i(plotted.r8, plotted.g8, plotted.b8), colours[i])
    assert_true(export_worst[0] <= ONE_STEP, "The export differs from the view by %d levels at %s" % export_worst)
    assert_true(plot_worst[0] <= ONE_STEP, "The plot differs from the view by %d levels at %s" % plot_worst)


## The shader's tuning table, read off the view: the Oklab chroma left of a
## stored red at each value, at the default knee and desaturation. Printed so
## the table in the roll-off notes can be retaken, and held to it.
func test_the_tuning_table_is_what_the_view_shows() -> void:
    var reds: Array[Color] = []
    for value: float in TABLE_REDS:
        reds.append(Color(value, 0.0, 0.0))
    var shown := _view(reds, true)
    var row := PackedStringArray()
    for i in reds.size():
        row.append(("%.3f" % _chroma(_lab(_bytes(shown, i)))).trim_prefix("0"))
    var line := "  ".join(row)
    print("    red's chroma    %s" % line)
    # The table lives on the roll-off's notes page, not in the shader's header.
    var page := ProjectSettings.globalize_path("res://").path_join("../docs/specs/view-rolloff.md")
    if not FileAccess.file_exists(page):
        skip("the roll-off notes page is not in this copy of the source")
        return
    var source := FileAccess.get_file_as_string(page)
    assert_true(source.contains("  red's chroma    %s\n" % line), "The spec page's table reads %s" % line)


## The cube on a grid of 1/16 per channel, as stored sRGB numbers.
static func _grid() -> Array[Color]:
    var out: Array[Color] = []
    for b in SIDE:
        for g in SIDE:
            for r in SIDE:
                out.append(Color(float(r) / STEPS, float(g) / STEPS, float(b) / STEPS))
    return out


## How many texels a row of the picture of *count* colours holds.
static func _width(count: int) -> int:
    return mini(count, SIDE * SIDE)


## *colours* as one texel each in a float texture, row after row.
static func _texture(colours: Array[Color]) -> SaTexture:
    var width := _width(colours.size())
    var height := ceili(float(colours.size()) / width)
    var texture := SaTexture.new(Vector2i(width, height))
    var texels := PackedFloat32Array()
    texels.resize(width * height * 4)
    for i in colours.size():
        var c := colours[i]
        texels[i * 4] = c.r
        texels[i * 4 + 1] = c.g
        texels[i * 4 + 2] = c.b
        texels[i * 4 + 3] = 1.0
    texture.rd.texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## *colours* drawn one texel a pixel through the canvas's own material into an
## 8-bit viewport, with the rolloff *on* or off, and read back.
func _view(colours: Array[Color], on: bool) -> Image:
    SaSettings.tonemap_highlights = on
    _canvas.sync_tonemap()
    var texture := _texture(colours)
    var viewport := SubViewport.new()
    viewport.size = texture.size
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = texture.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(texture.size)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    SaSettings.tonemap_highlights = _fresh_rolloff()
    return image


## *colours* through the export's rolloff and its eight bits, at the knee and
## desaturation the view has.
func _exported(colours: Array[Color]) -> Image:
    var params := SaExportGamut.tonemap_params(true, SaSettings.tonemap_knee, SaSettings.tonemap_desaturation, 1.0)
    return SaExportGamut.encoded_byte_image(_texture(colours), SaColorSpace.srgb(), null, params)


## A profile at *version* holding *knee* and the switch *on*, written to the
## scratch path and read the way a launch reads one.
func _load_profile(version: int, knee: float, on: bool) -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", version)
    config.set_value("ui", "tonemap_knee", knee)
    config.set_value("ui", "tonemap_highlights", on)
    var path := ProjectSettings.globalize_path(SaDataRoot.path(SCRATCH))
    assert_eq(config.save(path), OK, "The profile is written")
    SaSettings.settings_path = path
    SaSettings.load_settings()


static func _fresh_rolloff() -> bool:
    var fresh := SaSettingsValues.new()
    var on := fresh.tonemap_highlights
    fresh.free()
    return on


static func _bytes(image: Image, index: int) -> Vector3i:
    var place := _place(index, image.get_width())
    var c := image.get_pixel(place.x, place.y)
    return Vector3i(c.r8, c.g8, c.b8)


## Where the texel of colour *index* sits in a picture *width* texels wide.
static func _place(index: int, width: int) -> Vector2i:
    return Vector2i(index % width, floori(float(index) / width))


## The largest channel difference of *other* from *view*, kept in *worst* with
## the colour it was at when it is the largest yet.
static func _note_worst(worst: Array, view: Vector3i, other: Vector3i, at: Color) -> void:
    var differ := maxi(absi(view.x - other.x), maxi(absi(view.y - other.y), absi(view.z - other.z)))
    if differ > int(worst[0]):
        worst[0] = differ
        worst[1] = at


## *stored* sRGB numbers decoded to light, the mirrored curve the shader uses.
static func _decoded(stored: Color) -> Vector3:
    return OkhsvConversions.srgb_transfer_function_inv(Vector3(stored.r, stored.g, stored.b))


## Bytes on the screen as Oklab.
static func _lab(bytes: Vector3i) -> Vector3:
    return SaOklab.from_linear_srgb(_decoded(Color8(bytes.x, bytes.y, bytes.z)))


static func _chroma(lab: Vector3) -> float:
    return Vector2(lab.y, lab.z).length()


static func _hue(lab: Vector3) -> float:
    return atan2(lab.z, lab.y)
