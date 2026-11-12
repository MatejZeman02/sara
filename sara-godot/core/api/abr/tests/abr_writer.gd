## Writes Photoshop `.abr` collections, so every collection the reader's suites
## read is one this repository made rather than one downloaded.
##
## The three files under `fixtures/` are what [method fixtures] returns, and the
## suite fails when a file there and its bytes here part, so a fixture is never a
## binary nobody can explain. To write them again, after changing a picture
## here, run `godot --headless --path sara-godot -s
## res://core/api/abr/tests/write_abr_fixtures.gd`.
##
## Each layout is written field by field in the order `sa_abr_collection.gd`
## reads it, which is the order its comment lists, so the two files are two
## readings of one layout and a field that moves in one moves in the suite.
extends RefCounted

## Where the fixtures live, beside this file.
const FIXTURE_DIR: String = "res://core/api/abr/tests/fixtures"

## The three fixtures by file name.
const V1_NAME: String = "a-computed-brush-and-a-picture-v1.abr"
const V2_NAME: String = "three-tips-v2.abr"
const V6_NAME: String = "three-tips-v6.abr"


## One picture to write, as its texels at its depth, 16 bits big-endian.
class Picture:
    extends RefCounted

    var name: String
    var size: Vector2i
    var depth: int
    var packed: bool
    var data: PackedByteArray
    ## As a percentage of the tip, the way both layouts state it.
    var spacing: int
    ## The key a sectioned file finds the picture by.
    var key: String

    func _init(
        title: String, extent: Vector2i, bits: int, pack: bool, texels: PackedByteArray, percent: int, uuid: String = ""
    ) -> void:
        name = title
        size = extent
        depth = bits
        packed = pack
        data = texels
        spacing = percent
        key = uuid

    ## The coverage the reader should give texel *i*.
    func coverage(i: int) -> float:
        if depth == 16:
            return float((data[i * 2] << 8) | data[i * 2 + 1]) / 65535.0
        return float(data[i]) / 255.0


## The marker for a computed brush in a version 1 or 2 list, which carries a
## diameter and a hardness and no picture.
class Computed:
    extends RefCounted

    var name: String
    var diameter: int

    func _init(title: String, across: int) -> void:
        name = title
        diameter = across


## The three fixtures, by file name.
static func fixtures() -> Dictionary[String, PackedByteArray]:
    return {V1_NAME: v1_fixture(), V2_NAME: v2_fixture(), V6_NAME: v6_fixture()}


## A computed brush, then a raw picture, in version 1, which names neither.
static func v1_fixture() -> PackedByteArray:
    return old_layout(1, [Computed.new("", 19), Picture.new("", Vector2i(8, 8), 8, false, checker(8, 8), 30)])


## Three named pictures in version 2, the second packed.
static func v2_fixture() -> PackedByteArray:
    return old_layout(2, v2_pictures())


static func v2_pictures() -> Array[Picture]:
    return [
        Picture.new("Chalk", Vector2i(6, 5), 8, false, disc(6, 5), 25),
        Picture.new("Wide Flat", Vector2i(9, 4), 8, true, bar(9, 4), 10),
        Picture.new("Spatter", Vector2i(5, 7), 8, false, ramp(5, 7), 40),
    ]


## Three pictures in version 6, subversion 2, named by the descriptor: a raw
## disc, a packed half that tells left from right on a canvas, and a sixteen
## bit ramp.
static func v6_fixture() -> PackedByteArray:
    return sectioned(6, 2, v6_pictures(), true)


static func v6_pictures() -> Array[Picture]:
    return [
        Picture.new("Dry Disc", Vector2i(16, 16), 8, false, disc(16, 16), 25, uuid(1)),
        Picture.new("Left Half", Vector2i(24, 24), 8, true, bar(24, 24), 15, uuid(2)),
        Picture.new("Deep Ramp", Vector2i(12, 10), 16, false, ramp16(12, 10), 50, uuid(3)),
    ]


