## Between two lights the Welcome picture shows one sun and one reflection: a
## body carries its glow and its glitter on the lake, so two lights fading lay
## each once, where `PictureParts.Body.places` puts the body, and a sun and a
## moon hand over rather than show together.
##
## The pictures are the shipped ones, which `scripts/export_welcome_bodies.py`
## cut. How the window looks between summer's dawn and clear day is the
## `...` scenario under `scenarios/`.
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"

## Today's band at each light's own hour, before the glow and the reflection
## were cut, as its difference from the light's file plus 128, lossless.
const TODAY := "res://ui/welcome/tests/pictures/between-two-lights/"

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]

## Each pair of lights with a body the band fades between, the first into
## the second, round the day: the night into the dawn, the dawn into a day
## with a sun, that day into the dusk and the dusk into the night.
const PAIRS: Array[Array] = [
    ["night", "dawn"],
    ["dawn", "day-clear"],
    ["dawn", "day-hazy"],
    ["day-clear", "dusk"],
    ["day-hazy", "dusk"],
    ["dusk", "night"],
]
const FRACTIONS: Array[float] = [0.25, 0.5, 0.75]

## Where a body is laid to leave it out, far off the picture, and its glow and
## reflection with it.
const NOWHERE := Vector2(-100000.0, -100000.0)

## Every texel is read on a grid of this many pixels, which a disc of twenty
## and a glitter path of forty fill with dozens.
const STEP: int = 2

## A texel of the sky is a disc where the bodies change it by this share of
## the most they change any texel of the sky, the share the export found a
## disc's middle by.
const DISC: float = 0.85

const FAINT: float = 8.0

## A texel of the lake is a reflection where the bodies change it by this
## share of the most they change any texel of the lake. Two reflections each at
## its light's half both pass it, and the dim edge of one does not.
const GLITTER: float = 0.3

## Disc texels whose cells of `CELL` pixels touch are one blob, and so are
## glitter columns closer than `GAP` pixels. Two places of one light stand a
## hundred and fifty pixels apart, the glitter of one path a few.
const CELL: int = 12
const GAP: int = 120

## The fewest texels of the grid a blob is counted with, so a speck of a
## cloud's edge is not a disc.
const LEAST: int = 3

## How far a light at its own hour may be from today's band, a level of 255.
const WORST: int = 1

## The share of the most a light's body changes any texel by, from the
## band with no body, at which the core of what it adds is read: the disc and
## the brightest of its glow in the sky, the brightest of its glitter on the
## lake.
const CORE: float = 0.5

## A light whose body adds less than this share of what the other's adds, a
## sun that has set or a moon not yet come, is not counted as a second.
const SLIGHT: float = 0.1

## How many texels of the grid a core's brightest is read below the largest.
const SPECKS: int = 20


func _parts() -> Dictionary:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    return PictureParts.listed_in(said if said is Dictionary else {}, SHIPPED)


## *of* with its body and no reflection, so the disc and the glow are read
## apart from the glitter.
static func _unreflected(of: PictureParts) -> PictureParts:
    var body := PictureParts.Body.new(of.body.path, of.body.kind, of.body.box, of.body.at, of.body.sets, of.body.over_clouds)
    return PictureParts.new(of.back, of.clouds, of.land, of.top, of.origin, of.seam, body)


static func _file(season: String, light: String) -> String:
    return "0.18-%s-%s.png" % [season, light]


## *first* and *second*, in RGBA8, as the band fades the second over the first
## at *fraction*, in floats of levels.
static func _mixed(first: Image, second: Image, fraction: float) -> PackedFloat32Array:
    var a := first.get_data()
    var b := second.get_data()
    var mixed := PackedFloat32Array()
    mixed.resize(a.size())
    for at in a.size():
        mixed[at] = lerpf(float(a[at]), float(b[at]), fraction)
    return mixed


## The largest change of a channel at each texel of the grid, from *bare* to
## *with*, by its texel, for rows *from* up to *to*.
static func _change(with: PackedFloat32Array, bare: PackedFloat32Array, from: int, to: int) -> Dictionary:
    var change := {}
    for y in range(from, to, STEP):
        for x in range(0, 1440, STEP):
            var i := (y * 1440 + x) * 4
            var most := maxf(absf(with[i] - bare[i]), maxf(absf(with[i + 1] - bare[i + 1]), absf(with[i + 2] - bare[i + 2])))
            if most > 0.0:
                change[Vector2i(x, y)] = most
    return change


