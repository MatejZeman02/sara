## Tests for document format import/export operations and SettingsWindow logic.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")


func test_settings_window_creation() -> void:
    # Ensure the settings window instantiates correctly as a Window
    var window := preload("res://ui/settings/sa_settings_window.gd").new()
    assert_true(window is Window, "SaSettingsWindow must inherit from Window")
    assert_eq(window.title, "Preferences", "Title must match")
    # Not exclusive: a Preferences that blocks the parent
    # blocks the canvas beside it, and `ui/settings/tests/test_prefs_modal.gd` is where that
    # invariant is read back in every mode.
    assert_false(window.exclusive, "Must not be exclusive")
    assert_true(window.transient, "and is transient to the window it is about")
    window.free()


func test_document_export_png_jpg_sad() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    # Save .sad file
    var temp_sad_path := SaDataRoot.path("test_document.sad")
    var err: Error = SaExport.save_sad(doc, temp_sad_path)
    assert_eq(err, OK, "Saving .sad should return OK")
    assert_true(FileAccess.file_exists(temp_sad_path), "File test_document.sad should exist on disk")

    # Load .sad file
    var new_doc := SaDocument.new()
    err = SaExport.load_sad(new_doc, temp_sad_path, SaCompositor.new())
    assert_eq(err, OK, "Loading .sad should return OK")
    assert_eq(new_doc.canvas_size, Vector2i(64, 64), "Canvas dimensions should match")
    assert_true(new_doc.get_child_count() > 0, "Loaded document should have layers")
    assert_eq(new_doc.active_layer.blend_mode, SaLayer.BLEND_MODE.NORMAL, "Blend mode should round-trip as stable ID")

    # Clean up temp file
    DirAccess.remove_absolute(temp_sad_path)
    new_doc.free()
    doc.free()


func test_legacy_numeric_blend_mode_migration() -> void:
    assert_eq(SaLayer.blend_mode_from_legacy(1), SaLayer.BLEND_MODE.MULTIPLY, "Legacy numeric blend should migrate")
    assert_eq(SaLayer.blend_mode_from_legacy("overlay"), SaLayer.BLEND_MODE.OVERLAY, "Stable string blend should load")


const HEIGHT_FIELD: StringName = &"height"


func _first_layer(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        if child is SaLayer and child != document.stroke_layer:
            return child as SaLayer
    return null


func test_sad_v4_round_trips_pixels() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    _first_layer(doc).fill(Color(0.25, 0.5, 0.75, 1.0))

    var path := SaDataRoot.path("test_v4_pixels.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saving v4 should return OK")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "Loading v4 should return OK")

    var texture := _first_layer(loaded).get_field(Vector2i.ZERO)
    assert_not_null(texture, "The loaded layer should have the chunk that was saved")
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    assert_almost_eq(data.decode_float(0), 0.25, 0.001, "Red survives the round trip")
    assert_almost_eq(data.decode_float(4), 0.5, 0.001, "Green survives the round trip")
    assert_almost_eq(data.decode_float(8), 0.75, 0.001, "Blue survives the round trip")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()


## The container stores one blob per field of a chunk, so a layer with a second
## field keeps it.
func test_sad_v4_round_trips_every_field_and_the_schema() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    var layer := _first_layer(doc)
    var two_fields: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(),
        SaFieldSpec.create(HEIGHT_FIELD, RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
    ]
    layer.schema = two_fields
    layer.chunks.clear()
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.albedo().clear(Color(1.0, 0.0, 0.0, 1.0))
    chunk.field(HEIGHT_FIELD).clear(Color(0.375, 0.0, 0.0, 0.0))

    var path := SaDataRoot.path("test_v4_fields.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saving a two-field layer should return OK")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "Loading it back should return OK")

    var restored := _first_layer(loaded)
    assert_eq(restored.schema.size(), 2, "The schema itself round-trips, not just the pixels")
    var height_spec := SaFieldSpec.find(restored.schema, HEIGHT_FIELD)
    assert_not_null(height_spec, "The height field is in the restored schema")
    assert_eq(height_spec.format, RenderingDevice.DATA_FORMAT_R32_SFLOAT, "...with its own storage format")
    assert_false(height_spec.is_color, "...and still marked as not colour")

    var rd := GlobalShaderCompiler.get_rd()
    var height := restored.get_field(Vector2i.ZERO, HEIGHT_FIELD)
    assert_not_null(height, "The height field's texture was restored")
    var data: PackedByteArray = rd.texture_get_data(height.rid, 0)
    assert_almost_eq(data.decode_float(0), 0.375, 0.001, "A non-albedo field keeps its values")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()


