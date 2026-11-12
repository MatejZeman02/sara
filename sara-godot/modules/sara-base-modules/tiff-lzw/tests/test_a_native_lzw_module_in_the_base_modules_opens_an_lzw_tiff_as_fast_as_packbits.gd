## A native LZW module in the base modules opens an LZW TIFF as
## fast as PackBits.
##
## The same strips go through `SaTiffLzw`, the library of this folder, and
## through [SaTiffUnpacker]'s GDScript, asked for by a class name Godot does not
## have, and must give the same bytes and the same fault: whole strips of
## pictures from flat to noisy, the same strips with bytes damaged, cut short,
## or given less room than they unpack to, and bytes that were never LZW. With
## the library left out the GDScript unpacks every strip and a whole file opens
## as the same strips written with PackBits do.
extends "res://tests/test_framework.gd"

const Encoders = preload(
    "res://modules/sara-base-modules/image-formats/tiff/tests/test_a_tiff_compressed_with_lzw_or_packbits_opens.gd"
)

const LZW: int = 5
## A class name no build registers, which is how the unpacker is told to use
## its GDScript as it does when the library is not there.
const ABSENT := &"SaTiffLzwLeftOut"
const STRIPS: int = 240


func test_the_native_unpacker_gives_the_gdscripts_bytes_and_faults_strip_for_strip() -> void:
    if not ClassDB.class_exists(SaTiffUnpacker.LIBRARY):
        skip("the tiff-lzw library is not built, packaging/build.sh modules builds it")
        return
    var encoders := Encoders.new()
    var random := RandomNumberGenerator.new()
    random.seed = 239
    var differ := 0
    var faults := 0
    var first := ""
    for i in STRIPS:
        var raw := _strip(random, i)
        var packed: PackedByteArray = encoders._lzw(raw)
        var most := raw.size()
        match i % 5:
            1:
                for hit in random.randi_range(1, 4):
                    packed[random.randi() % packed.size()] = random.randi() & 0xFF
            2:
                packed = packed.slice(0, random.randi_range(0, packed.size()))
            3:
                most = random.randi_range(0, raw.size())
            4:
                packed = _noise(random, random.randi_range(1, 600))
        var native := SaTiffUnpacker.new(packed, LZW, most)
        var script := SaTiffUnpacker.new(packed, LZW, most, ABSENT)
        assert_true(native.native and not script.native, "strip %d went through the library and through the GDScript" % i)
        if not script.fault.is_empty():
            faults += 1
        if native.bytes != script.bytes or native.fault != script.fault:
            differ += 1
            if first.is_empty():
                first = (
                    "strip %d: %d bytes '%s' natively, %d bytes '%s' in GDScript"
                    % [i, native.bytes.size(), native.fault, script.bytes.size(), script.fault]
                )
        if i % 5 == 0:
            assert_true(native.bytes == raw, "the whole strip %d unpacks to what was packed" % i)
    print("  probe: %d strips, %d of them faults, %d differ" % [STRIPS, faults, differ])
    assert_eq(differ, 0, "the library and the GDScript agree on every strip %s" % first)
    @warning_ignore("integer_division")
    assert_true(faults > STRIPS / 5, "the damaged strips include faults to agree on, %d" % faults)


func test_with_the_library_left_out_the_gdscript_unpacks_and_the_file_opens() -> void:
    var encoders := Encoders.new()
    var random := RandomNumberGenerator.new()
    random.seed = 2390
    var width := 300
    var rows := 16
    var raw := PackedByteArray()
    var strips := []
    var plain := []
    for top in range(0, 64, rows):
        var strip := _strip_of(random, width * 3 * rows, top)
        raw.append_array(strip)
        strips.append(encoders._lzw(strip))
        plain.append(encoders._pack_bits(strip))
    for at in strips.size():
        var unpacker := SaTiffUnpacker.new(strips[at], LZW, width * 3 * rows, ABSENT)
        assert_false(unpacker.native, "strip %d is the GDScript's" % at)
        assert_eq(unpacker.fault, "", "strip %d unpacks" % at)
        assert_true(unpacker.bytes == raw.slice(at * width * 3 * rows, (at + 1) * width * 3 * rows), "strip %d as packed" % at)
    var fields := {256: [width], 257: [64], 258: [8, 8, 8], 259: [LZW], 262: [2], 277: [3], 278: [rows]}
    var picture := SaTiffReader.new(encoders._tiff(fields, strips), "left-out.tif").picture()
    fields[259] = [SaTiffUnpacker.PACK_BITS]
    var written := SaTiffReader.new(encoders._tiff(fields, plain), "left-out-packbits.tif").picture()
    assert_not_null(picture, "the file opens")
    if picture != null and written != null:
        assert_true(picture.get_data() == written.get_data(), "texel for texel as the same strips through PackBits")
    var default := SaTiffUnpacker.new(strips[0], LZW, width * 3 * rows)
    var loaded := ClassDB.class_exists(SaTiffUnpacker.LIBRARY)
    assert_eq(default.native, loaded, "the reader's unpacker takes the library exactly when Godot loaded it")


## A strip of *index*'s kind: flat, ramps, ramps under noise, or noise alone,
## so the table fills slowly or at once and clears or not.
func _strip(random: RandomNumberGenerator, index: int) -> PackedByteArray:
    return _strip_of(random, random.randi_range(1, 24000), index)


func _strip_of(random: RandomNumberGenerator, size: int, index: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(size)
    var level := random.randi_range(0, 255)
    @warning_ignore("integer_division")
    var kind := (index / 5) % 4
    for at in size:
        match kind:
            0:
                out[at] = level
            1:
                @warning_ignore("integer_division")
                out[at] = (at / 7 + level) & 0xFF
            2:
                @warning_ignore("integer_division")
                out[at] = (at / 11 + random.randi() % 17) & 0xFF
            _:
                out[at] = random.randi() & 0xFF
    return out


func _noise(random: RandomNumberGenerator, size: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(size)
    for at in size:
        out[at] = random.randi() & 0xFF
    return out
