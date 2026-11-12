## A Radiance picture opens with its sun and in every layout.
##
## Godot's loader, which File > Open used for a `.hdr` before `SaRadianceReader`, clamped
## every value past 65,408 and refused XYZE and every orientation but `-Y +X`.
## `SaRadianceReader` replaces it, and this suite writes small Radiance files of
## its own, flat and run-length, RGBE and XYZE, in each of the eight
## orientations, and reads every texel back as the file stores it.
##
## The writer here is Greg Ward's: a texel's brightest channel sets a shared
## exponent and each mantissa is the channel truncated to eight bits under it.
## What a texel should read back is worked out from its four bytes alone, the
## mantissa times two to the exponent less 136, so the suite checks the reader
## against the format rather than against a copy of the reader's arithmetic.
##
## 100,000 has no exact RGBE form, being 3,125 times 32, and a mantissa holds
## no more than 255. Ward's writer stores it as 195 under the exponent 145,
## which is 99,840, and that is the value the reader has to return, past the
## 65,408 Godot's loader stopped at.
##
## The fixture beside this suite, `sun.hdr`, is a synthetic sky panorama: 512
## by 256 texels of run-length RGBE stored `+Y -X`, rows from the bottom up and
## each from the right, so a reader that took it as `-Y +X` would show it upside
## down and mirrored. A sky in bands of eight rows grows from a deep blue at the
## top to a pale one at row 191, a dark ground lies under it, and a sun of radius
## eight centred on (384, 72) holds 100,000, stored as 99,840, inside a halo out
## to radius fourteen of 20,000, 18,000 and 15,000, stored as 19,968, 17,920 and
## 14,976. Ward's writer made it, in 11,617 bytes.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Ten by nine, so a scanline is at least eight texels either way and the
## run-length form is written whichever axis the lines run along.
const SIZE := Vector2i(10, 9)
## Where the picture holds its 100,000, and what the file stores of it.
const SUN := Vector2i(7, 2)
const SUN_ASKED := 100000.0
const SUN_STORED := 99840.0
const SUN_BYTES := [195, 195, 195, 145]
## The eight orientations, as Radiance writes the two axes of the resolution
## line: the major axis first.
const ORIENTATIONS: Array[String] = ["-Y +X", "-Y -X", "+Y -X", "+Y +X", "+X -Y", "+X +Y", "-X -Y", "-X +Y"]
const EXPONENT_BIAS := 136
const FIXTURE := "res://modules/sara-base-modules/image-formats/radiance/tests/sun.hdr"
const FIXTURE_SIZE := Vector2i(512, 256)
const FIXTURE_SUN := Vector2i(384, 72)

var _problems: Array[String] = []
var _scratch: Array[String] = []

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _problems.clear()
    _scratch.clear()
    # A line through `SaProblems` is a push_error while it announces, and a
    # deliberate one fails the run, so the lines come to the suite instead.
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    for path in _scratch:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The ask: every texel of an RGBE picture comes back as its bytes say, upright,
## in each orientation, flat and run-length, the sun at 99,840 among them.
func test_rgbe_reads_back_to_the_bit_in_every_orientation_flat_and_run_length() -> void:
    var texels := _encode(_picture())
    assert_eq(texels[SUN.y * SIZE.x + SUN.x], PackedByteArray(SUN_BYTES), "Ward's writer stores 100,000 as 195 under 145")
    assert_eq(_value(texels[SUN.y * SIZE.x + SUN.x], 0), SUN_STORED, "which is 99,840")
    for orientation in ORIENTATIONS:
        for run_length: bool in [false, true]:
            var form := "%s, %s" % [orientation, "run-length" if run_length else "flat"]
            var bytes := _file_bytes(texels, "32-bit_rle_rgbe", orientation, run_length)
            var image := SaRadianceReader.new(bytes, form).picture()
            assert_not_null(image, "%s is read" % form)
            if image == null:
                continue
            assert_eq(image.get_size(), SIZE, "%s at its own size" % form)
            assert_eq(image.get_format(), Image.FORMAT_RGBAF, "%s at full floats, since 99,840 is past a half" % form)
            var wrong := _mismatches(image, texels)
            assert_true(wrong.is_empty(), "%s holds every texel as its bytes say, upright: %s" % [form, wrong])
            assert_eq(image.get_pixel(SUN.x, SUN.y).r, SUN_STORED, "%s keeps the sun at 99,840" % form)


