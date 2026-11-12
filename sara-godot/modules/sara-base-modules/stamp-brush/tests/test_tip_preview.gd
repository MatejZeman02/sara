## The Brush Tip page's dab preview.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Here because the preview is a row the brush declares rather than a part of
## the brush editor.
##
## The brush tip is visible in the editor and reacts to rotation, mirror,
## hardness and the rest. The reacting is what is graded, and it is graded as numbers: two round dabs
## and two trees look alike enough in a screenshot that a preview which had
## stopped redrawing would pass one.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## A preview is a dab on a real document through the real paint path, which is
## the whole of why it is worth having.
const REQUIRES_GPU := true

## Where the image tip with a margin is written for the length of one test.
static var scratch_dir: String = SaDataRoot.path("test_tip_preview")


## One preview's report, the preview freed before it is handed back.
##
## A preview is a Node and a test that keeps one leaks it, which
## `run_tests.sh` fails the run over and which is worth more than the object:
## every one of these tests wants the numbers rather than the control.
func _report(settings: Resource) -> Dictionary:
    var preview := SaTipPreview.new()
    preview.bind_source(StateBrushScript, settings)
    preview.render_now()
    var report := preview.preview_report()
    preview.free()
    return report


func test_the_preview_draws_a_dab_rather_than_an_empty_square() -> void:
    var report := _report(StampSettingsScript.new())

    assert_true(bool(report["present"]), "there is a texture")
    assert_eq(int(report["renders"]), 1, "drawn once")
    assert_true(int(report["ink"]) > 0, "with ink on it")
    assert_true(float(report["coverage"]) < 1.0, "and card around it, or the measurement is reading the background")


## Ink is measured against the card and not against alpha. `SaPresetThumbs`
## paints onto a real document whose background is opaque, so every texel of the
## picture has an alpha of one and a preview measured that way reads as a solid
## square whatever the tip is.
func test_the_ink_is_what_differs_from_the_card_it_is_painted_on() -> void:
    var report := _report(StampSettingsScript.new())

    assert_true(float(report["coverage"]) > 0.05, "a dab at the preview radius covers a real share of the square")
    assert_true(float(report["coverage"]) < 0.9, "and nothing like all of it")


func test_ratio_squashes_the_dab_and_the_dump_says_so() -> void:
    var round_settings := StampSettingsScript.new()
    var squashed := StampSettingsScript.new()
    squashed.tip.ratio = 0.3

    var before := _report(round_settings)
    var after := _report(squashed)

    assert_eq(int(before["bounds"][2]), int(after["bounds"][2]), "the same width")
    assert_true(float(after["bounds"][3]) < float(before["bounds"][3]) * 0.5, "and under half the height")
    assert_true(int(after["ink"]) < int(before["ink"]), "with less ink in it")


## The size row is deliberately not one of the things the preview follows. A
## brush at two percent draws a dab three texels across, which says nothing about
## the shape, the hardness or the mirror the note asks to see.
func test_the_painter_s_own_size_does_not_move_the_preview() -> void:
    var small := StampSettingsScript.new()
    small.radius = 0.005
    var large := StampSettingsScript.new()
    large.radius = 0.2

    var thin := _report(small)
    var fat := _report(large)

    assert_eq(thin["bounds"], fat["bounds"], "the same dab at either size")


## And the copy is why. A preview that set the radius on the painter's own
## settings would resize the brush every time the page was opened.
func test_the_preview_leaves_the_settings_it_was_handed_alone() -> void:
    var settings := StampSettingsScript.new()
    settings.radius = 0.05

    _report(settings)

    assert_almost_eq(settings.radius, 0.05, 1e-6, "the brush is the size the painter set it")


## A Size option below full strength is drawn at the plain tip's size.
##
## The option scales every dab at full pressure, which is a size by another name,
## and the size is the one thing this preview does not follow. On the running app
## a Size option at 30 percent drew 23 texels where the plain tip drew 72.
func test_a_weak_size_option_spans_what_the_plain_tip_does() -> void:
    var plain := _report(StampSettingsScript.new())
    var weak_settings := StampSettingsScript.new()
    weak_settings.size_option.enabled = true
    weak_settings.size_option.strength = 0.3
    var weak := _report(weak_settings)

    for axis: int in [2, 3]:
        assert_true(
            absi(int(weak["bounds"][axis]) - int(plain["bounds"][axis])) <= 2,
            "the weak option's dab spans the plain tip's, %s against %s" % [weak["bounds"], plain["bounds"]]
        )
    var middle := float(SaTipPreview.SIDE) * 0.5
    var across := float(weak["bounds"][0]) + float(weak["bounds"][2]) * 0.5
    var down := float(weak["bounds"][1]) + float(weak["bounds"][3]) * 0.5
    assert_true(absf(across - middle) <= 3.0 and absf(down - middle) <= 3.0, "and sits in the middle of the square")


## The other half of what was measured on the old path: an image tip whose picture
## leaves a margin drew a smaller square than the plain tip at the same radius.
func test_an_image_tip_with_a_margin_spans_what_the_plain_tip_does() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var picture := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
    picture.fill(Color.WHITE)
    picture.fill_rect(Rect2i(4, 4, 8, 8), Color.BLACK)
    var path := scratch_dir.path_join("d59-margin.png")
    assert_eq(picture.save_png(path), OK, "The picture was written")
    var settings := StampSettingsScript.new()
    assert_true(SaBrushTipMask.select(settings.tip, path).error.is_empty(), "and loads as a tip")

    var plain := _report(StampSettingsScript.new())
    var margin := _report(settings)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

    assert_true(
        absi(int(margin["bounds"][2]) - int(plain["bounds"][2])) <= 2,
        "its dark square spans the plain tip's width, %s against %s" % [margin["bounds"], plain["bounds"]]
    )