## The texels of *change* at least *share* of its most.
static func _over(change: Dictionary, share: float) -> Array[Vector2i]:
    var most := 0.0
    for texel: Vector2i in change:
        most = maxf(most, change[texel])
    var found: Array[Vector2i] = []
    if most <= 0.0:
        return found
    for texel: Vector2i in change:
        if change[texel] >= most * share:
            found.append(texel)
    return found


## The texels of *change* that the bodies change by `FAINT` levels or more
## and that are at least *share* of the brightest of those in *made*.
static func _brightest(change: Dictionary, made: PackedFloat32Array, share: float) -> Array[Vector2i]:
    var bright := {}
    var most := 0.0
    for texel: Vector2i in change:
        if change[texel] >= FAINT:
            var i := (texel.y * 1440 + texel.x) * 4
            bright[texel] = made[i] + made[i + 1] + made[i + 2]
            most = maxf(most, bright[texel])
    var found: Array[Vector2i] = []
    for texel: Vector2i in bright:
        if bright[texel] >= most * share:
            found.append(texel)
    return found


## How many blobs *texels* make, their cells of `CELL` pixels touching, of
## at least `LEAST` texels each.
static func _blobs(texels: Array[Vector2i]) -> int:
    var left := {}
    for texel in texels:
        var cell := Vector2i(floori(texel.x / float(CELL)), floori(texel.y / float(CELL)))
        left[cell] = int(left.get(cell, 0)) + 1
    var count := 0
    while not left.is_empty():
        var start: Vector2i = left.keys()[0]
        var reached := [start]
        var held_texels := int(left[start])
        left.erase(start)
        var held := 0
        while held < reached.size():
            var at: Vector2i = reached[held]
            held += 1
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var near := at + Vector2i(dx, dy)
                    if left.has(near):
                        held_texels += int(left[near])
                        left.erase(near)
                        reached.append(near)
        if held_texels >= LEAST:
            count += 1
    return count


## How many paths *texels* make on the lake, their columns closer than `GAP`.
static func _paths(texels: Array[Vector2i]) -> int:
    var columns := {}
    for texel in texels:
        columns[texel.x] = int(columns.get(texel.x, 0)) + 1
    var xs: Array = columns.keys()
    xs.sort()
    var count := 0
    var last := -GAP * 2
    var held := 0
    for x: int in xs:
        if x - last >= GAP:
            if held >= LEAST:
                count += 1
            held = 0
        held += int(columns[x])
        last = x
    if held >= LEAST:
        count += 1
    return count


func test_every_light_with_a_body_carries_its_reflection() -> void:
    var parts := _parts()
    var with := 0
    for file: String in parts:
        var of: PictureParts = parts[file]
        if of.body == null:
            continue
        with += 1
        assert_false(of.body.reflection.is_empty(), "%s has its reflection as a part" % file)
    assert_eq(with, 20, "five lights in each of four seasons carry a body")