## The run-length form really is the one written, so the flat and the
## run-length halves of the case above are not one form read twice.
func test_the_run_length_file_is_the_smaller() -> void:
    var texels := _encode(_picture())
    var flat := _file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", false)
    var packed := _file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true)
    assert_true(packed.size() < flat.size(), "The run-length file is %d bytes against the flat %d" % [packed.size(), flat.size()])


## XYZE in every orientation: its X, Y and Z are decoded as the bytes say and
## carried into sRGB's primaries, equal energy adapted to D65, so the colour is
## the file's and a white stays white.
func test_xyze_reads_in_every_orientation_as_its_colour() -> void:
    var texels := _encode(_picture())
    # One texel of X, Y and Z at exactly one, Radiance's white.
    texels[0] = PackedByteArray([128, 128, 128, 129])
    var to_rgb := (
        SaColorSpace.linear_srgb().xyz_to_rgb() * SaColorSpace.adaptation(SaRadianceReader.WHITE_E, SaColorSpace.WHITE_D65)
    )
    for orientation in ORIENTATIONS:
        for run_length: bool in [false, true]:
            var form := "XYZE %s, %s" % [orientation, "run-length" if run_length else "flat"]
            var image := SaRadianceReader.new(_file_bytes(texels, "32-bit_rle_xyze", orientation, run_length), form).picture()
            assert_not_null(image, "%s is read" % form)
            if image == null:
                continue
            assert_eq(
                image.get_format(), Image.FORMAT_RGBAF, "%s at full floats, since the matrix makes values no half keeps" % form
            )
            var worst := 0.0
            for y in SIZE.y:
                for x in SIZE.x:
                    var bytes := texels[y * SIZE.x + x]
                    var stored := Vector3(_value(bytes, 0), _value(bytes, 1), _value(bytes, 2))
                    var wanted := to_rgb * stored
                    var read := image.get_pixel(x, y)
                    var scale := maxf(1.0, maxf(absf(wanted.x), maxf(absf(wanted.y), absf(wanted.z))))
                    worst = maxf(worst, (Vector3(read.r, read.g, read.b) - wanted).length() / scale)
            assert_true(worst < 1e-6, "%s holds each texel's XYZ in sRGB's primaries, worst relative error %s" % [form, worst])
            var white := image.get_pixel(0, 0)
            assert_true(
                absf(white.r - 1.0) < 1e-4 and absf(white.g - 1.0) < 1e-4 and absf(white.b - 1.0) < 1e-4,
                "%s keeps Radiance's white white, read %s" % [form, white]
            )
    assert_true(_problems.size() > 0 and _problems[0].contains("32 bits"), "and says why it is held at 32 bits: %s" % [_problems])


## A picture all of whose values a half keeps arrives as halves and names F16,
## with nothing said. One value past 65,504, or one under a half's smallest
## normal value, which Godot's conversion makes zero, makes it full floats and
## names F32, with a line saying which.
func test_the_depth_is_f16_when_every_value_fits_a_half_and_f32_said_in_a_line_when_one_does_not() -> void:
    var texels := _encode(_picture())
    texels[SUN.y * SIZE.x + SUN.x] = PackedByteArray([250, 250, 250, 140])
    var halves := SaRadianceReader.new(_file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true), "halves.hdr").picture()
    assert_eq(halves.get_format(), Image.FORMAT_RGBAH, "A sun of 4,000 and a sky fit halves")
    assert_eq(SaImageImport.depth_for(halves), SaColorSpace.Depth.F16, "so the picture names F16")
    var wrong := _mismatches(halves, texels)
    assert_true(wrong.is_empty(), "and every texel is still the file's: %s" % [wrong])
    assert_true(_problems.is_empty(), "with nothing said: %s" % [_problems])

    texels[SUN.y * SIZE.x + SUN.x] = PackedByteArray(SUN_BYTES)
    var bright := SaRadianceReader.new(_file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true), "bright.hdr").picture()
    assert_eq(SaImageImport.depth_for(bright), SaColorSpace.Depth.F32, "A sun at 99,840 names F32")
    assert_eq(_problems.size(), 1, "in one line")
    var said := _problems[0] if not _problems.is_empty() else ""
    assert_true(
        said.contains("bright.hdr") and said.contains("99,840") and said.contains("65,504"), "naming the value: %s" % said
    )

    _problems.clear()
    texels[SUN.y * SIZE.x + SUN.x] = PackedByteArray([250, 1, 250, EXPONENT_BIAS - 15])
    var dark := SaRadianceReader.new(_file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true), "dark.hdr").picture()
    assert_eq(SaImageImport.depth_for(dark), SaColorSpace.Depth.F32, "A green of 2 to the -15 names F32 too")
    assert_eq(dark.get_pixel(SUN.x, SUN.y).g, pow(2.0, -15.0), "and keeps it, where a half would hold zero")
    assert_true(_problems.size() == 1 and _problems[0].contains("would round"), "said in a line: %s" % [_problems])