## A version 1 or 2 file of *entries*, each a [Picture] or a [Computed].
static func old_layout(version: int, entries: Array) -> PackedByteArray:
    var out := u16(version) + u16(entries.size())
    for entry: RefCounted in entries:
        var body := PackedByteArray()
        if entry is Computed:
            var computed: Computed = entry
            # misc, spacing, diameter, roundness, angle, hardness
            body = u32(0) + u16(25) + u16(computed.diameter) + u16(100) + u16(0) + u16(80)
            out.append_array(u16(1) + u32(body.size()) + body)
            continue
        var picture: Picture = entry
        body = u32(0) + u16(picture.spacing)
        if version == 2:
            body.append_array(utf16(picture.name))
        body.append(1)
        # The bounds in two bytes a side, then in four.
        body.append_array(u16(0) + u16(0) + u16(picture.size.y) + u16(picture.size.x))
        body.append_array(u32(0) + u32(0) + u32(picture.size.y) + u32(picture.size.x))
        body.append_array(u16(picture.depth))
        body.append(1 if picture.packed else 0)
        body.append_array(encoded(picture))
        out.append_array(u16(2) + u32(body.size()) + body)
    return out


## A version 6 or later file of *pictures*, with a `desc` naming them when
## *named*, and a computed preset for each of *computed* after them.
static func sectioned(
    version: int, subversion: int, pictures: Array[Picture], named: bool, computed: PackedStringArray = PackedStringArray()
) -> PackedByteArray:
    var samples := PackedByteArray()
    var gap: int = 10 if subversion == 1 else 264
    for picture in pictures:
        var key := picture.key.to_ascii_buffer()
        var entry := PackedByteArray([key.size()]) + key
        entry.resize(entry.size() + gap)
        entry.append_array(u32(0) + u32(0) + u32(picture.size.y) + u32(picture.size.x))
        entry.append_array(u16(picture.depth))
        entry.append(1 if picture.packed else 0)
        entry.append_array(encoded(picture))
        samples.append_array(u32(entry.size()) + entry)
        while samples.size() % 4 != 0:
            samples.append(0)
    var out := u16(version) + u16(subversion) + section("samp", samples) + section("patt", PackedByteArray())
    if named:
        out.append_array(section("desc", descriptor(pictures, computed)))
    return out


## *picture*'s texels as the file holds them: raw, or a table of packed row
## lengths and the packed rows.
static func encoded(picture: Picture) -> PackedByteArray:
    if not picture.packed:
        return picture.data
    var row := picture.size.x * (picture.depth >> 3)
    var table := PackedByteArray()
    var rows := PackedByteArray()
    for y in picture.size.y:
        var line := packbits(picture.data.slice(y * row, (y + 1) * row))
        table.append_array(u16(line.size()))
        rows.append_array(line)
    return table + rows


static func section(tag: String, body: PackedByteArray) -> PackedByteArray:
    return "8BIM".to_ascii_buffer() + tag.to_ascii_buffer() + u32(body.size()) + body


## The `desc` section's body: a version, then a descriptor whose `Brsh` list
## holds one preset per picture and one per computed name.
##
## Each preset carries the fields Photoshop writes around the two the reader
## takes, a double, a whole number, an enum and a flag among them, so the walk
## is made to step over every kind it says it reads.
static func descriptor(pictures: Array[Picture], computed: PackedStringArray) -> PackedByteArray:
    var presets := PackedByteArray()
    for picture in pictures:
        var brush := (
            item("Dmtr", "UntF", "#Pxl".to_ascii_buffer() + f64(picture.size.x))
            + item("Angl", "UntF", "#Ang".to_ascii_buffer() + f64(0.0))
            + item("Spcn", "UntF", "#Prc".to_ascii_buffer() + f64(picture.spacing))
            + item("Intr", "bool", PackedByteArray([1]))
            + item("sampledData", "TEXT", utf16("$" + picture.key))
        )
        presets.append_array(preset(picture.name, "sampledBrush", 5, brush))
    for name in computed:
        var brush := (
            item("Dmtr", "UntF", "#Pxl".to_ascii_buffer() + f64(30.0))
            + item("Hrdn", "UntF", "#Prc".to_ascii_buffer() + f64(100.0))
            + item("Spcn", "UntF", "#Prc".to_ascii_buffer() + f64(25.0))
        )
        presets.append_array(preset(name, "computedBrush", 3, brush))
    var count := pictures.size() + computed.size()
    var root := utf16("") + id("null") + u32(1) + item("Brsh", "VlLs", u32(count) + presets)
    return u32(16) + root


