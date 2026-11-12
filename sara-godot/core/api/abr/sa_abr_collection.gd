## Reads Photoshop's `.abr`, a brush collection, as a list of tips.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Written from the format, not ported.** Adobe never published the `.abr`
## layout, so what is known of it is what the two open readers record, GIMP's
## `gimpbrush-load.c` and Krita's `kis_abr_brush_collection.cpp`, and the spec's
## Provenance table keeps Krita's row as the record of that. No line of either
## is taken: the layout below is a list of fields, and the reader is a walk over
## them with every length checked against the file it came out of.
##
## **Two layouts under one extension.**
##
## - Versions 1 and 2, Photoshop 6 and older: a big-endian version and a count,
##   then one entry per brush, each a type, a length and that many bytes. Type 1
##   is a computed brush, a shape drawn from a diameter, a roundness and a
##   hardness, and type 2 is a sampled one, a picture. Version 2 adds a name to
##   the picture, UTF-16 behind a count of code units.
## - Versions 6, 7 and 10, Photoshop 7 and later: a version and a subversion,
##   1 or 2, then sections, each `8BIM`, a four-letter tag and a length. `samp`
##   holds the pictures, each behind a key, and `desc` is a Photoshop action
##   descriptor listing the presets in the order Photoshop shows them, each
##   with its name, its spacing and either the key of its picture or the
##   numbers of a computed brush.
##
## **A picture is either raw or packed.** Raw is `width * height` texels of 8 or
## 16 bits, big-endian. Packed is PackBits per row: a table of each row's
## packed length, then the rows, which is the run-length scheme every Adobe
## format of the period uses. A texel is coverage, 255 a fully covered one,
## which is the reading a depth-1 GBR gets and the one both open readers give.
##
## **What is listed.** Every brush the file holds, in its order, as a
## [SaTipImage.Tip]: a picture as a tip that loaded, and a computed brush, or a
## picture this reader cannot take, as a tip whose `error` says why with its
## name kept, so a chooser can show the cell and the reason. **What refuses the
## whole file** is a file cut short, a version this reader does not know, and a
## section header that is not one, because past any of those no offset in the
## file can be believed.
##
## **The descriptor costs names and nothing else.** A version 6 file whose
## `desc` this reader cannot walk still lists its pictures, in the `samp`
## section's order and named after the file and its place, which is the name
## the open readers give every such picture. The pictures are what a painter loads, the names are what
## they read, and losing the second over a field this walk does not know would
## be refusing a file that paints.
class_name SaAbrCollection
extends RefCounted

## The versions read, by layout. Photoshop has written no others: 6 from
## Photoshop 7, 7 and 10 from later releases with the same sections, and a
## version outside these is refused by name rather than guessed at.
const OLD_VERSIONS: Array[int] = [1, 2]
const SECTION_VERSIONS: Array[int] = [6, 7, 10]

## The subversions a sectioned file may carry, which decide how far into a
## picture's entry its bounds start.
const SUBVERSIONS: Array[int] = [1, 2]

## Where a picture's bounds start in its `samp` entry, by subversion. Both
## begin with the picture's key, a Pascal string of thirty-seven bytes, and then
## carry ten and two hundred and sixty-four bytes nobody has documented.
## Fixed offsets rather than a walk past the key, because the bytes after it are
## not known well enough to walk.
const BOUNDS_AT: Dictionary[int, int] = {1: 47, 2: 301}

## The two brush types a version 1 or 2 entry names.
const COMPUTED: int = 1
const SAMPLED: int = 2

## The largest side a picture is believed at. Photoshop's own ceiling is 5000,
## and past 16384 the old format stores a picture in strips this reader does
## not take, which is where GIMP stops too. Refused rather than clamped, for the
## reason `sa_tip_image.gd` refuses an impossible spacing.
const MAX_SIDE: int = 16384

## The bit depths a texel may have.
const DEPTHS: Array[int] = [8, 16]