## Loading called layer.setup(), which allocated the whole chunk grid before
## overwriting it with the stored chunks, so a mostly empty document opened
## with every chunk of every field resident in VRAM.
func test_loading_allocates_only_the_chunks_the_file_holds() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(1024, 1024), SaCompositor.new())

    var layer := _first_layer(doc)
    layer.chunks.clear()
    layer.get_or_create_chunk(Vector2i(2, 3)).clear(Color(0.5, 0.25, 0.125, 1.0))

    var path := SaDataRoot.path("test_v4_sparse.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saving should return OK")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "Loading should return OK")

    var restored := _first_layer(loaded)
    assert_eq(restored.chunks.size(), 1, "A 4x4 grid with one stored chunk loads one chunk, not sixteen")
    assert_true(restored.chunks.has(Vector2i(2, 3)), "...and it is the one that was written")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()


# ---------------------------------------------------------------------------
# The document colour descriptor
# ---------------------------------------------------------------------------


func test_sad_v4_round_trips_the_colour_space() -> void:
    var doc := SaDocument.new()
    var space := SaColorSpace.acescg()
    space.depth = SaColorSpace.Depth.F16
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new(), space)
    assert_true(doc.color_space.matches(space), "setup_default_document must take the space it is given")

    var path := SaDataRoot.path("test_color_space.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saving a document with a colour space should return OK")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and it should load back")
    assert_true(loaded.color_space.matches(space), "ACEScg at F16 must survive the .sad header")
    assert_eq(loaded.color_space.id, SaColorSpace.ID_ACESCG, "under its own id")
    assert_true(loaded.color_space.is_specified, "and as something the file actually declared")

    DirAccess.remove_absolute(path)
    loaded.free()
    doc.free()


func test_a_v4_file_without_a_colour_space_loads_as_unspecified() -> void:
    # The v4 container shipped before the descriptor existed, so files with no
    # colour space are real and must keep opening. Hand-built rather than
    # produced by the writer, because the writer can no longer emit one.
    var header := {
        "format": "sad",
        "version": 4,
        "width": 64,
        "height": 64,
        "layers": [{"name": "Layer 1", "visible": true, "opacity": 1.0, "blend_mode": "normal", "chunks": []}],
    }
    var header_raw := JSON.stringify(header).to_utf8_buffer()
    var header_packed := header_raw.compress(FileAccess.COMPRESSION_ZSTD)

    var path := SaDataRoot.path("test_no_color_space.sad")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer("SAD2".to_ascii_buffer())
    file.store_32(4)
    file.store_32(header_packed.size())
    file.store_32(header_raw.size())
    file.store_buffer(header_packed)
    file.close()

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "A v4 file with no colour space must open")
    assert_false(loaded.color_space.is_specified, "and must not claim the file declared one")
    assert_true(loaded.color_space.matches(SaColorSpace.srgb()), "while still rendering as it was painted")

    DirAccess.remove_absolute(path)
    loaded.free()


