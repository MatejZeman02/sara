## The engine's sliders and its progress bar read the slider
## family.
##
## The shared theme names the slider classes, so an `HSlider` does not resolve
## Godot's own theme under every palette (on Paper White its fill would be white
## at 40 percent over a ground of 0.95). What is held here is that the shared
## theme answers for all three classes from the palette's Slider group, with
## the engine's own margins, and that the grabber is a disc in the palette's
## text colour rather than the engine's light grey.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Class -> the engine's stylebox name -> the state field its ground reads.
const GROUNDS := {
    "HSlider": {"slider": "slider_track", "grabber_area": "slider_handle", "grabber_area_highlight": "slider_hover"},
    "VSlider": {"slider": "slider_track", "grabber_area": "slider_handle", "grabber_area_highlight": "slider_hover"},
    "ProgressBar": {"background": "slider_track", "fill": "slider_handle"},
}

## The engine's icon name -> the palette colour its disc is drawn in.
const DISCS := {
    "grabber": "text_primary",
    "grabber_highlight": "border_selected",
    "grabber_disabled": "text_muted",
}

const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]

var _saved_theme: String = "default"
var _saved_shared: Theme = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_shared = SaUI.shared_theme


func after_each() -> void:
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared


## The hover derives from the gauge, like the handle it is drawn over, so the
## primary accent does not flash
## orange over the green fill.
func test_the_new_state_derives_from_the_gauge() -> void:
    assert_eq(String(SaPalette.STATE_BASES.get("slider_hover", "")), "accent_gauge", "slider_hover is a state with a base")
    assert_true(SaPalette.SLIDER_BOXES.has("hover"), "and the slider's table has a row for it")
    var fresh := SaPalette.new()
    fresh.derive_states()
    assert_eq(fresh.slider_hover, fresh.accent_gauge, "a palette nobody set derives it")


## A slider's fill is the palette's gauge rather than its orange
## fill, so orange on a slider no longer claims to mean on. White on Sara Green's
## gauge measures 4.84 to 1, where the orange measured 2.87.
func test_the_fill_is_the_gauge_in_sara_green_and_in_krita_grey() -> void:
    assert_eq(String(SaPalette.STATE_BASES.get("slider_handle", "")), "accent_gauge", "slider_handle derives from the gauge")
    var fresh := SaPalette.new()
    assert_eq(fresh.slider_handle, fresh.accent_gauge, "and a palette made in a script agrees before anything derives it")
    for id: String in ["default", "krita"]:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        assert_eq(palette.slider_handle, palette.accent_gauge, "%s: the fill is the gauge" % id)
        assert_true(palette.slider_handle != palette.accent_fill, "%s: and not the orange fill" % id)
        assert_eq(palette.slider_hover, palette.accent_gauge, "%s: and a hovered engine slider's fill is too" % id)
    SaTheme.use_named("default")
    var white_on_gauge := _contrast(Color.WHITE, SaTheme.palette.slider_handle)
    assert_true(white_on_gauge > 4.8, "White on Sara Green's fill measures %.2f to 1" % white_on_gauge)


func test_every_palette_grounds_the_engines_boxes() -> void:
    var engine := ThemeDB.get_default_theme()
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        var theme := SaUI.shared_theme
        for cls: String in GROUNDS:
            for box_name: String in GROUNDS[cls]:
                var field := String(GROUNDS[cls][box_name])
                var label := "%s: %s.%s" % [id, cls, box_name]
                assert_true(theme.has_stylebox(box_name, cls), "%s is on the shared theme" % label)
                var flat := theme.get_stylebox(box_name, cls) as StyleBoxFlat
                assert_not_null(flat, "%s is a flat box" % label)
                if flat == null:
                    continue
                assert_eq(flat.bg_color, SaTheme.palette.get(field), "%s grounds at %s" % [label, field])
                var theirs := engine.get_stylebox(box_name, cls)
                for side: Side in SIDES:
                    assert_eq(
                        flat.get_margin(side), theirs.get_margin(side), "%s keeps the engine's margin on side %d" % [label, side]
                    )


## A switch rewrites the same boxes in place, which is the whole reason they are
## bound: a theme built under one palette follows the next one.
func test_a_switch_repaints_the_boxes_and_the_discs() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var theme := SaUI.shared_theme
    var track := theme.get_stylebox("slider", "HSlider") as StyleBoxFlat
    assert_not_null(track, "the theme holds the track")
    SaTheme.use_named("paper")
    if track != null:
        assert_eq(track.bg_color, SaTheme.palette.slider_track, "the same object follows the switch")
    _assert_discs(theme, "paper after a switch")


func test_the_grabber_is_a_disc_in_the_palettes_text_colour() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        _assert_discs(SaUI.shared_theme, id)


func _assert_discs(theme: Theme, label: String) -> void:
    var engine := ThemeDB.get_default_theme()
    for cls: String in ["HSlider", "VSlider"]:
        for icon_name: String in DISCS:
            var key := String(DISCS[icon_name])
            assert_true(theme.has_icon(icon_name, cls), "%s: %s.%s is on the shared theme" % [label, cls, icon_name])
            if not theme.has_icon(icon_name, cls):
                continue
            var icon := theme.get_icon(icon_name, cls)
            assert_eq(
                icon.get_size(), engine.get_icon(icon_name, cls).get_size(), "%s: %s is the engine's size" % [label, icon_name]
            )
            var image := icon.get_image()
            var centre := image.get_pixel(int(image.get_width() * 0.5), int(image.get_height() * 0.5))
            var want: Color = SaTheme.palette.get(key)
            # Eight bits a channel is what a rasterised disc holds.
            var said := "%s: %s.%s centres on %s, %s against %s" % [label, cls, icon_name, key, centre.to_html(), want.to_html()]
            assert_true(_close(centre, want), said)
            assert_eq(image.get_pixel(0, 0).a, 0.0, "%s: and its corner is clear, so it is a disc" % label)


func _close(a: Color, b: Color) -> bool:
    var step := 1.5 / 255.0
    return absf(a.r - b.r) <= step and absf(a.g - b.g) <= step and absf(a.b - b.b) <= step and absf(a.a - b.a) <= step


## The WCAG contrast of *a* against *b*, both in the sRGB encoding.
func _contrast(a: Color, b: Color) -> float:
    var la := _luminance(a)
    var lb := _luminance(b)
    return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
    var linear := color.srgb_to_linear()
    return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
