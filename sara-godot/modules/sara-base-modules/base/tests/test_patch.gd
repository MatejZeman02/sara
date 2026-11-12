## The patch tool: the selection filled out of the ring around it.
##
## What the tool is graded on: a scenario selects a dark spot on a gradient,
## applies the tool and shoots the spot gone within the harness's tolerance
## against the gradient, the kernel dispatches over the selection's rectangle
## only, and undo restores the spot. The scenario is
## `scenarios/the-patch-tool.json` and this is the same three clauses read
## off the texels, where a shot can only be looked at.
##
## The picture is a horizontal ramp with a flat green channel, so a patch that
## merely averaged the whole ring would show up: the red channel has to come
## back near the ramp's own value at the spot, not near the ring's mean, and the
## green has to come back at the constant it never left.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")
const StatePatchScript = preload("res://modules/sara-base-modules/base/patch/state_patch.gd")

## The canvas, which is one chunk, so the readback is one texture and the
## dispatch count below is a number that can be written down.
const SIDE: int = 256

## The blemish: a square of black at full alpha, and the box the selection takes
## round it.
const SPOT := Rect2i(112, 112, 32, 32)


## The ramp the picture is painted with, at *x*: red climbs, blue falls, green
## stays where it is and alpha is opaque.
static func ramp_at(x: int) -> Color:
    var t := float(x) / float(SIDE - 1)
    return Color(t, 0.5, 1.0 - t, 1.0)


