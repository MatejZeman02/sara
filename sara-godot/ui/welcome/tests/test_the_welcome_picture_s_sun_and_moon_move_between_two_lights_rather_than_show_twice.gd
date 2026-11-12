## The Welcome picture's sun and moon move between two lights rather than show
## twice: each light's body ships as a part of its own, and two lights fading
## lay it once along a path, a sun into a sun at the place between them and a
## sun and a moon handing over, the sun behind the land.
##
## The pictures are the shipped ones, which `scripts/export_welcome_lights.py`
## solved from Sara's own exports of the source document. How the window
## looks is the `...` scenario under `scenarios/`.
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"

## The tolerance for a light composed against Sara's export of it.
const WORST: int = 8
const MEAN: float = 0.5

## A texel is the body's disc where the body changes it by this much of the
## most it changes any texel, the share the export found the disc's middle by.
const DISC: float = 0.85

## How far from where the middle should stand, in pixels, the middle read off
## the picture may be, since the clouds pass over a glow and take some of it.
const NEAR: float = 6.0

## Where a body is laid to leave it out, far off the picture.
const NOWHERE := Vector2(-100000.0, -100000.0)

## The side of the cells a disc's texels are gathered in, in pixels, so two
## texels of one place stand at most two cells apart. The dawn's sun carries a
## ray painted beside it, and a glow half set behind the land shows
## in specks along the ridge, both within a cell of their disc, while two
## places of one light would stand fifty pixels apart and more.
const CELL: int = 12

## The two fades, each from its first light to its second, in
## summer and in winter, the seasons furthest apart.
const FADES: Array[Array] = [
    ["0.18-summer-day-clear.png", "0.18-summer-dusk.png"],
    ["0.18-summer-dusk.png", "0.18-summer-night.png"],
    ["0.18-winter-day-clear.png", "0.18-winter-dusk.png"],
    ["0.18-winter-dusk.png", "0.18-winter-night.png"],
]
const FRACTIONS: Array[float] = [0.0, 0.5, 1.0]


func _parts() -> Dictionary:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    return PictureParts.listed_in(said if said is Dictionary else {}, SHIPPED)


func _flat(file: String) -> PackedByteArray:
    var image := Image.load_from_file(ProjectSettings.globalize_path(SHIPPED + file))
    image.convert(Image.FORMAT_RGBA8)
    return image.get_data()


## *first* and *second* composed with their bodies at *places*, mixed at
## *fraction* as the band fades the second over the first.
static func _mixed(first: Image, second: Image, fraction: float) -> PackedByteArray:
    var a := first.get_data()
    var b := second.get_data()
    var mixed := PackedByteArray()
    mixed.resize(a.size())
    for at in a.size():
        mixed[at] = roundi(lerpf(float(a[at]), float(b[at]), fraction))
    return mixed


## The largest change of one channel at each texel of the rows from *bare* to
## *with*, as floats in levels.
static func _change(with: PackedByteArray, bare: PackedByteArray, rows: int) -> PackedFloat32Array:
    var change := PackedFloat32Array()
    change.resize(1440 * rows)
    for at in change.size():
        var i := at * 4
        change[at] = maxi(absi(with[i] - bare[i]), maxi(absi(with[i + 1] - bare[i + 1]), absi(with[i + 2] - bare[i + 2])))
    return change


## The texels of *change* at least *least*: their middle, how many they are
## and where each is.
static func _disc(change: PackedFloat32Array, least: float) -> Dictionary:
    var sum := Vector2.ZERO
    var count := 0
    for at in change.size():
        if change[at] >= least:
            sum += Vector2(at % 1440, floori(at / 1440.0))
            count += 1
    var texels := {}
    for at in change.size():
        if change[at] >= least:
            texels[Vector2i(at % 1440, floori(at / 1440.0))] = true
    return {"middle": sum / float(maxi(count, 1)), "count": count, "texels": texels}


## Whether the texels of *disc* stand in one place: the cells of `CELL`
## pixels they fall in hold together, each beside another, but for a few
## texels, under a tenth of them, that a cloud's edge cut off.
static func _one_place(disc: Dictionary) -> bool:
    var left := {}
    for texel: Vector2i in disc.texels:
        var cell := Vector2i(floori(texel.x / float(CELL)), floori(texel.y / float(CELL)))
        left[cell] = int(left.get(cell, 0)) + 1
    var largest := 0
    while not left.is_empty():
        var start: Vector2i = left.keys()[0]
        var reached := [start]
        var texels := int(left[start])
        left.erase(start)
        var held := 0
        while held < reached.size():
            var at: Vector2i = reached[held]
            held += 1
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var near := at + Vector2i(dx, dy)
                    if left.has(near):
                        texels += int(left[near])
                        left.erase(near)
                        reached.append(near)
        largest = maxi(largest, texels)
    return largest * 10 >= int(disc.count) * 9


