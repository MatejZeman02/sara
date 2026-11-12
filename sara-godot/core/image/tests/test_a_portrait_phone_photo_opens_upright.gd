## A JPEG opens the way its EXIF orientation says it is shown. A phone writes
## a portrait photograph as landscape pixels with orientation 6 or 8, and the
## decoder hands the pixels back as stored, so the reader turns them.
##
## Each file is written here, an eight-bit JPEG of four flat quarters with an
## APP1 segment spliced in after its first marker, so no binary fixture is kept
## and the tag's every value and both byte orders are covered.
extends "res://tests/test_framework.gd"

## The stored picture, wider than it is tall, so a turn shows in its size.
const STORED := Vector2i(32, 16)

const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)
const BLUE := Color(0, 0, 1)
const WHITE := Color(1, 1, 1)

## How far a corner of a JPEG of flat quarters strays from its colour.
const SLACK := 0.1

## For each orientation, the shown corners in the order top left, top right,
## bottom left and bottom right, worked out by hand from the tag's definition
## for stored corners of red, green, blue and white, so the suite never shares
## a line with the reader it checks.
const SHOWN := {
    1: [RED, GREEN, BLUE, WHITE],
    2: [GREEN, RED, WHITE, BLUE],
    3: [WHITE, BLUE, GREEN, RED],
    4: [BLUE, WHITE, RED, GREEN],
    5: [RED, BLUE, GREEN, WHITE],
    6: [BLUE, RED, WHITE, GREEN],
    7: [WHITE, GREEN, BLUE, RED],
    8: [GREEN, WHITE, RED, BLUE],
}

## One run's output under `user://`, never committed.
static var scratch_path: String = SaDataRoot.path("h301-orientation-%d.jpg" % OS.get_process_id())


func after_each() -> void:
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(scratch_path)


## Four flat quarters, red, green, blue and white from the top left, as JPEG.
func _jpeg() -> PackedByteArray:
    var image := Image.create_empty(STORED.x, STORED.y, false, Image.FORMAT_RGB8)
    @warning_ignore("integer_division")
    var half := STORED / 2
    image.fill_rect(Rect2i(Vector2i.ZERO, half), RED)
    image.fill_rect(Rect2i(Vector2i(half.x, 0), half), GREEN)
    image.fill_rect(Rect2i(Vector2i(0, half.y), half), BLUE)
    image.fill_rect(Rect2i(half, half), WHITE)
    return image.save_jpg_to_buffer(0.95)


func _number(value: int, size: int, big: bool) -> PackedByteArray:
    var bytes := PackedByteArray()
    bytes.resize(size)
    for i in size:
        var byte := (value >> (8 * i)) & 0xFF
        bytes[size - 1 - i if big else i] = byte
    return bytes


## The TIFF block of an EXIF segment holding one IFD with the orientation and
## a tag before it, so the reader has to walk the entries.
func _tiff(orientation: int, big: bool) -> PackedByteArray:
    var tiff := ("MM" if big else "II").to_ascii_buffer()
    tiff += _number(42, 2, big)
    tiff += _number(8, 4, big)
    tiff += _number(2, 2, big)
    # ImageWidth, a LONG, which is not the tag asked for.
    tiff += _number(0x0100, 2, big) + _number(4, 2, big) + _number(1, 4, big) + _number(STORED.x, 4, big)
    tiff += _number(0x0112, 2, big) + _number(3, 2, big) + _number(1, 4, big) + _number(orientation, 2, big)
    tiff += _number(0, 2, big)
    tiff += _number(0, 4, big)
    return tiff


## *jpeg* with an APP1 segment holding *tiff* right after its start marker.
func _with_app1(jpeg: PackedByteArray, tiff: PackedByteArray) -> PackedByteArray:
    var body := "Exif".to_ascii_buffer() + PackedByteArray([0, 0]) + tiff
    var segment := PackedByteArray([0xFF, 0xE1]) + _number(body.size() + 2, 2, true) + body
    return jpeg.slice(0, 2) + segment + jpeg.slice(2)


func _read(bytes: PackedByteArray) -> Image:
    var file := FileAccess.open(scratch_path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return SaImageImport.read(scratch_path)


## The orientations 5 to 8 turn the picture a quarter, so it is shown tall.
func _assert_shown(image: Image, orientation: int, label: String) -> void:
    assert_not_null(image, "%s reads" % label)
    if image == null:
        return
    var size := image.get_size()
    var corners: Array = SHOWN[orientation]
    var expected := Vector2i(STORED.y, STORED.x) if orientation >= 5 else STORED
    assert_eq(size, expected, "%s is shown %s" % [label, expected])
    var at := [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), size - Vector2i.ONE]
    for i in at.size():
        var got := image.get_pixelv(at[i])
        var want: Color = corners[i]
        var off := maxf(maxf(absf(got.r - want.r), absf(got.g - want.g)), absf(got.b - want.b))
        assert_true(off < SLACK, "%s corner %s is %s, wanted %s" % [label, at[i], got, want])


func test_each_orientation_opens_as_a_viewer_shows_it() -> void:
    var jpeg := _jpeg()
    for orientation: int in SHOWN:
        for big: bool in [false, true]:
            var label := "orientation %d, %s" % [orientation, "big-endian" if big else "little-endian"]
            _assert_shown(_read(_with_app1(jpeg, _tiff(orientation, big))), orientation, label)


func test_a_portrait_phone_photo_is_taller_than_it_is_wide() -> void:
    var image := _read(_with_app1(_jpeg(), _tiff(6, false)))
    assert_not_null(image)
    if image != null:
        assert_true(image.get_height() > image.get_width(), "orientation 6 opens upright, got %s" % image.get_size())


func test_a_jpeg_with_no_exif_reads_as_stored() -> void:
    _assert_shown(_read(_jpeg()), 1, "no EXIF")


## The segment ends before the IFD it points at, so the tag cannot be followed
## and the picture reads as stored rather than turned on a guess.
func test_a_truncated_app1_segment_reads_as_stored() -> void:
    var cut := _tiff(6, false).slice(0, 12)
    _assert_shown(_read(_with_app1(_jpeg(), cut)), 1, "a truncated APP1")


## An orientation outside 1 to 8 is a damaged tag, read as stored.
func test_a_damaged_orientation_reads_as_stored() -> void:
    _assert_shown(_read(_with_app1(_jpeg(), _tiff(9, true))), 1, "orientation 9")
