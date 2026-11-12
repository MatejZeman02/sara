## The pattern resource, its three loaders, its store and its chooser.
##
## Every clause of the unit's Done-when is a test here: the store lists the
## shipped patterns and one this file adds from a PNG, each answers a
## texture of its tile size, a generated pattern regenerates at a second size
## without a file, the chooser shows them, and a preset round-trips the name.
## The PNG and the broken kernel are written by the test rather than committed,
## to `user://`, which the offscreen runner points at the checkout's own
## gitignored `scratch/`.
##
## **The `.pat` tests write their own files too**, from GIMP's header rather
## than from a paper anybody shipped, so a channel count and a truncation are
## a few bytes here rather than a binary in the tree. The one binary is
## `fixtures/sara-pat-paper.kpp`, which the scenario imports, and the last
## test below writes the same preset again and reads both back so the
## committed file cannot drift from the writer above it.
extends "res://tests/test_framework.gd"

## A pattern is a texture, and a generated one is a dispatch.
const REQUIRES_GPU := true

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_patterns")
static var scratch_preset_dir: String = SaDataRoot.path("test_pattern_presets")
const PNG_NAME := "scanned_paper.png"
const BROKEN_NAME := "no_pixel.gmacs"

## The `.kpp` writer's own pieces, and the committed preset the scenario
## imports. `Fixtures` is preloaded for its preset XML and its `.kpp` wrapper,
## which are the two halves of Krita's file format and are written once in the
## tree rather than twice.
const Fixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const FIXTURES_DIR := "res://modules/sara-base-modules/stamp-brush/tests/fixtures"
const PAT_KPP_COMMITTED := FIXTURES_DIR + "/sara-pat-paper.kpp"
const PAT_KPP_NAME := "Sara fixture paper"
const PAT_FILE := "sara-fixture-paper.pat"
static var scratch_pat_kpp_path := scratch_dir + "/sara-pat-paper.kpp"

## The paper the committed preset carries: one channel, a side of 64, a weave
## of dark threads over a light ground, so a stroke shot over it shows a grain
## rather than a flat wash.
const PAPER_SIDE := 64
const PAPER_GROUND := 235
const PAPER_THREAD := 90

## The ones the module ships, as the store names them, in the store's order.
## What the lit grain is on its own is `test_lit_grain.gd`.
const SHIPPED: Array[String] = ["Canvas Scumble", "Canvas Weave", "Dot Screen", "Lit Grain", "Paper Grain"]

const R32F := RenderingDevice.DATA_FORMAT_R32_SFLOAT


func after_each() -> void:
    for folder: String in [scratch_dir, scratch_preset_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)


## Four texels: white, black, mid grey and a transparent white. Under luminance
## times alpha the first is one, the second nought, the third a half and the
## fourth nought, which is the polarity a paper has: white is where paint lands.
func _write_png() -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
    image.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
    image.set_pixel(1, 0, Color(0.0, 0.0, 0.0, 1.0))
    image.set_pixel(0, 1, Color(0.5, 0.5, 0.5, 1.0))
    image.set_pixel(1, 1, Color(1.0, 1.0, 1.0, 0.0))
    var path := scratch_dir.path_join(PNG_NAME)
    image.save_png(path)
    return path


func _write_broken() -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(BROKEN_NAME)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("uniform float level = 0.5\n\nvec4 c = vec4(level)\n")
    file.close()
    return path


func _shipped_store() -> SaPatternStore:
    return SaPatternStore.new([SaPatternStore.SHIPPED_DIR])


func _both_store() -> SaPatternStore:
    return SaPatternStore.new([SaPatternStore.SHIPPED_DIR, scratch_dir])


## One texel of an `r32f` texture, read back the way the export path reads.
func _texel(texture: SaTexture, at: Vector2i) -> float:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float((at.y * texture.size.x + at.x) * 4)