## A document holding one layer painted with [method ramp_at] and a black square
## at [constant SPOT].
static func make_spotted_document() -> SaDocument:
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(SIDE, SIDE), SaCompositor.new())
    var layer := document.active_layer
    var texture: SaTexture = layer.get_or_create_field(Vector2i.ZERO)
    var texels := PackedFloat32Array()
    texels.resize(SIDE * SIDE * 4)
    for y in SIDE:
        for x in SIDE:
            var colour := ramp_at(x)
            if SPOT.has_point(Vector2i(x, y)):
                colour = Color(0.0, 0.0, 0.0, 1.0)
            var at := (y * SIDE + x) * 4
            texels[at] = colour.r
            texels[at + 1] = colour.g
            texels[at + 2] = colour.b
            texels[at + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return document


## The texel at *point* of the layer's one chunk.
static func texel_at(document: SaDocument, point: Vector2i) -> Color:
    var layer := document.active_layer
    var texture: SaTexture = layer.get_field(Vector2i.ZERO)
    var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (point.y * SIDE + point.x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## The whole of the first clause: the spot is gone, and what is in its place is
## the picture around it rather than a flat average of it. By Smooth, the
## method this suite was written for, which is the one a gradient wants.
func test_the_spot_goes_and_the_ramp_comes_back() -> void:
    var document := make_spotted_document()
    var before := texel_at(document, SPOT.get_center())
    assert_almost_eq(before.r, 0.0, 0.01, "the spot starts black")

    document.selection.select_rect(SPOT)
    var written := SaPatchScript.new().patch(document, document.active_layer, null, SaPatchScript.Method.SMOOTH)
    assert_true(written > 0, "the patch wrote at least one chunk")

    var centre := texel_at(document, SPOT.get_center())
    var wanted := ramp_at(SPOT.get_center().x)
    assert_almost_eq(centre.a, 1.0, 0.02, "the patch is as opaque as what it was drawn from")
    # The green channel is the strict one: it is the same everywhere in the
    # picture, so nothing the fill could do to it is an excuse.
    assert_almost_eq(centre.g, wanted.g, 0.02, "the flat channel comes back flat")
    # The ramp is the loose one. A normalised convolution is a smooth fill and
    # not an exact reconstruction, and the claim is "within the
    # harness's tolerance against the gradient".
    assert_almost_eq(centre.r, wanted.r, 0.06, "the climbing channel comes back near the ramp")
    assert_almost_eq(centre.b, wanted.b, 0.06, "the falling channel comes back near the ramp")
    document.free()


## The second clause. The count is exact rather than a bound, because what
## is asked about is the shape of the dispatch and a bound would pass on a
## kernel that ran over the canvas once. Smooth's shape, which the count is of,
## and `test_patch_texture.gd` holds Texture's dispatches to the same rule.
func test_the_dispatch_is_the_selections_rectangle() -> void:
    var document := make_spotted_document()
    document.selection.select_rect(SPOT)
    var work := SPOT.grow(SaPatchScript.RING)
    var passes := SaPatchScript.passes_for(work.size)

    SaCompute.reset_counters()
    SaPatchScript.new().patch(document, document.active_layer, null, SaPatchScript.Method.SMOOTH)
    var counted := SaCompute.counters()

    # One clear, one gather over the single chunk the work rectangle touches,
    # one sweep per pass, and one scatter over the single chunk the selection
    # touches. Nothing walks the canvas.
    assert_eq(int(counted["dispatches"]), passes + 3, "a dispatch per pass and one each for the three ends")
    var over_the_work := SaCompute.groups_for(work.size.x) * SaCompute.groups_for(work.size.y)
    var over_the_canvas := SaCompute.groups_for(SIDE) * SaCompute.groups_for(SIDE)
    assert_true(
        int(counted["workgroups"]) < over_the_canvas,
        (
            "the whole patch costs fewer workgroups than one canvas-wide pass: %d against %d"
            % [int(counted["workgroups"]), over_the_canvas]
        )
    )
    assert_true(
        int(counted["workgroups"]) <= (passes + 3) * over_the_work,
        (
            "every dispatch fits inside the work rectangle: %d workgroups against %d for %d of them"
            % [int(counted["workgroups"]), (passes + 3) * over_the_work, passes + 3]
        )
    )
    document.free()


## The third clause.
func test_undo_puts_the_spot_back() -> void:
    var document := make_spotted_document()
    document.selection.select_rect(SPOT)
    SaPatchScript.new().patch(document, document.active_layer)
    assert_true(document.undo_redo.has_undo(), "the patch is one history step")

    document.undo_redo.undo()
    var centre := texel_at(document, SPOT.get_center())
    assert_almost_eq(centre.r, 0.0, 0.01, "undo puts the black back")
    assert_almost_eq(centre.g, 0.0, 0.01, "and every channel of it")
    document.free()


## Outside the selection nothing moves, which is what makes the tool safe to
## reach for on a picture that is nearly finished.
func test_the_ring_is_left_alone() -> void:
    var document := make_spotted_document()
    document.selection.select_rect(SPOT)
    SaPatchScript.new().patch(document, document.active_layer)
    for point: Vector2i in [Vector2i(SPOT.position.x - 1, SPOT.get_center().y), Vector2i(40, 40), Vector2i(200, 200)]:
        var here := texel_at(document, point)
        var wanted := ramp_at(point.x)
        assert_almost_eq(here.r, wanted.r, 0.001, "the picture outside the selection is untouched at %s" % point)
        assert_almost_eq(here.b, wanted.b, 0.001, "in every channel at %s" % point)
    document.free()


## With no selection there is nothing to patch, and the tool says so rather than
## filling the layer.
func test_no_selection_patches_nothing() -> void:
    var document := make_spotted_document()
    var written := SaPatchScript.new().patch(document, document.active_layer)
    assert_eq(written, 0, "a patch with no selection writes nothing")
    assert_almost_eq(texel_at(document, SPOT.get_center()).r, 0.0, 0.01, "and the spot is still there")
    assert_false(document.undo_redo.has_undo(), "and no history step was recorded")
    document.free()


## The tool's own door, which the Patch row on the tool's options presses and a
## click inside the selection reaches: the same call, so a scenario driving
## either proves the other.
func test_the_tool_row_patches() -> void:
    var surface := Fixtures.make_surface()
    var document := surface.get_document()
    document.fill_layer(Color(0.25, 0.75, 0.5, 1.0))
    document.selection.select_rect(SPOT)

    var tool_state := StatePatchScript.new()
    tool_state.surface = surface
    assert_true(tool_state.patch_now() > 0, "the Patch row wrote a chunk")

    var report := tool_state.capture_report(&"patch", true)
    assert_true(report.has("patch"), "the tool tells a capture what it is looking at")
    assert_true(bool((report["patch"] as Dictionary)["selection"]), "and that there is a selection")
    document.free()
    surface.easel.free()
