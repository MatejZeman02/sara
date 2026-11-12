## A brush pipe's cells are expanded on the card, not in GDScript.
##
## `SaTipCache` sends each cell of a pipe as the file holds it, one byte a texel
## for a grey pipe and four for a colour one, and `tip_cell.gmacs` makes the
## `r32g32f` tip from them. The tip a stroke binds has to stay what it was, so
## every suite here reads both roads back and holds them equal texel for texel:
## the GDScript road, `SaGihPipe.read_bytes` and `SaTipImage.upload` as a
## single picture tip still loads, and the card's, `SaTipCache.Picture`.
##
## The colour pipe's texels are drawn from a seeded stream, with the corners of
## the colour cube among them, because a colour texel's lightness is a sum of
## three products rounded twice and the card makes those roundings in integers.
## A sum that rounds differently is one texel of thousands, and only a cell that
## holds thousands of colours can show it.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: what is compared is textures.
const REQUIRES_GPU := true

## The seed the colour cells are drawn from, so a failure names a texel that
## the next run draws again.
const SEED := 33007

## Colours every colour cell starts with: black, white, whose luminance sums
## past one before its clamp, each primary at its least and most, and a grey.
const CORNERS: Array[Color] = [
    Color8(0, 0, 0, 0),
    Color8(255, 255, 255, 255),
    Color8(1, 0, 0, 1),
    Color8(0, 1, 0, 254),
    Color8(0, 0, 1, 128),
    Color8(255, 0, 0, 255),
    Color8(0, 255, 0, 255),
    Color8(0, 0, 255, 255),
    Color8(128, 128, 128, 77),
]

## The scratch folder every pipe here is written into and taken out of.
static var scratch_dir: String = SaDataRoot.path("test_d7_tip_cells")


func before_each() -> void:
    SaTipCache.shared().forget()
    DirAccess.make_dir_recursive_absolute(scratch_dir)


func after_each() -> void:
    SaTipCache.shared().forget()
    for file: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file))
    DirAccess.remove_absolute(scratch_dir)


## A `.gih` of one cell a size in *sizes*, *depth* bytes a texel, written as
## *file_name* and answered by path. A grey cell's coverage counts up through
## every byte, and a colour cell's texels are the corners and then the stream.
func _pipe(file_name: String, sizes: Array[Vector2i], depth: int) -> String:
    var random := RandomNumberGenerator.new()
    random.seed = SEED
    var count := sizes.size()
    var line := "%d ncells:%d step:20 dim:1 placement:constant rank0:%d sel0:incremental" % [count, count, count]
    var bytes := ("%s\n%s\n" % [file_name.get_basename(), line]).to_utf8_buffer()
    for index in sizes.size():
        var size := sizes[index]
        var texels := PackedByteArray()
        texels.resize(size.x * size.y * depth)
        for at in texels.size():
            texels[at] = (at * 7 + index) % 256 if depth == 1 else random.randi_range(0, 255)
        if depth == 4:
            for corner in mini(CORNERS.size(), size.x * size.y):
                var colour := CORNERS[corner]
                texels.encode_u32(corner * 4, colour.to_abgr32())
        bytes.append_array(_gbr("cell %d" % index, size, depth, texels))
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


## A version 2 GBR of *size*, *depth* bytes a texel, holding *texels*.
func _gbr(tip_name: String, size: Vector2i, depth: int, texels: PackedByteArray) -> PackedByteArray:
    var named := tip_name.to_utf8_buffer()
    var out := PackedByteArray()
    for word: int in [28 + named.size() + 1, 2, size.x, size.y, depth, SaTipImage.GBR_MAGIC, 20]:
        out.append_array(PackedByteArray([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF]))
    out.append_array(named)
    out.append(0)
    out.append_array(texels)
    return out


## Every cell of *path* as GDScript makes it, read back off the card.
func _the_gdscript_road(path: String) -> Array[PackedByteArray]:
    var pipe := SaGihPipe.read_bytes(FileAccess.get_file_as_bytes(path), path.get_file())
    assert_true(pipe.ok(), "The pipe reads: %s" % pipe.error)
    var out: Array[PackedByteArray] = []
    for tip: SaTipImage.Tip in pipe.tips:
        var texture := SaTipImage.upload(tip)
        out.append(texture.rd.texture_get_data(texture.rid, 0))
    return out


## Every cell of *mask* read back off the card.
func _read_back(mask: SaBrushTipMask) -> Array[PackedByteArray]:
    var out: Array[PackedByteArray] = []
    for cell: SaTexture in mask.pipe_cells:
        assert_eq(cell.format, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, "A cell keeps the tip's format")
        out.append(cell.rd.texture_get_data(cell.rid, 0))
    return out