func _range_of(texture: SaTexture) -> Vector2:
    var floats := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
    var low := 1e9
    var high := -1e9
    for value in floats:
        low = minf(low, value)
        high = maxf(high, value)
    return Vector2(low, high)


# --- The store -----------------------------------------------------------------


func test_the_store_lists_the_shipped_patterns() -> void:
    var store := _shipped_store()
    assert_eq(Array(store.names()), Array(SHIPPED), "every kernel in the module's patterns folder, sorted by name")
    for pattern_name in SHIPPED:
        assert_true(store.has(pattern_name), "%s is there" % pattern_name)
        assert_true(store.pattern(pattern_name).is_generated(), "and is a kernel rather than a picture")
    assert_null(store.pattern("Nothing"), "a name no file has answers null")


func test_the_store_lists_one_the_test_adds_from_a_png() -> void:
    _write_png()
    var store := _both_store()
    assert_eq(store.names().size(), SHIPPED.size() + 1, "the shipped ones and the one written")
    var scanned := store.pattern("Scanned Paper")
    assert_not_null(scanned, "under its stem made readable")
    assert_false(scanned.is_generated(), "a picture rather than a kernel")
    assert_eq(SaPatternStore.name_for("paper_grain.gmacs"), "Paper Grain", "the naming rule, on its own")


func test_a_file_added_while_the_store_lives_is_seen_after_a_rescan() -> void:
    var store := _both_store()
    assert_eq(store.names().size(), SHIPPED.size(), "before the file exists")
    _write_png()
    assert_eq(store.names().size(), SHIPPED.size(), "a listed store does not read the disk again by itself")
    store.rescan()
    assert_eq(store.names().size(), SHIPPED.size() + 1, "and does after a rescan")


# --- The textures ----------------------------------------------------------------


func test_each_shipped_pattern_answers_a_texture_of_its_tile_size() -> void:
    var store := _shipped_store()
    for pattern_name in SHIPPED:
        var pattern := store.pattern(pattern_name)
        var texture := pattern.texture()
        assert_not_null(texture, "%s compiles and runs: %s" % [pattern_name, pattern.error])
        if texture == null:
            continue
        assert_eq(texture.size, Vector2i(SaPattern.DEFAULT_TILE, SaPattern.DEFAULT_TILE), "%s is one tile across" % pattern_name)
        assert_eq(texture.format, R32F, "%s is coverage, one channel" % pattern_name)
        assert_true(pattern.texture() == texture, "the second ask answers the first texture")
        var span := _range_of(texture)
        assert_true(span.x >= 0.0 and span.y <= 1.0, "%s stays inside nought to one (%s)" % [pattern_name, str(span)])
        assert_true(span.y - span.x > 0.1, "%s is not a flat tile (%s)" % [pattern_name, str(span)])


func test_the_dot_screen_is_one_on_a_dot_and_nought_between() -> void:
    var pattern := _shipped_store().pattern("Dot Screen")
    var texture := pattern.texture()
    assert_not_null(texture, "the dot screen runs: %s" % pattern.error)
    if texture == null:
        return
    # Eight dots across 256 texels is a cell of 32, so the first disc is centred
    # at 16 and the corner between four discs is at 0.
    assert_almost_eq(_texel(texture, Vector2i(16, 16)), 1.0, 0.01, "the centre of the first disc")
    assert_almost_eq(_texel(texture, Vector2i(0, 0)), 0.0, 0.01, "the corner between discs")
    assert_almost_eq(_texel(texture, Vector2i(255, 255)), 0.0, 0.01, "and the far corner, which is the same corner once tiled")


func test_the_canvas_weave_never_reaches_nought() -> void:
    var pattern := _shipped_store().pattern("Canvas Weave")
    var texture := pattern.texture()
    assert_not_null(texture, "the weave runs: %s" % pattern.error)
    if texture == null:
        return
    var span := _range_of(texture)
    assert_true(span.x > 0.3, "a canvas takes some paint everywhere (%s)" % str(span))
    assert_almost_eq(span.y, 1.0, 0.01, "and the top of a thread takes it all")


