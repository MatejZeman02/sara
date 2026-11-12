## The selection's marching ants look the same at every zoom.
##
## The ants must look the same, drawn in screen space, at all zoom levels.
##
## `shaders/canvas/selection.gdshader` stepped a texel either way to find the
## edge above 100 percent, so every screen pixel of the edge texel was an ant
## and at 1600 percent the outline was sixteen pixels wide. It also took the
## screen derivatives of the mask inside the branch only edge fragments enter,
## where a derivative is undefined, so the direction the dashes walk was
## guessed wrong and a straight edge at 100 percent showed dashes twice as long
## as `ant_period` on one side and the period on the other. The edge is now a
## screen pixel's step and the derivatives are taken before the branch.
##
## This suite reads the record pictures of
## `scenarios/the-selection-s-marching-ants-look-the-same-at-every-zoom.json`,
## an ellipse and a rectangle at 25, 100, 400 and 1600 percent, each the same
## size on the screen, as `tests/shots/<scenario>/<variant>/` keeps them for
## every GPU recorded. An ant is a pure black or pure white pixel on the mid
## grey canvas, and the outline is one pixel wide when no two by two block of
## pixels is all ants.
extends "res://tests/test_framework.gd"

const SHOTS := "res://tests/shots/the-selection-s-marching-ants-look-the-same-at-every-zoom"
const ZOOMS: Array[String] = ["25", "100", "400", "1600"]
const SHAPES: Array[String] = ["ellipse", "rectangle"]

## The shader's own default, which the overlay never overrides.
const ANT_PERIOD := 8.0

## The part of the shot the shapes are drawn in, inside the canvas's free rect
## and clear of every docker the default layout puts beside it.
const WINDOW := Rect2i(600, 250, 780, 600)

## The rectangle's outline in screen pixels at each zoom, inclusive, from each
## shot's state dump: the canvas's offset plus the selection's bounds times
## the zoom, and the first and last screen pixel whose centre lies inside. A
## change to how the view zooms moves these, and the scenario's centres with
## them, and so does a change to the text size, which moves the canvas down
## the window when the shots are taken again.
const RECTANGLE_PIXELS := {
    "25": Rect2i(787, 423, 400, 240),
    "100": Rect2i(780, 419, 400, 240),
    "400": Rect2i(747, 405, 400, 240),
    "1600": Rect2i(636, 350, 400, 240),
}

## Where the texel grid's lines fall on the screen at 1600 percent, the
## canvas offset of that shot's state dump modulo sixteen.
const GRID_1600 := Vector2(11.9, 14.0)


func test_every_zoom_was_recorded() -> void:
    for variant in _variants():
        for shape in SHAPES:
            for zoom in ZOOMS:
                assert_false(_ants(variant, shape, zoom).is_empty(), "%s has %s at %s percent" % [variant, shape, zoom])


func test_the_outline_is_one_screen_pixel_wide_at_every_zoom() -> void:
    for variant in _variants():
        for shape in SHAPES:
            for zoom in ZOOMS:
                var ants := _ants(variant, shape, zoom)
                if ants.is_empty():
                    continue
                assert_true(ants.size() > 1000, "%s at %s percent is outlined, %d ants" % [shape, zoom, ants.size()])
                var blocks := 0
                for at: Vector2i in ants:
                    if ants.has(at + Vector2i(1, 0)) and ants.has(at + Vector2i(0, 1)) and ants.has(at + Vector2i(1, 1)):
                        blocks += 1
                assert_eq(blocks, 0, "%s at %s percent has no two by two block of ants" % [shape, zoom])


func test_the_dash_is_ant_period_long_at_every_zoom() -> void:
    for variant in _variants():
        for shape in SHAPES:
            for zoom in ZOOMS:
                var ants := _ants(variant, shape, zoom)
                if ants.is_empty():
                    continue
                var periods := _periods(ants)
                assert_true(periods.size() > 50, "%s at %s percent has dashes to measure, %d" % [shape, zoom, periods.size()])
                periods.sort()
                var count := float(periods.size())
                var quarter := periods[floori(count * 0.25)]
                var middle := periods[floori(count * 0.5)]
                var three_quarters := periods[floori(count * 0.75)]
                var said := (
                    "%s at %s percent, dash and gap %.2f, middle half %.2f to %.2f"
                    % [shape, zoom, middle, quarter, three_quarters]
                )
                assert_almost_eq(middle, ANT_PERIOD, 1.0, said)
                # The ellipse at 1600 percent is outlined along a staircase of
                # texel edges, and a dash that rounds a stair is measured
                # across its corner, shorter than it walks. How many dashes
                # round one moves with where the texel grid falls on the
                # screen, so the quarters there are let two pixels off.
                # The ellipse at 400 percent rounds a stair of two to four pixels
                # the same way, so its quarters are let the same.
                var spread := 2.5 if shape == "ellipse" and (zoom == "1600" or zoom == "400") else 1.0
                assert_true(absf(quarter - ANT_PERIOD) <= spread and absf(three_quarters - ANT_PERIOD) <= spread, said)


