## `read_pixels` with `max_size` makes the layer smaller and
## eight bits a channel on the graphics card, so a notebook's picture of a 1920
## by 1080 layer crosses as 512 by 288 bytes rather than 33 MB of float32.
##
## Every chunk is cleared to one colour, so the full read's mean is the colour of
## each chunk weighted by the texels it has inside the rectangle, read out of
## the full read itself, and the preview is graded against that.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const LayerPreview = preload("res://harness/sa_layer_preview.gd")

## Needs a RenderingDevice, because every case reads chunks back.
const REQUIRES_GPU := true

## The lab's screen, which the note measured the delay on.
const SIZE := Vector2i(1920, 1080)


## The small form of a 1920 by 1080 layer at 512 is 512 by 288 bytes whose mean
## is the full read's to within one step of eight bits, and it made no float
## readback, where the full read made one.
func test_a_small_read_is_eight_bits_at_512_and_its_mean_is_the_full_reads() -> void:
    var doc := _document()
    var layer := doc.active_layer
    var side := layer.CHUNK_SIZE
    var grid := Vector2i(ceili(SIZE.x / float(side)), ceili(SIZE.y / float(side)))
    for gy in grid.y:
        for gx in grid.x:
            layer.get_or_create_chunk(Vector2i(gx, gy)).albedo().clear(_colour_of(gx, gy))
    var folder := _folder()
    var rect := [0, 0, SIZE.x, SIZE.y]

    var before := PixelDriver.float_reads
    var asked := {"layer": String(layer.name), "rect": rect, "max_size": 512, "file": "small.npy"}
    var small := PixelDriver.read_into(doc, asked, folder)
    assert_false(small.has("error"), "the small read answers without a refusal: %s" % small)
    assert_eq(PixelDriver.float_reads, before, "the small read made no float readback")
    assert_eq(small["shape"], [288, 512, 4], "the long side is 512 and the short one in proportion")
    assert_eq(small["dtype"], "uint8", "and the answer says the bytes are eight bits")
    assert_eq(small["from"], [1920, 1080], "made from the whole rectangle")
    var bytes := _body(String(small["path"]), "|u1")
    assert_eq(bytes.size(), 512 * 288 * 4, "the file holds 512 by 288 texels of four bytes, about 590 KB")

    var full := PixelDriver.read_into(doc, {"layer": String(layer.name), "rect": rect, "file": "full.npy"}, folder)
    assert_eq(PixelDriver.float_reads, before + 1, "the full read is the one float readback")
    var floats := _body(String(full["path"]), "<f4")
    assert_eq(floats.size(), SIZE.x * SIZE.y * 16, "and holds the whole layer in float32")

    var want := _full_mean(floats, grid, side)
    var got := _byte_mean(bytes)
    for channel in 4:
        assert_true(
            absf(got[channel] - want[channel]) <= 1.0,
            (
                "channel %d of the preview averages %.3f where the full read's eight bits average %.3f"
                % [channel, got[channel], want[channel]]
            )
        )
    doc.free()
    _clear(folder)


## The size rule: the long side is the number asked for, the short one in
## proportion and never under a texel, and a smaller rectangle is not enlarged.
func test_the_preview_keeps_the_proportion_and_never_enlarges() -> void:
    assert_eq(LayerPreview.size_for(Vector2i(1920, 1080), 512), Vector2i(512, 288), "landscape")
    assert_eq(LayerPreview.size_for(Vector2i(100, 4000), 512), Vector2i(13, 512), "portrait")
    assert_eq(LayerPreview.size_for(Vector2i(300, 200), 512), Vector2i(300, 200), "already small")
    assert_eq(LayerPreview.size_for(Vector2i(5000, 1), 512), Vector2i(512, 1), "a line keeps one texel")


## A small read over no paint is zero bytes and allocates nothing, and a
## `max_size` that is no whole number above zero is refused by name.
func test_a_small_read_over_no_paint_is_zeros_and_a_bad_size_is_refused() -> void:
    var doc := _document()
    var folder := _folder()
    var answer := PixelDriver.read_into(doc, {"rect": [100, 100, 600, 40], "max_size": 300, "file": "empty.npy"}, folder)
    assert_eq(answer["shape"], [20, 300, 4], "600 by 40 at 300 is 300 by 20")
    var bytes := _body(String(answer["path"]), "|u1")
    var zeros := PackedByteArray()
    zeros.resize(300 * 20 * 4)
    assert_eq(bytes, zeros, "and every byte is zero")
    for bad: Variant in [0, -4, 1.5, "big"]:
        var refused := PixelDriver.read_into(doc, {"rect": [0, 0, 8, 8], "max_size": bad}, folder)
        assert_true(String(refused.get("error", "")).contains("max_size"), "max_size %s is refused by name" % [bad])
    doc.free()
    _clear(folder)


## The chunk at *gx*, *gy*'s colour: values above one and below zero among
## them, which the preview clips the way `sara.tone_map` does, and an alpha
## that varies too.
func _colour_of(gx: int, gy: int) -> Color:
    if gx == 0 and gy == 0:
        return Color(2.0, -0.5, 0.5, 1.0)
    return Color(gx / 8.0, gy / 5.0, 0.3 + 0.07 * ((gx + gy) % 5), 0.5 if (gx + gy) % 2 == 1 else 1.0)


## The mean of each channel of the full read narrowed to eight bits, as
## `sara.tone_map` narrows it: one texel of each chunk read out of the file,
## weighted by the texels the chunk has inside the layer's 1920 by 1080.
func _full_mean(floats: PackedByteArray, grid: Vector2i, side: int) -> Array[float]:
    var sums: Array[float] = [0.0, 0.0, 0.0, 0.0]
    for gy in grid.y:
        for gx in grid.x:
            var origin := Vector2i(gx, gy) * side
            var count := mini(side, SIZE.x - origin.x) * mini(side, SIZE.y - origin.y)
            var offset := (origin.y * SIZE.x + origin.x) * 16
            for channel in 4:
                var value := floats.decode_float(offset + channel * 4)
                sums[channel] += roundf(clampf(value, 0.0, 1.0) * 255.0) * count
    var total := float(SIZE.x * SIZE.y)
    return [sums[0] / total, sums[1] / total, sums[2] / total, sums[3] / total]


func _byte_mean(bytes: PackedByteArray) -> Array[float]:
    var sums: Array[float] = [0.0, 0.0, 0.0, 0.0]
    for at in bytes.size():
        sums[at % 4] += bytes[at]
    var total := bytes.size() / 4.0
    return [sums[0] / total, sums[1] / total, sums[2] / total, sums[3] / total]


## The body of the `.npy` at *path*, its header said to hold *descr*.
func _body(path: String, descr: String) -> PackedByteArray:
    var bytes := FileAccess.get_file_as_bytes(path)
    var length := bytes.decode_u16(8)
    var text := bytes.slice(10, 10 + length).get_string_from_ascii()
    assert_true(text.contains("'descr': '%s'" % descr), "the file holds %s: %s" % [descr, text])
    return bytes.slice(10 + length)


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-d60-preview-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    return folder


func _clear(folder: String) -> void:
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)