## The largest spacing, as a percentage, believed in a file. The old format's
## field is two bytes and a descriptor's is a double, and neither states a
## ceiling: past ten times the tip a stroke is separate stamps, so a bigger
## number is a misread rather than a spacing, and it falls to
## [constant SaTipImage.SPACING_WHEN_UNSTATED].
const MAX_SPACING_PERCENT: float = 1000.0

## The file's own name, which every refusal and every name made up for a
## picture the file left unnamed quotes.
var file_name: String = ""

## The version as the file states it, and the subversion when it has one.
var version: int = 0
var subversion: int = 0

## Every brush the file holds, in its order. A tip whose `error` is set is
## listed and not loadable.
var tips: Array[SaTipImage.Tip] = []

## Why the file was not read. Empty when [member tips] is the whole of it.
var error: String = ""


func _init(name: String) -> void:
    file_name = name


func ok() -> bool:
    return error.is_empty()


## The tips that loaded, which is what a stroke can be given.
func pictures() -> Array[SaTipImage.Tip]:
    var out: Array[SaTipImage.Tip] = []
    for tip in tips:
        if tip.ok():
            out.append(tip)
    return out


## Reads the collection at *path*.
static func load_from(path: String) -> SaAbrCollection:
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        var out := SaAbrCollection.new(path.get_file())
        out.error = "%s could not be read." % path.get_file()
        return out
    return read(bytes, path.get_file())


## Reads a collection out of *bytes*, naming it *name* in what it says.
static func read(bytes: PackedByteArray, name: String) -> SaAbrCollection:
    var out := SaAbrCollection.new(name)
    out._read(bytes)
    return out


func _read(bytes: PackedByteArray) -> void:
    if bytes.size() < 4:
        error = "%s is %d bytes, too short to be a brush collection." % [file_name, bytes.size()]
        return
    var head := Bytes.new(bytes, 0, bytes.size())
    version = head.u16()
    var second := head.u16()
    if version in OLD_VERSIONS:
        _read_entries(bytes, second)
        return
    if not version in SECTION_VERSIONS:
        error = "%s is ABR version %d, and Sara reads versions 1, 2, 6, 7 and 10." % [file_name, version]
        return
    subversion = second
    if not subversion in SUBVERSIONS:
        error = "%s is ABR version %d with subversion %d, and Sara reads subversions 1 and 2." % [file_name, version, subversion]
        return
    _read_sections(bytes)


## Versions 1 and 2: *count* entries, each a type, a length and its bytes.
func _read_entries(bytes: PackedByteArray, count: int) -> void:
    var at := 4
    for index in count:
        if at + 6 > bytes.size():
            _cut_short("brush %d" % (index + 1), at + 6, bytes.size())
            return
        var entry := Bytes.new(bytes, at, bytes.size())
        var kind := entry.u16()
        var length := entry.u32()
        var ends := at + 6 + length
        if ends > bytes.size():
            _cut_short("brush %d" % (index + 1), ends, bytes.size())
            return
        tips.append(_entry(Bytes.new(bytes, at + 6, ends), kind, index + 1))
        at = ends


## One version 1 or 2 entry, read inside its own length.
func _entry(entry: Bytes, kind: int, number: int) -> SaTipImage.Tip:
    var name := _made_up_name(number)
    if kind == COMPUTED:
        return _computed(name)
    if kind != SAMPLED:
        return _refused(name, "%s is a brush of type %d, which is neither a picture nor a computed brush." % [name, kind])
    entry.skip(4)
    var spacing := _spacing(float(entry.u16()))
    if version == 2:
        var written := entry.utf16()
        if not written.is_empty():
            name = written
    # The antialiasing flag and the bounds in two bytes a side, which the four
    # byte bounds after them repeat.
    entry.skip(9)
    var top := entry.s32()
    var left := entry.s32()
    var bottom := entry.s32()
    var right := entry.s32()
    var depth := entry.u16()
    var packed := entry.u8() != 0
    if entry.overrun:
        return _refused(name, "%s stops before its picture starts." % name)
    return _picture(entry, name, Vector2i(right - left, bottom - top), depth, packed, spacing)


