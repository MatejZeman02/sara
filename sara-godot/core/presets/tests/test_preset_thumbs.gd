## The preset thumbnails: the rendered stroke, the cache, and the delete hook.
##
## The three shipped presets are the fixture, because the requirement is
## that they differ from each other by more than a threshold: a
## renderer that draws the same blob whatever the settings would pass every
## other assertion here.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A thumbnail is a stroke on a real document through the real paint path.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_preset_thumbs")

## Two thumbnails count as different when this many of their pixels differ by
## more than an eighth of full scale.
##
## Sixty-four, and the number is measured rather than chosen. The three shipped
## presets come apart as Fill against Paint 2768, Fill against Sketch 2768, and
## Paint against Sketch 118. The last pair is the one that matters: both are
## hairlines at 128 by 64, one from a 0.005 radius and one from 0.023, so they
## can only differ along the stroke and the stroke is a few hundred pixels. A
## renderer that ignored its settings would answer zero for every pair, so the
## threshold is set at half the closest real pair and not at a fraction of the
## strip, which would have passed a renderer that only got Fill right.
const DIFFERENT_PIXELS: int = 64


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    SaPresetThumbs.renders = 0
    SaPresetThumbs.cache_hits = 0


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A store holding the three presets Sara ships, written from live settings the
## way `install_shipped` does.
func _shipped_store() -> SaPresetStore:
    var store := _store()
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    return store


func _pixels_differing(a: Image, b: Image) -> int:
    if a == null or b == null or a.get_size() != b.get_size():
        return -1
    var count := 0
    for y in a.get_height():
        for x in a.get_width():
            var left := a.get_pixel(x, y)
            var right := b.get_pixel(x, y)
            if absf(left.r - right.r) > 0.125 or absf(left.a - right.a) > 0.125:
                count += 1
    return count


func _render(settings: Resource) -> Image:
    return SaPresetThumbs.render(StateBrushScript, settings, SaPresetThumbs.SIZE)


## The first requirement: a renderer that draws the same blob three
## times fails.
func test_the_three_shipped_presets_render_three_different_strokes() -> void:
    var store := _shipped_store()
    var names := store.list_names()
    assert_true(names.size() >= 3, "The store holds the shipped presets: %s" % str(names))
    var images: Array[Image] = []
    for preset_name: String in names:
        var image := _render(store.load_preset(preset_name))
        assert_not_null(image, "'%s' renders" % preset_name)
        if image != null:
            images.append(image)
    for i in images.size():
        for j in range(i + 1, images.size()):
            var differing := _pixels_differing(images[i], images[j])
            assert_true(
                differing > DIFFERENT_PIXELS,
                "'%s' and '%s' draw different strokes: %d pixels apart" % [names[i], names[j], differing]
            )


## A stroke, not a blank strip, and the ink is the fixed one rather than whatever
## colour the settings carry: `copy_settings` excludes the colour on purpose.
func test_a_thumbnail_is_a_stroke_in_the_fixed_ink() -> void:
    var settings := BrushSettingsScript.new()
    settings.radius = 0.12
    settings.color = Color(1.0, 0.0, 0.0, 1.0)
    var image := _render(settings)
    assert_not_null(image, "an image comes back")
    if image == null:
        return
    assert_eq(image.get_size(), SaPresetThumbs.SIZE, "at the size the spec names")
    var inked := 0
    for y in image.get_height():
        for x in image.get_width():
            var c := image.get_pixel(x, y)
            if c.r < 0.3 and c.g < 0.3:
                inked += 1
    assert_true(inked > 200, "with the stroke on it: %d inked pixels" % inked)
    assert_almost_eq(image.get_pixel(0, 0).r, image.get_pixel(0, 0).b, 0.01, "and the corner is not the red the settings named")


## The pressure ramps from nothing to full and back, so the middle of the stroke
## is wider than either end. That is what makes a thumbnail say what a brush
## does.
func test_the_stroke_tapers_at_both_ends() -> void:
    var settings := BrushSettingsScript.new()
    settings.radius = 0.16
    settings.size_by_pressure = true
    var image := _render(settings)
    if image == null:
        return
    assert_almost_eq(SaPresetThumbs._pressure_at(0.0), 0.0, 0.001, "No pressure at the start")
    assert_almost_eq(SaPresetThumbs._pressure_at(0.5), 1.0, 0.001, "full in the middle")
    assert_almost_eq(SaPresetThumbs._pressure_at(1.0), 0.0, 0.001, "and none at the end")