func test_a_generated_pattern_regenerates_at_a_second_size_without_a_file() -> void:
    var pattern := _shipped_store().pattern("Dot Screen")
    var tile := pattern.texture()
    var small := pattern.generate(Vector2i(64, 64))
    assert_not_null(small, "a second size comes out of the same kernel: %s" % pattern.error)
    if small == null or tile == null:
        return
    assert_eq(small.size, Vector2i(64, 64), "at the size asked")
    assert_true(small != tile, "as a texture of its own")
    assert_true(pattern.texture() == tile, "and the tile-size one is untouched")
    # `tile` followed the size, so eight discs still cross the tile: a cell of 8
    # with the first disc centred at 4.
    assert_almost_eq(_texel(small, Vector2i(4, 4)), 1.0, 0.01, "the first disc is where it is at 256, scaled")
    assert_almost_eq(_texel(small, Vector2i(0, 0)), 0.0, 0.01, "and the corner is still between discs")
    var picture := pattern.image_at(32)
    assert_not_null(picture, "a chooser's picture is a third size")
    assert_eq(picture.get_size(), Vector2i(32, 32), "at the size the cell asked")
    # Eight discs across 32 texels is a cell of 4: the centre of the first disc
    # is texel 2 and the corner between discs is texel 0.
    assert_true(picture.get_pixel(2, 2).r > 0.9, "the picture is the pattern, a disc where the tile has one")
    assert_true(picture.get_pixel(0, 0).r < 0.1, "and nothing between the discs")


func test_a_picture_pattern_answers_its_own_size_and_the_mask_rule() -> void:
    _write_png()
    var pattern := _both_store().pattern("Scanned Paper")
    var texture := pattern.texture()
    assert_not_null(texture, "the PNG uploads: %s" % pattern.error)
    if texture == null:
        return
    assert_eq(texture.size, Vector2i(2, 2), "at the picture's own size")
    assert_eq(pattern.texture_size(), Vector2i(2, 2), "which is what the size asks answers")
    assert_almost_eq(_texel(texture, Vector2i(0, 0)), 1.0, 0.01, "white is one, where paint lands")
    assert_almost_eq(_texel(texture, Vector2i(1, 0)), 0.0, 0.01, "black is nought")
    assert_almost_eq(_texel(texture, Vector2i(0, 1)), 0.5, 0.02, "a mid grey is a half, as encoded")
    assert_almost_eq(_texel(texture, Vector2i(1, 1)), 0.0, 0.01, "and a transparent texel is nought however light")
    assert_null(pattern.generate(Vector2i(64, 64)), "a picture has one size")
    assert_true(pattern.error.contains("one size"), "and says so")


func test_a_kernel_without_the_function_answers_no_texture_and_names_itself() -> void:
    _write_broken()
    var pattern := _both_store().pattern("No Pixel")
    assert_not_null(pattern, "the file is listed, because the store reads names and not kernels")
    assert_null(pattern.texture(), "and answers no texture")
    assert_true(pattern.error.contains(BROKEN_NAME), "the error names the file: %s" % pattern.error)
    assert_true(pattern.error.contains("def pixel"), "and the function it lacks")


func test_the_shipped_kernels_declare_the_tile_uniform() -> void:
    for pattern_name in SHIPPED:
        var pattern := _shipped_store().pattern(pattern_name)
        var kernel := SaPatternKernel.new(pattern.source)
        assert_true(kernel.declares(SaPatternKernel.TILE_UNIFORM), "%s wraps at its edge" % pattern_name)
        assert_true(pattern.kernel_uniforms().size() >= 2, "and has at least one slider of its own")


# --- The preset ------------------------------------------------------------------