## Versions 6 and later: sections, of which `samp` holds the pictures and
## `desc` their names.
func _read_sections(bytes: PackedByteArray) -> void:
    var at := 4
    var samples: Dictionary[String, SaTipImage.Tip] = {}
    var keys: PackedStringArray = PackedStringArray()
    var presets: Array[Descriptor.Preset] = []
    var read_pictures := false
    while at < bytes.size():
        if at + 12 > bytes.size():
            if read_pictures:
                break
            _cut_short("section header at byte %d" % at, at + 12, bytes.size())
            return
        var head := Bytes.new(bytes, at, bytes.size())
        var signature := head.ascii(4)
        var tag := head.ascii(4)
        var length := head.u32()
        var ends := at + 12 + length
        if signature != "8BIM":
            # Past the pictures, a section that is not one costs the names at
            # most, for the reason the class says a descriptor does.
            if read_pictures:
                break
            error = "%s has no section where one should start, at byte %d." % [file_name, at]
            return
        if ends > bytes.size():
            if read_pictures:
                break
            _cut_short("%s section" % tag, ends, bytes.size())
            return
        if tag == "samp" and not read_pictures:
            if not _read_samples(bytes, at + 12, ends, samples, keys):
                return
            read_pictures = true
        elif tag == "desc":
            presets = Descriptor.presets(Bytes.new(bytes, at + 12, ends))
        at = ends
    _list(samples, keys, presets)


## The `samp` section, between *from* and *to*, into *samples* by key, with
## *keys* in the order the section holds them. False when the file refused.
func _read_samples(
    bytes: PackedByteArray,
    from: int,
    to: int,
    samples: Dictionary[String, SaTipImage.Tip],
    keys: PackedStringArray,
) -> bool:
    var at := from
    while at + 4 <= to:
        var length := Bytes.new(bytes, at, to).u32()
        var starts := at + 4
        var ends := starts + length
        var number := keys.size() + 1
        if ends > bytes.size():
            _cut_short("picture %d" % number, ends, bytes.size())
            return false
        if ends > to:
            error = (
                "%s has picture %d running to byte %d, past the end of its section at byte %d." % [file_name, number, ends, to]
            )
            return false
        var entry := Bytes.new(bytes, starts, ends)
        var key := entry.pascal()
        if key.is_empty() or samples.has(key):
            key = "#%d" % number
        entry = Bytes.new(bytes, starts + BOUNDS_AT[subversion], ends)
        var top := entry.s32()
        var left := entry.s32()
        var bottom := entry.s32()
        var right := entry.s32()
        var depth := entry.u16()
        var packed := entry.u8() != 0
        var name := _made_up_name(number)
        if entry.overrun:
            samples[key] = _refused(name, "%s stops before its picture starts." % name)
        else:
            samples[key] = _picture(entry, name, Vector2i(right - left, bottom - top), depth, packed, _spacing(0.0))
        keys.append(key)
        # Each entry is padded to a whole four bytes, and the length leaves the
        # padding out.
        at = starts + ((length + 3) & ~3)
    return true


## The listing of a sectioned file: the presets in the descriptor's order,
## then any picture no preset named, or the pictures alone in their order when
## there is no descriptor this reader could walk.
func _list(samples: Dictionary[String, SaTipImage.Tip], keys: PackedStringArray, presets: Array[Descriptor.Preset]) -> void:
    var named: Dictionary[String, bool] = {}
    for preset in presets:
        var name := preset.name
        if name.is_empty():
            name = _made_up_name(tips.size() + 1)
        var named_key := preset.picture
        if named_key.is_empty():
            tips.append(_computed(name))
            continue
        var key := _matching(samples, named_key)
        if key.is_empty():
            tips.append(_refused(name, "%s names a picture this file does not hold." % name))
            continue
        named[key] = true
        tips.append(_as_preset(samples[key], name, preset.spacing))
    for key in keys:
        if not named.has(key):
            tips.append(samples[key])


