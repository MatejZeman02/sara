## An effect layer's row shows its result and a crop leaves the pictures drawn,
## both the Layers docker's pictures.
##
## Bug 6: an effect layer's row showed its input. Its chunks are a cache of the
## input before its records run, and the row sampled the chunks, so a
## kaleidoscope's row was a small copy of the photograph. The row now draws
## `SaEffectLayer.result_at`, the cache through the records.
##
## Bug 8: every row was a white square in a shot taken straight after Crop to
## Selection or Rotate. A shot settles each picture and then forces a frame, and
## a picture of a new size is a new texture: the forced frame drew what the last
## redraw had left, which named the texture the settle had just let go, and the
## engine draws a freed texture as white. A painter never saw it, because a frame
## the engine draws itself runs the queued redraw first. A picture now says it is
## stale until it is drawn, and the shot is asked for again a frame later.
##
## A suite runs inside one frame and no queued redraw runs in it, so the picture
## drawn a frame later is proven in the running app, by
## `scenarios/layer-thumbnails-show-the-result-and-stay-drawn-through-a-crop.json`.
extends "res://tests/test_framework.gd"

## The pictures are compute dispatches over the chunks, read back here the way
## the suites beside this one read them.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Two chunks across and one down, so the picture is 32 texels by 16.
const SIZE := Vector2i(512, 256)
## Blue over red, which the fixture invert turns into red over blue, so either
## picture says which of the two it was drawn from whatever the display encode.
const PAINT := Color(0.2, 0.5, 0.8, 1.0)

## Where a shot is written, removed after each case.
static var scratch_out_dir: String = SaDataRoot.path("p6_thumbnail_shot_test")

const LABEL := "shot"

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types


## A layer named Source painted all over, and an effect layer above it reading
## it through the fixture invert, composited once so the cache is filled.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        source.get_or_create_chunk(grid_pos).clear(PAINT)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    Bench.composite(easel)
    return easel


## The picture's texel in the middle of its first chunk's half, half floats.
static func _middle(texture: SaTexture) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (floori(texture.size.y * 0.5) * texture.size.x + floori(texture.size.x * 0.25)) * 8
    return Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6))


## The picture *layer* draws, refreshed now.
static func _picture_of(layer: SaLayer, doc: SaDocument) -> Color:
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    thumb.refresh()
    var shown := _middle(thumb._texture) if thumb._texture != null else Color(0, 0, 0, 0)
    thumb.free()
    return shown


func test_the_effect_rows_picture_is_its_result_and_not_its_input() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    var source := doc.get_node("Source") as SaLayer
    var cached := Bench.texel(effect.get_field(Vector2i(0, 0)), Vector2i(128, 128))
    assert_true(cached.b > cached.r, "The effect's chunks cache its input, blue over red: %s" % cached)

    var input := _picture_of(source, doc)
    var result := _picture_of(effect, doc)
    assert_true(input.b > input.r + 0.2, "Source's row shows its paint, blue over red: %s" % input)
    assert_true(result.r > result.b + 0.2, "The effect's row shows the inverted result, red over blue: %s" % result)
    assert_true(absf(result.a - 1.0) < 0.01, "and opaque, with no checker under it")
    easel.free()


## The result is what the records make, so with its one record switched off the
## effect shows its input, and the row says so.
func test_an_effect_whose_record_is_switched_off_shows_its_input() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    effect.filters[0].enabled = false
    var result := _picture_of(effect, doc)
    assert_true(result.b > result.r + 0.2, "The row shows the input the effect now shows: %s" % result)
    easel.free()


## Where the effect shows something, which is where its picture is drawn from:
## its cache's chunks, cut to the document's grid.
func test_the_result_is_drawn_where_the_cache_is() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    var positions := SaEffectLayer.result_positions(doc, effect)
    assert_eq(positions.size(), 2, "both chunks of the canvas: %s" % [positions.keys()])
    var shown := SaEffectLayer.result_at(doc, effect, Vector2i(1, 0))
    assert_not_null(shown, "and the result there is a texture")
    if shown != null:
        var texel := Bench.texel(shown, Vector2i(64, 64))
        assert_true(texel.r > texel.b, "holding the inverted paint: %s" % texel)
    easel.free()


## The crop case: the picture is a new size, so a new texture, and the
## slot on screen names the old one until a frame draws it. The shot is asked
## for again a frame later rather than taken of that slot.
func test_a_shot_after_a_crop_waits_a_frame_for_the_picture_of_the_new_size() -> void:
    var easel := _painting()
    var doc := easel.document
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(doc.get_node("Source") as SaLayer, doc)
    EventBus.add_child(thumb)
    thumb.refresh()
    var before := thumb._texture
    assert_eq(before.size, Vector2i(32, 16), "The picture of the whole canvas is 32 by 16")

    assert_true(SaCrop.new(doc).crop_to(Rect2i(0, 0, 256, 256)), "The canvas is cropped to its first chunk")
    thumb.mark_dirty()
    var run := _shoot()

    assert_true(thumb._texture != before, "The shot's settle drew the picture again, in a texture of its own")
    assert_eq(thumb._texture.size, Vector2i(32, 32), "of the square the crop left")
    assert_true(thumb.stale(), "which no frame has drawn yet")
    assert_eq(run.steps, [{"wait": 1}, {"shot": LABEL}], "so the shot is asked for again a frame later")
    assert_false(FileAccess.file_exists(scratch_out_dir.path_join("%s.png" % LABEL)), "and nothing is written of this one")
    _clean_up(thumb, easel)


## A picture no frame draws, its row hidden or out of the tree, holds no shot
## back, or a shot of a docker with a hidden picture would wait for ever.
func test_a_picture_that_is_not_shown_is_never_stale() -> void:
    var easel := _painting()
    var doc := easel.document
    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(doc.get_node("Source") as SaLayer, doc)
    thumb.refresh()
    assert_false(thumb.stale(), "Out of the tree nothing draws it")
    EventBus.add_child(thumb)
    thumb.visible = false
    assert_false(SaLayerThumbnail.settle_all(EventBus), "Hidden, the settle answers that nothing waits")
    var run := _shoot()
    assert_eq(run.steps.size(), 0, "and the shot is taken where it stands")
    assert_true(FileAccess.file_exists(scratch_out_dir.path_join("%s.png" % LABEL)), "and written")
    _clean_up(thumb, easel)


func _shoot() -> SaCaptureRun:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_out_dir))
    var run := SaCaptureRun.new(scratch_out_dir)
    run.shoot(LABEL)
    return run


func _clean_up(thumb: SaLayerThumbnail, easel: SaEasel) -> void:
    thumb.get_parent().remove_child(thumb)
    thumb.free()
    easel.free()
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    DirAccess.remove_absolute(folder.path_join("%s.png" % LABEL))
    DirAccess.remove_absolute(folder)