func test_a_preset_round_trips_the_pattern_name() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var settings := SettingsScript.new()
    assert_eq(settings.pattern_name, "", "a new brush has no pattern, which is what an older preset loads as")
    settings.pattern_name = "Paper Grain"
    assert_eq(store.save_preset("Grainy", settings), "Grainy", "saved under its name")
    var loaded := store.load_preset("Grainy")
    assert_not_null(loaded, "and loads")
    if loaded == null:
        return
    assert_eq(loaded.pattern_name, "Paper Grain", "with the pattern's name on it")
    var target := SettingsScript.new()
    SaPresetStore.copy_settings(loaded, target)
    assert_eq(target.pattern_name, "Paper Grain", "and the copy onto a live brush carries it")


# --- The chooser -----------------------------------------------------------------


func test_the_chooser_shows_every_pattern_and_picks_one() -> void:
    _write_png()
    var chooser := SaPatternChooser.new(_both_store(), 48)
    assert_eq(chooser.visible_names().size(), SHIPPED.size() + 1, "a cell per pattern")
    var report := chooser.chooser_report()
    assert_eq(int(report["drawn"]), SHIPPED.size() + 1, "every cell has its picture: %s" % str(report["errors"]))
    assert_eq(int(report["icon_size"]), 48, "at the size it was built at")
    assert_eq(String(report["selected"]), "", "nothing pressed yet")

    var chosen: Array[String] = []
    chooser.pattern_chosen.connect(func(pattern_name: String) -> void: chosen.append(pattern_name))
    chooser.pick("Dot Screen")
    assert_eq(chooser.selected, "Dot Screen", "pressed")
    assert_eq(chosen, ["Dot Screen"] as Array[String], "and the host told")
    chooser.pick("Nothing")
    assert_eq(chooser.selected, "", "a name the store lacks clears the choice")

    chooser.icon_size = 96
    chooser.refresh()
    assert_eq(int(chooser.chooser_report()["drawn"]), SHIPPED.size() + 1, "the grid draws again at a second size")
    chooser.free()


# --- The GIMP pattern --------------------------------------------


## A `.pat` from the format: six big-endian words, the name terminated, then
## *texels* row by row. Written here rather than committed so a test can say
## what a channel count and a truncation do in a few bytes.
static func _pat_bytes(width: int, height: int, channels: int, pat_name: String, texels: PackedByteArray) -> PackedByteArray:
    var name_bytes := pat_name.to_utf8_buffer()
    name_bytes.append(0)
    var out := PackedByteArray()
    var header := [
        SaPatternPat.HEADER_BYTES + name_bytes.size(),
        SaPatternPat.VERSION,
        width,
        height,
        channels,
        SaPatternPat.MAGIC,
    ]
    for word: int in header:
        out.append_array(PackedByteArray([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF]))
    out.append_array(name_bytes)
    out.append_array(texels)
    return out


## The committed preset's paper: a 64 by 64 one-channel weave.
static func _paper_pat() -> PackedByteArray:
    var texels := PackedByteArray()
    texels.resize(PAPER_SIDE * PAPER_SIDE)
    for y in PAPER_SIDE:
        for x in PAPER_SIDE:
            var on_thread := (x % 8) < 2 or (y % 8) < 2
            texels[y * PAPER_SIDE + x] = PAPER_THREAD if on_thread else PAPER_GROUND
    return _pat_bytes(PAPER_SIDE, PAPER_SIDE, 1, "Sara fixture paper", texels)


## The `.kpp` the scenario imports: a round tip with the texture block on and
## the paper above embedded as a `patterns` resource, which is the shape a
## Krita preset carrying one of Krita's bundled papers has.
static func _pat_kpp() -> PackedByteArray:
    var paper := _paper_pat()
    var params: Dictionary = Fixtures._common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="60"/> </Brush>'
        )
    ]
    params["Texture/Pattern/Enabled"] = ["internal", "true"]
    params["Texture/Pattern/PatternFileName"] = ["string", PAT_FILE]
    params["Texture/Pattern/Strength"] = ["internal", "1"]
    var resources := [{"name": PAT_FILE.get_basename(), "filename": PAT_FILE, "type": "patterns", "bytes": paper}]
    return Fixtures._kpp(Fixtures._preset_xml(PAT_KPP_NAME, params, resources), "zTXt")