func test_the_rectangle_is_outlined_on_its_texel_boundary() -> void:
    for variant in _variants():
        for zoom in ZOOMS:
            var ants := _ants(variant, "rectangle", zoom)
            if ants.is_empty():
                continue
            var box := RECTANGLE_PIXELS[zoom] as Rect2i
            var outside := 0
            for at: Vector2i in ants:
                var on_side := at.x == box.position.x or at.x == box.end.x - 1 or at.y == box.position.y or at.y == box.end.y - 1
                if not box.has_point(at) or not on_side:
                    outside += 1
            assert_eq(outside, 0, "Every ant at %s percent is on the rectangle's inner row of pixels" % zoom)
            assert_eq(ants.size(), 2 * (box.size.x + box.size.y) - 4, "and that row is all ants at %s percent" % zoom)


## At 1600 percent a texel is sixteen pixels, so an ant of a curve that sits
## on the boundary of the texels it outlines is within a pixel of a grid line.
func test_the_ellipse_is_outlined_on_its_texel_boundaries_at_1600() -> void:
    for variant in _variants():
        var ants := _ants(variant, "ellipse", "1600")
        if ants.is_empty():
            continue
        var off := 0
        for at: Vector2i in ants:
            var across := fposmod(float(at.x) + 0.5 - GRID_1600.x, 16.0)
            var down := fposmod(float(at.y) + 0.5 - GRID_1600.y, 16.0)
            if not (across < 1.0 or across > 15.0 or down < 1.0 or down > 15.0):
                off += 1
        assert_eq(off, 0, "Every ant of the ellipse at 1600 percent is beside a texel boundary")


func _variants() -> Array[String]:
    var found: Array[String] = []
    var root := ProjectSettings.globalize_path(SHOTS)
    for name in DirAccess.get_directories_at(root):
        found.append(root.path_join(name))
    assert_true(not found.is_empty(), "The scenario has a recorded variant")
    return found


## The ants of one shot, each pixel inside WINDOW that is pure black, as
## false, or pure white, as true. Empty when the shot is missing.
func _ants(variant: String, shape: String, zoom: String) -> Dictionary:
    var path := variant.path_join("%s-%s.png" % [shape, zoom])
    if not FileAccess.file_exists(path):
        return {}
    var image := Image.load_from_file(path)
    image.convert(Image.FORMAT_RGB8)
    var data := image.get_data()
    var width := image.get_width()
    var ants := {}
    for y in range(WINDOW.position.y, WINDOW.end.y):
        for x in range(WINDOW.position.x, WINDOW.end.x):
            var at := (y * width + x) * 3
            var red := data[at]
            if (red == 0 or red == 255) and data[at + 1] == red and data[at + 2] == red:
                ants[Vector2i(x, y)] = red == 255
    return ants


## How far apart on the screen the starts of consecutive dark dashes are,
## walking the outline. The walk takes a side neighbour before a corner one and
## starts again where it strands, so a dash is never counted across a gap.
func _periods(ants: Dictionary) -> Array[float]:
    const STEPS: Array[Vector2i] = [
        Vector2i(1, 0),
        Vector2i(0, 1),
        Vector2i(-1, 0),
        Vector2i(0, -1),
        Vector2i(1, 1),
        Vector2i(-1, 1),
        Vector2i(1, -1),
        Vector2i(-1, -1),
    ]
    var periods: Array[float] = []
    var seen := {}
    for start: Vector2i in ants:
        if seen.has(start):
            continue
        var at := start
        seen[at] = true
        var dark_start := Vector2i(-1, -1)
        while true:
            var next := Vector2i(-1, -1)
            for step in STEPS:
                if ants.has(at + step) and not seen.has(at + step):
                    next = at + step
                    break
            if next.x < 0:
                break
            seen[next] = true
            if ants[at] and not ants[next]:
                if dark_start.x >= 0:
                    periods.append(Vector2(next - dark_start).length())
                dark_start = next
            at = next
    return periods