func test_an_unspecified_document_writes_no_colour_key() -> void:
    # Saving must not turn "nobody said" into "the user chose sRGB". A converter
    # reading that back would transform pixels on the strength of a guess this
    # code made.
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new(), SaColorSpace.unspecified())

    var path := SaDataRoot.path("test_unspecified.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "An unspecified document still saves")

    var reloaded := SaDocument.new()
    assert_eq(SaExport.load_sad(reloaded, path, SaCompositor.new()), OK, "and reloads")
    assert_false(reloaded.color_space.is_specified, "still unspecified, not silently promoted to sRGB")

    DirAccess.remove_absolute(path)
    reloaded.free()
    doc.free()


## PNG and JPEG export used to build an RGBAF image straight from the readback,
## which is only right at F32. An F16 document hands back eight bytes per texel
## where RGBAF needs sixteen, so Image rejected the buffer and export failed on
## exactly the documents that chose the smaller depth.
func test_the_flattened_image_is_read_at_the_documents_own_depth() -> void:
    for depth: int in [RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT]:
        var texture := SaTexture.new(Vector2i(8, 8), depth)
        texture.clear(Color(1.0, 0.5, 0.25, 1.0))

        var image := SaExportScript.get_texture_image_float(texture)

        assert_not_null(image, "A %d-byte texel must read back" % SaFieldSpec.BYTES_PER_TEXEL[depth])
        if image != null:
            assert_eq(image.get_format(), Image.FORMAT_RGBAF, "Every caller gets RGBAF whatever the storage depth")
            assert_almost_eq(image.get_pixel(0, 0).r, 1.0, 0.001, "and the pixels are the ones stored")
            assert_almost_eq(image.get_pixel(0, 0).b, 0.25, 0.001, "in every channel")


func _bytes(path: String) -> PackedByteArray:
    return FileAccess.get_file_as_bytes(path)


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The destination used to be truncated the instant it was opened, so
## a save that failed part way destroyed the previous good file. Occupying the
## temporary name with a directory is a write failure the test can stage.
func test_a_failed_save_leaves_the_previous_file_intact() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var path := SaDataRoot.path("test_atomic.sad")
    _remove(path)
    _remove(path + "1")
    assert_eq(SaExport.save_sad(easel.document, path, 0), OK, "The first save lands")
    var before := _bytes(path)

    var blocker := ProjectSettings.globalize_path(path + SaSadFile.SAD_TEMP_SUFFIX)
    DirAccess.make_dir_absolute(blocker)
    easel.document.fill_layer(Color.RED)
    var err: Error = SaExport.save_sad(easel.document, path, 0)
    DirAccess.remove_absolute(blocker)

    assert_true(err != OK, "The save reports its failure")
    assert_eq(_bytes(path), before, "and the file on disk is the one from before")
    assert_false(FileAccess.file_exists(path + "1"), "No version was rotated for a save that did not happen")

    _remove(path)
    easel.free()


## The file being replaced becomes `.sad1`, the one before that `.sad2`, and the
## chain is as long as the count says. Zero keeps nothing.
func test_a_save_keeps_the_previous_versions_it_was_asked_to() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var doc := easel.document
    var path := SaDataRoot.path("test_versions.sad")
    for suffix: String in ["", "1", "2", "3"]:
        _remove(path + suffix)

    assert_eq(SaExport.save_sad(doc, path, 2), OK, "First save")
    var first := _bytes(path)
    doc.fill_layer(Color.RED)
    assert_eq(SaExport.save_sad(doc, path, 2), OK, "Second save")
    var second := _bytes(path)
    doc.fill_layer(Color.BLUE)
    assert_eq(SaExport.save_sad(doc, path, 2), OK, "Third save")

    assert_eq(_bytes(path + "1"), second, ".sad1 is the file the last save replaced")
    assert_eq(_bytes(path + "2"), first, ".sad2 is the one before")
    assert_false(FileAccess.file_exists(path + "3"), "and the chain stops at the count")
    assert_true(first != second, "The versions are different files, so the check means something")

    doc.fill_layer(Color.GREEN)
    assert_eq(SaExport.save_sad(doc, path, 0), OK, "A save keeping nothing")
    assert_eq(_bytes(path + "1"), second, "rotates nothing, so .sad1 is what it was")

    for suffix: String in ["", "1", "2", "3"]:
        _remove(path + suffix)
    easel.free()


## The default count comes from Preferences, so a painter's choice reaches the
## save without every caller passing it.
func test_the_versions_count_defaults_to_the_preference() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var path := SaDataRoot.path("test_versions_pref.sad")
    _remove(path)
    _remove(path + "1")
    var previous: int = SaSettings.sad_versions
    SaSettings.sad_versions = 0
    assert_eq(SaExport.save_sad(easel.document, path), OK, "First save")
    assert_eq(SaExport.save_sad(easel.document, path), OK, "Second save")
    assert_false(FileAccess.file_exists(path + "1"), "Preferences said keep none")
    SaSettings.sad_versions = previous
    _remove(path)
    easel.free()
