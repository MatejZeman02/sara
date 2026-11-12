## An OpenRaster zip stores every entry.
##
## A document of three paint layers and a group is exported as OpenRaster and
## the file is read as a format sniffer and a zip reader read it: the first
## local header and the eight bytes after it, the end record, and each record
## of the central directory, with the local header it points at. Every entry
## is method 0, `image/openraster` stands at byte 38, and what `ZIPReader`
## reads of each entry is the stored bytes the local header wraps. The writer
## is read on its own as well, with entries the suite knows to the byte.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_o1_stored.ora")
static var scratch_zip: String = SaDataRoot.path("test_o1_stored.zip")

## Where a sniffer reads the type: a thirty-byte local header and `mimetype`.
const TYPE_AT := 38
const END_BYTES := 22
const CENTRAL_BYTES := 46

var _easel: SaEasel
var _doc: SaDocument
var _metadata := SaExportMetadata.new("O1", 1790190245, 120)
## The layers the bench's document held before the suite painted any.
var _bench_layers: int
var _group: SaLayer

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _bench_layers = SaLayerStack.members(_doc, null).size()
    var colours := [Color(0.8, 0.2, 0.4, 1.0), Color(0.4, 0.8, 0.2, 0.6), Color(0.6, 0.4, 0.8, 1.0)]
    var painted: Array[SaLayer] = []
    for i in colours.size():
        var layer := ops.add()
        layer.name = "Paint %d" % i
        layer.get_or_create_chunk(Vector2i(i % 2, 0)).clear(colours[i])
        painted.append(layer)
    _group = ops.group_layers([painted[2]])
    _group.name = "Group"
    _doc.update_caches()
    Bench.composite(_easel)


func after_each() -> void:
    for path: String in [scratch, scratch_zip]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _group = null
    _doc = null
    _easel.free()
    _easel = null


# --- Reading the bytes --------------------------------------------------------


