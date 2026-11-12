## A tab container's panel is drawn from the palette, not Godot's
## dark default.
##
## A tab container's panel must not stay the engine's black, which on Paper
## White's cream read as `#706f6e` and made text hard to read.
## The `panel` box a `TabContainer` draws behind its pages
## was Godot's own, a black at `(0.1, 0.1, 0.1, 0.6)`. Under the dark palettes
## that black is close to the window's own colour, which is why it went unseen.
##
## Held here: the Welcome window's own `Panes`, built under every shipped
## palette, draws its page in the palette's page colour, and the muted
## descriptions on it read against that. Beside it is a sweep: every class
## Sara's UI makes, stood in a tree under the shared theme, and no box of it
## the engine's own unless it is named below with the reason it stays.
extends "res://tests/test_framework.gd"

## The WCAG ratio for text that has to stay readable.
const READABLE := 4.5

## How far a channel of the panel may sit from the palette's page colour.
const NEAR := 0.02

## Every class Sara's UI makes that draws a box of its own, built by name here
## so that a class added tomorrow is one line away from being swept. The
## windows (`PopupMenu`, `PopupPanel` and the rest) are not `Control`s and are
## held by `test_theme_defaults.gd` and the strip suites. `Tree` is not here
## because nothing in Sara builds one: the engine's fallback `FileDialog`, which
## a platform with no native picker reaches, is the only place a `Tree` shows.
const SWEPT: Array[String] = [
    "Panel",
    "PanelContainer",
    "TabContainer",
    "TabBar",
    "ScrollContainer",
    "ItemList",
    "RichTextLabel",
    "LinkButton",
    "FoldableContainer",
    "ColorPicker",
    "ColorPickerButton",
    "Button",
    "CheckBox",
    "CheckButton",
    "OptionButton",
    "MenuButton",
    "MenuBar",
    "SpinBox",
    "HSlider",
    "VSlider",
    "HScrollBar",
    "VScrollBar",
    "LineEdit",
    "TextEdit",
    "HSplitContainer",
    "HSeparator",
    "VSeparator",
]

## The boxes that stay the engine's, each with the reason. `Class/box`.
const STAYS := {
    "OptionButton/normal_mirrored": "right to left layouts only, and Sara draws none",
    "OptionButton/hover_mirrored": "right to left layouts only, and Sara draws none",
    "OptionButton/pressed_mirrored": "right to left layouts only, and Sara draws none",
    "OptionButton/disabled_mirrored": "right to left layouts only, and Sara draws none",
    "TabBar/button_pressed": "the close button of a tab, which Sara's tab bars never show",
    "TabBar/button_highlight": "the close button of a tab, which Sara's tab bars never show",
}


func _saved() -> Array:
    return [SaUI.shared_theme, SaTheme.palette_id]


func _restore(saved: Array) -> void:
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme


## A host under the real tree whose theme is the shared one, the way a window
## wears it. The suite never shows a `Window`, which hangs the run.
func _host() -> Control:
    SaUI.init_global_theme(null)
    var host := Control.new()
    host.theme = SaUI.shared_theme
    EventBus.add_child(host)
    return host


## The WCAG contrast of *a* against *b*, both in the sRGB encoding.
func _contrast(a: Color, b: Color) -> float:
    var la := _luminance(a)
    var lb := _luminance(b)
    return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
    var channels: Array[float] = []
    for v: float in [c.r, c.g, c.b]:
        channels.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < NEAR and absf(a.g - b.g) < NEAR and absf(a.b - b.b) < NEAR and absf(a.a - b.a) < NEAR


## The Welcome window's own tab container, taken out of the window that built
## it and stood under *host*, with the panes it holds.
func _panes(host: Control) -> TabContainer:
    var window := SaWelcomeWindow.new()
    var tabs := window.tabs
    tabs.get_parent().remove_child(tabs)
    host.add_child(tabs)
    window.free()
    return tabs


