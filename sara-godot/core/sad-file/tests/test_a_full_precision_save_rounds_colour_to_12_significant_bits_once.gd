## A save the painter asks for rounds full precision colour to
## 12 significant bits, to nearest with ties to even, once. A document holds
## strokes, values above one and below zero, an infinity of each sign, a NaN
## and the largest finite float, written into its colour on the card, and a
## mask and a height of busy mantissas. Saved as the painter saves, in the
## background, and as the scripting door saves, at once, it reopens with every
## colour channel the rounding of what was painted and every other field as it
## was, a second and a third save change nothing, and the colour's blobs are
## smaller than the same document's saved with nothing rounded.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

## The chunk the strokes are painted over, and the chunk written texel by
## texel with the busy values and the ones a float holds at its edges.
const STROKED := Vector2i(0, 0)
const WRITTEN := Vector2i(1, 0)
const POSITIONS: Array[Vector2i] = [STROKED, WRITTEN]
const FIELDS: Array[StringName] = [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT, SaFieldSpec.MASK]

## The patterns the first texels of [constant WRITTEN] hold, channel by
## channel: an infinity of each sign, a quiet NaN and the largest finite float,
## which the rounding would carry to infinity and so keeps.
const EDGES: Array[int] = [0x7F800000, 0xFF800000, 0x7FC00001, 0x7F7FFFFF]

## A difference of at most this share of the painted value.
const SHARE := 1.0 / 4096.0

static var first: String = SaDataRoot.path("test_first.sad")
static var second: String = SaDataRoot.path("test_second.sad")
static var third: String = SaDataRoot.path("test_third.sad")
static var lossless: String = SaDataRoot.path("test_lossless.sad")


func after_each() -> void:
    SaSadFile.finish_saves()
    for path: String in [first, second, third, lossless]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A document of one layer at full precision in *space*, holding colour, a
## height and a mask over [constant POSITIONS]. Two strokes of a colour above
## one and below zero at part strength cross [constant STROKED], and
## [constant WRITTEN] holds random values from below zero to above one, with
## [constant EDGES] in its first texel, written on the card as the bench writes.
static func painted(space: SaColorSpace) -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), space.with_depth(SaColorSpace.Depth.F32))
    var layer := doc.active_layer
    var colour_spec := SaFieldSpec.albedo(doc.color_space.texel_format())
    var fields: Array[SaFieldSpec] = [colour_spec, SaFieldSpec.height(), SaFieldSpec.mask()]
    layer.schema = fields
    layer.chunks.clear()
    for grid_pos in POSITIONS:
        layer.get_or_create_chunk(grid_pos)
    for stroke: Color in [Color(5.123457, -0.3141593, 0.7777777, 0.61803), Color(-1.414213, 2.718281, 0.1, 0.333333)]:
        doc.begin_stroke(0.7071, &"normal")
        doc.stroke_layer.get_or_create_field(STROKED, SaFieldSpec.ALBEDO).clear(stroke)
        doc.commit_stroke()
    var rng := RandomNumberGenerator.new()
    rng.seed = 140
    var colour := layer.get_or_create_field(WRITTEN, SaFieldSpec.ALBEDO)
    var bytes := PackedByteArray()
    bytes.resize(colour.size.x * colour.size.y * 16)
    for at in range(0, bytes.size(), 4):
        bytes.encode_float(at, rng.randf_range(-3.0, 7.0))
    for channel in EDGES.size():
        bytes.encode_u32(channel * 4, EDGES[channel])
    rd.texture_update(colour.rid, 0, bytes)
    for field_id: StringName in [SaFieldSpec.HEIGHT, SaFieldSpec.MASK]:
        for grid_pos in POSITIONS:
            var texture := layer.get_or_create_field(grid_pos, field_id)
            var layout: Vector2i = SaSadBlob.LAYOUT[texture.format]
            var busy := PackedByteArray()
            busy.resize(texture.size.x * texture.size.y * layout.x * layout.y)
            for at in range(0, busy.size(), layout.y):
                if layout.y == 2:
                    busy.encode_half(at, rng.randf_range(-2.0, 2.0))
                else:
                    busy.encode_float(at, rng.randf_range(-2.0, 2.0))
            rd.texture_update(texture.rid, 0, busy)
    return doc


