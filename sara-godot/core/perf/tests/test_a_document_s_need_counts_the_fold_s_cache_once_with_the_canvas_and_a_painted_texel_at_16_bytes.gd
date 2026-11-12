## A document's need counts the fold's cache once with the
## canvas, and a painted texel at 16 bytes.
##
## read the 32 bytes a painted texel as two textures: a chunk's colour
## field, 16 bytes and one for every painted texel, and `SaLayerFold`'s bottom
## cache, 16 bytes over the canvas and made once when the first paint layer
## goes over the background. `PAINTED_BYTES_PER_TEXEL` carried both, so a
## forty-layer painting was charged the cache forty times over. Read here are
## `for_canvas` at the figures the 4096 painting gives, and `for_sad`
## against what the running app held with that painting open.
##
## `tests/data/forty_layers_4096_header.sad` is the forty-layer
## painting at 4096, painted and saved by the unit's scenario, cut to the
## container's four bytes of magic, its three sizes and its header block,
## which is the whole of what `SaCardMemory.for_sad` reads. Its chunks' blobs,
## the other 17 MB, stay in the proof folder: a fixture that opened as itself
## would have to carry every one of them.
extends "res://tests/test_framework.gd"

## the forty-layer painting, as its header alone.
const FIXTURE := "res://tests/data/forty_layers_4096_header.sad"
const SIDE := 4096
const GIB := 1 << 30

## What `scenarios/...json` read on 2026-10-23 on a desktop GPU, the
## `vram_bytes` of `g-in-hand.json`: the fixture's painting saved, let go of
## and opened again, after the fold had paid the debt a load leaves it and made
## the bottom cache. `f-opened.json`, the instant after the load and before
## that debt is paid, reads 2,446,624,826.
const OPEN_VRAM_BYTES := 2715060282
## The texels of paint the fixture's forty-two layers hold, 1805 chunks of 256.
const FIXTURE_PAINTED := 118292480


func after_each() -> void:
    SaCardMemory.stand_in(-1)


## the 4096 painting, forty canvases of paint, is the figure the note gives:
## 10.75 GiB where the constants read 20.5 before this unit.
func test_forty_canvases_of_paint_at_4096_cost_half_what_they_did() -> void:
    var canvas := Vector2i(SIDE, SIDE)
    var texels := SIDE * SIDE
    var painted := 40 * texels
    var needed := SaCardMemory.for_canvas(canvas, painted)
    assert_eq(needed, texels * 32 + texels * 16 + painted * 16, "the easel, the fold's cache once, and the paint")
    assert_almost_eq(float(needed) / GIB, 10.75, 0.001, "10.75 GiB")
    var before := texels * 32 + painted * 32
    assert_almost_eq(float(before) / GIB, 20.5, 0.001, "where the constants read 20.5 GiB")
    assert_almost_eq(float(before - needed) / GIB, 9.75, 0.001, "9.75 GiB less than today")


## The cache arrives whole with the first painted texel and never again, so an
## empty document is the 32 bytes a canvas texel and a painted one 48.
func test_the_cache_is_charged_once_and_not_to_an_empty_document() -> void:
    var canvas := Vector2i(1024, 1024)
    var texels := 1024 * 1024
    assert_eq(SaCardMemory.for_canvas(canvas), texels * 32, "an empty document is the easel's textures alone")
    assert_eq(SaCardMemory.for_canvas(canvas, 1), texels * 48 + 16, "the first painted texel brings the cache")
    var chunk := SaChunk.SIZE * SaChunk.SIZE
    var one := SaCardMemory.for_canvas(canvas, chunk)
    var two := SaCardMemory.for_canvas(canvas, 2 * chunk)
    assert_eq(two - one, chunk * 16, "and a chunk painted after it adds its 16 bytes a texel and no more")


## What the sentence a refusal gives the painter says, which stays
## exactly as written: only the figure it is handed has changed.
func test_the_refusal_sentence_is_unchanged() -> void:
    var expected := (
        "There is no room on the graphics card for another document. Sara keeps to a budget of %s of the card's"
        + " %s, the open documents hold %s and this one needs %s. Close a document and try again."
    )
    assert_eq(SaCardMemory.NO_ROOM, expected, "the sentence as written")
    SaCardMemory.stand_in(4 << 30)
    assert_eq(SaCardMemory.refusal(1 << 20, 0), "", "nothing is refused while it fits")
    var said := SaCardMemory.refusal(4 << 30, 0)
    assert_true(said.begins_with("There is no room on the graphics card"), "and one that does not reads: %s" % said)
    assert_true(said.contains("the card's 4.0 GiB"), "with the card's memory in it: %s" % said)
    assert_true(said.contains("needs 4.0 GiB"), "and what the document needs: %s" % said)


## The clause the note measures the change by: what `for_sad` asks for and what
## the running app held with the same painting open agree within a tenth.
func test_s_forty_layer_painting_is_within_a_tenth_of_what_the_open_held() -> void:
    var path := ProjectSettings.globalize_path(FIXTURE)
    var header := SaSadFile.header_at(path)
    assert_eq(Vector2i(int(header["width"]), int(header["height"])), Vector2i(SIDE, SIDE), "a 4096 canvas")
    assert_eq(SaTyped.list(header.get("layers")).size(), 42, "the ground, the thirty-nine bands and the background")
    var needed := SaCardMemory.for_sad(path)
    var texels := SIDE * SIDE
    assert_eq(needed, texels * 32 + texels * 16 + FIXTURE_PAINTED * 16, "the easel, the cache once and 1805 chunks")
    var gap := absi(needed - OPEN_VRAM_BYTES)
    assert_true(gap * 10 <= OPEN_VRAM_BYTES, "within a tenth of the open's %d: asked %d" % [OPEN_VRAM_BYTES, needed])
    var before := texels * 32 + FIXTURE_PAINTED * 32
    assert_true(before * 10 > OPEN_VRAM_BYTES * 11, "where the old constants asked for %d, past a tenth over" % before)
