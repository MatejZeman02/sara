## The JPEG XL module in Sara registers a codec the save can
## ask for by name. The module is `modules/sara-jxl`, its library `SaJxl` built
## by `packaging/build.sh modules`, and the codec is asked for as `&"jxl"`
## through [SaCodecRegistry], never by the library's name.
##
## With the module in, four chunks go through the codec and come back byte for
## byte: half and full precision colour, a height chunk and an empty one. With
## it left out, the name answers nothing, and a document saves and opens as it
## did before the unit, the save writing the same bytes whether a codec is
## registered or not, since nothing in the unit asks for one yet.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the colour chunks are a document's own textures.
const REQUIRES_GPU := true

const Kept = preload("res://core/sad-file/tests/test_half_precision_and_the_autosaves_keep_every_bit.gd")
const Rounding = preload("res://core/sad-file/tests/test_a_full_precision_save_rounds_colour_to_12_significant_bits_once.gd")
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

static var scratch: String = SaDataRoot.path("test_no_module.sad")
static var with_codec: String = SaDataRoot.path("test_with_codec.sad")

## The codec registry a save asked when the case began, put back after.
var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _registries.register_builtins()


func after_each() -> void:
    SaSadFile.finish_saves()
    SaCodecRegistry.install(_was_installed)
    _was_installed = null
    _registries = null
    for path: String in [scratch, scratch + "1", with_codec, with_codec + "1"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Registers the JPEG XL module into the suite's registries as the loader does.
func _load_the_module() -> SaModule:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return module


## The four chunks the row names, `[what, texels, channels, bytes a channel]`
## apiece, each the size of a chunk as the document makes one.
static func _chunks() -> Array:
    var rd := GlobalShaderCompiler.get_rd()
    var chunks: Array = []
    for depth: SaColorSpace.Depth in [SaColorSpace.Depth.F16, SaColorSpace.Depth.F32]:
        var doc := Kept.painted(depth)
        var colour := doc.active_layer.get_field(Rounding.POSITIONS[0])
        var layout: Vector2i = SaSadBlob.LAYOUT[colour.format]
        var what := "half precision colour" if layout.y == 2 else "full precision colour"
        chunks.append([what, rd.texture_get_data(colour.rid, 0), colour.size, layout.x, layout.y])
        if depth == SaColorSpace.Depth.F16:
            # The height field is one half float a texel, from below the
            # paper to above it, written here as the card holds it.
            var rng := RandomNumberGenerator.new()
            rng.seed = 203
            var height := PackedByteArray()
            height.resize(colour.size.x * colour.size.y * 2)
            for at in range(0, height.size(), 2):
                height.encode_half(at, rng.randf_range(-2.0, 3.0))
            chunks.append(["height", height, colour.size, 1, 2])
            var empty := PackedByteArray()
            empty.resize(colour.size.x * colour.size.y * layout.x * layout.y)
            chunks.append(["empty", empty, colour.size, layout.x, layout.y])
        doc.free()
    return chunks


func test_the_codec_asked_for_by_name_gives_every_byte_of_four_chunks_back() -> void:
    if not ClassDB.class_exists(&"SaJxl"):
        skip("the JPEG XL library is not built here, packaging/build.sh modules builds it")
        return
    _load_the_module()
    var codec := SaCodecRegistry.shared().named(CODEC)
    assert_not_null(codec, "The JPEG XL module registers a codec the save asks for as 'jxl'")
    if codec == null:
        return
    assert_true(codec == _registries.codecs.named(CODEC), "and it is the app's registry that answers it")
    for chunk: Array in _chunks():
        var what: String = chunk[0]
        var texels: PackedByteArray = chunk[1]
        var size: Vector2i = chunk[2]
        var stream := codec.encode(texels, size.x, size.y, chunk[3], chunk[4])
        assert_true(stream.size() > 0, "The %s chunk codes" % what)
        var back := codec.decode(stream, size.x, size.y, chunk[3], chunk[4])
        assert_eq(back.size(), texels.size(), "The %s chunk decodes to as many bytes as went in" % what)
        assert_true(back == texels, "and every decoded byte of the %s chunk is the byte put in" % what)


func test_with_the_module_left_out_no_codec_answers_the_name() -> void:
    assert_null(_registries.codecs.named(CODEC), "With no module the app's registry holds no 'jxl'")
    assert_null(SaCodecRegistry.shared().named(CODEC), "and the registry a save asks answers none")
    SaCodecRegistry.install(null)
    assert_null(SaCodecRegistry.shared().named(CODEC), "and with no app at all none either")


func test_a_module_that_unloads_takes_its_codec_with_it() -> void:
    if not ClassDB.class_exists(&"SaJxl"):
        skip("the JPEG XL library is not built here, packaging/build.sh modules builds it")
        return
    var module := _load_the_module()
    assert_not_null(_registries.codecs.named(CODEC), "The module's codec is registered")
    module.context.remove_all_registrations()
    assert_null(_registries.codecs.named(CODEC), "and gone once the module unloads")


func test_a_document_saved_and_opened_with_no_module_reads_as_it_did_before() -> void:
    var source := Kept.painted(SaColorSpace.Depth.F16)
    var before := Kept.colour_of(source)
    assert_true(Rounding.save_as_the_painter(source, scratch), "The save with no module lands")
    var back := Rounding.reopened(scratch)
    assert_not_null(back, "and the file opens")
    if back != null:
        assert_eq(Kept.colour_of(back), before, "and reads bit for bit as painted")
        back.free()
    if ClassDB.class_exists(&"SaJxl"):
        _load_the_module()
        assert_true(Rounding.save_as_the_painter(source, with_codec), "The save with the codec registered lands")
        assert_eq(
            FileAccess.get_file_as_bytes(with_codec),
            FileAccess.get_file_as_bytes(scratch),
            "and writes the bytes the save with no module wrote, since nothing asks for the codec yet"
        )
    source.free()
