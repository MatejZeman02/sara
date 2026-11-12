## An OpenRaster file Sara writes opens as the same picture and
## the same stack.
##
## A document of every kind of layer [SaExportOra] handles is exported at eight
## and at sixteen bits and opened again by [SaOraReader] into a second easel.
## The two are compared three ways. Every layer whose texels are its own comes
## back texel for texel, the composite of the whole picture comes back texel for
## texel, and the stack comes back with its names, the opacity Sara draws each
## at, visibility, blend modes and groups. What the format cannot carry is
## listed, and the list is what the suite expects, rather than a difference
## found by accident.
##
## Every colour is a whole number of 255ths, which is also a whole number of
## 65535ths, so it survives both depths exactly and "equal" means within half
## a step of the file's depth. Both documents are sRGB at full floats, so the
## file's bytes are the stored numbers with no gamut between them and no half
## float rounding them differently on the way out and on the way back.
##
## The Exclusion layer is hidden: its mode falls back to normal, and hidden it
## is still in the file and in the list while the composite stays comparable.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_o4_round_trip.ora")
const CANVAS := Vector2i(512, 256)

const GROUND := Color(0.2, 0.4, 0.6, 1.0)
const FIRST := Color(0.8, 0.2, 0.4, 1.0)
const SECOND := Color(0.4, 0.8, 0.2, 0.6)
const MULTIPLIED := Color(0.6, 0.4, 0.8, 1.0)
const HIDDEN := Color(0.2, 0.2, 0.8, 1.0)
const MASKED := Color(0.8, 0.6, 0.2, 1.0)
const FILTERED := Color(0.2, 0.6, 0.4, 1.0)
const EXCLUDED := Color(0.4, 0.4, 0.4, 1.0)
const HELD := Color(0.6, 0.8, 0.4, 0.8)

## The masked layer shows the left half of its chunk and hides the right.
const SHOWN_AT := Vector2i(40, 10)
const HIDDEN_AT := Vector2i(200, 10)

## Bottom first, a group's node above its members, as Sara keeps them.
const ORDER := [
    "Ground",
    "Layer 1",
    "Paint A",
    "Paint B",
    "Multiply",
    "Group",
    "Hidden",
    "Masked",
    "Filtered",
    "Exclusion",
    "Held",
    "Masked group",
]

## What does not come back as itself, and why: every one a feature the
## format has no place for, baked into pixels or left out, and the opacity a
## pass-through group hands its members so a reader draws it as Sara does.
const LOST := [
    "Ground: generated, opens as its pixels",
    "Group: opacity 0.5, moved onto its members",
    "Masked: mask, baked into its pixels",
    "Filtered: filters, baked into its pixels",
    "Exclusion: blend mode exclusion, opens as normal",
    "Masked group: mask, left out",
]

## The layers whose texels are their own, with nothing baked into them.
const PLAIN := ["Layer 1", "Paint A", "Paint B", "Multiply", "Hidden", "Exclusion", "Held"]

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _opened: SaEasel
var _metadata := SaExportMetadata.new("O4", 1790190245, 0)

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _easel = _new_easel()
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _build()
    Bench.composite(_easel)


func after_each() -> void:
    if FileAccess.file_exists(scratch):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
    _ops = null
    _doc = null
    _easel.free()
    _easel = null
    if _opened != null:
        _opened.free()
        _opened = null


# --- The document -------------------------------------------------------------


## An sRGB easel at full floats whose compositor knows the blend modes and the
## fixture invert, as [code]Bench.easel[/code] builds one at the default depth.
func _new_easel() -> SaEasel:
    var made := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    made.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(InvertFilter.new(), Bench.OWNER)
    made.compositor.filter_chain.registry = filters
    return made


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## A layer called *layer_name* above the active one, holding *color* in the
## chunk at *grid_pos* alone.
func _painted(layer_name: String, color: Color, grid_pos: Vector2i) -> SaLayer:
    var layer := _ops.add()
    layer.name = layer_name
    layer.get_or_create_chunk(grid_pos).clear(color)
    return layer


## One over the left half of the first chunk and zero over the right half.
func _write_half(coverage: SaTexture) -> void:
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < 128 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())