## The exposure line is read, every one of them multiplied, and said when the
## product is not one. The values stay as the file stores them, which is what
## every other program shows of it.
func test_the_exposure_line_is_read_and_said_and_the_values_stay_as_stored() -> void:
    var texels := _encode(_picture())
    texels[SUN.y * SIZE.x + SUN.x] = PackedByteArray([250, 250, 250, 140])
    var even := _file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true, ["EXPOSURE=2", "EXPOSURE=0.5"])
    var reader := SaRadianceReader.new(even, "even.hdr")
    var image := reader.picture()
    assert_eq(reader.exposure, 1.0, "Two lines are multiplied, two by a half")
    assert_true(_problems.is_empty(), "and a product of one says nothing: %s" % [_problems])

    var brighter := SaRadianceReader.new(_file_bytes(texels, "32-bit_rle_rgbe", "-Y +X", true, ["EXPOSURE=4"]), "brighter.hdr")
    image = brighter.picture()
    assert_eq(brighter.exposure, 4.0, "An exposure of four is read")
    var wrong := _mismatches(image, texels)
    assert_true(wrong.is_empty(), "and every value is the file's, not divided by it: %s" % [wrong])
    assert_true(_problems.size() == 1 and _problems[0].contains("exposure of 4"), "said in a line: %s" % [_problems])


## A flat line may carry the older form's repeat, `1 1 1 n`, the texel before
## it n times over, and two in a row count in eight bits more, as Radiance's own
## reader takes them.
func test_the_older_repeat_in_a_flat_line() -> void:
    var head := "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 1 +X 300\n".to_ascii_buffer()
    var bytes := head.duplicate()
    bytes.append_array(PackedByteArray([128, 64, 32, 129, 250, 250, 250, 140]))
    # 1 then 1 << 8: 257 copies of the 4,000 texel, which with the two before
    # it is 259, and forty-one plain texels make the 300.
    bytes.append_array(PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1]))
    for _texel in 41:
        bytes.append_array(PackedByteArray([128, 128, 128, 128]))
    var image := SaRadianceReader.new(bytes, "older.hdr").picture()
    assert_not_null(image, "The file is read")
    if image == null:
        return
    assert_eq(image.get_pixel(0, 0), Color(1.0, 0.5, 0.25, 1.0), "The first texel is its own")
    for x: int in [1, 2, 130, 258]:
        assert_eq(image.get_pixel(x, 0).r, 4000.0, "Texel %d is the 4,000 repeated" % x)
    assert_eq(image.get_pixel(259, 0).r, 0.5, "and the plain texels follow")


## What the reader does not read, it names, and numbers that do not hold
## together are refused as unreadable, each in one line.
func test_a_layout_it_does_not_read_and_a_broken_file_are_said() -> void:
    var cases := {
        "32-bit_rle_spectral": _file_bytes(_encode(_picture()), "32-bit_rle_spectral", "-Y +X", true),
        "it ends inside a scanline": _file_bytes(_encode(_picture()), "32-bit_rle_rgbe", "-Y +X", true).slice(0, 80),
        "rather than X and Y": "#?RADIANCE\n\n-Y 2 +Z 2\n".to_ascii_buffer(),
        "its header never ends": "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n".to_ascii_buffer(),
    }
    for clause: String in cases:
        _problems.clear()
        assert_null(SaRadianceReader.new(cases[clause], "case.hdr").picture(), "A file whose trouble is '%s' is refused" % clause)
        assert_true(_problems.size() == 1 and _problems[0].contains(clause), "in one line naming it: %s" % [_problems])


