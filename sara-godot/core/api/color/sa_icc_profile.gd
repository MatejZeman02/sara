## A monitor's ICC profile read as the colour space its panel shows, from its
## colorant and white point tags.
##
## Sara's window is untagged, since Godot does not speak
## `wp_color_management_v1`, and in its default colour mode mutter hands an
## untagged window's numbers to the panel without converting them, loading only
## the profile's `vcgt` curves into the gamma table. So the conversion into the
## panel's own primaries is Sara's, and this is what it needs of the profile: the
## three primaries and the white, which make an `SaColorSpace` the display chain
## already knows how to finish into.
##
## The same reading serves a profile a picture carries, `SaEmbeddedProfile`'s,
## where the tone curve matters as much as the primaries: Adobe RGB's is a gamma
## of 563/256 and ProPhoto's one of 1.8, and reading either through sRGB's curve
## shifts every mid tone. So the curve is read too, by [ToneCurve]. The display
## chain asks a monitor profile for its gamut alone, and the curve it now carries
## changes nothing there.
##
## **A matrix and tone curve profile only**, version 2 or 4. A profile with no
## colorant tags is a lookup table one, and it is refused with the reason rather
## than read approximately, which keeps littlecms out of the tree. So is one whose
## parametric curve no Sara curve stands for, see [ToneCurve], while a curve
## table is read as the table, see [TableCurve].
@tool
class_name SaIccProfile
extends RefCounted

## The profile connection space's white, D50, as the ICC specification fixes it.
const PCS_WHITE := Vector3(0.9642, 1.0, 0.8249)

## What the header carries before the tag table, and where the table starts.
const HEADER_SIZE := 128

## The profile's name, from its `desc` tag, or the file's name when it has none.
var name: String = ""

## The panel or the picture as a colour space, with `ID_CUSTOM` and the curve
## [ToneCurve] read, or null when the profile could not be read.
var space: SaColorSpace = null

## Why [member space] is null, in a sentence for the painter, or empty.
var problem: String = ""


## The profile at *path*, read or refused.
static func read(path: String) -> SaIccProfile:
    if path.is_empty():
        return _refused("", "No monitor profile file is chosen.")
    if not FileAccess.file_exists(path):
        return _refused(path.get_file(), "The monitor profile %s is not there." % path)
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return _refused(path.get_file(), "The monitor profile %s could not be read." % path)
    var profile := parse(bytes)
    if profile.name.is_empty():
        profile.name = path.get_file()
    return profile


## The profile whose bytes are *bytes*, read or refused.
static func parse(bytes: PackedByteArray) -> SaIccProfile:
    if bytes.size() < HEADER_SIZE + 4 or _tag_sig(bytes, 36) != "acsp":
        return _refused("", "The file is not an ICC profile.")
    var version := bytes[8]
    if version != 2 and version != 4:
        return _refused("", "The profile is ICC version %d, and Sara reads versions 2 and 4." % version)
    if _tag_sig(bytes, 16) != "RGB ":
        return _refused("", "The profile does not describe an RGB device.")
    var tags := _tag_table(bytes)
    var profile := SaIccProfile.new()
    profile.name = _description(bytes, tags)
    for colorant: String in ["rXYZ", "gXYZ", "bXYZ"]:
        if not tags.has(colorant):
            var held := "it is a lookup table profile, which Sara does not read" if tags.has("A2B0") else "it holds no primaries"
            profile.problem = "The profile has no %s tag, so %s." % [colorant, held]
            return profile
    var red := _xyz(bytes, tags["rXYZ"])
    var green := _xyz(bytes, tags["gXYZ"])
    var blue := _xyz(bytes, tags["bXYZ"])
    var to_pcs := _adaptation_to_pcs(bytes, tags)
    if is_zero_approx(to_pcs.determinant()):
        profile.problem = "The profile's chromatic adaptation cannot be undone."
        return profile
    var from_pcs := to_pcs.inverse()
    var primaries := PackedVector2Array()
    for colorant: Vector3 in [red, green, blue]:
        var native := from_pcs * colorant
        if native.x + native.y + native.z <= 0.0:
            profile.problem = "The profile's colorants hold no light."
            return profile
        primaries.append(_xy(native))
    var white := _xy(from_pcs * (red + green + blue))
    var curve := ToneCurve.new(bytes, tags)
    if curve.function == null:
        profile.problem = curve.problem
        return profile
    profile.space = SaColorSpace.create(SaColorSpace.ID_CUSTOM, primaries, white, curve.function)
    return profile