## A second open reads the PNG and renders nothing, which is the clause a counter
## rather than a picture has to answer.
func test_a_second_open_reads_the_cache() -> void:
    var store := _shipped_store()
    var name_of := store.list_names()[0]
    var settings := store.load_preset(name_of)

    var first := SaPresetThumbs.ensure(store.dir, name_of, StateBrushScript, settings)
    assert_false(first.is_empty(), "The first ask writes a PNG")
    assert_true(FileAccess.file_exists(first), "which is on disk")
    assert_eq(SaPresetThumbs.renders, 1, "and cost one render")
    assert_eq(SaPresetThumbs.cache_hits, 0, "with nothing to read")

    var second := SaPresetThumbs.ensure(store.dir, name_of, StateBrushScript, settings)
    assert_eq(second, first, "The second ask answers the same path")
    assert_eq(SaPresetThumbs.renders, 1, "and renders nothing")
    assert_eq(SaPresetThumbs.cache_hits, 1, "having read the cache")


## A preset saved again is a `.tres` newer than its PNG, which is the one thing
## that makes a thumbnail stale.
func test_a_resaved_preset_is_stale_again() -> void:
    var store := _shipped_store()
    var name_of := store.list_names()[0]
    var settings := store.load_preset(name_of)
    SaPresetThumbs.ensure(store.dir, name_of, StateBrushScript, settings)
    assert_false(SaPresetThumbs.is_stale(store.dir, name_of), "A freshly drawn thumbnail is not stale")

    # A whole second, because the file system answers modification times in them
    # and a resave inside the same second is a resave nothing can see.
    OS.delay_msec(1100)
    settings.radius = 0.19
    store.save_preset(name_of, settings)
    assert_true(SaPresetThumbs.is_stale(store.dir, name_of), "and a preset written after it is")


## Deleting a preset leaves no orphan PNG, which is the store's one hook.
func test_deleting_a_preset_removes_its_thumbnail() -> void:
    var store := _shipped_store()
    var name_of := store.list_names()[0]
    var png := SaPresetThumbs.ensure(store.dir, name_of, StateBrushScript, store.load_preset(name_of))
    assert_true(FileAccess.file_exists(png), "The thumbnail is there")
    assert_true(store.delete_preset(name_of), "The preset goes")
    assert_false(FileAccess.file_exists(png), "and so does its thumbnail")


## The thumbnails live where `list_names` cannot see them, or a painter would be
## offered a PNG as a brush.
func test_the_thumbnails_are_not_offered_as_presets() -> void:
    var store := _shipped_store()
    var before := store.list_names()
    for preset_name: String in before:
        SaPresetThumbs.ensure(store.dir, preset_name, StateBrushScript, store.load_preset(preset_name))
    assert_eq(store.list_names(), before, "The list is what it was before the thumbnails were drawn")
    assert_true(SaPresetThumbs.DIR_NAME.begins_with("."), "The directory is hidden, and it is a directory")


# --- The tip fills its cell ---------------------------------------------

const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## A texel is paint when a channel is this far from the corner's. Coarser than
## the renderer's own five levels and measured here rather than asked of it, so a
## framing that measured itself wrongly cannot also pass its own test.
const PAINT_DISTANCE: float = 0.05


## The smallest rectangle holding every texel of *image* that is not the corner.
func _painted(image: Image) -> Rect2i:
    var card := image.get_pixel(0, 0)
    var low := Vector2i(image.get_width(), image.get_height())
    var high := Vector2i(-1, -1)
    for y in image.get_height():
        for x in image.get_width():
            var texel := image.get_pixel(x, y)
            if absf(texel.r - card.r) > PAINT_DISTANCE or absf(texel.g - card.g) > PAINT_DISTANCE:
                low = Vector2i(mini(low.x, x), mini(low.y, y))
                high = Vector2i(maxi(high.x, x), maxi(high.y, y))
    if high.x < 0:
        return Rect2i()
    return Rect2i(low, high - low + Vector2i.ONE)


## How many texels of *image* are not the corner.
func _ink(image: Image) -> int:
    var card := image.get_pixel(0, 0)
    var count := 0
    for y in image.get_height():
        for x in image.get_width():
            if absf(image.get_pixel(x, y).r - card.r) > PAINT_DISTANCE:
                count += 1
    return count