func _write_scratch(file_name: String, bytes: PackedByteArray) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


## One channel is a grey read straight, which is a paper's polarity: white is
## where the paint lands, exactly as a PNG pattern is read.
func test_a_one_channel_pat_reads_as_its_greys() -> void:
    var bytes := _pat_bytes(2, 2, 1, "Rough Paper", PackedByteArray([255, 0, 128, 64]))
    var pat := SaPatternPat.read_bytes(bytes, "rough.pat")
    assert_true(pat.ok(), "a one-channel .pat is read: %s" % pat.error)
    if not pat.ok():
        return
    assert_eq(pat.image.get_size(), Vector2i(2, 2), "at the size the header states")
    assert_eq(pat.pat_name, "Rough Paper", "under the name between the header and the rows")
    var mask := SaPatternImage.mask_of(pat.image)
    assert_almost_eq(mask.get_pixel(0, 0).r, 1.0, 0.01, "255 is one, where the paint lands")
    assert_almost_eq(mask.get_pixel(1, 0).r, 0.0, 0.01, "0 is nought")
    assert_almost_eq(mask.get_pixel(0, 1).r, 0.502, 0.02, "128 is a half, as encoded")
    assert_almost_eq(mask.get_pixel(1, 1).r, 0.251, 0.02, "and 64 is a quarter")


## Three channels are a colour pattern read as its luminance, which is the
## picture loader's one rule and not a second one written here.
func test_a_three_channel_pat_reads_as_its_luminance() -> void:
    var texels := PackedByteArray([255, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0])
    var bytes := _pat_bytes(2, 2, 3, "Coloured Paper", texels)
    var pat := SaPatternPat.read_bytes(bytes, "coloured.pat")
    assert_true(pat.ok(), "a three-channel .pat is read: %s" % pat.error)
    if not pat.ok():
        return
    assert_eq(pat.image.get_size(), Vector2i(2, 2), "at the size the header states")
    assert_eq(pat.pat_name, "Coloured Paper", "under its own name")
    var mask := SaPatternImage.mask_of(pat.image)
    assert_almost_eq(mask.get_pixel(0, 0).r, 1.0, 0.01, "white is one")
    assert_almost_eq(mask.get_pixel(1, 0).r, 0.0, 0.01, "black is nought")
    assert_almost_eq(mask.get_pixel(0, 1).r, SaPatternImage.LUMINANCE.x, 0.02, "red is Rec. 709's red weight")
    assert_almost_eq(mask.get_pixel(1, 1).r, SaPatternImage.LUMINANCE.y, 0.02, "and green is its green weight")


## Two and four channels carry an alpha, and a transparent texel is nought
## however light it is, which is the same clause the PNG mask rule has.
func test_the_alpha_channels_multiply_in() -> void:
    var grey_alpha := SaPatternPat.read_bytes(_pat_bytes(2, 1, 2, "Grey", PackedByteArray([255, 255, 255, 0])), "ga.pat")
    assert_true(grey_alpha.ok(), "a two-channel .pat is read: %s" % grey_alpha.error)
    var rgba := SaPatternPat.read_bytes(
        _pat_bytes(2, 1, 4, "Colour", PackedByteArray([255, 255, 255, 255, 255, 255, 255, 0])), "rgba.pat"
    )
    assert_true(rgba.ok(), "and so is a four-channel one: %s" % rgba.error)
    if not grey_alpha.ok() or not rgba.ok():
        return
    for mask: Image in [SaPatternImage.mask_of(grey_alpha.image), SaPatternImage.mask_of(rgba.image)]:
        assert_almost_eq(mask.get_pixel(0, 0).r, 1.0, 0.01, "an opaque white is one")
        assert_almost_eq(mask.get_pixel(1, 0).r, 0.0, 0.01, "and a transparent white is nought")