## The matrix taking the panel's own XYZ to the PCS's, from the `chad` tag.
##
## A version 2 profile often has none, and then its white point tag is the
## panel's white and the colorants were adapted from it to D50, so the same
## Bradford step the rest of Sara uses stands for the missing tag. A white point
## of D50 itself, a version 4 profile without `chad`, gives the identity.
static func _adaptation_to_pcs(bytes: PackedByteArray, tags: Dictionary[String, Vector2i]) -> Basis:
    if tags.has("chad"):
        var at := tags["chad"].x
        var rows: Array[Vector3] = []
        for row in 3:
            var start := at + 8 + row * 12
            rows.append(Vector3(_s15(bytes, start), _s15(bytes, start + 4), _s15(bytes, start + 8)))
        return Basis(
            Vector3(rows[0].x, rows[1].x, rows[2].x),
            Vector3(rows[0].y, rows[1].y, rows[2].y),
            Vector3(rows[0].z, rows[1].z, rows[2].z)
        )
    if not tags.has("wtpt"):
        return Basis.IDENTITY
    var media := _xyz(bytes, tags["wtpt"])
    if media.is_equal_approx(PCS_WHITE):
        return Basis.IDENTITY
    return SaColorSpace.adaptation(_xy(media), _xy(PCS_WHITE))


## Signature to its offset and size, for the tags that fit inside the file.
static func _tag_table(bytes: PackedByteArray) -> Dictionary[String, Vector2i]:
    var tags: Dictionary[String, Vector2i] = {}
    var count := _u32(bytes, HEADER_SIZE)
    for i in mini(count, floori((bytes.size() - HEADER_SIZE - 4) / 12.0)):
        var entry := HEADER_SIZE + 4 + i * 12
        var offset := _u32(bytes, entry + 4)
        var size := _u32(bytes, entry + 8)
        if offset + size <= bytes.size() and size >= 8:
            tags[_tag_sig(bytes, entry)] = Vector2i(offset, size)
    return tags


## The `desc` tag's text, a version 2 `desc` type or a version 4 `mluc`, or empty.
static func _description(bytes: PackedByteArray, tags: Dictionary[String, Vector2i]) -> String:
    if not tags.has("desc"):
        return ""
    var at := tags["desc"].x
    var size := tags["desc"].y
    match _tag_sig(bytes, at):
        "desc":
            var count := _u32(bytes, at + 8)
            var text := bytes.slice(at + 12, mini(at + 12 + count, at + size))
            return text.get_string_from_ascii().strip_edges()
        "mluc":
            if _u32(bytes, at + 8) == 0:
                return ""
            # The first record, which is the profile's own language, since
            # Sara has no way to say which of several it would rather have.
            var length := _u32(bytes, at + 20)
            var start := at + _u32(bytes, at + 24)
            if start + length > at + size:
                return ""
            var units := PackedByteArray()
            for i in range(0, length - 1, 2):
                units.append(bytes[start + i + 1])
                units.append(bytes[start + i])
            return units.get_string_from_utf16().strip_edges()
    return ""


static func _refused(file_name: String, reason: String) -> SaIccProfile:
    var profile := SaIccProfile.new()
    profile.name = file_name
    profile.problem = reason
    return profile


## The three numbers of an `XYZ ` type tag.
static func _xyz(bytes: PackedByteArray, tag: Vector2i) -> Vector3:
    var at := tag.x
    return Vector3(_s15(bytes, at + 8), _s15(bytes, at + 12), _s15(bytes, at + 16))


static func _xy(xyz: Vector3) -> Vector2:
    var total := xyz.x + xyz.y + xyz.z
    return Vector2(xyz.x / total, xyz.y / total) if total > 0.0 else Vector2.ZERO