## *of* with its body and no reflection, since the reflection on the lake
## goes with the body and would pull the disc's middle down to it.
static func _unreflected(of: PictureParts) -> PictureParts:
    var body := PictureParts.Body.new(of.body.path, of.body.kind, of.body.box, of.body.at, of.body.sets, of.body.over_clouds)
    return PictureParts.new(of.back, of.clouds, of.land, of.top, of.origin, of.seam, body)


static func _rows(of: PictureParts) -> int:
    return (PictureParts.image_of(of.clouds, true)).get_height()


func test_every_light_with_a_sun_or_moon_ships_it_as_a_part_with_its_painted_place() -> void:
    var parts := _parts()
    var kinds := {}
    for file: String in parts:
        var of: PictureParts = parts[file]
        if of.body == null:
            continue
        kinds[file] = of.body.kind
        assert_true(PictureParts.image_of(of.body.path, true) != null, "%s's body loads as an image" % file)
        assert_true(of.body.sets > of.body.at.y, "%s's body sets below where it is painted" % file)
    var wanted := {}
    for season: String in PictureLights.SEASONS:
        for light: String in ["dawn", "day-clear", "day-hazy", "dusk"]:
            wanted["0.18-%s-%s.png" % [season, light]] = "sun"
        wanted["0.18-%s-night.png" % season] = "moon"
    assert_eq(kinds, wanted, "every sunny or moonlit light carries its body, in every season, the overcast day none")


func test_the_back_holds_no_body_of_its_own() -> void:
    var parts := _parts()
    for file: String in parts:
        var of: PictureParts = parts[file]
        if of.body == null:
            continue
        var rows := _rows(of)
        var unreflected := _unreflected(of)
        var bare := unreflected.compose_from_sources(0.0, [], NOWHERE).get_data()
        var with := unreflected.compose_from_sources(0.0).get_data()
        var change := _change(with, bare, rows)
        var most := 0.0
        for at in change.size():
            most = maxf(most, change[at])
        var disc := _disc(change, most * DISC)
        assert_true(most >= 24.0, "%s's body changes its light by %d levels, so the back lacks it" % [file, roundi(most)])
        assert_true(
            disc.middle.distance_to(of.body.at) <= NEAR,
            "%s's body is laid where it is painted: %s for %s" % [file, disc.middle, of.body.at]
        )
        assert_true(_one_place(disc), "%s's body shows at one place, %d texels" % [file, disc.count])


func test_the_paths_between_two_lights() -> void:
    var day := PictureParts.Body.new("", "sun", Vector2i.ZERO, Vector2(1000.0, 30.0), 270.0)
    var dusk := PictureParts.Body.new("", "sun", Vector2i.ZERO, Vector2(820.0, 220.0), 280.0)
    var night := PictureParts.Body.new("", "moon", Vector2i.ZERO, Vector2(950.0, 100.0), 270.0)
    var first := Vector2(1000.0, 30.0)
    var between := Vector2(910.0, 125.0)
    var second := Vector2(820.0, 220.0)
    assert_eq(PictureParts.Body.places(day, dusk, 0.0), [first, first], "two suns at naught share the first's place")
    assert_eq(PictureParts.Body.places(day, dusk, 0.5), [between, between], "and half way, the place between")
    assert_eq(PictureParts.Body.places(day, dusk, 1.0), [second, second], "and at one the second's")
    var handing := PictureParts.Body.HANDOVER
    assert_eq(
        PictureParts.Body.places(dusk, night, 0.0),
        [Vector2(820.0, 220.0), Vector2(950.0, 100.0)],
        "a sun stands where painted and the moon where it is painted"
    )
    assert_eq(PictureParts.Body.shares(dusk, night, 0.0), [1.0, 0.0], "and the moon is not shown yet")
    assert_eq(
        PictureParts.Body.places(dusk, night, handing / 2.0),
        [Vector2(820.0, 250.0), Vector2(950.0, 100.0)],
        "half way to the handover the sun is half way down"
    )
    assert_eq(PictureParts.Body.shares(dusk, night, handing / 2.0), [1.0, 0.0], "and the moon still not shown")
    assert_eq(
        PictureParts.Body.places(dusk, night, handing),
        [Vector2(820.0, 280.0), Vector2(950.0, 100.0)],
        "at the handover the sun has set"
    )
    assert_almost_eq(
        PictureParts.Body.shares(dusk, night, (1.0 + handing) / 2.0)[1], 0.5, 1e-5, "and the moon fades in from there"
    )
    assert_eq(
        PictureParts.Body.places(dusk, night, 1.0),
        [Vector2(820.0, 280.0), Vector2(950.0, 100.0)],
        "and at one the sun has set and the moon is where painted"
    )
    assert_eq(PictureParts.Body.shares(dusk, night, 1.0), [1.0, 1.0], "and shown whole")
    assert_almost_eq(
        PictureParts.Body.shares(night, day, handing / 2.0)[0], 0.5, 1e-5, "a moon handing over fades out by the handover"
    )
    assert_eq(PictureParts.Body.places(night, day, handing)[1], Vector2(1000.0, 270.0), "where the sun begins to rise")
    assert_eq(PictureParts.Body.places(dusk, null, 0.5)[0], Vector2(820.0, 220.0), "a body with no partner keeps its place")
    assert_eq(PictureParts.Body.places(null, night, 0.5)[1], Vector2(950.0, 100.0), "on either side")


