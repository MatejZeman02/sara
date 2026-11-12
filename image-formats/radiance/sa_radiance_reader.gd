## A Radiance `.hdr` read into floats, for a file whose first line is `#?RADIANCE`
## or `#?RGBE`.
##
## Sara's own, as `SaTiffReader` is, because Godot's loader keeps less than the
## file holds. It reads into `FORMAT_RGBE9995`, which rounds a texel past 32,768,
## clamps every value past 65,408, and refuses the XYZE layout and every
## orientation but `-Y +X`. Hard rule 5 says nothing clamps.
##
## It reads the header to its blank line (`FORMAT` and `EXPOSURE`), the
## resolution line in any of the eight orientations, then flat or run-length
## scanlines, including the older repeat texel `1 1 1 n`. Any other layout, or
## numbers that do not hold together, is refused in a sentence.
##
## **Every texel exactly as the file says.** Each value is the mantissa times two
## to the exponent less 136, which a single float holds exactly, so a sun at
## 100,000 stays where the file put it.
##
## **F16 when every value fits a half, F32 when one does not.** A half holds
## every value from 2 to the -14 up to 65,504 exactly and takes half the VRAM.
## Below 2 to the -14 Godot's conversion turns a half's subnormals into zero, so
## a value there makes the picture F32, and the reader says why in a line.
##
## **XYZE is turned into sRGB's primaries**, since no document gamut can name
## XYZ. Radiance's XYZ has equal energy as its white, so the matrix adapts it to
## D65 by Bradford first and a white texel stays white. That is a colour
## conversion a half does not keep, so such a picture is F32.
##
## **The exposure is said, not undone.** `EXPOSURE` is a factor already
## multiplied into the values. Sara keeps the values as stored, which is what
## every other program shows, and names the factor in a line when it is not one.
class_name SaRadianceReader
extends RefCounted

## The two first lines a Radiance file may open with, the first being the one
## Radiance itself writes. `SaImageImport.format_of_header` sniffs them.
const MAGICS: Array[String] = ["#?RADIANCE", "#?RGBE"]
## The two pixel layouts of the header's `FORMAT` line, and the one a header with
## no `FORMAT` line is in.
const FORMAT_RGBE: String = "32-bit_rle_rgbe"
const FORMAT_XYZE: String = "32-bit_rle_xyze"
## Two to this less than the exponent byte is what a mantissa of one is worth:
## the format's bias of 128 and the eight bits of the mantissa.
const EXPONENT_BIAS: int = 136
## The lengths a run-length scanline may have. A line outside them is flat, as
## Radiance's own writer makes it.
const RUN_LENGTH_MIN: int = 8
const RUN_LENGTH_MAX: int = 0x7FFF
## A count byte above this is a run of the next byte, the count less this many
## times, and at or below it is that many literal bytes.
const RUN_MARK: int = 128
## The exponents between which every texel's three values are halves exactly:
## at the lowest a mantissa of one is two to the -14, a half's smallest normal
## value, and at the highest a mantissa of 255 is 65,280, under a half's 65,504.
const HALF_EXPONENT_LOW: int = EXPONENT_BIAS - 14
const HALF_EXPONENT_HIGH: int = EXPONENT_BIAS + 8
const HALF_MAX: float = 65504.0
## Radiance's white, equal energy, which its XYZ is relative to.
const WHITE_E := Vector2(1.0 / 3.0, 1.0 / 3.0)

## The picture's width and height, read from the resolution line.
var width := 0
var height := 0
## Whether the values are CIE XYZ rather than RGB.
var xyz := false
## The product of every `EXPOSURE` line, one when there is none.
var exposure := 1.0

var _bytes: PackedByteArray
var _source := ""
## Where the scanlines start.
var _at := 0
## How the scanlines lie: rows when Y is the major axis and columns when X is,
## and which way each axis runs. See [method _orient].
var _rows := true
var _top_first := true
var _left_first := true
## Why [method picture] cannot build the picture, as the whole sentence the
## painter reads, "" while it can.
var _reason := ""
## Whether `_reason` names a layout this reader does not read, rather than
## numbers that do not hold together. A layout's reason is the name the file
## gives it, and the sentence round it is made in [method refusal].
var _declined := false
## Whether every value read so far is one a half holds exactly, and the
## brightest value past a half's reach when one is.
var _halves := true
var _peak := 0.0
## Two to the exponent less the bias, for each exponent byte, so a texel's value
## is one product. Zero for an exponent of zero, which is black whatever its
## mantissas say.
static var _scales := PackedFloat64Array()
## One for each exponent under which a texel's values may be ones a half does
## not keep, outside the two bounds above and not zero.
static var _unsure := PackedByteArray()
## A run of each byte value, as long as the longest run a count byte can say,
## so a run is one slice rather than a loop.
static var _runs: Array[PackedByteArray] = []