func _build() -> void:
    _ops.remove(_doc.get_node("Background") as SaLayer)
    var ground := _ops.add(&"background", _registries().layer_types)
    ground.name = "Ground"
    _doc.fill_layer(GROUND, ground)
    _ops.move(ground, -1)
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    _painted("Paint A", FIRST, Vector2i(1, 0))
    var second := _painted("Paint B", SECOND, Vector2i(0, 0))
    _ops.set_opacity(second, 0.75)
    var multiply := _painted("Multiply", MULTIPLIED, Vector2i(0, 0))
    _ops.set_blend_mode(multiply, &"multiply")
    var hidden := _painted("Hidden", HIDDEN, Vector2i(1, 0))
    _ops.set_visible(hidden, false)
    var masked := _painted("Masked", MASKED, Vector2i(0, 0))
    assert_true(SaMaskOps.new(_doc).add(masked), "The masked layer takes a mask")
    _write_half(masked.mask.get_or_create(Vector2i(0, 0)))
    var filtered := _painted("Filtered", FILTERED, Vector2i(1, 0))
    assert_true(SaFilterOps.new(_doc).attach(filtered, Bench.INVERT) != null, "The filtered layer takes the invert")
    var excluded := _painted("Exclusion", EXCLUDED, Vector2i(1, 0))
    excluded.blend_mode = &"exclusion"
    _ops.set_visible(excluded, false)
    var group := _ops.group_layers([multiply])
    group.name = "Group"
    _ops.set_opacity(group, 0.5)
    var held := _painted("Held", HELD, Vector2i(0, 0))
    _ops.set_blend_mode(held, &"screen")
    var masked_group := _ops.group_layers([held])
    masked_group.name = "Masked group"
    # A mask that hides nothing, so leaving it out changes no texel of the
    # picture, only what the stack holds.
    assert_true(SaMaskOps.new(_doc).add(masked_group), "The group takes a mask")
    _doc.set_active_layer(second)
    SaLayerStack.invalidate_layer_chunks(_doc, masked)
    _doc.update_caches()


## Exports at *bits* and opens the file into a second easel of the same size,
## which [member _opened] holds.
func _round_trip(bits: int) -> SaOraReader:
    var ora := SaExportOra.new(_doc, bits, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata)
    assert_eq(ora.write(_easel.output, scratch), OK, "The %d-bit export succeeds" % bits)
    if _opened != null:
        _opened.free()
    _opened = _new_easel()
    var reader := SaOraReader.new(ProjectSettings.globalize_path(scratch), SaColorSpace.Depth.F32)
    assert_eq(reader.open_into(_opened.document), OK, "and the %d-bit file opens" % bits)
    Bench.composite(_opened)
    return reader


# --- Comparing ----------------------------------------------------------------


func _names(document: SaDocument) -> Array:
    return _every(document).map(func(node: SaLayer) -> String: return String(node.name))


