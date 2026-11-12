## The clouds of the Welcome picture drift in from a new place at each opening:
## every light ships as a back, the clouds as a strip that repeats in X and the
## land in front, and the window composes the three once at an offset drawn
## for the opening.
##
## The parts are the shipped ones, which `scripts/export_welcome_lights.py`
## solved from Sara's own exports of the source document, and the flat
## flat lights beside them give the three back with no drift. How
## the window looks is the two `...` scenarios under `scenarios/`.
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"

## The most one channel of a texel of a light composed with no drift may differ
## from the flat light, in levels of 255, outside the seam's band, and the most
## the mean of that difference may be. The solve of each part rounds to eight
## bits and the blends round again, and a few texels along the land's edge where
## a gradient map grades a mixed texel otherwise than its parts take 4 to 7:
## the dawn is the worst, at 7 on 19 texels.
const WORST: int = 8
const MEAN: float = 0.5

## A screened sun's glow may stand in front of the land's edge in the flat
## light, where the parts lay the body behind the land so that a sun going
## down is hidden by the ridge. There the land's own texels show with no glow
## on them, a dull patch under the sun that the parts cannot carry. Texels
## over `WORST` are let stand only within `GLOW` pixels of the body's place and
## only `PATCH` of them, which the autumn dawn's 287 are well within.
const GLOW: float = 120.0
const PATCH: int = 400

## In the seam's band, the columns either side of where the strip starts, the
## strip fades into itself moved by half its width, so the clouds there are
## not the frame's by design. Only the mean of the band is held, to 3 levels:
## the clear day, the most cloud that crosses the seam, comes to 2.5.
const SEAM_MEAN: float = 3.0

## The rolls other than naught the clouds are drifted by.
const ROLLS: Array[float] = [0.3, 0.7]


func _sidecar() -> Dictionary:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    return said if said is Dictionary else {}


func _parts() -> Dictionary:
    return PictureParts.listed_in(_sidecar(), SHIPPED)


func _flat(file: String) -> Image:
    var image := Image.load_from_file(ProjectSettings.globalize_path(SHIPPED + file))
    image.convert(Image.FORMAT_RGBA8)
    return image


func _part(path: String) -> Image:
    var image := PictureParts.image_of(path, true)
    image.convert(Image.FORMAT_RGBA8)
    return image


## Whether column *x* of a light *width* wide lies in the seam's band of *parts*.
static func _in_seam(parts: PictureParts, x: int, width: int) -> bool:
    var from_seam := posmod(x - parts.origin, width)
    return mini(from_seam, width - from_seam) <= parts.seam


## The largest difference of one channel, in levels, between *a* and *b* at
## *x* and *y*.
static func _apart(a: PackedByteArray, b: PackedByteArray, at: int) -> int:
    return maxi(absi(a[at] - b[at]), maxi(absi(a[at + 1] - b[at + 1]), absi(a[at + 2] - b[at + 2])))


func test_every_light_ships_in_the_three_parts_and_each_is_read_as_an_image() -> void:
    var lights := PictureLights.lights_in(_sidecar(), SHIPPED)
    var parts := _parts()
    assert_eq(parts.size(), 24, "the six lights of each of the four seasons come in parts")
    for light in lights:
        var file := light.path.get_file()
        assert_true(parts.has(file), "%s comes in parts" % file)
        var of: PictureParts = parts[file]
        var back := PictureParts.image_of(of.back, true)
        var strip := PictureParts.image_of(of.clouds, true)
        var land := PictureParts.image_of(of.land, true)
        assert_true(back != null and strip != null and land != null, "%s's parts load as images, which the CPU composes" % file)
        assert_eq(back.get_size(), Vector2i(1440, 480), "%s's back is the light's size" % file)
        assert_eq(strip.get_width(), 1440, "%s's strip is as wide as the light, so it wraps once across it" % file)
        assert_eq(land.get_size(), strip.get_size(), "%s's land covers the strip's rows" % file)
        var rows := strip.get_height()
        assert_true(rows <= 301, "and only the sky's rows are composed, to the skyline: %d" % rows)
        assert_eq(
            of.origin,
            (parts.values()[0] as PictureParts).origin,
            "every light's strip starts at one column, so a fade between two drifts as one sky"
        )