static func _tag_sig(bytes: PackedByteArray, at: int) -> String:
    return bytes.slice(at, at + 4).get_string_from_ascii()


## A big-endian unsigned 32-bit number. `PackedByteArray`'s own decoders read
## little-endian, so the bytes are put together by hand.
static func _u32(bytes: PackedByteArray, at: int) -> int:
    if at + 4 > bytes.size():
        return 0
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## A big-endian unsigned 16-bit number.
static func _u16(bytes: PackedByteArray, at: int) -> int:
    if at + 2 > bytes.size():
        return 0
    return (bytes[at] << 8) | bytes[at + 1]


## A big-endian s15Fixed16 number.
static func _s15(bytes: PackedByteArray, at: int) -> float:
    var raw := _u32(bytes, at)
    if raw >= 0x80000000:
        raw -= 0x100000000
    return raw / 65536.0


## The profile's tone curve as one of Sara's transfer functions, from its
## `rTRC`, `gTRC` and `bTRC` tags, or the reason none stands for it.
##
## Three kinds of tag. A `curv` of one entry is a pure gamma and a `para` is
## ICC's parametric curve, and both are taken as the numbers say, since Sara's
## four-number curve holds a gamma and the sRGB-shaped `para` of type 3 exactly.
## A `curv` table is sampled and stands as the nearest of Sara's curves, a
## preset or the pure gamma that meets it at a half, when that one is within
## [constant TABLE_BOUND] everywhere, and is read as the table itself, a
## [TableCurve], otherwise. A table that falls anywhere is refused, since a
## colour cannot be taken back through it. The bound still refuses a `para`
## curve no Sara curve stands for, which claims a shape and is held to it.
## A curve that is a preset written in fixed point, a version 4 profile's `para`
## of sRGB's numbers above all, is taken as the preset, so the picture opens on
## sRGB's curve rather than on a custom one a hair from it.
##
## Sara's colour space has one curve, so three curves that differ by more than
## the bound are refused too. A profile with no curve tags at all is taken on
## sRGB's, the curve a monitor profile was read with before curves were read.
class ToneCurve:
    ## The largest difference in linear light, across the curve, a `curv` table
    ## may stand from the Sara curve that takes its place: under half an 8-bit
    ## code value at the top, where a code value is widest in linear light.
    const TABLE_BOUND := 0.002
    ## The largest difference a curve may stand from a preset and still be that
    ## preset written in s15Fixed16. Adobe RGB's 563/256 stands 0.00013 from a
    ## gamma of 2.2, so it stays its own curve.
    const FIXED_POINT_BOUND := 5e-5
    ## Where the curves are compared, evenly over 0 to 1.
    const SAMPLES := 256

    ## The curve, or null when the profile's is not one Sara has.
    var function: SaTransferFunction = null
    ## Why [member function] is null, in a sentence, or empty.
    var problem: String = ""

    func _init(bytes: PackedByteArray, tags: Dictionary[String, Vector2i]) -> void:
        if not (tags.has("rTRC") or tags.has("gTRC") or tags.has("bTRC")):
            function = SaTransferFunction.srgb()
            return
        var read: Array[Dictionary] = []
        for signature: String in ["rTRC", "gTRC", "bTRC"]:
            if not tags.has(signature):
                problem = "The profile has no %s tag." % signature
                return
            var one := _read(bytes, tags[signature])
            if one.has("problem"):
                problem = one["problem"]
                return
            read.append(one)
        var samples: PackedFloat32Array = read[0]["samples"]
        for other: Dictionary in read.slice(1):
            var theirs: PackedFloat32Array = other["samples"]
            if _distance(samples, theirs) > TABLE_BOUND:
                problem = "The profile's red, green and blue tone curves differ, and a colour space in Sara has one curve."
                return
        var nearest := _nearest(samples)
        if nearest[1] <= FIXED_POINT_BOUND:
            function = nearest[0]
            return
        var exact: SaTransferFunction = read[0].get("exact")
        if exact != null and _distance(samples, _sampled(exact)) <= FIXED_POINT_BOUND:
            function = exact
            return
        var fitted := _fitted_gamma(samples)
        if fitted != null and _distance(samples, _sampled(fitted)) < nearest[1]:
            nearest = [fitted, _distance(samples, _sampled(fitted))]
        if nearest[1] <= TABLE_BOUND:
            function = nearest[0]
            return
        if read[0].has("table") and fitted != null:
            var table: PackedFloat32Array = read[0]["table"]
            function = TableCurve.new(table, fitted.exponent)
            return
        var shown: SaTransferFunction = nearest[0]
        problem = (
            "The profile's tone curve stands %.4f in linear light from the nearest curve Sara has, %s, and Sara allows %.4f."
            % [nearest[1], shown.display_name, TABLE_BOUND]
        )

    ## One curve tag as `samples`, the linear light at each of [constant SAMPLES]
    ## points, and `exact`, Sara's curve of its numbers where it has one, or as
    ## `problem`.
    static func _read(bytes: PackedByteArray, tag: Vector2i) -> Dictionary:
        var at := tag.x
        match SaIccProfile._tag_sig(bytes, at):
            "curv":
                var count := SaIccProfile._u32(bytes, at + 8)
                if count == 0:
                    return {"samples": _sampled(SaTransferFunction.linear()), "exact": SaTransferFunction.linear()}
                if count == 1:
                    var g := SaIccProfile._u16(bytes, at + 12) / 256.0
                    if g <= 0.0:
                        return {"problem": "The profile's tone curve is a gamma of nought."}
                    var power := SaTransferFunction.gamma(g)
                    return {"samples": _sampled(power), "exact": power}
                if at + 12 + count * 2 > at + tag.y:
                    return {"problem": "The profile's tone curve table runs past its tag."}
                var table := PackedFloat32Array()
                for i in count:
                    table.append(SaIccProfile._u16(bytes, at + 12 + i * 2) / 65535.0)
                for i in count - 1:
                    if table[i + 1] < table[i]:
                        var falls := "The profile's tone curve table falls between entries %d and %d" % [i, i + 1]
                        return {"problem": falls + ", so no colour can be taken back through it."}
                if table[count - 1] <= table[0]:
                    return {"problem": "The profile's tone curve table does not rise."}
                return {"samples": _table_samples(table), "table": table}
            "para":
                return _parametric(bytes, at, tag.y)
        return {"problem": "The profile's tone curve is of a type Sara does not read."}

    ## A `para` tag: its samples, and Sara's curve of its numbers for the types
    ## of the sRGB shape, a power above a straight segment through nought.
    static func _parametric(bytes: PackedByteArray, at: int, size: int) -> Dictionary:
        var kind := SaIccProfile._u16(bytes, at + 8)
        var counts: Array[int] = [1, 3, 4, 5, 7]
        if kind >= counts.size() or 12 + counts[kind] * 4 > size:
            return {"problem": "The profile's parametric tone curve is of a type Sara does not read."}
        var p := PackedFloat32Array([1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        for i in counts[kind]:
            p[i] = SaIccProfile._s15(bytes, at + 12 + i * 4)
        var g := p[0]
        var a := p[1]
        var b := p[2]
        var c := p[3]
        var d := p[4]
        var e := p[5]
        var f := p[6]
        if kind == 1:
            d = -b / a if not is_zero_approx(a) else 0.0
        elif kind == 2:
            d = -b / a if not is_zero_approx(a) else 0.0
            f = c
            e = c
            c = 0.0
        var samples := PackedFloat32Array()
        for i in SAMPLES:
            var x := i / float(SAMPLES - 1)
            var y := c * x + f if x < d else pow(maxf(a * x + b, 0.0), g) + e
            samples.append(y)
        var found := {"samples": samples}
        if kind == 0:
            found["exact"] = SaTransferFunction.gamma(g)
        elif a > 0.0 and g > 0.0 and is_zero_approx(e) and is_zero_approx(f) and (d <= 0.0 or c > 0.0):
            var slope := 1.0 / c if d > 0.0 else 1.0
            var curve := SaTransferFunction.from_params(&"profile", [slope, maxf(d, 0.0), 1.0 / a, g])
            if curve != null:
                curve.display_name = "Profile curve"
                found["exact"] = curve
        return found

    ## The preset nearest *samples*, and how far it stands.
    static func _nearest(samples: PackedFloat32Array) -> Array:
        var best: SaTransferFunction = null
        var distance := INF
        for preset: SaTransferFunction in SaTransferFunction.presets():
            var apart := _distance(samples, _sampled(preset))
            if apart < distance:
                best = preset
                distance = apart
        return [best, distance]

    ## The pure gamma whose half is the curve's half, or null for a curve that
    ## does not pass between nought and one there.
    static func _fitted_gamma(samples: PackedFloat32Array) -> SaTransferFunction:
        var half := SAMPLES >> 1
        var x := half / float(SAMPLES - 1)
        var y := samples[half]
        if y <= 0.0 or y >= 1.0:
            return null
        return SaTransferFunction.gamma(log(y) / log(x))

    static func _sampled(curve: SaTransferFunction) -> PackedFloat32Array:
        var samples := PackedFloat32Array()
        for i in SAMPLES:
            samples.append(curve.decode(i / float(SAMPLES - 1)))
        return samples

    ## A table of any length read at [constant SAMPLES] points, between its
    ## entries in a straight line, as the specification reads one.
    static func _table_samples(table: PackedFloat32Array) -> PackedFloat32Array:
        var samples := PackedFloat32Array()
        var last := table.size() - 1
        for i in SAMPLES:
            var position := i / float(SAMPLES - 1) * last
            var below := mini(floori(position), last - 1)
            samples.append(lerpf(table[below], table[below + 1], position - below))
        return samples

    static func _distance(one: PackedFloat32Array, other: PackedFloat32Array) -> float:
        var largest := 0.0
        for i in one.size():
            largest = maxf(largest, absf(one[i] - other[i]))
        return largest


## A `curv` table no Sara curve meets, applied as the table says: a lookup with
## a straight line between entries for decode, and the same line read backwards
## for encode.
##
## A calibration writes this kind of curve, Windows' own `CalibratedDisplayProfile`
## above all, with 256 entries a few thousandths of linear light from any power
## curve, and the profile is the one the panel really has. Refusing it left the
## display on sRGB, which is further off than the table is from anything.
##
## A kernel takes a curve as four numbers, so the numbers this curve holds are
## the pure gamma that meets the table at its half, and a dispatch that reads
## them gets that gamma, a few thousandths away. The display chain asks a monitor
## profile for its gamut alone, so the panel's view is untouched by the gap, and
## a document saved in this space reopens on the gamma, which is what its
## kernels painted with. Past either end the gamma carries on from the table's
## last entry, since Sara keeps values over one and nothing clamps.
class TableCurve:
    extends SaTransferFunction

    ## The table's entries, in linear light, rising from the first to the last.
    var table: PackedFloat32Array

    func _init(entries: PackedFloat32Array, fitted_exponent: float) -> void:
        table = entries
        id = SaTransferFunction.ID_GAMMA
        display_name = "Profile table"
        slope = 1.0
        threshold = 0.0
        gain = 1.0
        exponent = clampf(fitted_exponent, SaTransferFunction.MIN_GAMMA, SaTransferFunction.MAX_GAMMA)

    func is_identity() -> bool:
        return false

    func decode(value: float) -> float:
        var m := absf(value)
        var last := table.size() - 1
        if m >= 1.0:
            return signf(value) * table[last] * pow(m, exponent)
        var position := m * last
        var below := mini(floori(position), last - 1)
        return signf(value) * lerpf(table[below], table[below + 1], position - below)

    func encode(value: float) -> float:
        var m := absf(value)
        var last := table.size() - 1
        if m >= table[last]:
            return signf(value) * pow(m / table[last], 1.0 / exponent)
        # The first entry at or above the value, by halves, since the table rises.
        var low := 0
        var high := last
        while high - low > 1:
            var middle := (low + high) >> 1
            if table[middle] < m:
                low = middle
            else:
                high = middle
        var step := table[high] - table[low]
        var along := (m - table[low]) / step if step > 0.0 else 0.0
        return signf(value) * (low + along) / last

    func matches(other: SaTransferFunction) -> bool:
        var same_table := other is TableCurve and (other as TableCurve).table == table
        return same_table and super.matches(other)
