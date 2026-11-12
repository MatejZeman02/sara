## Tests for the preview a v4 `.sad` file carries.
##
## The preview is the first blob of the region, so a recent-files grid can read
## a thumbnail without building the document. These tests save a document with
## and without one and read the file back both ways.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, because saving reads chunks off the GPU.
const REQUIRES_GPU := true

## The preview is shrunk to this on its long side, and a document wider than it
## is the one whose shrink is exercised.
const PREVIEW_LONG_EDGE := 256

const PREVIEW_SIZE := Vector2i(300, 200)

## One step of an eight-bit channel, and the room a card gets on top of it: the
## preview is stored as a lossy WebP, the view is not.
const GREY_STEP := 1.0 / 255.0
const CARD_ALLOWANCE := 3.0 * GREY_STEP


## An easel holding the default grey background, composited so `output` carries
## it, in the colour space the app's own document opens on.
func _grey_easel(size: Vector2i, space: SaColorSpace) -> SaEasel:
    var easel := SaEasel.create_default(size, null, space)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The JSON header of the v4 file at *path*, parsed back out of the container.
func _header(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)  # magic
    file.get_32()  # version
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var header := file.get_buffer(packed_size).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
    file.close()
    return JSON.parse_string(header.get_string_from_utf8())


func _layer_count(document: SaDocument) -> int:
    var count := 0
    for child in document.get_children():
        if child is SaLayer:
            count += 1
    return count


func test_a_preview_round_trips_off_the_file() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    # Wider than the 256-pixel thumbnail, so the shrink is exercised and the
    # ratio is the assertion.
    var preview := Image.create(800, 400, false, Image.FORMAT_RGBA8)
    preview.fill(Color(0.1, 0.2, 0.3, 1.0))

    var path := SaDataRoot.path("test_w2_preview.sad")
    assert_eq(SaExport.save_sad(doc, path, 0, preview), OK, "Saving with a preview should return OK")

    var header := _header(path)
    assert_true(header.has("preview"), "The header carries the preview key")
    var entry: Dictionary = header["preview"]
    assert_eq(int(entry.get("width", 0)), 256, "The long side is shrunk to 256")
    assert_eq(int(entry.get("height", 0)), 128, "and the short side keeps the ratio")
    assert_eq(int(entry.get("offset", 0)), 0, "The preview is the first blob, at offset 0")

    var read_back := SaSadFile.read_preview(path)
    assert_not_null(read_back, "SaSadFile.read_preview decodes the preview")
    if read_back != null:
        assert_eq(read_back.get_size(), Vector2i(256, 128), "and it matches the size the header names")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "A file with a preview still loads")
    assert_eq(loaded.canvas_size, Vector2i(64, 64), "Its canvas size is unchanged")
    assert_eq(_layer_count(loaded), _layer_count(doc), "and its layer count is unchanged")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()


func test_a_file_saved_without_a_preview_reads_back_null() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    var path := SaDataRoot.path("test_w2_no_preview.sad")
    assert_eq(SaExport.save_sad(doc, path, 0), OK, "Saving without a preview still returns OK")
    assert_null(SaSadFile.read_preview(path), "A file saved with no preview reads back null")

    DirAccess.remove_absolute(path)
    doc.free()


func test_read_returns_null_quietly_for_a_file_that_is_not_a_v4_sad() -> void:
    var not_sad := SaDataRoot.path("test_w2_not_sad.bin")
    var file := FileAccess.open(not_sad, FileAccess.WRITE)
    file.store_buffer("not a sad file at all".to_ascii_buffer())
    file.close()
    assert_null(SaSadFile.read_preview(not_sad), "A file that is not a .sad reads back null")

    DirAccess.remove_absolute(not_sad)


## d7: an Oklab document's preview is the picture, not the numbers it stores.
##
## A default document stores Oklab, so its mid grey background is `L 0.6, a 0,
## b 0`, and a preview narrowed straight to eight bits drew that as a dark red
## field on the recent pane's card. The preview is converted into the space a
## person sees first, which is the conversion a recorded frame already made.
func test_an_oklab_documents_preview_is_the_picture_not_the_stored_numbers() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = PREVIEW_SIZE
    canvas.easel = _grey_easel(PREVIEW_SIZE, SaColorSpace.oklab())
    canvas.add_child(canvas.easel)

    var preview := SaExport.get_preview_image(canvas.easel)
    assert_not_null(preview, "the preview was read back")
    if preview == null:
        canvas.free()
        return

    var path := SaDataRoot.path("test_d7_oklab_preview.sad")
    assert_eq(SaExport.save_sad(canvas.document, path, 0, preview), OK, "Saving with a preview should return OK")

    var card := SaSadFile.read_preview(path)
    assert_not_null(card, "SaSadFile.read_preview decodes the preview")
    if card != null:
        assert_eq(card.get_size(), Vector2i(PREVIEW_LONG_EDGE, 171), "the card is the canvas at the preview's long side")
        var texel := card.get_pixel(4, 4)
        assert_almost_eq(texel.r, texel.g, CARD_ALLOWANCE, "the stored Oklab grey is not read as a red channel")
        assert_almost_eq(texel.g, texel.b, CARD_ALLOWANCE, "and the two other channels agree")
        assert_almost_eq(texel.r, 0.5, CARD_ALLOWANCE, "and it stands at the display grey the document opened on")

        # The recorder's frame is the app's own answer to what the view draws,
        # so the card says the same thing about the same canvas.
        var recorder := SaRecorder.new()
        recorder.bind_canvas(canvas)
        var frame := recorder.display_image(canvas)
        recorder.free()
        assert_not_null(frame, "the recorder read the same canvas")
        if frame != null:
            var drawn := frame.get_pixel(4, 4)
            assert_almost_eq(texel.r, drawn.r, CARD_ALLOWANCE, "and the card holds what the view draws, in R")
            assert_almost_eq(texel.g, drawn.g, CARD_ALLOWANCE, "in G")
            assert_almost_eq(texel.b, drawn.b, CARD_ALLOWANCE, "and in B")

    # What the card held before d7: the stored numbers of the same canvas, read
    # straight as RGB. That read is right for a PNG named for the document's
    # gamut and wrong for anything a painter looks at, and the two must stay
    # apart rather than one of them becoming the other.
    var stored := SaExport.get_canvas_image(canvas.easel)
    assert_not_null(stored, "the stored-numbers read still answers for the same canvas")
    if stored != null:
        var raw := stored.get_pixel(4, 4)
        assert_true(raw.r - raw.g > 0.3, "and it reads the Oklab grey as a dark red, which a card never holds")

    DirAccess.remove_absolute(path)
    canvas.free()