func test_a_fade_shows_one_disc_in_the_sky_and_one_reflection_on_the_lake() -> void:
    var parts := _parts()
    var bare := {}
    for season in SEASONS:
        for pair in PAIRS:
            var first: PictureParts = parts[_file(season, pair[0])]
            var second: PictureParts = parts[_file(season, pair[1])]
            for of: PictureParts in [first, second]:
                if not bare.has(of):
                    bare[of] = of.compose_from_sources(0.0, [], NOWHERE)
            var lake := maxi(
                first.top + PictureParts.image_of(first.land, true).get_height(),
                second.top + PictureParts.image_of(second.land, true).get_height()
            )
            var plain_first := _unreflected(first)
            var plain_second := _unreflected(second)
            for fraction in FRACTIONS:
                var places := PictureParts.Body.places(first.body, second.body, fraction)
                var shares := PictureParts.Body.shares(first.body, second.body, fraction)
                var lit_first := first.compose_from_sources(0.0, [], places[0], shares[0])
                var lit_second := second.compose_from_sources(0.0, [], places[1], shares[1])
                var made := _mixed(lit_first, lit_second, fraction)
                var unreflected := _mixed(
                    plain_first.compose_from_sources(0.0, [], places[0], shares[0]),
                    plain_second.compose_from_sources(0.0, [], places[1], shares[1]),
                    fraction
                )
                var without := _mixed(bare[first], bare[second], fraction)
                var name := "%s from %s to %s at %.2f" % [season, pair[0], pair[1], fraction]
                var lit := [lit_first, lit_second]
                for rows: Vector2i in [Vector2i(0, lake), Vector2i(lake, 480)]:
                    var cores: Array[Rect2i] = []
                    var weights: Array[float] = []
                    for at in 2:
                        var of: PictureParts = [first, second][at]
                        var core := _core(_change_of(lit[at], bare[of], rows))
                        cores.append(core[0])
                        weights.append(core[1] * (fraction if at == 1 else 1.0 - fraction))
                    if minf(weights[0], weights[1]) < maxf(weights[0], weights[1]) * SLIGHT:
                        continue
                    var meet := cores[0].grow(STEP)
                    if rows.x > 0:
                        meet = Rect2i(meet.position.x, cores[1].position.y, meet.size.x, cores[1].size.y)
                    assert_true(
                        meet.intersects(cores[1]),
                        (
                            "%s lays both lights' bodies as one in %s: %s and %s"
                            % [name, "the sky" if rows.x == 0 else "the lake", cores[0], cores[1]]
                        )
                    )
                var sky := _change(unreflected, without, 0, lake)
                var disc := _brightest(sky, unreflected, DISC)
                var discs := _blobs(disc)
                assert_eq(discs, 1, "%s shows one disc in the sky: %s" % [name, _where(disc)])
                var glitter := _over(_change(made, unreflected, lake, 480), GLITTER)
                assert_eq(_paths(glitter), 1, "%s shows one reflection on the lake: %s" % [name, _where(glitter)])


## The largest change of a channel at each texel of the grid from *bare* to
## *with*, one light each, over *rows*, by its texel.
static func _change_of(with: Image, bare: Image, rows: Vector2i) -> Dictionary:
    var now := with.get_data()
    var was := bare.get_data()
    var change := {}
    for y in range(rows.x, rows.y, STEP):
        for x in range(0, 1440, STEP):
            var i := (y * 1440 + x) * 4
            var most := maxi(absi(now[i] - was[i]), maxi(absi(now[i + 1] - was[i + 1]), absi(now[i + 2] - was[i + 2])))
            if most > 0:
                change[Vector2i(x, y)] = float(most)
    return change


## The box round the texels of *change* at `CORE` of its brightest or more,
## and the whole of *change* summed, as [box, weight]. The brightest is the
## `SPECKS`-th largest change, so one sparkle of snow, as the winter's clear
## day has at a sixth of its reflection's strength, never makes the core.
static func _core(change: Dictionary) -> Array:
    var weight := 0.0
    var values: Array[float] = []
    for texel: Vector2i in change:
        weight += change[texel]
        values.append(change[texel])
    var box := Rect2i()
    if values.is_empty():
        return [box, weight]
    values.sort()
    var brightest := values[maxi(values.size() - SPECKS, 0)]
    for texel: Vector2i in change:
        if change[texel] >= brightest * CORE:
            box = Rect2i(texel, Vector2i.ONE) if not box.has_area() else box.expand(texel + Vector2i.ONE)
    return [box, weight]


## The cells of forty pixels *texels* fall in, with how many, for a message.
static func _where(texels: Array[Vector2i]) -> String:
    var cells := {}
    for texel in texels:
        @warning_ignore("integer_division")
        var cell := texel / 40 * 40
        cells[cell] = int(cells.get(cell, 0)) + 1
    return str(cells)


func test_a_light_at_its_own_hour_is_today_s_band() -> void:
    var parts := _parts()
    for file: String in parts:
        var of: PictureParts = parts[file]
        if of.body == null:
            continue
        var made := of.compose_from_sources(0.0)
        made.clear_mipmaps()
        var light := Image.load_from_file(ProjectSettings.globalize_path(SHIPPED + file))
        light.convert(Image.FORMAT_RGBA8)
        var today := Image.load_from_file(ProjectSettings.globalize_path(TODAY + file.get_basename() + "-today.webp"))
        today.convert(Image.FORMAT_RGBA8)
        var now := made.get_data()
        var was := light.get_data()
        var apart := today.get_data()
        var worst := 0
        for at in now.size():
            if at % 4 == 3:
                continue
            worst = maxi(worst, absi(now[at] - posmod(was[at] + apart[at] - 128, 256)))
        assert_true(worst <= WORST, "%s at its own hour is today's band within %d level: %d" % [file, WORST, worst])