func _u16(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


func _u32(bytes: PackedByteArray, at: int) -> int:
    return _u16(bytes, at) | (_u16(bytes, at + 2) << 16)


## Each record of the central directory as `{"name", "method", "crc", "size",
## "offset"}`, in the directory's order, and the local header's method, name
## and stored bytes beside it.
func _entries(bytes: PackedByteArray) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var end := bytes.size() - END_BYTES
    assert_eq(_u32(bytes, end), SaZipStored.END_SIGNATURE, "The file ends on the end record")
    var count := _u16(bytes, end + 10)
    var at := _u32(bytes, end + 16)
    assert_eq(at + _u32(bytes, end + 12), end, "The directory runs up to the end record")
    for i in count:
        assert_eq(_u32(bytes, at), SaZipStored.CENTRAL_SIGNATURE, "Record %d is a central record" % i)
        var name_size := _u16(bytes, at + 28)
        var extra := _u16(bytes, at + 30) + _u16(bytes, at + 32)
        var offset := _u32(bytes, at + 42)
        var local_name := _u16(bytes, offset + 26)
        var data_at := offset + SaZipStored.LOCAL_HEADER_BYTES + local_name + _u16(bytes, offset + 28)
        var size := _u32(bytes, at + 24)
        (
            out
            . append(
                {
                    "name": bytes.slice(at + CENTRAL_BYTES, at + CENTRAL_BYTES + name_size).get_string_from_utf8(),
                    "method": _u16(bytes, at + 10),
                    "packed": _u32(bytes, at + 20),
                    "size": size,
                    "crc": _u32(bytes, at + 16),
                    "local_signature": _u32(bytes, offset),
                    "local_method": _u16(bytes, offset + 8),
                    "local_name": bytes.slice(offset + 30, offset + 30 + local_name).get_string_from_utf8(),
                    "data": bytes.slice(data_at, data_at + size),
                }
            )
        )
        at += CENTRAL_BYTES + name_size + extra
    return out


# --- The tests ------------------------------------------------------------------


func test_the_document_holds_three_layers_and_a_group() -> void:
    var names := SaLayerStack.members(_doc, null).map(func(layer: SaLayer) -> String: return String(layer.name))
    assert_eq(names.slice(_bench_layers), ["Paint 0", "Paint 1", "Group"], "Two layers and the group above the bench's")
    var inside := SaLayerStack.members(_doc, _group).map(func(layer: SaLayer) -> String: return String(layer.name))
    assert_eq(inside, ["Paint 2"], "and the third layer in the group")


func test_a_sniffer_finds_the_type_at_byte_38() -> void:
    var ora := SaExportOra.new(_doc, 8, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata)
    assert_eq(ora.write(_easel.output, scratch), OK, "The export succeeds")
    var bytes := FileAccess.get_file_as_bytes(scratch)
    assert_eq(_u32(bytes, 0), SaZipStored.LOCAL_SIGNATURE, "The file starts with a local header")
    assert_eq(_u16(bytes, 8), 0, "whose method is stored")
    assert_eq(bytes.slice(30, TYPE_AT).get_string_from_ascii(), "mimetype", "for the mimetype")
    var type := SaExportOra.MIMETYPE
    assert_eq(bytes.slice(TYPE_AT, TYPE_AT + type.length()).get_string_from_ascii(), type, "and the type is at 38")


func test_every_entry_is_stored_and_reads_back_equal() -> void:
    var ora := SaExportOra.new(_doc, 8, PackedFloat32Array(), SaGamutMapping.CLIP, _metadata)
    assert_eq(ora.write(_easel.output, scratch), OK, "The export succeeds")
    var entries := _entries(FileAccess.get_file_as_bytes(scratch))
    var reader := ZIPReader.new()
    assert_eq(reader.open(scratch), OK, "ZIPReader opens the file")
    var names := entries.map(func(entry: Dictionary) -> String: return entry["name"])
    assert_eq(Array(reader.get_files()), names, "ZIPReader lists the directory's entries in its order")
    assert_eq(names.slice(0, 2), ["mimetype", "stack.xml"], "mimetype first, the stack after it")
    assert_eq(names.slice(-2), ["Thumbnails/thumbnail.png", "mergedimage.png"], "the thumbnail and the merged image last")
    var pngs := names.filter(func(name: String) -> bool: return name.begins_with("data/")).size()
    assert_eq(pngs, _bench_layers + 3, "One PNG a layer, the bench's and the suite's three")
    for entry: Dictionary in entries:
        var name: String = entry["name"]
        assert_eq(entry["method"], 0, "%s is stored in the directory" % name)
        assert_eq(entry["local_method"], 0, "and in its local header")
        assert_eq(entry["local_signature"], SaZipStored.LOCAL_SIGNATURE, "which the directory points at")
        assert_eq(entry["local_name"], name, "and which names it the same")
        assert_eq(entry["packed"], entry["size"], "%s takes as many bytes as it holds" % name)
        assert_eq(entry["crc"], SaExportGamut.crc32(entry["data"]), "%s carries its CRC" % name)
        assert_eq(reader.read_file(name), entry["data"], "ZIPReader reads %s back equal" % name)
    reader.close()


func test_the_writer_alone_stores_what_it_is_given() -> void:
    var given := {
        "mimetype": SaExportOra.MIMETYPE.to_ascii_buffer(),
        "empty": PackedByteArray(),
        "data/bytes.bin": PackedByteArray(range(256)),
        "data/naïve.txt": "ümlaut".to_utf8_buffer(),
    }
    var zip := SaZipStored.new(scratch_zip, 1790190245)
    for name: String in given:
        assert_eq(zip.add(name, given[name]), OK, "%s is added" % name)
    assert_eq(zip.close(), OK, "The zip closes")
    assert_true(zip.add("late", PackedByteArray()) != OK, "A closed zip takes no entry")
    var entries := _entries(FileAccess.get_file_as_bytes(scratch_zip))
    assert_eq(entries.map(func(entry: Dictionary) -> String: return entry["name"]), given.keys(), "The names in order")
    var reader := ZIPReader.new()
    assert_eq(reader.open(scratch_zip), OK, "ZIPReader opens it")
    for name: String in given:
        assert_eq(reader.read_file(name), given[name], "%s reads back equal" % name)
    reader.close()


func test_the_date_is_the_painters_clock() -> void:
    # 2026-09-24 14:04:05 UTC read two hours ahead, 16:04:04 at the two
    # seconds MS-DOS counts in.
    var zip := SaZipStored.new(scratch_zip, 1790258645 + 7200)
    assert_eq(zip.add("mimetype", SaExportOra.MIMETYPE.to_ascii_buffer()), OK, "The entry is added")
    assert_eq(zip.close(), OK, "The zip closes")
    var bytes := FileAccess.get_file_as_bytes(scratch_zip)
    assert_eq(_u16(bytes, 10), (16 << 11) | (4 << 5) | 2, "The time")
    assert_eq(_u16(bytes, 12), ((2026 - 1980) << 9) | (9 << 5) | 24, "The date")


func test_a_path_that_cannot_open_refuses_every_entry() -> void:
    var zip := SaZipStored.new(SaDataRoot.path("no/such/folder/o1.zip"))
    assert_true(zip.add("mimetype", PackedByteArray()) != OK, "No entry is written")
    assert_true(zip.close() != OK, "Nor is the zip closed")