func _every(document: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in document.get_children():
        if child is SaLayer:
            found.append(child as SaLayer)
    return found


## Half a step of a *bits* file, the most a number on its grid moves.
func _half_step(bits: int) -> float:
    return 0.5 / float((1 << bits) - 1)


## The float texels of *texture*, or of a transparent chunk of *side* where
## there is none.
func _floats(texture: SaTexture, side: int) -> PackedFloat32Array:
    if texture == null:
        var empty := PackedFloat32Array()
        empty.resize(side * side * 4)
        return empty
    return SaExport.get_texture_image_float(texture).get_data().to_float32_array()


## The first texel where *got* and *want* differ by more than *tolerance*, as
## a line, or an empty string when none does.
func _first_difference(got: PackedFloat32Array, want: PackedFloat32Array, tolerance: float, width: int) -> String:
    if got.size() != want.size():
        return "sizes %d and %d" % [got.size(), want.size()]
    for i in got.size():
        if absf(got[i] - want[i]) > tolerance:
            var texel := i >> 2
            var at := Vector2i(texel % width, floori(float(texel) / width))
            return "texel %d,%d channel %d: %f against %f" % [at.x, at.y, i % 4, got[i], want[i]]
    return ""


## The opacity the writer gives *node*: full for a pass-through group, and for
## anything else its own times the pass-through groups' around it, which is
## the opacity Sara draws it at.
func _written_opacity(node: SaLayer) -> float:
    if node.is_group and not SaLayerStack.isolates(node):
        return 1.0
    return node.opacity * SaLayerStack.passthrough_multiplier(node)


## Every feature of the stack that does not come back as itself.
func _lost(original: SaDocument, opened: SaDocument) -> Array:
    var lines: Array = []
    for node in _every(original):
        var back := opened.get_node_or_null(NodePath(String(node.name))) as SaLayer
        if back == null:
            lines.append("%s: missing" % node.name)
            continue
        if node.is_generated() and not back.is_generated():
            lines.append("%s: generated, opens as its pixels" % node.name)
        if node.mask != null and back.mask == null:
            var where := "left out" if node.is_group else "baked into its pixels"
            lines.append("%s: mask, %s" % [node.name, where])
        if SaFilterChain.has_enabled(node.filters) and not SaFilterChain.has_enabled(back.filters):
            lines.append("%s: filters, baked into its pixels" % node.name)
        if node.is_group and not SaLayerStack.isolates(node) and not is_equal_approx(back.opacity, node.opacity):
            lines.append("%s: opacity %s, moved onto its members" % [node.name, node.opacity])
        if back.blend_mode != node.blend_mode:
            lines.append("%s: blend mode %s, opens as %s" % [node.name, node.blend_mode, back.blend_mode])
    return lines


# --- The tests ------------------------------------------------------------------


func test_the_document_holds_what_the_suite_built() -> void:
    assert_eq(_names(_doc), ORDER, "Bottom first, each group above its member")
    assert_true((_doc.get_node("Ground") as SaLayer).is_generated(), "The ground is a generated layer")
    var dropped := SaExportOra.dropped(_doc).map(func(node: SaLayer) -> String: return String(node.name))
    assert_eq(dropped, ["Masked group"], "The writer names the group whose mask it leaves out")
    var fallen := SaExportOra.fallen_back(_doc).map(func(node: SaLayer) -> String: return String(node.name))
    assert_eq(fallen, ["Exclusion"], "and the layer whose mode it writes as normal")


func test_the_stack_comes_back_the_same() -> void:
    for bits: int in [8, 16]:
        var reader := _round_trip(bits)
        var opened := _opened.document
        assert_eq(_names(opened), ORDER, "%d bits: the same names in the same order" % bits)
        assert_eq(opened.canvas_size, CANVAS, "%d bits: the same size" % bits)
        assert_almost_eq(opened.dpi, float(roundi(_doc.dpi)), 1e-4, "%d bits: at the same resolution" % bits)
        assert_eq(opened.active_layer.name, &"Paint B", "%d bits: the same layer active" % bits)
        for node in _every(_doc):
            var back := opened.get_node(NodePath(String(node.name))) as SaLayer
            var what := "%d bits, %s" % [bits, node.name]
            assert_eq(back.is_group, node.is_group, "%s: a group comes back a group" % what)
            assert_almost_eq(back.opacity, _written_opacity(node), 1e-4, "%s: at the opacity Sara draws it at" % what)
            assert_eq(back.visible, node.visible, "%s: shown or hidden as it was" % what)
            var parent := "" if node.group == null else String(node.group.name)
            var parent_back := "" if back.group == null else String(back.group.name)
            assert_eq(parent_back, parent, "%s: in the same group" % what)
            if node.is_group:
                assert_eq(back.isolated, SaLayerStack.isolates(node), "%s: isolated as it composited" % what)
        assert_eq(_lost(_doc, opened), LOST, "%d bits: what the format cannot carry, and nothing else" % bits)
        # The writer already wrote Exclusion as `svg:src-over`, so the reader
        # meets only operators it has a mode for.
        assert_true(reader.fallen_back.is_empty(), "%d bits: the reader finds no op it lacks" % bits)
        assert_true(reader.left_out.is_empty(), "%d bits: and leaves no layer out" % bits)


func test_every_plain_texel_comes_back_equal() -> void:
    for bits: int in [8, 16]:
        _round_trip(bits)
        var tolerance := _half_step(bits)
        for layer_name: String in PLAIN:
            var node := _doc.get_node(layer_name) as SaLayer
            var back := _opened.document.get_node(layer_name) as SaLayer
            var places: Dictionary = {}
            for grid_pos: Vector2i in node.chunks:
                places[grid_pos] = true
            for grid_pos: Vector2i in back.chunks:
                places[grid_pos] = true
            for grid_pos: Vector2i in places:
                var got := _floats(back.get_field(grid_pos), SaChunk.SIZE)
                var want := _floats(node.get_field(grid_pos), SaChunk.SIZE)
                var difference := _first_difference(got, want, tolerance, SaChunk.SIZE)
                assert_eq(difference, "", "%d bits, %s at %s: every texel equal" % [bits, layer_name, grid_pos])


func test_the_baked_layers_hold_what_they_showed() -> void:
    for bits: int in [8, 16]:
        _round_trip(bits)
        var tolerance := _half_step(bits)
        var opened := _opened.document
        var ground := opened.get_node("Ground") as SaLayer
        assert_eq(ground.chunks.size(), 2, "%d bits: the ground comes back as the two chunks it covered" % bits)
        _near(Bench.texel(ground.get_field(Vector2i(1, 0)), Vector2i(255, 255)), GROUND, tolerance, "%d bits: the ground" % bits)
        var masked := (opened.get_node("Masked") as SaLayer).get_field(Vector2i(0, 0))
        _near(Bench.texel(masked, SHOWN_AT), MASKED, tolerance, "%d bits: the mask shows the left half" % bits)
        assert_eq(Bench.texel(masked, HIDDEN_AT).a, 0.0, "%d bits: and hid the right half" % bits)
        var filtered := (opened.get_node("Filtered") as SaLayer).get_field(Vector2i(1, 0))
        var inverted := Color(1.0 - FILTERED.r, 1.0 - FILTERED.g, 1.0 - FILTERED.b, FILTERED.a)
        _near(Bench.texel(filtered, Vector2i(10, 10)), inverted, tolerance, "%d bits: the invert is in the pixels" % bits)


func test_the_picture_comes_back_equal() -> void:
    for bits: int in [8, 16]:
        _round_trip(bits)
        var want := _floats(_easel.output, 0)
        var got := _floats(_opened.output, 0)
        var difference := _first_difference(got, want, _half_step(bits), CANVAS.x)
        assert_eq(difference, "", "%d bits: every texel of the composite equal" % bits)


func _near(got: Color, want: Color, tolerance: float, what: String) -> void:
    assert_almost_eq(got.r, want.r, tolerance, "%s: red" % what)
    assert_almost_eq(got.g, want.g, tolerance, "%s: green" % what)
    assert_almost_eq(got.b, want.b, tolerance, "%s: blue" % what)
    assert_almost_eq(got.a, want.a, tolerance, "%s: alpha" % what)
