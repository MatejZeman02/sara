## A `.cube` file loads as a colour lookup table filter.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The files are written to the data root and read back through the dialog's own
## load, so the parser, the record and the kernel are all on the path. The layer
## is a ramp across two chunks, red running to 1.4, so a lookup is also read
## past the table's domain, where an identity table has to leave it alone.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)
const CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const PEAK := 1.4
const UNCHANGED := 1e-4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaLutFilter = null
var _key: StringName = &""
var _files: Array[String] = []


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    _filter = SaLutFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)


func after_each() -> void:
    for path in _files:
        DirAccess.remove_absolute(path)
    _files.clear()
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The text of a `.cube` file of *size* a side whose entry at grid point
## (r, g, b) in 0 to 1 is *mapping* of that point.
static func _cube_text(size: int, mapping: Callable, header: String = "") -> String:
    var text := '# written by the suite\nTITLE "suite"\n%sLUT_3D_SIZE %d\n' % [header, size]
    for b in size:
        for g in size:
            for r in size:
                var out: Vector3 = mapping.call(Vector3(r, g, b) / float(size - 1))
                text += "%.7f %.7f %.7f\n" % [out.x, out.y, out.z]
    return text


## Writes *text* as a file called *file* and answers its path.
func _write(file: String, text: String) -> String:
    var path := SaDataRoot.path(file)
    var handle := FileAccess.open(path, FileAccess.WRITE)
    handle.store_string(text)
    handle.close()
    _files.append(ProjectSettings.globalize_path(path))
    return ProjectSettings.globalize_path(path)


## What the dialog's button does once the picker answers, over *path*.
func _load(path: String) -> Dictionary:
    var panel := SaLutFilter.LutPanel.new(_filter)
    panel.load_file(path)
    var line := (panel.get_node("LutLine") as Label).text
    panel.free()
    return {"values": _filter.parameters(), "line": line}


static func _colour_at(x: int, y: int) -> Color:
    return Color(float(x) / float(SIZE.x - 1) * PEAK, float(y % 200) / 199.0 * 0.9, 0.25, 1.0)


func _paint_ramp() -> void:
    for grid_pos: Vector2i in CHUNKS:
        var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        var values := PackedFloat32Array()
        values.resize(texture.size.x * texture.size.y * 4)
        for y in texture.size.y:
            for x in texture.size.x:
                var c := _colour_at(grid_pos.x * texture.size.x + x, y)
                var i := (y * texture.size.x + x) * 4
                values[i] = c.r
                values[i + 1] = c.g
                values[i + 2] = c.b
                values[i + 3] = 1.0
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
    _doc.history.reset()
    _doc.undo_redo.clear_history()


