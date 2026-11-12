## A TIFF past classic TIFF's four gigabytes is refused.
##
## The strip's byte count and offset are LONGs, and a 16384 square at float is
## exactly 2^32 bytes of strip, which wrapped to a byte count of nought in a
## file the export called saved. Every case here asks the arithmetic alone, so
## no picture of that size is ever allocated, and the one image the suite makes
## is a single pixel.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const SQUARE := Vector2i(16384, 16384)

var _refusals: Array[String] = []

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    _refusals = []
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            if kind == SaProblems.Kind.REFUSAL:
                _refusals.append(line)
    )


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true


func test_a_float_square_of_16384_is_refused() -> void:
    assert_false(SaExportTiff.strip_fits(SQUARE, SaExportTiff.BYTES_PER_SAMPLE), "2^32 bytes of strip is one past a LONG")


## The writer offers no eight-bit depth, so eight bits is asked of the
## arithmetic at one byte a sample, which is the case that matters.
func test_an_eight_bit_square_of_16384_is_let_through() -> void:
    assert_true(SaExportTiff.strip_fits(SQUARE, 1), "a gigabyte of strip fits")


func test_a_sixteen_bit_square_of_16384_is_let_through() -> void:
    assert_true(SaExportTiff.strip_fits(SQUARE, SaExportTiff.BYTES_PER_SAMPLE_SIXTEEN), "two gigabytes fit")


## One row short of the square is the largest float picture of that width,
## and one byte of offset past `LIMIT_32` is refused however small the strip.
func test_the_edges_of_the_limit() -> void:
    assert_true(SaExportTiff.strip_fits(Vector2i(16384, 16383), SaExportTiff.BYTES_PER_SAMPLE), "just under fits")
    assert_false(SaExportTiff.strip_fits(Vector2i.ONE, 4, SaExportTiff.LIMIT_32 + 1), "an offset past a LONG")
    assert_true(SaExportTiff.strip_fits(Vector2i.ONE, 4, SaExportTiff.LIMIT_32), "an offset at the limit")


## The refusal the export shows: the float square is refused with a line in
## the corner and the error `SaZipStored` gives its own limit, and the 16-bit
## one says nothing.
func test_the_refusal_reaches_the_corner() -> void:
    assert_eq(SaExportTiff.refuse_size(SQUARE, SaExportTiff.BITS_PER_SAMPLE), ERR_FILE_CANT_WRITE, "float refused")
    assert_eq(_refusals.size(), 1, "one line in the corner")
    assert_true(_refusals[0].contains("16384 by 16384"), "the line names the size: %s" % _refusals[0])
    assert_true(_refusals[0].contains("16 bits"), "and the depth that would fit")
    assert_eq(SaExportTiff.refuse_size(SQUARE, SaExportTiff.BITS_PER_SAMPLE_SIXTEEN), OK, "16 bits let through")
    assert_eq(_refusals.size(), 1, "and says nothing")


## A small picture still writes, so the check sits in front of the path
## rather than across it.
func test_a_small_picture_still_writes() -> void:
    var image := Image.create(1, 1, false, Image.FORMAT_RGBAF)
    var path := SaDataRoot.path("test_d9_small.tiff")
    assert_eq(SaExportTiff.write(image, path), OK, "one pixel writes")
    assert_true(FileAccess.file_exists(path), "and leaves its file")
    DirAccess.remove_absolute(path)
    assert_eq(_refusals.size(), 0, "with no refusal")