## One `Objc` of a preset list: its name, a whole number, an enum and its brush
## of *count* items.
static func preset(name: String, kind: String, count: int, brush: PackedByteArray) -> PackedByteArray:
    var fields := (
        item("Nm  ", "TEXT", utf16(name))
        + item("Brsh", "Objc", utf16("") + id(kind) + u32(count) + brush)
        + item("Usrs", "long", u32(7))
        + item("Mde ", "enum", id("BlnM") + id("Nrml"))
        + item("Opct", "doub", f64(1.0))
    )
    return "Objc".to_ascii_buffer() + utf16("") + id("brushPreset") + u32(5) + fields


static func item(key: String, type: String, value: PackedByteArray) -> PackedByteArray:
    return id(key) + type.to_ascii_buffer() + value


## A key or class: four letters behind a nought, or a length and the letters.
static func id(text: String) -> PackedByteArray:
    var raw := text.to_ascii_buffer()
    return u32(0) + raw if raw.size() == 4 else u32(raw.size()) + raw


## PackBits: a run of two or more as one byte repeated, the rest as literals,
## each packet at most 128 long.
static func packbits(row: PackedByteArray) -> PackedByteArray:
    var out := PackedByteArray()
    var at := 0
    while at < row.size():
        var ends := at + 1
        while ends < row.size() and row[ends] == row[at] and ends - at < 128:
            ends += 1
        if ends - at >= 2:
            out.append(257 - (ends - at))
            out.append(row[at])
            at = ends
            continue
        var literal := PackedByteArray()
        while at < row.size() and literal.size() < 128 and not (at + 1 < row.size() and row[at] == row[at + 1]):
            literal.append(row[at])
            at += 1
        out.append(literal.size() - 1)
        out.append_array(literal)
    return out


static func u16(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 8) & 0xFF, value & 0xFF])


static func u32(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


static func f64(value: float) -> PackedByteArray:
    var raw := PackedByteArray()
    raw.resize(8)
    raw.encode_double(0, value)
    raw.reverse()
    return raw


## A count of UTF-16 code units, the terminating nought among them, and the
## units big-endian.
static func utf16(text: String) -> PackedByteArray:
    var out := u32(text.length() + 1)
    for i in text.length():
        out.append_array(u16(text.unicode_at(i)))
    return out + u16(0)


## The key of picture *number*, a UUID's shape.
static func uuid(number: int) -> String:
    return "5a8c%04d-0b1e-4c2a-9d3f-a1b2c3d4e5f6" % number


## Full coverage inside an ellipse filling *width* by *height*, none outside.
static func disc(width: int, height: int) -> PackedByteArray:
    var out := PackedByteArray()
    for y in height:
        for x in width:
            var at := Vector2((x + 0.5) / width - 0.5, (y + 0.5) / height - 0.5) * 2.0
            out.append(255 if at.length() <= 1.0 else 0)
    return out


## Full coverage on the left half and none on the right, which packs to two
## runs a row.
static func bar(width: int, height: int) -> PackedByteArray:
    var out := PackedByteArray()
    for y in height:
        for x in width:
            out.append(255 if x < width / 2.0 else 0)
    return out


## Every texel a different value, which leaves PackBits nothing to pack.
static func ramp(width: int, height: int) -> PackedByteArray:
    var out := PackedByteArray()
    for i in width * height:
        out.append((i * 37 + 11) % 256)
    return out


## A sixteen bit ramp, big-endian, whose low bytes differ from its high ones,
## so a reader taking one byte of the two reads the wrong value.
static func ramp16(width: int, height: int) -> PackedByteArray:
    var out := PackedByteArray()
    for i in width * height:
        out.append_array(u16((i * 997 + 301) % 65536))
    return out


## A checker of single texels, half and full.
static func checker(width: int, height: int) -> PackedByteArray:
    var out := PackedByteArray()
    for y in height:
        for x in width:
            out.append(255 if (x + y) % 2 == 0 else 128)
    return out


## Writes every fixture into *dir*, false when one could not be written.
static func write_all(dir: String) -> bool:
    DirAccess.make_dir_recursive_absolute(dir)
    var files := fixtures()
    for name in files:
        var file := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
        if file == null:
            return false
        file.store_buffer(files[name])
        file.close()
    return true