func _texels() -> Dictionary:
    var out := {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in _layer.chunks.keys():
        var texture := _layer.get_field(grid_pos)
        var bytes := rd.texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                out[grid_pos * texture.size + Vector2i(x, y)] = SaFieldSpec.decode_texel(
                    bytes, texture.format, y * texture.size.x + x
                )
    return out


func _apply(values: Dictionary) -> void:
    assert_true(SaFilterOps.new(_doc).apply_once(_layer, _key, values, "LUT"), "Bake writes the layer")


func _identity_case(size: int) -> void:
    _paint_ramp()
    var before := _texels()
    var path := _write("f7_identity_%d.cube" % size, _cube_text(size, func(p: Vector3) -> Vector3: return p))
    var loaded := _load(path)
    var values: Dictionary = loaded["values"]
    assert_eq(int(values["size"]), size, "The table's size is read as %d" % size)
    assert_eq(values["name"], "f7_identity_%d.cube" % size, "and the record names the file")
    _apply(values)
    var worst := 0.0
    var after := _texels()
    for at: Vector2i in before:
        if at.x % 5 != 0 or at.y % 7 != 0:
            continue
        var a: Color = before[at]
        var b: Color = after[at]
        worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    assert_true(worst <= UNCHANGED, "An identity table of %d leaves the layer, past the domain too, worst %s" % [size, worst])
    var edge: Color = after[Vector2i(SIZE.x - 1, 0)]
    assert_true(edge.r > 1.3, "and the red of %s past one stays above it, read %s" % [PEAK, edge.r])


func test_an_identity_table_of_two_leaves_the_layer() -> void:
    _identity_case(2)


func test_an_identity_table_of_seventeen_leaves_the_layer() -> void:
    _identity_case(17)


func test_a_table_that_swaps_red_and_blue_turns_a_red_layer_blue() -> void:
    _layer.fill(Color(1.0, 0.0, 0.0, 1.0))
    var path := _write("f7_swap.cube", _cube_text(2, func(p: Vector3) -> Vector3: return Vector3(p.z, p.y, p.x)))
    _apply(_load(path)["values"])
    var c: Color = _texels()[Vector2i(300, 100)]
    assert_true(c.r < 1e-3 and c.g < 1e-3 and absf(c.b - 1.0) < 1e-3, "Red reads blue after the swap: %s" % c)


func test_a_table_is_mixed_trilinearly_between_its_entries() -> void:
    _layer.fill(Color(0.25, 0.5, 0.75, 1.0))
    var invert := func(p: Vector3) -> Vector3: return Vector3.ONE - p
    _apply(_load(_write("f7_invert.cube", _cube_text(3, invert)))["values"])
    var c: Color = _texels()[Vector2i(300, 100)]
    var exact := absf(c.r - 0.75) < 1e-4 and absf(c.g - 0.5) < 1e-4 and absf(c.b - 0.25) < 1e-4
    assert_true(exact, "A linear table is exact between its points: %s" % c)


func test_a_domain_other_than_nought_to_one_places_the_value_inside_it() -> void:
    _layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var header := "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n"
    var text := _cube_text(2, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, 1.0 - p.z), header)
    _apply(_load(_write("f7_domain.cube", text))["values"])
    var c: Color = _texels()[Vector2i(300, 100)]
    var placed := absf(c.r - 0.25) < 1e-4 and absf(c.g) < 1e-4 and absf(c.b - 0.75) < 1e-4
    assert_true(placed, "0.5 in a domain of 2 sits a quarter of the way: %s" % c)


func test_a_table_with_an_input_range_line_loads_identity() -> void:
    var header := "LUT_3D_INPUT_RANGE 0.0 1.0\n"
    var text := _cube_text(2, func(p: Vector3) -> Vector3: return p, header)
    var path := _write("identity_input_range.cube", text)
    var cube := SaLutFilter.Cube.parse(FileAccess.get_file_as_string(path))
    assert_eq(cube.problem, "", "The table parses with no problem")
    assert_eq(cube.size, 2, "Size is 2")
    var expected_entries := PackedFloat32Array(
        [
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            1.0,
            0.0,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
        ]
    )
    assert_eq(cube.entries, expected_entries, "The table holds the identity entries")
    var loaded := _load(path)
    var values: Dictionary = loaded["values"]
    assert_eq(int(values["size"]), 2, "Loaded table has size 2")
    assert_eq(values["name"], "identity_input_range.cube", "The record names the file")


func test_an_input_range_line_matches_domain_min_and_max() -> void:
    _paint_ramp()
    var mapping := func(p: Vector3) -> Vector3: return Vector3(p.x * 0.8, p.y * 0.6, 1.0 - p.z)
    var domain_header := "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 0.5 0.5 0.5\n"
    var domain_text := _cube_text(2, mapping, domain_header)
    var domain_path := _write("domain.cube", domain_text)
    _apply(_load(domain_path)["values"])
    var domain_texels := _texels()

    _paint_ramp()
    var range_header := "LUT_3D_INPUT_RANGE 0.0 0.5\n"
    var range_text := _cube_text(2, mapping, range_header)
    var range_path := _write("range.cube", range_text)
    _apply(_load(range_path)["values"])
    var range_texels := _texels()

    var worst := 0.0
    for at: Vector2i in domain_texels:
        var a: Color = domain_texels[at]
        var b: Color = range_texels[at]
        worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    assert_true(worst < 1e-4, "Texels with LUT_3D_INPUT_RANGE match DOMAIN_MIN and DOMAIN_MAX, worst diff %s" % worst)