## Reads the header and the resolution line of *bytes*, which *source* names.
## Nothing is reported until [method picture] is asked.
func _init(bytes: PackedByteArray, source: String) -> void:
    _bytes = bytes
    _source = source
    _reason = _read_header()


## The Radiance file at *path* as a picture, or null with the reason reported.
static func read(path: String) -> Image:
    return SaRadianceReader.new(FileAccess.get_file_as_bytes(path), path).picture()


## The sentence the painter reads when the file is refused, translated whole
## with the file's name in it. A layout this reader does not read is named by
## the file, and the sentence round that name is made here, so a language can
## order its words. `refusal` is the name the refusal sweep reads as a sentence
## already translated.
func refusal() -> String:
    if _declined:
        return (
            TranslationServer.translate(
                "'%s' is a Radiance file stored as %s. Sara reads only standard HDR files, in RGBE or XYZE."
            )
            % [_source, _reason]
        )
    return _reason


## The picture upright, as `FORMAT_RGBAH` when every value fits a half and
## `FORMAT_RGBAF` when one does not, in linear light with an opaque alpha. Null
## with the reason reported when the file cannot be read.
func picture() -> Image:
    var values := PackedFloat32Array()
    if _reason.is_empty():
        values.resize(width * height * 3)
        _reason = _read_scanlines(values)
    if not _reason.is_empty():
        SaProblems.refuse("SaRadianceReader", self.refusal())
        return null
    if xyz:
        _to_srgb(values)
    var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBF, values.to_byte_array())
    image.convert(Image.FORMAT_RGBAH if _halves else Image.FORMAT_RGBAF)
    _say_depth()
    if not is_equal_approx(exposure, 1.0):
        SaProblems.refuse(
            "SaRadianceReader",
            (
                TranslationServer.translate(
                    "'%s' records an exposure of %s already multiplied into its values, and they are read as stored."
                )
                % [_source, String.num(exposure, 4)]
            )
        )
    return image


## The line that says why a picture is held at 32 bits, and nothing when it is
## held at 16.
func _say_depth() -> void:
    if _halves:
        return
    var line := "'%s' holds values a 16-bit float would round, so it is read at 32 bits a channel."
    if xyz:
        line = "'%s' is stored as CIE XYZ, and its colours in sRGB's primaries are read at 32 bits a channel."
    if _peak > HALF_MAX:
        line = "'%s' holds a value of %s, past the 65,504 a 16-bit float reaches, so it is read at 32 bits a channel."
        SaProblems.refuse("SaRadianceReader", TranslationServer.translate(line) % [_source, _grouped(_peak)])
        return
    SaProblems.refuse("SaRadianceReader", TranslationServer.translate(line) % _source)


## *value* in digits grouped by threes, as the line beside it writes 65,504, and
## in powers of ten past what a painter reads digit by digit.
static func _grouped(value: float) -> String:
    if value >= 1e12:
        return String.num_scientific(value)
    var digits := str(roundi(value))
    var out := ""
    while digits.length() > 3:
        out = "," + digits.right(3) + out
        digits = digits.left(digits.length() - 3)
    return digits + out


## The header and the resolution line, or the refusal they earn. Leaves `_at` at
## the first scanline.
func _read_header() -> String:
    var first := _line().replace("\t", " ")
    if not first.get_slice(" ", 0).strip_edges() in MAGICS:
        return _broken("Could not read '%s' as an image because it does not begin with #?RADIANCE.")
    var layout := FORMAT_RGBE
    while true:
        if _at >= _bytes.size():
            return _broken("Could not read '%s' as an image because its header never ends.")
        var line := _line().strip_edges()
        if line.is_empty():
            break
        if line.begins_with("FORMAT="):
            layout = line.trim_prefix("FORMAT=").strip_edges()
        elif line.begins_with("EXPOSURE="):
            var factor := line.trim_prefix("EXPOSURE=").strip_edges()
            # A factor that is not a positive number says nothing a reader can
            # use, and Radiance's own reader passes it over the same way.
            if factor.is_valid_float() and factor.to_float() > 0.0:
                exposure *= factor.to_float()
    if layout != FORMAT_RGBE and layout != FORMAT_XYZE:
        return _unread(layout)
    xyz = layout == FORMAT_XYZE
    return _orient(_line().strip_edges().split(" ", false))