## Whether *box* spans more than three quarters of a tip cell on its longer side.
func _fills(box: Rect2i) -> bool:
    return float(maxi(box.size.x, box.size.y)) > 0.75 * float(SaPresetThumbs.TIP_SIZE.x)


## The note's own case, "the Brush tip mode in the brush presets are too small.
## They should fill the whole container", on a preset saved at twelve pixels and
## through the cache a chooser cell reads.
func test_a_twelve_pixel_presets_tip_spans_three_quarters_of_its_cell() -> void:
    var settings := StampSettingsScript.new()
    settings.radius = 6.0 / 1080.0
    var store := _store()
    store.save_preset("Twelve", settings)
    var path := SaPresetThumbs.ensure(store.dir, "Twelve", StateBrushScript, store.load_preset("Twelve"), true)
    assert_true(FileAccess.file_exists(path), "The tip was drawn to the cache")
    var box := _painted(Image.load_from_file(path))
    assert_true(_fills(box), "and spans more than three quarters of its cell, %s" % box)


## A Size option below full strength scales every dab at full pressure, which was
## a twelve texel dot in the middle of the cell on the running app.
func test_a_weak_size_option_still_fills_the_cell_and_stays_centred() -> void:
    var settings := StampSettingsScript.new()
    settings.size_option.enabled = true
    settings.size_option.strength = 0.3
    var box := _painted(SaPresetThumbs.render_tip(StateBrushScript, settings))
    assert_true(_fills(box), "A dab at 30 percent strength fills the cell, %s" % box)
    var centre := box.get_center()
    var middle := Vector2(SaPresetThumbs.TIP_SIZE) * 0.5
    assert_true(absf(centre.x - middle.x) <= 3.0 and absf(centre.y - middle.y) <= 3.0, "in the middle of it, %s" % centre)


## An image tip whose picture leaves a margin, a dark square over the middle
## quarter of a white one, paints half its box on each side. That is the small
## square the note's screenshot shows.
func test_an_image_tip_with_a_margin_fills_the_cell() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var picture := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
    picture.fill(Color.WHITE)
    picture.fill_rect(Rect2i(4, 4, 8, 8), Color.BLACK)
    var path := scratch_dir.path_join("d38-margin.png")
    assert_eq(picture.save_png(path), OK, "The picture was written")
    var settings := StampSettingsScript.new()
    var mask := SaBrushTipMask.select(settings.tip, path)
    assert_true(mask.error.is_empty(), "and loads as a tip, '%s'" % mask.error)
    var box := _painted(SaPresetThumbs.render_tip(StateBrushScript, settings))
    assert_true(_fills(box), "Its dark square fills the cell, %s" % box)


## The shape is the preset's own. A squashed tip is framed on its longer side and
## stays squashed rather than being stretched to the square.
func test_a_framed_tip_keeps_its_ratio() -> void:
    var settings := StampSettingsScript.new()
    settings.tip.ratio = 0.3
    var box := _painted(SaPresetThumbs.render_tip(StateBrushScript, settings))
    assert_true(_fills(box), "The long side fills the cell, %s" % box)
    assert_true(float(box.size.y) < float(box.size.x) * 0.5, "and the short side is still under half of it")


## The frame is the cell's alone. The preset keeps its radius and its Size option,
## and the stroke picture keeps the preset's size, because a stroke is judged at
## its size.
func test_framing_a_tip_leaves_the_preset_and_the_stroke_alone() -> void:
    var thin := StampSettingsScript.new()
    thin.radius = 6.0 / 1080.0
    thin.size_option.enabled = true
    thin.size_option.strength = 0.3
    SaPresetThumbs.render_tip(StateBrushScript, thin)
    assert_almost_eq(thin.radius, 6.0 / 1080.0, 1e-9, "The preset is the size it was saved at")
    assert_almost_eq(thin.size_option.strength, 0.3, 1e-6, "with its Size option untouched")
    var fat := StampSettingsScript.new()
    fat.radius = 0.05
    var thin_ink := _ink(SaPresetThumbs.render(StateBrushScript, thin))
    var fat_ink := _ink(SaPresetThumbs.render(StateBrushScript, fat))
    assert_true(thin_ink < fat_ink, "A thin stroke still draws less than a fat one, %d against %d" % [thin_ink, fat_ink])


## One picture is one render on the counter even when the tip was painted twice,
## so a chooser's dump counts presets rather than passes.
func test_a_redrawn_tip_counts_as_one_render() -> void:
    var settings := StampSettingsScript.new()
    settings.size_option.enabled = true
    settings.size_option.strength = 0.3
    var before := SaPresetThumbs.renders
    SaPresetThumbs.render_tip(StateBrushScript, settings)
    assert_eq(SaPresetThumbs.renders, before + 1, "One render for one tip")


