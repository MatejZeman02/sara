## Opening a picture asks which float depth to store it at, unless the file has
## already said.
##
## A file that carries no float size information offers a choice of FP16 or
## FP32 rather than 32 automatically. Two halves that have to stay apart. A file that names a float width has answered
## and is not asked, and a file that names none opens on the last answer the
## painter gave rather than on a constant.
##
## `SaDocumentFiles.open_image_into` is the document half of the flow's own path,
## the seam `test_open_image_as_document.gd` already uses and for its reason: the
## flow's `_document()` asks Sara's main scene for its canvas and no suite builds
## that.
## `scenarios/an-opened-picture-chooses-its-depth.json` is what proves the
## window itself.
extends "res://tests/test_framework.gd"

## Chunk allocation is what a depth decides, so this needs a real device.
const REQUIRES_GPU := true

## Eight bits a channel, so the file says nothing about a float width.
const PNG := "res://tests/data/import_gradient.png"

## Float channels, so the file does say.
const EXR := "res://tests/data/import_linear.exr"


func test_a_png_names_no_depth_and_an_exr_names_one() -> void:
    var png := SaImageImport.read(PNG)
    assert_not_null(png, "The PNG reads")
    assert_eq(SaImageImport.depth_for(png), -1, "and eight bits a channel is not a float width")

    var exr := SaImageImport.read(EXR)
    assert_not_null(exr, "The EXR reads")
    var named := SaImageImport.depth_for(exr)
    assert_true(named >= 0, "and a float file carries its own width")
    assert_true(SaColorSpace.storage_depths().has(named), "which is one chunk storage can allocate")
    assert_eq(SaImageImport.depth_for(null), -1, "Nothing names nothing")


## The clause "a file that names a depth opens at it": no window, no setting,
## the file's own answer.
func test_a_file_that_names_a_depth_opens_at_it() -> void:
    var was := SaSettings.import_depth
    var named := SaImageImport.depth_for(SaImageImport.read(EXR))
    # The opposite of what the file says, so a document that ignored the file
    # would land here instead and this assertion would see it.
    SaSettings.import_depth = "f16" if named == SaColorSpace.Depth.F32 else "f32"

    var easel := SaEasel.create_default(Vector2i(256, 256))
    var layer := SaDocumentFiles.open_image_into(easel.document, EXR)
    assert_not_null(layer, "The picture is read and placed")
    assert_eq(easel.document.color_space.depth, named, "The document is stored at the depth the file names")

    SaSettings.import_depth = was
    easel.free()


## The clause "the dropdown's choice is remembered": the answer is a setting, it
## survives a word nothing knows, and the next open is built on it.
func test_the_chosen_depth_is_remembered_and_is_the_next_default() -> void:
    var was := SaSettings.import_depth
    assert_eq(SaImportFitDialog.depth_from_setting("f16"), SaColorSpace.Depth.F16, "Each word names a depth")
    assert_eq(SaImportFitDialog.depth_from_setting("f32"), SaColorSpace.Depth.F32, "including the wide one")
    assert_eq(SaImportFitDialog.setting_for_depth(SaColorSpace.Depth.F16), "f16", "and the other way round")
    assert_eq(SaImportFitDialog.setting_for_depth(SaColorSpace.Depth.F32), "f32", "for both of them")

    SaSettings.import_depth = "f16"
    assert_eq(SaSettings.import_depth, "f16", "The choice is kept")
    assert_eq(SaImportFitDialog.remembered_depth(), SaColorSpace.Depth.F16, "and it is what the dropdown opens on")
    SaSettings.import_depth = "f8"
    assert_eq(SaSettings.import_depth, "f16", "and a word nothing knows falls back to the default, 16-bit")

    SaSettings.import_depth = was


## A host outside the tree cannot show a window, and a headless test is one. It
## answers from the remembered choice rather than hanging, which is the shape
## `place` already has and the reason this path can be walked here at all.
func test_a_detached_host_opens_on_the_remembered_choice() -> void:
    var was := SaSettings.import_depth
    SaSettings.import_depth = "f16"
    var chosen: Array[SaColorSpace] = []
    SaImportFitDialog.choose_depth(
        null, SaImageImport.read(PNG), SaColorSpace.srgb(), func(space: SaColorSpace) -> void: chosen.append(space)
    )
    assert_eq(chosen.size(), 1, "The question was answered without a window")
    assert_eq(chosen[0].depth, SaColorSpace.Depth.F16, "on the depth the painter last picked")
    assert_eq(String(chosen[0].id), String(SaColorSpace.srgb().id), "and the gamut the caller guessed is untouched")

    SaSettings.import_depth = was


## The file's own width beats the remembered choice, so a habit picked up from a
## folder of screenshots does not quietly halve the next EXR.
func test_a_named_depth_beats_the_remembered_one() -> void:
    var was := SaSettings.import_depth
    SaSettings.import_depth = "f16"
    var named := SaImageImport.depth_for(SaImageImport.read(EXR))
    var chosen: Array[SaColorSpace] = []
    SaImportFitDialog.choose_depth(
        null, SaImageImport.read(EXR), SaColorSpace.linear_srgb(), func(space: SaColorSpace) -> void: chosen.append(space)
    )
    assert_eq(chosen.size(), 1, "The file answered for itself")
    assert_eq(chosen[0].depth, named, "at its own width rather than the remembered one")

    SaSettings.import_depth = was


## What a painter chooses this for, and the reason the scenario's dump carries a
## memory row: the same picture costs half as much at F16. Read off the chunks
## rather than assumed, which is hard rule 3.
func test_the_chosen_depth_is_what_the_chunks_cost() -> void:
    var wide := _bytes_opened_at(SaColorSpace.Depth.F32)
    var half := _bytes_opened_at(SaColorSpace.Depth.F16)
    assert_true(wide > 0, "An opened picture allocates something")
    assert_eq(half * 2, wide, "and half the width is half the bytes")


## The bytes the picture's layer holds after being opened with *depth*
## remembered, so the whole chain from the setting to the allocation is walked.
func _bytes_opened_at(depth: int) -> int:
    var was := SaSettings.import_depth
    SaSettings.import_depth = SaImportFitDialog.setting_for_depth(depth)
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var layer := SaDocumentFiles.open_image_into(easel.document, PNG)
    assert_eq(easel.document.color_space.depth, depth, "The document is stored at the remembered depth")
    var bytes := _layer_bytes(layer)
    SaSettings.import_depth = was
    easel.free()
    return bytes


## Summed per field over the layer's own schema, never off an assumed sixteen
## bytes a texel, which is the Info docker's own sum and hard rule 3.
func _layer_bytes(layer: SaLayer) -> int:
    if layer == null:
        return 0
    var texels_per_chunk := SaLayer.CHUNK_SIZE * SaLayer.CHUNK_SIZE
    var per_chunk := 0
    for spec: SaFieldSpec in layer.schema:
        per_chunk += texels_per_chunk * int(SaFieldSpec.BYTES_PER_TEXEL.get(spec.format, 0))
    return layer.chunks.size() * per_chunk