func test_an_invalid_input_range_line_is_refused() -> void:
    SaProblems.announce = false
    var cases := {
        "one_num.cube": ["LUT_3D_INPUT_RANGE 0.0\nLUT_3D_SIZE 2\n" + "0 0 0\n".repeat(8), "LUT_3D_INPUT_RANGE"],
        "equal.cube": ["LUT_3D_INPUT_RANGE 0.5 0.5\nLUT_3D_SIZE 2\n" + "0 0 0\n".repeat(8), "LUT_3D_INPUT_RANGE"],
        "below.cube": ["LUT_3D_INPUT_RANGE 0.8 0.2\nLUT_3D_SIZE 2\n" + "0 0 0\n".repeat(8), "LUT_3D_INPUT_RANGE"],
        "1d_range.cube": ["LUT_1D_INPUT_RANGE 0.0 1.0\nLUT_3D_SIZE 2\n", "1D"],
    }
    var kept := _filter.parameters()
    for file: String in cases:
        var loaded := _load(_write(file, cases[file][0]))
        var line: String = loaded["line"]
        var wanted: String = cases[file][1]
        assert_true(line.begins_with(file), "The line names %s: %s" % [file, line])
        assert_true(line.contains(wanted), "Line says what was wrong, '%s': %s" % [wanted, line])
        assert_eq(loaded["values"], kept, "The record keeps what it had")
    SaProblems.announce = true


func test_a_file_that_does_not_parse_is_refused_with_its_name_and_the_reason() -> void:
    SaProblems.announce = false
    var cases := {
        "f7_no_size.cube": ["0 0 0\n", "no_size"],
        "f7_short.cube": ["LUT_3D_SIZE 2\n0 0 0\n1 1 1\n", "holds 8 rows and this has 2"],
        "f7_1d.cube": ["LUT_1D_SIZE 4\n", "1D"],
        "f7_1d_range.cube": ["LUT_1D_INPUT_RANGE 0.0 1.0\n", "1D"],
        "f7_word.cube": ["LUT_3D_SIZE 2\n0 0 zero\n", "line 2"],
        "f7_domain_flat.cube": ["DOMAIN_MIN 1 1 1\nDOMAIN_MAX 1 1 1\nLUT_3D_SIZE 2\n" + "0 0 0\n".repeat(8), "DOMAIN_MAX"],
    }
    var kept := _filter.parameters()
    for file: String in cases:
        var loaded := _load(_write(file, cases[file][0]))
        var line: String = loaded["line"]
        var wanted: String = cases[file][1]
        assert_true(line.begins_with(file), "The line names %s: %s" % [file, line])
        if wanted != "no_size":
            assert_true(line.contains(wanted), "and says what was wrong, '%s': %s" % [wanted, line])
        assert_eq(loaded["values"], kept, "and the record keeps what it had")
    SaProblems.announce = true


func test_the_table_saves_with_the_document_and_survives_the_file_going() -> void:
    var trip := RoundTrip.new(SaLutFilter.new(), OWNER)
    var path := _write("f7_round_trip.cube", _cube_text(5, func(p: Vector3) -> Vector3: return Vector3(p.z, p.y * 0.5, p.x)))
    var cube := SaLutFilter.Cube.parse(FileAccess.get_file_as_string(path))
    trip.filter.set_parameters(SaLutFilter.values_for(cube, "f7_round_trip.cube"))
    var plain := trip.texels()
    var kept := trip.attach(trip.filter.parameters())
    var before := trip.texels()
    assert_true(RoundTrip.distance(plain, before) > 0.1, "Attached, the table moves the composite")
    DirAccess.remove_absolute(path)
    assert_false(FileAccess.file_exists(path), "The .cube file is gone")
    var loaded := trip.round_trip()
    assert_eq(loaded.get("table"), kept["table"], "The loaded record carries the table")
    assert_eq(loaded.get("name"), "f7_round_trip.cube", "and the file's name")
    var after := trip.texels()
    assert_true(RoundTrip.distance(before, after) < UNCHANGED, "and draws the same composite, %s against %s" % [before, after])
    trip.release()


func test_it_is_listed_under_colour() -> void:
    assert_eq(_filter.family(), &"color", "Colour")
    assert_false(_filter.finishes(), "and runs where it stands in a chain")