## The import reaches the reader for a `.hdr` and for a Radiance file under
## another name, and the layouts Godot's loader refused open.
func test_the_import_reads_through_the_reader() -> void:
    var texels := _encode(_picture())
    var path := _file("test_u6_columns.hdr", _file_bytes(texels, "32-bit_rle_xyze", "-X +Y", true))
    assert_eq(SaImageImport.sniff_format(path), "hdr", "A Radiance file is sniffed as one")
    var image := SaImageImport.read(path)
    assert_not_null(image, "An XYZE file stored in columns from the right opens")
    assert_eq(SaImageImport.depth_for(image), SaColorSpace.Depth.F32, "and names F32")
    assert_eq(SaImageImport.space_for(path).id, SaColorSpace.ID_LINEAR_SRGB, "in linear sRGB")

    var named_wrong := _file("test_u6_sky.png", _file_bytes(texels, "32-bit_rle_rgbe", "+Y -X", true))
    var sky := SaImageImport.read(named_wrong)
    assert_not_null(sky, "A Radiance file called .png is read by its bytes")
    if sky != null:
        var wrong := _mismatches(sky, texels)
        assert_true(wrong.is_empty(), "to the bit: %s" % [wrong])


## The sky panorama opens upright, at full floats, with its sun where
## the file put it and at the value the file stores.
func test_the_fixture_opens_upright_with_its_sun() -> void:
    var image := SaImageImport.read(FIXTURE)
    assert_not_null(image, "The fixture is read")
    if image == null:
        return
    assert_eq(image.get_size(), FIXTURE_SIZE, "at its own size")
    assert_eq(SaImageImport.depth_for(image), SaColorSpace.Depth.F32, "naming F32 for its sun")
    assert_eq(image.get_pixel(FIXTURE_SUN.x, FIXTURE_SUN.y), Color(SUN_STORED, SUN_STORED, SUN_STORED, 1.0), "The sun is 99,840")
    assert_eq(image.get_pixel(FIXTURE_SUN.x + 11, FIXTURE_SUN.y), Color(19968.0, 17920.0, 14976.0, 1.0), "inside its halo")
    var mirrored := image.get_pixel(FIXTURE_SIZE.x - 1 - FIXTURE_SUN.x, FIXTURE_SIZE.y - 1 - FIXTURE_SUN.y)
    assert_true(mirrored.r < 1.0, "and nothing bright lies where a reader taking the file the wrong way up would put it")
    var sky := image.get_pixel(10, 4)
    var ground := image.get_pixel(10, 250)
    assert_true(sky.b > sky.r and sky.b > 0.7, "The top is sky, read %s" % [sky])
    assert_true(ground.r > ground.b and ground.r < 0.1, "and the bottom is ground, read %s" % [ground])
    assert_true(_problems.size() == 1 and _problems[0].contains("99,840"), "said in a line: %s" % [_problems])


## The picture the cases encode: a sky over a ground with runs along each row,
## black texels, values under one and over it, and the 100,000.
func _picture() -> Array[Color]:
    var out: Array[Color] = []
    for y in SIZE.y:
        for x in SIZE.x:
            var value := Color(0.25 + 0.0625 * y, 0.5, 0.75 + x * 0.125)
            if y == 6:
                value = Color(3.0, 3.0, 3.0)
            elif y == 8 and x < 5:
                value = Color(0.0, 0.0, 0.0)
            elif y == 8:
                value = Color(0.001 * x, 0.02, 12.5 * x)
            out.append(value)
    out[SUN.y * SIZE.x + SUN.x] = Color(SUN_ASKED, SUN_ASKED, SUN_ASKED)
    return out