## The orientation and the size from the resolution line's four words, one of
## Radiance's eight: the major axis first, each with its sign and its count.
##
## Radiance's Y runs up the picture and its X to the right. `-Y H +X W` is the
## standard, rows from the top down and each row from the left. A `+` on Y is
## rows from the bottom up, a `-` on X is each row from the right, and X first is
## columns rather than rows, each running along Y.
func _orient(words: PackedStringArray) -> String:
    if words.size() != 4 or not words[1].is_valid_int() or not words[3].is_valid_int():
        return _broken("Could not read '%s' as an image because its resolution line is not two axes and two sizes.")
    var major := words[0]
    var minor := words[2]
    var axes := major.right(1) + minor.right(1)
    if major.length() != 2 or minor.length() != 2 or not axes in ["YX", "XY"]:
        return _broken(
            "Could not read '%s' as an image because its resolution line names %s and %s rather than X and Y.", [major, minor]
        )
    if not major.left(1) in ["+", "-"] or not minor.left(1) in ["+", "-"]:
        return _broken(
            "Could not read '%s' as an image because its resolution line gives no direction to %s or %s.", [major, minor]
        )
    _rows = axes == "YX"
    var y_word := major if _rows else minor
    var x_word := minor if _rows else major
    _top_first = y_word.begins_with("-")
    _left_first = x_word.begins_with("+")
    height = (words[1] if _rows else words[3]).to_int()
    width = (words[3] if _rows else words[1]).to_int()
    if width <= 0 or height <= 0:
        return _broken("Could not read '%s' as an image because its resolution line gives a size of %s by %s.", [width, height])
    return ""


## Every scanline into *values*, three floats a texel in the picture's own rows,
## or the reason the scanlines do not hold together.
func _read_scanlines(values: PackedFloat32Array) -> String:
    _prepare_tables()
    var length := width if _rows else height
    var count := height if _rows else width
    for line in count:
        # Where the line's first texel lands and how far each next one is.
        var start := 0
        var step := 0
        if _rows:
            var row := line if _top_first else height - 1 - line
            start = row * width + (0 if _left_first else width - 1)
            step = 1 if _left_first else -1
        else:
            var column := line if _left_first else width - 1 - line
            start = (0 if _top_first else (height - 1) * width) + column
            step = width if _top_first else -width
        var reason := (
            _read_run_length(values, length, start, step) if _is_run_length(length) else _read_flat(values, length, start, step)
        )
        if not reason.is_empty():
            return reason
    return ""


## Whether the line at `_at` is the newer run-length form: a length it may have
## and the four bytes `2 2` and the length that open it.
func _is_run_length(length: int) -> bool:
    if length < RUN_LENGTH_MIN or length > RUN_LENGTH_MAX or _at + 4 > _bytes.size():
        return false
    return _bytes[_at] == 2 and _bytes[_at + 1] == 2 and _bytes[_at + 2] & 0x80 == 0


## One run-length line of *length* texels: its four planes of bytes, each in runs
## and literals, then the texels the planes make.
func _read_run_length(values: PackedFloat32Array, length: int, start: int, step: int) -> String:
    var said := (_bytes[_at + 2] << 8) | _bytes[_at + 3]
    if said != length:
        return _broken(
            "Could not read '%s' as an image because a scanline says its length is %s where the picture's lines are %s.",
            [said, length]
        )
    _at += 4
    var planes := PackedByteArray()
    var end := _bytes.size()
    for plane_end: int in [length, length * 2, length * 3, length * 4]:
        while planes.size() < plane_end:
            if _at >= end:
                return _broken("Could not read '%s' as an image because it ends inside a scanline.")
            var code: int = _bytes[_at]
            var run := code > RUN_MARK
            if run:
                code -= RUN_MARK
            if planes.size() + code > plane_end:
                return _broken("Could not read '%s' as an image because a run reaches past its scanline.")
            var taken := 1 if run else code
            if _at + 1 + taken > end:
                return _broken("Could not read '%s' as an image because it ends inside a scanline.")
            if run:
                planes.append_array(_runs[_bytes[_at + 1]].slice(0, code))
            else:
                planes.append_array(_bytes.slice(_at + 1, _at + 1 + code))
            _at += 1 + taken
    # The texel written here rather than through [method _put], and each plane
    # a slice of its own, because a call and three sums a texel cost about a
    # third of the time a sky takes.
    var reds := planes.slice(0, length)
    var greens := planes.slice(length, length * 2)
    var blues := planes.slice(length * 2, length * 3)
    var powers := planes.slice(length * 3)
    var scales := _scales
    var unsure := _unsure
    var to := start * 3
    var stride := step * 3
    for i in length:
        var power: int = powers[i]
        var scale: float = scales[power]
        values[to] = reds[i] * scale
        values[to + 1] = greens[i] * scale
        values[to + 2] = blues[i] * scale
        if unsure[power]:
            _note_half(values[to], values[to + 1], values[to + 2])
        to += stride
    return ""


