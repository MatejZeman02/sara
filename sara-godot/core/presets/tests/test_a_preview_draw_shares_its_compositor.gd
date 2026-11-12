## A preview draw composites through one shared compositor.
##
## bounded how often the Brush Editor's previews draw during a drag and left
## what each draw costs, a hundred milliseconds, eighty-five of them filed as the
## one dab. Timed here, the dab itself is a millisecond. The eighty-five were a
## fresh `SaCompositor` per throwaway easel loading its blend pipelines on the
## first composite, which is the stroke's commit on the release.
##
## The claims are structural rather than a stopwatch, because a suite that fails
## on wall-clock time fails on a busy machine and not on a slow change. The
## timing is printed so the record can quote it: every render reuses one
## compositor, and a render through it paints exactly what a render through a
## private one paints.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true
const RUNS := 5


func _settings() -> Resource:
    var tool := StateBrushScript.new() as ToolState
    return tool.get("settings") as Resource


## One dab through the real tool into a fresh easel on *compositor*, read back,
## the same steps `SaPresetThumbs._paint` takes for a tip.
func _paint_on(compositor: SaCompositor, settings: Resource, size: Vector2i) -> Image:
    var easel := SaEasel.create_default(size, compositor)
    var view := SaPresetThumbs.ThumbView.new()
    var surface := SaSurface.create(&"preset_thumb", easel, view)
    var painter := StateBrushScript.new() as ToolState
    painter.surface = surface
    var target := painter.get("settings") as Resource
    SaPresetStore.copy_settings(settings, target)
    target.set("color", SaPresetThumbs.INK)
    SaPresetThumbs._stroke(painter, view, size, true)
    easel.document.commit_stroke()
    easel.request_full_composite()
    easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(easel)
    easel.document.free()
    easel.free()
    return image


## Every render asks for the same compositor, which is the whole of the fix: the
## pipelines load once rather than once per preview.
func test_every_render_reuses_one_compositor() -> void:
    var shared := SaPresetThumbs.shared_compositor()
    assert_not_null(shared, "There is a shared compositor")
    SaPresetThumbs.render_tip(StateBrushScript, _settings())
    assert_true(SaPresetThumbs.last_compositor == shared, "A tip render's easel composited through it")
    SaPresetThumbs.render(StateBrushScript, _settings(), SaPresetThumbs.SIZE)
    assert_true(SaPresetThumbs.last_compositor == shared, "and so did a stroke render's")
    assert_true(SaPresetThumbs.shared_compositor() == shared, "and neither replaced it")


## Sharing changed the cost and not the picture. A dab through the shared
## compositor is the same texels as a dab through a private one, so the
## "the real tool's dab through the real kernel" still holds.
func test_a_shared_compositor_paints_the_same_dab() -> void:
    var settings := _settings()
    var size := SaPresetThumbs.TIP_SIZE * SaPresetThumbs.SUPERSAMPLE
    var private_image := _paint_on(null, settings, size)
    var shared_image := _paint_on(SaPresetThumbs.shared_compositor(), settings, size)
    assert_not_null(private_image, "A private compositor reads back")
    assert_not_null(shared_image, "and so does the shared one")
    if private_image == null or shared_image == null:
        return
    assert_eq(shared_image.get_size(), private_image.get_size(), "at the same size")
    var differing := 0
    for y in private_image.get_height():
        for x in private_image.get_width():
            if not private_image.get_pixel(x, y).is_equal_approx(shared_image.get_pixel(x, y)):
                differing += 1
    assert_eq(differing, 0, "and not one texel differs")
    var centre := private_image.get_pixel(size.x >> 1, size.y >> 1)
    assert_true(centre.a > 0.5, "The dab is really there, alpha %.3f at the centre" % centre.a)


## The easel is still fresh per render, so a second dab does not read the first:
## a render after another render through the shared compositor is the same
## picture as the first, not the two dabs on top of each other.
func test_the_shared_compositor_carries_no_picture_between_renders() -> void:
    var settings := _settings()
    var size := SaPresetThumbs.TIP_SIZE * SaPresetThumbs.SUPERSAMPLE
    var shared := SaPresetThumbs.shared_compositor()
    var once := _paint_on(shared, settings, size)
    var again := _paint_on(shared, settings, size)
    assert_not_null(once, "A first render")
    assert_not_null(again, "and a second")
    if once == null or again == null:
        return
    var differing := 0
    for y in once.get_height():
        for x in once.get_width():
            if not once.get_pixel(x, y).is_equal_approx(again.get_pixel(x, y)):
                differing += 1
    assert_eq(differing, 0, "The second render is the first picture again, not a build-up")


## The split the record quotes, printed rather than asserted. Five renders after a
## first, through a private compositor and through the shared one.
func test_print_the_split_for_the_record() -> void:
    var settings := _settings()
    var size := SaPresetThumbs.TIP_SIZE * SaPresetThumbs.SUPERSAMPLE
    for mode: String in ["private", "shared"]:
        var total := 0
        for run in range(RUNS + 1):
            var start := Time.get_ticks_usec()
            var image := _paint_on(null if mode == "private" else SaPresetThumbs.shared_compositor(), settings, size)
            var spent := Time.get_ticks_usec() - start
            assert_not_null(image, "%s render %d reads back" % [mode, run])
            if run > 0:
                total += spent
        print("%s compositor, one dab painted and read back: %.1f ms" % [mode, float(total) / float(RUNS) / 1000.0])