## The key in *samples* a preset's *key* names, or empty.
##
## **Compared without a leading `$`**, because the descriptor writes one in
## front of the key the `samp` entry holds. Then, when nothing matches whole,
## a key that begins the other, for a file that writes the two a character
## apart in length: the open readers record the entry's key only as bytes they
## skip, so how long it is in every file is not known, and a picture is matched
## by thirty characters of a UUID or not at all.
static func _matching(samples: Dictionary[String, SaTipImage.Tip], key: String) -> String:
    var bare := key.trim_prefix("$")
    for held in samples:
        if held.trim_prefix("$") == bare:
            return held
    for held in samples:
        var other := held.trim_prefix("$")
        if mini(other.length(), bare.length()) >= 30 and (other.begins_with(bare) or bare.begins_with(other)):
            return held
    return ""


## *picture* under a preset's *name* and spacing, a tip of its own because two
## presets may share one picture. The texel arrays are shared until written.
func _as_preset(picture: SaTipImage.Tip, name: String, percent: float) -> SaTipImage.Tip:
    if not picture.ok():
        return _refused(name, picture.error.replace(picture.tip_name, name))
    var tip := SaTipImage.Tip.new()
    tip.size = picture.size
    tip.mask = picture.mask
    tip.lightness = picture.lightness
    tip.tip_name = name
    tip.spacing = _spacing(percent)
    return tip


## One picture of *size* at *depth* bits, raw or *packed*, read from *entry*
## where its texels start.
func _picture(entry: Bytes, name: String, size: Vector2i, depth: int, packed: bool, spacing: float) -> SaTipImage.Tip:
    if size.x <= 0 or size.y <= 0:
        return _refused(name, "%s says it is %d × %d px, which is not a valid tip size." % [name, size.x, size.y])
    if size.x > MAX_SIDE or size.y > MAX_SIDE:
        return _refused(name, "%s is %d by %d, past the %d a side Sara reads." % [name, size.x, size.y, MAX_SIDE])
    if not depth in DEPTHS:
        return _refused(name, "%s is %d-bit. Sara reads 8-bit and 16-bit brushes." % [name, depth])
    var row := size.x * (depth >> 3)
    var data := entry.unpacked(size.y, row) if packed else entry.take(row * size.y)
    if data.size() != row * size.y:
        if packed:
            return _refused(name, "%s is packed, and its rows do not unpack to %d by %d." % [name, size.x, size.y])
        return _refused(name, "%s wants %d bytes of picture and its entry holds %d." % [name, row * size.y, entry.left()])
    var tip := SaTipImage.Tip.new()
    tip.size = size
    tip.tip_name = name
    tip.spacing = spacing
    tip.mask = _coverage(data, size, depth)
    tip.lightness.resize(size.x * size.y)
    tip.lightness.fill(SaTipImage.NEUTRAL_LIGHTNESS)
    return tip


## Texels as coverage, 0 to 1.
##
## Eight bits go through Godot's own conversion, which divides by 255 in
## native code: a picture of four thousand pixels a side is sixteen million
## texels, which a loop in GDScript takes seconds over. Sixteen bits have no
## such format to go through and take the loop.
static func _coverage(data: PackedByteArray, size: Vector2i, depth: int) -> PackedFloat32Array:
    if depth == 8:
        var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, data)
        image.convert(Image.FORMAT_RF)
        return image.get_data().to_float32_array()
    var out := PackedFloat32Array()
    out.resize(size.x * size.y)
    for i in out.size():
        out[i] = float((data[i * 2] << 8) | data[i * 2 + 1]) / 65535.0
    return out


func _computed(name: String) -> SaTipImage.Tip:
    var reason := "%s is a computed brush, a shape Photoshop draws from a diameter and a hardness rather than a picture" % name
    return _refused(name, reason + ", and Sara loads pictures only.")


static func _refused(name: String, reason: String) -> SaTipImage.Tip:
    var tip := SaTipImage.Tip.new()
    tip.tip_name = name
    tip.error = reason
    return tip


## A spacing given as a percentage of the tip, as a fraction, or the default
## when the file says nothing believable.
static func _spacing(percent: float) -> float:
    if percent <= 0.0 or percent > MAX_SPACING_PERCENT:
        return SaTipImage.SPACING_WHEN_UNSTATED
    return percent / 100.0