## One flat line of *length* texels, four bytes each, where a texel `1 1 1 n`
## repeats the one before it n times, and each such texel straight after another
## counts in the next eight bits up, as Radiance's `oldreadcolrs` reads it.
func _read_flat(values: PackedFloat32Array, length: int, start: int, step: int) -> String:
    var i := 0
    var shift := 0
    while i < length:
        if _at + 4 > _bytes.size():
            return _broken("Could not read '%s' as an image because it ends inside a scanline.")
        var red: int = _bytes[_at]
        var green: int = _bytes[_at + 1]
        var blue: int = _bytes[_at + 2]
        var power: int = _bytes[_at + 3]
        _at += 4
        if red == 1 and green == 1 and blue == 1:
            var repeats := power << shift
            if i == 0 or i + repeats > length:
                return _broken(
                    "Could not read '%s' as an image because a repeat has no texel before it or reaches past its scanline."
                )
            var from := (start + (i - 1) * step) * 3
            for _repeat in repeats:
                var to := (start + i * step) * 3
                values[to] = values[from]
                values[to + 1] = values[from + 1]
                values[to + 2] = values[from + 2]
                i += 1
            shift += 8
            continue
        _put(values, (start + i * step) * 3, red, green, blue, power)
        i += 1
        shift = 0
    return ""


## One texel's three values at *to*: each mantissa times two to *power* less the
## bias, which a float holds exactly. Notes whether a half would hold them too.
func _put(values: PackedFloat32Array, to: int, red: int, green: int, blue: int, power: int) -> void:
    var scale := _scales[power]
    values[to] = red * scale
    values[to + 1] = green * scale
    values[to + 2] = blue * scale
    if _unsure[power]:
        _note_half(red * scale, green * scale, blue * scale)


## Whether each of three values is one a half holds exactly, kept in `_halves`,
## and the brightest past a half's reach kept in `_peak`.
func _note_half(red: float, green: float, blue: float) -> void:
    for value: float in [red, green, blue]:
        if value > HALF_MAX:
            _halves = false
            _peak = maxf(_peak, value)
        elif value != 0.0 and not _half_keeps(value):
            _halves = false


## Whether *value*, a non-negative float, comes back from a half as it went in,
## through the conversion Godot makes, which is the one an upload makes.
static func _half_keeps(value: float) -> bool:
    var half := PackedByteArray()
    half.resize(2)
    half.encode_half(0, value)
    return half.decode_half(0) == value


## Every texel of *values* from Radiance's XYZ into linear sRGB, and whether a
## half keeps the result noted as [method _put] notes it.
func _to_srgb(values: PackedFloat32Array) -> void:
    _halves = true
    _peak = 0.0
    var to_rgb := SaColorSpace.linear_srgb().xyz_to_rgb() * SaColorSpace.adaptation(WHITE_E, SaColorSpace.WHITE_D65)
    for at in range(0, values.size(), 3):
        var rgb := to_rgb * Vector3(values[at], values[at + 1], values[at + 2])
        values[at] = rgb.x
        values[at + 1] = rgb.y
        values[at + 2] = rgb.z
        if _halves and not (_half_keeps(values[at]) and _half_keeps(values[at + 1]) and _half_keeps(values[at + 2])):
            _halves = false
        if rgb.x > HALF_MAX or rgb.y > HALF_MAX or rgb.z > HALF_MAX:
            _peak = maxf(_peak, maxf(rgb.x, maxf(rgb.y, rgb.z)))


## The next line of the header as text, without its line end, leaving `_at` past
## it. The header is ASCII by the format's own definition.
func _line() -> String:
    var end := _bytes.find(10, _at)
    if end < 0:
        end = _bytes.size()
    var text := _bytes.slice(_at, end).get_string_from_ascii()
    _at = end + 1
    return text


## The two tables every texel is read through, built once.
static func _prepare_tables() -> void:
    if not _scales.is_empty():
        return
    _scales.resize(256)
    _unsure.resize(256)
    for power in 256:
        _scales[power] = 0.0 if power == 0 else pow(2.0, power - EXPONENT_BIAS)
        _unsure[power] = 1 if power != 0 and (power < HALF_EXPONENT_LOW or power > HALF_EXPONENT_HIGH) else 0
    for value in 256:
        var run := PackedByteArray()
        run.resize(RUN_MARK - 1)
        run.fill(value)
        _runs.append(run)


## *clause*, naming a layout this reader does not read, marked as that kind of
## reason.
func _unread(clause: String) -> String:
    _declined = true
    return clause


## The sentence for *message*, saying why a file's own numbers do not hold
## together, marked as that kind. The message is translated whole, the file's
## name its first value and *values* the rest, so a language that wants the
## reason first can put it there.
func _broken(message: String, values: Array = []) -> String:
    _declined = false
    return tr(message) % ([_source] + values)