## Each colour as Ward's `float2rgbe` writes it.
func _encode(picture: Array[Color]) -> Array[PackedByteArray]:
    var out: Array[PackedByteArray] = []
    for colour in picture:
        var brightest := maxf(colour.r, maxf(colour.g, colour.b))
        if brightest < 1e-32:
            out.append(PackedByteArray([0, 0, 0, 0]))
            continue
        # frexp: the brightest is a fraction in [0.5, 1) times two to this.
        var power := floori(log(brightest) / log(2.0)) + 1
        while brightest / pow(2.0, power) >= 1.0:
            power += 1
        while brightest / pow(2.0, power) < 0.5:
            power -= 1
        var scale := 256.0 / pow(2.0, power)
        out.append(PackedByteArray([int(colour.r * scale), int(colour.g * scale), int(colour.b * scale), power + 128]))
    return out


## Channel *channel* of a texel's four bytes as the format defines it.
func _value(bytes: PackedByteArray, channel: int) -> float:
    return 0.0 if bytes[3] == 0 else bytes[channel] * pow(2.0, bytes[3] - EXPONENT_BIAS)


## Every texel of *image* that is not exactly what its bytes say, as text.
func _mismatches(image: Image, texels: Array[PackedByteArray]) -> Array[String]:
    var out: Array[String] = []
    for y in SIZE.y:
        for x in SIZE.x:
            var bytes := texels[y * SIZE.x + x]
            var read := image.get_pixel(x, y)
            var wanted := Color(_value(bytes, 0), _value(bytes, 1), _value(bytes, 2), 1.0)
            if read != wanted:
                out.append("(%d, %d) read %s for %s" % [x, y, read, wanted])
    return out


## A whole Radiance file of *texels*, a row at a time from the top, written in
## *orientation* under the `FORMAT` line *layout*, flat or run-length.
func _file_bytes(
    texels: Array[PackedByteArray], layout: String, orientation: String, run_length: bool, extra: Array = []
) -> PackedByteArray:
    var axes := orientation.split(" ")
    var rows := axes[0].ends_with("Y")
    var y_down := (axes[0] if rows else axes[1]).begins_with("-")
    var x_right := (axes[1] if rows else axes[0]).begins_with("+")
    var header := "#?RADIANCE\nFORMAT=%s\n" % layout
    for line: String in extra:
        header += "%s\n" % line
    header += "\n"
    if rows:
        header += "%s %d %s %d\n" % [axes[0], SIZE.y, axes[1], SIZE.x]
    else:
        header += "%s %d %s %d\n" % [axes[0], SIZE.x, axes[1], SIZE.y]
    var bytes := header.to_ascii_buffer()
    var count := SIZE.y if rows else SIZE.x
    var length := SIZE.x if rows else SIZE.y
    for line in count:
        var scan: Array[PackedByteArray] = []
        for along in length:
            var x := 0
            var y := 0
            if rows:
                y = line if y_down else SIZE.y - 1 - line
                x = along if x_right else SIZE.x - 1 - along
            else:
                x = line if x_right else SIZE.x - 1 - line
                y = along if y_down else SIZE.y - 1 - along
            scan.append(texels[y * SIZE.x + x])
        if run_length:
            bytes.append_array(PackedByteArray([2, 2, length >> 8, length & 0xFF]))
            for channel in 4:
                var plane := PackedByteArray()
                for texel in scan:
                    plane.append(texel[channel])
                bytes.append_array(_runs(plane))
        else:
            for texel in scan:
                bytes.append_array(texel)
    return bytes


## One plane in the run-length form: a run of four or more equal bytes as a count
## over 128 and the byte, and the rest as literals of up to 128.
func _runs(plane: PackedByteArray) -> PackedByteArray:
    var out := PackedByteArray()
    var at := 0
    var literal := PackedByteArray()
    while at < plane.size():
        var run := 1
        while at + run < plane.size() and plane[at + run] == plane[at] and run < 127:
            run += 1
        if run >= 4:
            _flush(out, literal)
            out.append_array(PackedByteArray([128 + run, plane[at]]))
            at += run
            continue
        literal.append(plane[at])
        at += 1
        if literal.size() == 128:
            _flush(out, literal)
    _flush(out, literal)
    return out


func _flush(out: PackedByteArray, literal: PackedByteArray) -> void:
    if literal.is_empty():
        return
    out.append(literal.size())
    out.append_array(literal)
    literal.clear()


func _file(name: String, bytes: PackedByteArray) -> String:
    var path := SaDataRoot.path(name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    _scratch.append(path)
    return path