## Every refusal names the file and the field that disagreed, the way the tip
## loader refuses an `.abr`, because a truncated header and a wrong magic word
## are different faults and a blank paper says neither.
func test_a_file_the_header_does_not_describe_is_refused_by_name() -> void:
    var flat := PackedByteArray()
    flat.resize(16)
    flat.fill(128)
    var whole := _pat_bytes(4, 4, 1, "Paper", flat)

    var truncated := SaPatternPat.read_bytes(whole.slice(0, whole.size() - 6), "cut.pat")
    assert_false(truncated.ok(), "a file that stops inside its rows is no pattern")
    assert_true(truncated.error.contains("cut.pat"), "naming the file: %s" % truncated.error)
    assert_true(truncated.error.contains("holds"), "and how many bytes it holds: %s" % truncated.error)

    var short_header := SaPatternPat.read_bytes(whole.slice(0, 12), "stub.pat")
    assert_false(short_header.ok(), "a file shorter than the header is refused")
    assert_true(short_header.error.contains("too short"), "saying so: %s" % short_header.error)

    var wrong_magic := whole.duplicate()
    wrong_magic[20] = 0x00
    var refused := SaPatternPat.read_bytes(wrong_magic, "notapat.pat")
    assert_false(refused.ok(), "a file with no GPAT is not a .pat whatever it is called")
    assert_true(refused.error.contains("GPAT"), "and the message says which word is missing: %s" % refused.error)

    var wrong_version := whole.duplicate()
    wrong_version[7] = 9
    assert_true(SaPatternPat.read_bytes(wrong_version, "v9.pat").error.contains("version 9"), "a version the format has not got")

    var wrong_channels := whole.duplicate()
    wrong_channels[19] = 7
    assert_true(
        SaPatternPat.read_bytes(wrong_channels, "seven.pat").error.contains("7 channels"), "and a texel of seven channels"
    )


## The store lists a `.pat` beside a PNG and a kernel, and the pattern reads
## its texture through the picture loader's upload.
func test_the_store_lists_a_pat_and_it_answers_a_texture() -> void:
    _write_scratch("rough_paper.pat", _pat_bytes(2, 2, 1, "Rough Paper", PackedByteArray([255, 0, 128, 64])))
    assert_true(SaPatternStore.is_pattern_file("anything.pat"), "a .pat is a file a pattern can come from")
    assert_true(SaPatternStore.is_pattern_file("ANYTHING.PAT"), "whatever case it is written in")
    var pattern := _both_store().pattern("Rough Paper")
    assert_not_null(pattern, "listed under its file's stem rather than the name in its header")
    if pattern == null:
        return
    assert_false(pattern.is_generated(), "a picture rather than a kernel")
    var texture := pattern.texture()
    assert_not_null(texture, "the .pat uploads: %s" % pattern.error)
    if texture == null:
        return
    assert_eq(texture.size, Vector2i(2, 2), "at the pattern's own size")
    assert_eq(texture.format, R32F, "as coverage, one channel")
    assert_almost_eq(_texel(texture, Vector2i(0, 0)), 1.0, 0.01, "white is one, where paint lands")
    assert_almost_eq(_texel(texture, Vector2i(1, 1)), 0.251, 0.02, "and a quarter grey is a quarter")


## A `.pat` the reader refuses is a pattern with no texture and the reader's
## own reason on it, not "could not be read".
func test_a_broken_pat_in_the_store_quotes_the_readers_reason() -> void:
    _write_scratch("torn_paper.pat", _pat_bytes(4, 4, 1, "Torn", PackedByteArray([1, 2, 3, 4])))
    var pattern := _both_store().pattern("Torn Paper")
    assert_not_null(pattern, "the file is listed, because the store reads names and not headers")
    if pattern == null:
        return
    assert_null(pattern.texture(), "and answers no texture")
    assert_true(pattern.error.contains("torn_paper.pat"), "the error names the file: %s" % pattern.error)
    assert_true(pattern.error.contains("wants"), "and the length that disagreed: %s" % pattern.error)