func test_with_no_drift_each_light_is_s_flat_light() -> void:
    var parts := _parts()
    for file: String in parts:
        var of: PictureParts = parts[file]
        var made := of.compose_from_sources(0.0).get_data()
        var flat := _flat(file)
        var wanted := flat.get_data()
        var width := flat.get_width()
        var worst := 0
        var total := 0
        var counted := 0
        var seam_total := 0
        var seam_counted := 0
        var patch := 0
        for y in flat.get_height():
            for x in width:
                var at := (y * width + x) * 4
                var apart := _apart(made, wanted, at)
                if _in_seam(of, x, width):
                    seam_total += apart
                    seam_counted += 1
                    continue
                if apart > WORST and of.body != null and Vector2(x, y).distance_to(of.body.at) <= GLOW:
                    patch += 1
                    total += apart
                    counted += 1
                    continue
                worst = maxi(worst, apart)
                total += apart
                counted += 1
        var mean := float(total) / float(counted)
        var seam_mean := float(seam_total) / float(seam_counted)
        assert_true(
            worst <= WORST, "%s with no drift is its flat light within %d levels outside the seam: %d" % [file, WORST, worst]
        )
        assert_true(patch <= PATCH, "%s has %d texels over %d levels in its sun's glow, within %d" % [file, patch, WORST, PATCH])
        assert_true(mean <= MEAN, "%s is %.2f on the mean, within %.1f" % [file, mean, MEAN])
        assert_true(seam_mean <= SEAM_MEAN, "and %.2f on the mean of the seam's band, within %.1f" % [seam_mean, SEAM_MEAN])


func test_at_two_other_drifts_the_land_stays_and_the_clouds_move() -> void:
    var parts := _parts()
    for file: String in ["0.18-summer-dusk.png", "0.18-winter-day-clear.png"]:
        var of: PictureParts = parts[file]
        var still := of.compose_from_sources(0.0).get_data()
        var back := _under_the_clouds(of).get_data()
        var strip_image := _part(of.clouds)
        var strip := strip_image.get_data()
        var land := _part(of.land).get_data()
        var width := strip_image.get_width()
        var rows := strip_image.get_height()
        for roll in ROLLS:
            var drifted := of.compose_from_sources(roll)
            var made := drifted.get_data()
            var outside := 0
            for y in range(of.top + rows, 480):
                for x in range(0, width, 3):
                    outside = maxi(outside, _apart(made, still, (y * width + x) * 4))
            assert_eq(outside, 0, "%s at %.1f: every row under the clouds' is the light unchanged" % [file, roll])
            var shift := posmod(of.origin + floori(roll * float(width)), width)
            var land_moved := 0
            var land_seen := 0
            var clouds_off := 0
            var clouds_seen := 0
            var moved := 0
            for y in rows:
                for x in width:
                    var at := ((of.top + y) * width + x) * 4
                    var in_strip := (y * width + x) * 4
                    if land[in_strip + 3] == 255:
                        land_seen += 1
                        if _apart(made, still, at) > 0:
                            land_moved += 1
                        continue
                    if land[in_strip + 3] != 0 or x % 2 != 0:
                        continue
                    var from_strip := (y * width + posmod(x - shift, width)) * 4
                    var cloud := Color8(strip[from_strip], strip[from_strip + 1], strip[from_strip + 2], strip[from_strip + 3])
                    var sky := Color8(back[at], back[at + 1], back[at + 2], 255)
                    var laid := sky.blend(cloud)
                    var got := Color8(made[at], made[at + 1], made[at + 2], 255)
                    clouds_seen += 1
                    if maxf(absf(laid.r - got.r), maxf(absf(laid.g - got.g), absf(laid.b - got.b))) > 1.5 / 255.0:
                        clouds_off += 1
                    if _apart(made, still, at) > WORST:
                        moved += 1
            assert_true(land_seen > 1000, "%s has land standing in front of the clouds' rows: %d texels" % [file, land_seen])
            assert_eq(land_moved, 0, "%s at %.1f: not one texel of the land in front moved" % [file, roll])
            assert_eq(
                clouds_off,
                0,
                (
                    "%s at %.1f: the sky is the back with the strip laid %d columns round, every one of %d texels"
                    % [file, roll, shift, clouds_seen]
                )
            )
            assert_true(
                moved * 20 > clouds_seen,
                (
                    "%s at %.1f: and the clouds are somewhere else, %d texels of %d past %d levels"
                    % [file, roll, moved, clouds_seen, WORST]
                )
            )