# --- A stroke too small for the picture (d6) ----------------------------------


## A store holding all twenty-one shipped presets, which the pre-C4 template the
## other tests use cannot carry.
func _shipped_brush_store() -> SaPresetStore:
    var store := _store()
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    return store


## The Spatter's picture carries ink, which is d6's proof, and the picture one
## render would have given carries none, which is the defect it was filed for.
## The Spatter is set back to the 0.0028 it shipped at when d6 was filed, since
## The shipped brush carries eight times that, which the cell
## reads in one render.
func test_a_stroke_the_picture_cannot_show_is_drawn_again_larger() -> void:
    var store := _shipped_brush_store()
    var spatter := store.load_preset("Spatter")
    assert_not_null(spatter, "The spatter is one of the shipped presets")
    if spatter == null:
        return
    spatter.set("radius", 0.0028)
    var picture := SaPresetThumbs.render(StateBrushScript, spatter)
    assert_not_null(picture, "Its picture renders")
    assert_true(_ink(picture) > 0, "and carries ink, %d texels of it" % _ink(picture))
    assert_almost_eq(float(spatter.get("radius")), 0.0028, 1e-6, "on a preset left at the radius it was saved at")

    # The one render the second drawing replaces, scaled down the same way:
    # measured, not one texel of it is paint. That is an empty cell.
    var once := SaPresetThumbs._paint(StateBrushScript, spatter, SaPresetThumbs.SIZE * SaPresetThumbs.SUPERSAMPLE, false)
    once.resize(SaPresetThumbs.SIZE.x, SaPresetThumbs.SIZE.y, Image.INTERPOLATE_LANCZOS)
    assert_eq(_ink(once), 0, "The one render it replaces carries none, which is the defect")


## A preset the picture can read is not drawn again: the picture is the one
## render, so the size kept is still what the cell shows.
func test_a_stroke_the_picture_can_show_is_left_at_its_own_size() -> void:
    var settings := StampSettingsScript.new()
    settings.radius = 0.05
    var drawn := SaPresetThumbs.render(StateBrushScript, settings)
    var once := SaPresetThumbs._paint(StateBrushScript, settings, SaPresetThumbs.SIZE * SaPresetThumbs.SUPERSAMPLE, false)
    once.resize(SaPresetThumbs.SIZE.x, SaPresetThumbs.SIZE.y, Image.INTERPOLATE_LANCZOS)
    assert_eq(drawn.get_data(), once.get_data(), "A stroke the cell can read is the render it always was")
    assert_almost_eq(settings.radius, 0.05, 1e-9, "and the preset is the size it was saved at")


# --- The compressor over the live preview -------------------------------------


func _strip() -> SaBrushPreviewStrip:
    var strip := SaBrushPreviewStrip.new()
    var settings := BrushSettingsScript.new()
    settings.radius = 0.1
    strip.bind_source(StateBrushScript, settings)
    return strip


## The first call goes straight through, so a page switch draws at once.
func test_the_first_request_renders_immediately() -> void:
    var strip := _strip()
    strip.request()
    assert_eq(strip.renders, 1, "The first request drew")
    assert_not_null(strip.texture, "and put a texture on the strip")
    strip.free()


## Every request inside the window is one render when it expires, not one each.
## That is the whole of the compressor: a curve dragged by hand emits an event
## per pixel.
func test_requests_inside_the_window_coalesce() -> void:
    var strip := _strip()
    strip.request()
    for _i in 20:
        strip.request()
    assert_eq(strip.renders, 1, "Twenty more requests drew nothing")
    assert_eq(strip.compressor.coalesced, 20, "and every one of them was counted rather than dropped")
    assert_true(strip.compressor.pending, "with one waiting for the window to expire")
    strip.free()


## A request that arrives while a render is running is remembered rather than
## started, so two renders never race to one texture.
func test_a_request_during_a_render_never_starts_a_second() -> void:
    var strip := _strip()
    strip.render_now()
    assert_eq(strip.renders, 1, "One render")
    assert_false(strip.compressor.pending, "with nothing waiting")
    strip.request()
    assert_true(strip.compressor.coalesced >= 1 or strip.renders == 2, "and a request after it either draws or waits, never both")
    strip.free()