## The Krita import writes a preset's embedded `.pat` where the store lists it
## and stops tagging the preset "not carried: pattern pat".
func test_the_import_carries_a_pat_paper() -> void:
    var kpp := _write_scratch("sara-pat-paper.kpp", _pat_kpp())
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var results := SaKppImport.import_path(kpp, store, SettingsScript.new())
    assert_eq(results.size(), 1, "one preset read")
    if results.is_empty():
        return
    var described := SaKppImport.describe(results[0])
    assert_false(described.contains("pattern pat"), "and its paper carries: %s" % described)

    var loaded := store.load_preset(PAT_KPP_NAME)
    assert_not_null(loaded, "the preset is stored")
    if loaded == null:
        return
    assert_eq(loaded.pattern_name, SaPatternStore.name_for(PAT_FILE), "naming the paper as the store lists it")
    var written := SaPatternStore.saved_dir().path_join(PAT_FILE)
    assert_true(FileAccess.file_exists(written), "the .pat itself is in the painter's patterns folder")
    var pattern := SaPattern.new(loaded.pattern_name, written)
    assert_eq(pattern.texture_size(), Vector2i(PAPER_SIDE, PAPER_SIDE), "and reads at the size the fixture wrote")
    DirAccess.remove_absolute(written)


## A preset whose embedded `.pat` is corrupt keeps the tag rather than landing
## with a paper that paints nothing.
func test_the_import_refuses_a_corrupt_pat_and_keeps_the_tag() -> void:
    var params: Dictionary = Fixtures._common_params()
    params["Texture/Pattern/Enabled"] = ["internal", "true"]
    params["Texture/Pattern/PatternFileName"] = ["string", "broken.pat"]
    var resources := [{"name": "broken", "filename": "broken.pat", "type": "patterns", "bytes": _paper_pat().slice(0, 40)}]
    var xml: String = Fixtures._preset_xml("Sara broken paper", params, resources)
    var kpp := _write_scratch("broken-pat.kpp", Fixtures._kpp(xml, "zTXt"))
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var results := SaKppImport.import_path(kpp, store, SettingsScript.new())
    assert_eq(results.size(), 1, "one preset read")
    if results.is_empty():
        return
    assert_true(SaKppImport.describe(results[0]).contains("pattern pat"), "tagged, because the header does not describe the file")
    assert_false(FileAccess.file_exists(SaPatternStore.saved_dir().path_join("broken.pat")), "and nothing was written")


## The committed fixture the scenario imports is the one the writer above
## makes, which is what keeps a binary in the tree from drifting.
func test_the_committed_pat_preset_is_the_written_one() -> void:
    var written := SaKppReader.read_file(_write_scratch("sara-pat-paper-check.kpp", _pat_kpp()))
    var committed := SaKppReader.read_file(PAT_KPP_COMMITTED)
    for key: String in ["name", "engine", "options", "error"]:
        assert_eq(committed[key], written[key], "sara-pat-paper.kpp agrees on %s" % key)
    var resource: Dictionary = (committed["resources"] as Dictionary)[PAT_FILE.get_basename()]
    assert_eq(String(resource["type"]), "patterns", "the paper rides as a patterns resource")
    var pat := SaPatternPat.read_bytes(resource["bytes"], PAT_FILE)
    assert_true(pat.ok(), "and reads as a .pat: %s" % pat.error)
    if pat.ok():
        assert_eq(pat.image.get_size(), Vector2i(PAPER_SIDE, PAPER_SIDE), "at the side the writer chose")