## Every field of *doc*'s active layer, the one painted, at each of [constant POSITIONS], as the
## card holds it, keyed by field and then by position.
static func fields_of(doc: SaDocument) -> Dictionary[StringName, Dictionary]:
    var rd := GlobalShaderCompiler.get_rd()
    var layer := doc.active_layer
    var found: Dictionary[StringName, Dictionary] = {}
    for field_id in FIELDS:
        var each := {}
        for grid_pos in POSITIONS:
            var texture := layer.get_field(grid_pos, field_id) if layer != null else null
            each[grid_pos] = rd.texture_get_data(texture.rid, 0) if texture != null else PackedByteArray()
        found[field_id] = each
    return found


## The document at *path*, or null when it would not open.
static func reopened(path: String) -> SaDocument:
    var doc := SaDocument.new()
    if SaExport.load_sad(doc, path, SaCompositor.new()) != OK:
        doc.free()
        return null
    return doc


## Saves *doc* to *path* as the painter's File > Save does, in the background
## with the rounding asked for, and answers whether it ended.
static func save_as_the_painter(doc: SaDocument, path: String) -> bool:
    SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true)
    return SaSadFile.finish_saves()


## The bytes of every colour blob of the file at *path*, compressed, summed.
static func colour_bytes(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return 0
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    var header := SaTyped.strings(JSON.parse_string(text))
    file.close()
    var total := 0
    for layer: Variant in header.get("layers", []):
        for chunk: Variant in SaTyped.strings(layer).get("chunks", []):
            var slots := SaTyped.strings(SaTyped.strings(chunk).get("fields", {}))
            total += SaTyped.int_at(SaTyped.strings(slots.get("albedo", {})), "size", 0)
    return total


func test_the_reference_rounds_to_nearest_with_ties_to_even() -> void:
    assert_eq(SaSadSnapshot.round_bits(0x3F800000), 0x3F800000, "One keeps its pattern")
    assert_eq(SaSadSnapshot.round_bits(0x3F8007FF), 0x3F800000, "Below half a step goes down")
    assert_eq(SaSadSnapshot.round_bits(0x3F800801), 0x3F801000, "above half a step goes up")
    assert_eq(SaSadSnapshot.round_bits(0x3F800800), 0x3F800000, "a tie goes to the even pattern below")
    assert_eq(SaSadSnapshot.round_bits(0x3F801800), 0x3F802000, "and a tie above an odd one goes up to the even")
    assert_eq(SaSadSnapshot.round_bits(0xBF801800), 0xBF802000, "A negative value rounds its magnitude alike")
    assert_eq(SaSadSnapshot.round_bits(0x3FFFFFFF), 0x40000000, "A carry out of the mantissa raises the exponent")
    for edge in EDGES:
        assert_eq(SaSadSnapshot.round_bits(edge), edge, "Pattern %x is kept as it is" % edge)


func test_a_painter_s_save_rounds_every_colour_channel_once_and_keeps_every_other_field() -> void:
    _rounds_once(SaColorSpace.srgb(), true)


func test_the_scripting_door_s_save_at_once_rounds_the_same() -> void:
    _rounds_once(SaColorSpace.srgb(), false)


func test_an_oklab_document_rounds_its_l_a_and_b_the_same() -> void:
    _rounds_once(SaColorSpace.oklab(), true)


func _rounds_once(space: SaColorSpace, background: bool) -> void:
    var how := "%s, saved %s" % [space.id, "as the painter does" if background else "at once as the door does"]
    var source := painted(space)
    var painted_fields := fields_of(source)
    var saved := save_as_the_painter(source, first) if background else SaExport.save_sad(source, first, 0, null, true) == OK
    assert_true(saved, "%s: the save lands" % how)
    assert_eq(fields_of(source), painted_fields, "%s: and the document on the card is as painted" % how)
    var back := reopened(first)
    assert_not_null(back, "%s: the file opens" % how)
    if back == null:
        source.free()
        return
    var opened := fields_of(back)
    for grid_pos in POSITIONS:
        var where := "%s, chunk %s" % [how, grid_pos]
        _reads_rounded(painted_fields[SaFieldSpec.ALBEDO][grid_pos], opened[SaFieldSpec.ALBEDO][grid_pos], where)
        for field_id: StringName in [SaFieldSpec.HEIGHT, SaFieldSpec.MASK]:
            var said := "%s: the %s is as painted" % [where, field_id]
            assert_eq(opened[field_id][grid_pos], painted_fields[field_id][grid_pos], said)
    source.free()
    back.free()


## Reads every channel of *opened* the rounding of the same channel of
## *painted*, within a 4096th of it, with its sign and its exponent whole.
func _reads_rounded(painted_bytes: PackedByteArray, opened: PackedByteArray, how: String) -> void:
    assert_eq(opened.size(), painted_bytes.size(), "%s: the colour comes back whole" % how)
    if opened.size() != painted_bytes.size():
        return
    var wrong := 0
    var far := 0
    var turned := 0
    var moved := 0
    for at in range(0, painted_bytes.size(), 4):
        var bits := painted_bytes.decode_u32(at)
        var back := opened.decode_u32(at)
        if back != SaSadSnapshot.round_bits(bits):
            wrong += 1
        var exponent := (bits >> 23) & 0xFF
        var back_exponent := (back >> 23) & 0xFF
        if (bits ^ back) & 0x80000000 != 0:
            turned += 1
        # The one change of exponent a rounding makes is the carry, one up,
        # to a mantissa of zero.
        if back_exponent != exponent and not (back_exponent == exponent + 1 and back & 0x7FFFFF == 0):
            moved += 1
        if exponent != 0xFF:
            var value := painted_bytes.decode_float(at)
            if absf(opened.decode_float(at) - value) > absf(value) * SHARE:
                far += 1
    assert_eq(wrong, 0, "%s: every channel is the 12 bit rounding of the painted one" % how)
    assert_eq(far, 0, "%s: none moves by more than a 4096th of itself" % how)
    assert_eq(turned, 0, "%s: no sign changes" % how)
    assert_eq(moved, 0, "%s: no exponent changes but by a carry" % how)
    for channel in EDGES.size():
        if how.ends_with(str(WRITTEN)):
            assert_eq(opened.decode_u32(channel * 4), EDGES[channel], "%s: pattern %x is as painted" % [how, EDGES[channel]])


func test_a_second_and_a_third_save_round_nothing() -> void:
    var source := painted(SaColorSpace.srgb())
    assert_true(save_as_the_painter(source, first), "The first save lands")
    var once := reopened(first)
    assert_true(save_as_the_painter(once, second), "The reopened document saves again")
    var twice := reopened(second)
    assert_true(save_as_the_painter(twice, third), "and that a third time")
    var thrice := reopened(third)
    var expected := fields_of(once)
    assert_eq(fields_of(twice), expected, "The second file reopens equal to the first, bit for bit")
    assert_eq(fields_of(thrice), expected, "and so does the third")
    for doc: SaDocument in [source, once, twice, thrice]:
        doc.free()


func test_the_rounded_colour_is_smaller_than_the_same_colour_kept_whole() -> void:
    var source := painted(SaColorSpace.srgb())
    assert_true(save_as_the_painter(source, first), "The painter's save lands")
    SaSadFile.save_in_background(source, lossless, 0, null, true, Callable(), false)
    assert_true(SaSadFile.finish_saves(), "and so does the same save with nothing rounded")
    var rounded := colour_bytes(first)
    var whole := colour_bytes(lossless)
    assert_true(rounded > 0 and rounded < whole, "The colour's blobs are smaller rounded, %d bytes against %d" % [rounded, whole])
    print("The colour's blobs rounded are %d of %d bytes, %.1f%%" % [rounded, whole, 100.0 * rounded / maxi(whole, 1)])
    source.free()