func test_the_panes_panel_is_the_palettes_page_under_every_shipped_palette() -> void:
    var saved := _saved()
    var seen := 0
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var host := _host()
        var tabs := _panes(host)
        var box := tabs.get_theme_stylebox("panel") as StyleBoxFlat
        assert_not_null(box, "%s: the panes' panel is a flat box" % id)
        if box != null:
            seen += 1
            var page := _near(box.bg_color, SaTheme.palette.bg_primary)
            assert_true(page, "%s: the panel is the page colour, not %s" % [id, box.bg_color])
            assert_true(box.bg_color.a >= 1.0, "%s: and it is opaque, so nothing under it shows through" % id)
            assert_true(_near(box.border_color, SaTheme.palette.border_secondary), "%s: with the palette's rim" % id)
        host.free()
    assert_eq(seen, SaTheme.PALETTES.size(), "every shipped palette was read")
    _restore(saved)


func test_the_muted_text_on_the_panel_reads_under_every_shipped_palette() -> void:
    var saved := _saved()
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var host := _host()
        var tabs := _panes(host)
        var ground := (tabs.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
        var muted := 0
        for node: Node in tabs.get_child(3).find_children("*", "Label", true, false):
            var label := node as Label
            if label.text.strip_edges().is_empty() or label.get_theme_color("font_color") != SaTheme.palette.text_muted:
                continue
            muted += 1
            var ratio := _contrast(label.get_theme_color("font_color"), ground)
            assert_true(ratio >= READABLE, "%s: %s reads %.2f to 1" % [id, label.text.left(24), ratio])
        assert_true(muted > 0, "%s: Quick settings carries muted descriptions to read" % id)
        host.free()
    _restore(saved)


## A switch rewrites the box in place, so the Welcome window left open while the
## painter picks a theme in its own Quick settings follows without a rebuild.
func test_a_theme_switch_repaints_the_panel_where_it_stands() -> void:
    var saved := _saved()
    SaTheme.use_named("default")
    var host := _host()
    var tabs := _panes(host)
    var before := (tabs.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
    assert_true(_near(before, SaTheme.palette.bg_primary), "built under the default palette it is that palette's page")
    SaTheme.use_named("paper")
    var after := (tabs.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
    assert_true(_near(after, SaTheme.palette.bg_primary), "and after the switch it is Paper White's, without a rebuild")
    assert_true(_luminance(after) > 0.5, "which is the cream and not the dark: %s" % after)
    host.free()
    _restore(saved)


## The engine's margin is what the table says it is, since the table is read off
## `ThemeDB.get_default_theme()` and a control that padded differently would
## move every row it holds.
func test_the_frames_keep_the_margins_the_engine_gave_the_boxes() -> void:
    var engine := ThemeDB.get_default_theme()
    var read := 0
    for cls: String in SaThemeFrames.FRAMES:
        var frame: Dictionary = SaThemeFrames.FRAMES[cls]
        for box_name: String in frame:
            var theirs := engine.get_stylebox(box_name, cls) as StyleBoxFlat
            assert_not_null(theirs, "%s/%s is a flat box in the engine's theme" % [cls, box_name])
            if theirs == null:
                continue
            read += 1
            var margin: int = int((frame[box_name] as Array)[1])
            assert_eq(int(theirs.content_margin_left), margin, "%s/%s: the table's margin is the engine's" % [cls, box_name])
    assert_true(read > 20, "the walk read the table: %d boxes" % read)


## The sweep: a control of each
## class Sara makes, stood in a tree under the shared theme, resolves no box to
## the very object the engine's own theme holds, except where named above. An
## empty box draws nothing and is not counted.
func test_no_class_sara_makes_draws_a_box_that_is_still_the_engines() -> void:
    var saved := _saved()
    var engine := ThemeDB.get_default_theme()
    var host := _host()
    var strays: Array[String] = []
    var checked := 0
    for cls: String in SWEPT:
        var control := ClassDB.instantiate(cls) as Control
        host.add_child(control)
        var chain := cls
        while chain != "" and chain != "Object":
            for box_name: String in engine.get_stylebox_list(chain):
                var theirs := engine.get_stylebox(box_name, chain)
                if theirs is StyleBoxEmpty or control.has_theme_stylebox_override(box_name):
                    continue
                checked += 1
                if control.get_theme_stylebox(box_name) == theirs and not STAYS.has("%s/%s" % [chain, box_name]):
                    strays.append("%s/%s" % [chain, box_name])
            chain = ClassDB.get_parent_class(chain)
    assert_true(checked > 100, "the sweep read the boxes: %d" % checked)
    assert_eq(strays, [] as Array[String], "every box Sara's classes draw is the palette's")
    host.free()
    _restore(saved)
