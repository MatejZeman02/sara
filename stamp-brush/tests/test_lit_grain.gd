## The lit grain, the fourth shipped pattern.
##
## Every clause of the unit's Done-when is a test here: the store lists the
## kernel and the four numbers a painter changes, the tile is seamless at both
## its edges, its mean is the neutral it declares, and turning the light
## through half a turn moves a grain's highlight to the other side of it.
##
## The kernel is run through [SaPatternKernel] rather than through
## [method SaPattern.texture], because every clause but the first is about a
## uniform over the declared default and the pattern object has no door for
## one.
extends "res://tests/test_framework.gd"

## A pattern is a dispatch.
const REQUIRES_GPU := true

## What the store calls the file, and the numbers it declares.
const PATTERN_NAME := "Lit Grain"
const DIALS: Array[String] = ["grain", "density", "light", "relief", "neutral"]

## The kernel's own defaults, which the assertions below quote.
const NEUTRAL := 0.65
const LIGHT := 225.0
const GRAIN := 12.0

## Big enough that a grain of twelve texels fits twenty-one times across, so a
## seam has something to be seamless over.
const SIDE := 256


func _shipped_store() -> SaPatternStore:
    return SaPatternStore.new([SaPatternStore.SHIPPED_DIR])


func _loader() -> SaPatternKernel:
    var pattern := _shipped_store().pattern(PATTERN_NAME)
    return SaPatternKernel.new(pattern.source) if pattern != null else null


## The tile as floats, row by row, with *values* over the declared defaults.
func _tile(kernel: SaPatternKernel, values: Dictionary = {}) -> PackedFloat32Array:
    var texture := kernel.generate(Vector2i(SIDE, SIDE), values)
    if texture == null:
        return PackedFloat32Array()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


func _mean(values: PackedFloat32Array) -> float:
    var total := 0.0
    for value in values:
        total += value
    return total / float(values.size())


# --- The store -------------------------------------------------------------


func test_the_store_lists_the_lit_grain_and_the_numbers_it_offers() -> void:
    var store := _shipped_store()
    assert_true(store.has(PATTERN_NAME), "the fourth shipped pattern is listed")
    var pattern := store.pattern(PATTERN_NAME)
    assert_not_null(pattern, "under its stem made readable")
    if pattern == null:
        return
    assert_true(pattern.is_generated(), "as a kernel rather than a picture")
    var declared := PackedStringArray()
    for field: Dictionary in pattern.kernel_uniforms():
        declared.append(String(field["name"]))
    for dial in DIALS:
        assert_true(declared.has(dial), "%s is a number a painter changes" % dial)
    assert_true(declared.has(SaPatternKernel.TILE_UNIFORM), "and the loader has a tile to write")


# --- The tile --------------------------------------------------------------


func test_the_tile_is_seamless_at_both_its_edges() -> void:
    var kernel := _loader()
    var values := _tile(kernel)
    assert_eq(values.size(), SIDE * SIDE, "the kernel runs: %s" % kernel.error)
    if values.size() != SIDE * SIDE:
        return
    # A seam is invisible when the step across it is no bigger than the biggest
    # step inside the tile: the lattice wraps at `tile`, so the last column is
    # the first column's left neighbour and behaves like any other pair.
    var inner_step := 0.0
    var seam_x := 0.0
    var seam_y := 0.0
    for line in SIDE:
        var row := line * SIDE
        for step in range(1, SIDE):
            inner_step = maxf(inner_step, absf(values[row + step] - values[row + step - 1]))
            inner_step = maxf(inner_step, absf(values[step * SIDE + line] - values[step * SIDE - SIDE + line]))
        seam_x = maxf(seam_x, absf(values[row] - values[row + SIDE - 1]))
        seam_y = maxf(seam_y, absf(values[line] - values[(SIDE - 1) * SIDE + line]))
    assert_true(inner_step > 0.0, "the tile has grains in it at all")
    assert_true(seam_x <= inner_step, "the left and right edges join (%f against %f)" % [seam_x, inner_step])
    assert_true(seam_y <= inner_step, "the top and bottom edges join (%f against %f)" % [seam_y, inner_step])