func test_two_fades_show_one_body_where_each_light_paints_it_and_one_between() -> void:
    var parts := _parts()
    for fade: Array in FADES:
        var first: PictureParts = parts[fade[0]]
        var second: PictureParts = parts[fade[1]]
        var rows := maxi(_rows(first), _rows(second))
        var bare := _mixed(first.compose_from_sources(0.0, [], NOWHERE), second.compose_from_sources(0.0, [], NOWHERE), 0.5)
        var most := 0.0
        for fraction in FRACTIONS:
            var places := PictureParts.Body.places(first.body, second.body, fraction)
            var made_first := first.compose_from_sources(0.0, [], places[0])
            var made_second := second.compose_from_sources(0.0, [], places[1])
            var name := "%s into %s at %.1f" % [fade[0], fade[1], fraction]
            if fraction == 0.0 or fraction == 1.0:
                var shown: PictureParts = first if fraction == 0.0 else second
                var made := (made_first if fraction == 0.0 else made_second).get_data()
                var at_end := _change(made, shown.compose_from_sources(0.0, [], NOWHERE).get_data(), rows)
                most = 0.0
                for at in at_end.size():
                    most = maxf(most, at_end[at])
                var end_disc := _disc(at_end, most * DISC)
                assert_true(
                    end_disc.middle.distance_to(shown.body.at) <= NEAR,
                    "%s shows its body where it is painted: %s for %s" % [name, end_disc.middle, shown.body.at]
                )
                assert_true(_one_place(end_disc), "%s shows it at one place" % name)
                _assert_the_export(made, fade[0 if fraction == 0.0 else 1], shown, name)
                continue
            for at in 2:
                var of: PictureParts = first if at == 0 else second
                var made := (made_first if at == 0 else made_second).get_data()
                var by_own := _change(made, of.compose_from_sources(0.0, [], NOWHERE).get_data(), rows)
                var own := 0.0
                for i in by_own.size():
                    own = maxf(own, by_own[i])
                var own_disc := _disc(by_own, own * DISC)
                if own_disc.count > 0:
                    var said := "%s: %s's body shows at one place, %d texels" % [name, fade[at], own_disc.count]
                    assert_true(_one_place(own_disc), said)
            var change := _change(_mixed(made_first, made_second, fraction), bare, rows)
            var both := 0.0
            for i in change.size():
                both = maxf(both, change[i])
            var disc := _disc(change, both * DISC)
            if first.body.kind == second.body.kind:
                assert_true(
                    disc.middle.distance_to(places[0]) <= NEAR,
                    "%s shows one sun at the place between: %s for %s" % [name, disc.middle, places[0]]
                )
                assert_true(_one_place(disc), "%s shows the sun at one place, %d texels" % [name, disc.count])
            else:
                assert_true(places[0].distance_to(places[1]) > 50.0, "%s: the sun and the moon never share a place" % name)


func test_a_sun_that_has_set_is_behind_the_land() -> void:
    var dusk: PictureParts = _parts()["0.18-summer-dusk.png"]
    var rows := _rows(dusk)
    var bare := dusk.compose_from_sources(0.0, [], NOWHERE).get_data()
    var painted := _change(dusk.compose_from_sources(0.0).get_data(), bare, rows)
    var most := 0.0
    for at in painted.size():
        most = maxf(most, painted[at])
    var setting := dusk.compose_from_sources(0.0, [], Vector2(dusk.body.at.x, dusk.body.sets)).get_data()
    var gone := _disc(_change(setting, bare, rows), most * DISC)
    assert_eq(gone.count, 0, "the dusk's sun where it sets shows none of its disc over the land")


## That *made*, *of* composed with its body where painted, is Sara's export of
## *file* within the composing tolerance outside the seam's band.
func _assert_the_export(made: PackedByteArray, file: String, of: PictureParts, name: String) -> void:
    var wanted := _flat(file)
    var worst := 0
    var total := 0
    var counted := 0
    for y in 480:
        for x in 1440:
            var from_seam := posmod(x - of.origin, 1440)
            if mini(from_seam, 1440 - from_seam) <= of.seam:
                continue
            var at := (y * 1440 + x) * 4
            var apart := maxi(absi(made[at] - wanted[at]), absi(made[at + 1] - wanted[at + 1]))
            apart = maxi(apart, absi(made[at + 2] - wanted[at + 2]))
            worst = maxi(worst, apart)
            total += apart
            counted += 1
    var mean := float(total) / float(counted)
    assert_true(worst <= WORST, "%s is Sara's export of %s within %d levels: %d" % [name, file, WORST, worst])
    assert_true(mean <= MEAN, "and %.2f on the mean, within %.1f" % [mean, MEAN])