## The name of a brush the file left unnamed: the file's own and its place.
func _made_up_name(number: int) -> String:
    return "%s %d" % [file_name.get_basename(), number]


func _cut_short(what: String, wants: int, ends: int) -> void:
    error = "%s is cut short: its %s runs to byte %d and the file ends at byte %d." % [file_name, what, wants, ends]


## A big-endian read between two offsets, which says when it was asked past
## its end rather than reading what lies beyond.
##
## Bounded at both ends because every length in the format is a field a cut or
## corrupt file is free to lie about, and an entry read past its own end is
## reading the next one as if it were this.
class Bytes:
    extends RefCounted

    var bytes: PackedByteArray
    var at: int
    var ends: int
    ## Set once a read asked for more than was left, after which every read
    ## gives nought.
    var overrun: bool = false

    func _init(source: PackedByteArray, from: int, to: int) -> void:
        bytes = source
        at = from
        ends = mini(to, source.size())

    func left() -> int:
        return maxi(ends - at, 0)

    func _has(count: int) -> bool:
        if overrun or at + count > ends:
            overrun = true
            return false
        return true

    func u8() -> int:
        if not _has(1):
            return 0
        at += 1
        return bytes[at - 1]

    func u16() -> int:
        if not _has(2):
            return 0
        at += 2
        return (bytes[at - 2] << 8) | bytes[at - 1]

    func u32() -> int:
        if not _has(4):
            return 0
        at += 4
        return (bytes[at - 4] << 24) | (bytes[at - 3] << 16) | (bytes[at - 2] << 8) | bytes[at - 1]

    ## A signed four bytes, which is what a bound is: a picture's box may start
    ## left of its origin.
    func s32() -> int:
        var value := u32()
        return value - 0x100000000 if value >= 0x80000000 else value

    func f64() -> float:
        if not _has(8):
            return 0.0
        var swapped := bytes.slice(at, at + 8)
        swapped.reverse()
        at += 8
        return swapped.decode_double(0)

    func skip(count: int) -> void:
        if _has(count):
            at += count

    func take(count: int) -> PackedByteArray:
        if count < 0 or not _has(count):
            return PackedByteArray()
        at += count
        return bytes.slice(at - count, at)

    func ascii(count: int) -> String:
        return take(count).get_string_from_ascii()

    ## A length byte and that many bytes.
    func pascal() -> String:
        return ascii(u8())

    ## A count of UTF-16 code units, big-endian, and the units, with the
    ## terminating nought the count usually includes taken off before the
    ## decode, which reports a nought it meets as an error.
    func utf16() -> String:
        var count := u32()
        var raw := take(count * 2)
        if raw.size() != count * 2:
            return ""
        while count > 0 and raw[count * 2 - 2] == 0 and raw[count * 2 - 1] == 0:
            count -= 1
        raw.resize(count * 2)
        for i in count:
            var high := raw[i * 2]
            raw[i * 2] = raw[i * 2 + 1]
            raw[i * 2 + 1] = high
        return raw.get_string_from_utf16()

    ## *rows* rows of PackBits, each unpacking to *row* bytes, behind a table of
    ## their packed lengths. Shorter than `rows * row` when a row does not
    ## unpack to its length, which the caller reads as a refusal.
    ##
    ## A header byte under 128 is that many and one bytes copied, one over 128
    ## is the next byte repeated 257 less it times, and 128 itself is nothing.
    ## Whole runs are appended rather than bytes, so a packed picture costs a
    ## loop over its runs and not over its texels.
    func unpacked(rows: int, row: int) -> PackedByteArray:
        var lengths := PackedInt32Array()
        for i in rows:
            lengths.append(u16())
        var out := PackedByteArray()
        for i in rows:
            var line := PackedByteArray()
            var stop := at + lengths[i]
            if stop > ends:
                overrun = true
                return out
            while at < stop:
                var head := int(bytes[at])
                at += 1
                if head < 128:
                    line.append_array(bytes.slice(at, mini(at + head + 1, stop)))
                    at += head + 1
                elif head > 128 and at < stop:
                    var run := PackedByteArray()
                    run.resize(257 - head)
                    run.fill(bytes[at])
                    line.append_array(run)
                    at += 1
            if line.size() != row or at != stop:
                return out
            out.append_array(line)
        return out