func test_the_mean_of_a_tile_is_the_neutral_it_declares() -> void:
    var kernel := _loader()
    var values := _tile(kernel)
    assert_eq(values.size(), SIDE * SIDE, "the kernel runs: %s" % kernel.error)
    if values.size() != SIDE * SIDE:
        return
    # A round bump's slope points one way on one flank and the other way on the
    # other, so what the light adds on one side it takes on the other and the
    # tile averages out at the value a flat stretch of paper takes.
    assert_almost_eq(_mean(values), NEUTRAL, 0.005, "the grains give back what they take")
    var coarse := _tile(kernel, {"grain": GRAIN * 4.0})
    assert_almost_eq(_mean(coarse), NEUTRAL, 0.005, "and fewer, wider grains average to the same")
    var moved := _tile(kernel, {"neutral": 0.4})
    assert_almost_eq(_mean(moved), 0.4, 0.005, "a painter moving the neutral moves the mean with it")
    var flat := _tile(kernel, {"relief": 0.0})
    assert_almost_eq(flat[0], NEUTRAL, 0.0001, "and no relief is flat paper")
    assert_almost_eq(_mean(flat), NEUTRAL, 0.0001, "everywhere")
    # Density is the share of cells carrying a grain at all, which is what
    # keeps the lattice from reading as a lattice. None of them is flat paper
    # too, and by a different road than no relief.
    var empty := _tile(kernel, {"density": 0.0})
    assert_almost_eq(_mean(empty), NEUTRAL, 0.0001, "no grains at all is flat paper as well")
    var grainy := 0
    var sparse := 0
    var thick := _tile(kernel, {"density": 1.0})
    for i in values.size():
        sparse += 1 if absf(values[i] - NEUTRAL) > 0.01 else 0
        grainy += 1 if absf(thick[i] - NEUTRAL) > 0.01 else 0
    assert_true(grainy > sparse, "and a full screen of them covers more than six in ten do (%d against %d)" % [grainy, sparse])


func test_turning_the_light_moves_the_highlight_to_the_other_side_of_a_grain() -> void:
    var kernel := _loader()
    var values := _tile(kernel)
    assert_eq(values.size(), SIDE * SIDE, "the kernel runs: %s" % kernel.error)
    if values.size() != SIDE * SIDE:
        return
    var bright := 0
    for i in values.size():
        if values[i] > values[bright]:
            bright = i
    var bx := bright % SIDE
    var by := floori(float(bright) / float(SIDE))
    # The darkest texel within one grain's width of the brightest is the far
    # flank of the same grain, because a grain never crosses into its
    # neighbour's cell.
    var reach := int(GRAIN * 0.5)
    var dark := bright
    for y in range(maxi(by - reach, 0), mini(by + reach + 1, SIDE)):
        for x in range(maxi(bx - reach, 0), mini(bx + reach + 1, SIDE)):
            if values[y * SIDE + x] < values[dark]:
                dark = y * SIDE + x
    assert_true(values[bright] > NEUTRAL, "a grain has a lit flank (%f)" % values[bright])
    assert_true(values[dark] < NEUTRAL, "and a shadowed one across it (%f)" % values[dark])
    var turned := _tile(kernel, {"light": LIGHT + 180.0})
    assert_true(turned[bright] < NEUTRAL, "half a turn puts the lit flank in shadow (%f)" % turned[bright])
    assert_true(turned[dark] > NEUTRAL, "and lights the flank that was in shadow (%f)" % turned[dark])
    # The shading is a dot product with the light's direction, so reversing the
    # direction reflects every value through the neutral exactly.
    assert_almost_eq(turned[bright], 2.0 * NEUTRAL - values[bright], 0.002, "the highlight's size is the shadow's")