func test_the_strip_s_edge_columns_continue_each_other() -> void:
    var parts := _parts()
    for file: String in parts:
        var of: PictureParts = parts[file]
        var strip_image := _part(of.clouds)
        var strip := strip_image.get_data()
        var width := strip_image.get_width()
        var half := width >> 1
        var worst_pair := 0.0
        var across := 0.0
        var beside := 0.0
        for y in strip_image.get_height():
            var first := _premultiplied(strip, (y * width) * 4)
            var last := _premultiplied(strip, (y * width + width - 1) * 4)
            var middle_right := _premultiplied(strip, (y * width + half) * 4)
            var middle_left := _premultiplied(strip, (y * width + half - 1) * 4)
            worst_pair = maxf(worst_pair, maxf(_levels(first, middle_right), _levels(last, middle_left)))
            across += _levels(first, last)
            beside += _levels(middle_right, middle_left)
        assert_true(worst_pair <= 1.0, "%s's edge columns are its middle two, within a level: %.1f" % [file, worst_pair])
        assert_true(
            absf(across - beside) / float(strip_image.get_height()) <= 1.0,
            (
                "so the step across the wrap is the step between two neighbours: %.2f and %.2f levels a row"
                % [across / strip_image.get_height(), beside / strip_image.get_height()]
            )
        )


func test_the_window_shows_a_light_composed_from_its_parts() -> void:
    var band := WelcomePicture.new()
    band.show_at(13.0, "", null)
    band.settle()
    var shown := band.picture.texture
    assert_true(shown is ImageTexture, "the band shows the composed light, not a file: %s" % shown)
    assert_eq(shown.get_size(), Vector2(1440, 480), "at the light's size")
    assert_true((shown as ImageTexture).get_image().has_mipmaps(), "with the mipmaps that keep it clean at scale 1")
    assert_true(band.drift >= 0.0 and band.drift <= 1.0, "the drift is a roll of the strip's width")
    band.free()


## The back of *of* with its body laid on it, when the body is laid under the
## clouds, which is the sky the strip drifts over.
func _under_the_clouds(of: PictureParts) -> Image:
    var sky := _part(of.back)
    if of.body != null and not of.body.over_clouds:
        var body := _part(of.body.path)
        var rows := (PictureParts.image_of(of.clouds, true)).get_height()
        var laid := Rect2i(of.body.box, body.get_size()).intersection(Rect2i(0, of.top, sky.get_width(), rows))
        sky.blend_rect(body, Rect2i(laid.position - of.body.box, laid.size), laid.position)
    return sky


## The colour of the texel at *at* times its alpha, in levels of 255.
static func _premultiplied(bytes: PackedByteArray, at: int) -> Vector3:
    var alpha := float(bytes[at + 3]) / 255.0
    return Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) * alpha


static func _levels(a: Vector3, b: Vector3) -> float:
    var apart := (a - b).abs()
    return maxf(apart.x, maxf(apart.y, apart.z))
