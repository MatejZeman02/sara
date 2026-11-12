## Under Pink the filter docker's preview stood on a saturated
## mid pink.
##
## The preview's frame was bound to `bg_input`, and Pink's is `#884A5A`, Oklab
## lightness 0.49 and chroma 0.086, where the dark palettes' read 0.21 to 0.26
## and at most 0.039. The picture inside is kept to its aspect, so wherever it
## does not fill the frame the frame's ground shows round it. The frame is now
## bound to `preview_ground`, which calms a loud ground and leaves every other
## shipped palette's `bg_input` as it was. Pink's own file is pinned colour by
## colour, so it is not touched.
extends "res://tests/test_framework.gd"

const MAX_LIGHTNESS := 0.3
const MAX_CHROMA := 0.039
const CHANNEL := 0.02

var _saved_theme: String = "default"
var _preview: SaFilterPreview = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    if _preview != null:
        _preview.free()
    _preview = null
    SaTheme.use_named(_saved_theme)


func _ground_under(id: String) -> Color:
    SaTheme.use_named(id)
    if _preview != null:
        _preview.free()
    _preview = SaFilterPreview.new()
    var box := _preview.frame.get_theme_stylebox("panel") as StyleBoxFlat
    return box.bg_color


func test_under_pink_the_surround_is_dark_and_nearly_grey() -> void:
    var lch := OkhslConversions.srgb_to_oklch(_ground_under("pink"))
    assert_true(lch.z < MAX_LIGHTNESS, "Pink's surround has Oklab lightness under 0.3, it reads %.3f" % lch.z)
    assert_true(lch.y <= MAX_CHROMA, "and chroma at most 0.039, it reads %.3f" % lch.y)


func test_every_other_palette_keeps_the_surround_it_has() -> void:
    var checked := 0
    for id: String in SaTheme.PALETTES:
        if id == "pink":
            continue
        var palette := load(SaTheme.PALETTES[id]) as SaPalette
        var ground := _ground_under(id)
        var was := palette.bg_input
        for channel: String in ["r", "g", "b"]:
            assert_true(
                absf(ground[channel] - was[channel]) <= CHANNEL,
                "%s's surround keeps its %s channel, %.3f against %.3f" % [id, channel, ground[channel], was[channel]]
            )
        checked += 1
    assert_eq(checked, SaTheme.PALETTES.size() - 1, "every palette that is not Pink was read")


func test_the_surround_follows_the_palette_when_it_switches() -> void:
    var dark := _ground_under("pink")
    var box := _preview.frame.get_theme_stylebox("panel") as StyleBoxFlat
    SaTheme.use_named("paper")
    assert_true(box.bg_color.get_luminance() > 0.9, "the same frame turns near white under Paper White")
    SaTheme.use_named("pink")
    assert_eq(box.bg_color, dark, "and back to Pink's dark grey")