## *made* against *wanted*, cell by cell, naming the first texel that differs.
func _same(made: Array[PackedByteArray], wanted: Array[PackedByteArray], sizes: Array[Vector2i], what: String) -> void:
    assert_eq(made.size(), wanted.size(), "%s: every cell is made" % what)
    for index in mini(made.size(), wanted.size()):
        if made[index] == wanted[index]:
            assert_true(true)
            continue
        var ours := made[index].to_float32_array()
        var theirs := wanted[index].to_float32_array()
        var first := 0
        while first < mini(ours.size(), theirs.size()) and ours[first] == theirs[first]:
            first += 1
        @warning_ignore("integer_division")
        var texel := first / 2
        @warning_ignore("integer_division")
        var row := texel / sizes[index].x
        assert_true(
            false,
            (
                "%s: cell %d differs first at texel (%d, %d), %s %f on the card and %f in GDScript"
                % [
                    what,
                    index,
                    texel % sizes[index].x,
                    row,
                    "coverage" if first % 2 == 0 else "lightness",
                    ours[first] if first < ours.size() else NAN,
                    theirs[first] if first < theirs.size() else NAN,
                ]
            )
        )


func test_a_grey_pipe_is_the_same_texel_for_texel_both_ways() -> void:
    # Odd sizes among them, so a cell's bytes are not a whole number of words
    # and a cell is not a whole number of workgroups.
    var sizes: Array[Vector2i] = [Vector2i(64, 64), Vector2i(37, 23), Vector2i(1, 1), Vector2i(255, 3)]
    var path := _pipe("grey.gih", sizes, 1)
    var mask := SaTipCache.Picture.new(path).finish()
    assert_true(mask.error.is_empty(), "The grey pipe loads: %s" % mask.error)
    assert_false(mask.colourful, "A grey pipe carries no colour")
    _same(_read_back(mask), _the_gdscript_road(path), sizes, "grey")


func test_a_colour_pipe_is_the_same_texel_for_texel_both_ways() -> void:
    var sizes: Array[Vector2i] = [Vector2i(256, 256), Vector2i(128, 96), Vector2i(3, 5), Vector2i(97, 41)]
    var path := _pipe("colour.gih", sizes, 4)
    var mask := SaTipCache.Picture.new(path).finish()
    assert_true(mask.error.is_empty(), "The colour pipe loads: %s" % mask.error)
    assert_true(mask.colourful, "A colour pipe carries colour")
    _same(_read_back(mask), _the_gdscript_road(path), sizes, "colour")


## The road off the stroke, a share a frame, makes what a press makes, with a
## share's edge falling inside the pipe.
func test_a_pipe_loaded_a_share_a_frame_is_the_same_both_ways() -> void:
    var sizes: Array[Vector2i] = []
    for index in 24:
        sizes.append(Vector2i(256, 256))
    var path := _pipe("shares.gih", sizes, 4)
    var cache := SaTipCache.new()
    cache.ahead(path)
    var deadline := Time.get_ticks_msec() + 60000
    var shares := 0
    while cache.busy() and Time.get_ticks_msec() < deadline:
        cache.pump()
        shares += 1
        OS.delay_msec(2)
    assert_false(cache.busy(), "The load ends")
    assert_true(shares > 2, "The 24 cells went up over more than one share, %d" % shares)
    _same(_read_back(cache.mask_for(path)), _the_gdscript_road(path), sizes, "shares")
    cache.forget()


## The two tables the kernel reads are the CPU's own numbers, and every share
## of the luminance a whole number of two to the minus 64, which is the
## kernel's whole premise: read back, each share times its byte's weight is the
## double `SaTipImage` multiplies.
func test_every_luminance_share_is_a_whole_number_of_its_fixed_point() -> void:
    var table := SaTipCells.share_table()
    var weights := SaTipImage.LUMINANCE_WEIGHTS
    for channel in 3:
        for value in 256:
            var at := (channel * 256 + value) * 8
            var low := table.decode_u32(at)
            var high := table.decode_u32(at + 4)
            var wanted := float(value) / 255.0 * weights[channel]
            # Two to the minus 32 and minus 64, each exact in a double.
            var read := float(high) * 2.3283064365386963e-10 + float(low) * 5.421010862427522e-20
            if read != wanted:
                assert_eq(read, wanted, "share of %d in channel %d" % [value, channel])
                return
    assert_true(true)