## A Photoshop action descriptor, walked for the presets of a `desc` section.
##
## The format is a class, a count, and that many items, each a key, a
## four-letter type and a value of that type, some of which are descriptors and
## lists in their turn. The walk reads every type a brush descriptor holds into
## dictionaries and arrays, and gives up on a type it does not know, which
## costs the names and nothing else.
class Descriptor:
    extends RefCounted

    ## How deep a descriptor may nest before the walk stops believing it. A
    ## preset list is three deep, so thirty-two is a corrupt file rather than a
    ## brush.
    const MAX_NESTING: int = 32

    ## The keys of a preset: the list of them, its name, its brush, the
    ## brush's picture key and its spacing. Photoshop's own spelling, padding
    ## included.
    const KEY_PRESETS: String = "Brsh"
    const KEY_NAME: String = "Nm  "
    const KEY_BRUSH: String = "Brsh"
    const KEY_PICTURE: String = "sampledData"
    const KEY_SPACING: String = "Spcn"

    ## One preset of the list: its name, the key of its picture, empty for a
    ## computed brush, and its spacing as a percentage, nought when unstated.
    class Preset:
        extends RefCounted

        var name: String
        var picture: String
        var spacing: float

        func _init(fields: Dictionary, brush: Dictionary) -> void:
            name = SaTyped.text_at(fields, KEY_NAME, "")
            picture = SaTyped.text_at(brush, KEY_PICTURE, "")
            spacing = SaTyped.float_at(brush, KEY_SPACING, 0.0)

    ## The presets of the descriptor in *source*, in its order. Empty when the
    ## walk gave up anywhere.
    static func presets(source: Bytes) -> Array[Preset]:
        var out: Array[Preset] = []
        source.u32()
        var root := SaTyped.strings(_object(source, 0))
        if source.overrun:
            return out
        for item: Variant in SaTyped.list(root.get(KEY_PRESETS)):
            if not item is Dictionary:
                return []
            var fields: Dictionary = item
            out.append(Preset.new(fields, SaTyped.strings(fields.get(KEY_BRUSH))))
        return out

    ## A descriptor's items as a dictionary by key, or null where the walk gave
    ## up.
    static func _object(source: Bytes, depth: int) -> Variant:
        if depth > MAX_NESTING:
            return null
        source.utf16()
        _id(source)
        var count := source.u32()
        if count > source.left():
            return null
        var items := {}
        for i in count:
            var key := _id(source)
            var value: Variant = _value(source, source.ascii(4), depth)
            if value == null or source.overrun:
                return null
            items[key] = value
        return items

    ## A key or a class: a length, and four letters when the length is nought.
    static func _id(source: Bytes) -> String:
        var length := source.u32()
        return source.ascii(4 if length == 0 else length)

    ## One value of *type*, or null for a type the walk does not read.
    static func _value(source: Bytes, type: String, depth: int) -> Variant:
        match type:
            "Objc", "GlbO":
                return _object(source, depth + 1)
            "VlLs":
                var count := source.u32()
                if count > source.left():
                    return null
                var list: Array = []
                for i in count:
                    var item: Variant = _value(source, source.ascii(4), depth + 1)
                    if item == null:
                        return null
                    list.append(item)
                return list
            "TEXT":
                return source.utf16()
            "UntF":
                source.skip(4)
                return source.f64()
            "doub":
                return source.f64()
            "long":
                return source.s32()
            "bool":
                return source.u8() != 0
            "enum":
                _id(source)
                return _id(source)
            "type", "GlbC":
                source.utf16()
                return _id(source)
            "tdta", "alis":
                source.skip(source.u32())
                return true
            "UnFl":
                source.skip(4)
                source.skip(source.u32() * 8)
                return true
            "comp":
                source.skip(8)
                return true
        return null
