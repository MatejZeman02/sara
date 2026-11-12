## A control nobody styled is drawn in the palette, not in Godot's theme.
##
## `SaTheme.bind_font` is opt-in and almost nobody
## opted in, so half of Preferences, the menu bar and every layer name kept the
## engine's white and were unreadable the moment a light palette shipped. The
## fix is a default on the shared `Theme`, and what has to be held is that the
## default is there, that it follows a switch, that an explicit override still
## beats it, and that a real page built from real code has no text left over.
##
## The last of those is the one worth more than the fix: a
## walk of a built Preferences window that fails on a `Label` whose effective
## `font_color` is neither `text_primary` nor `text_muted`. It is written
## against the window rather than against a list of call sites,
## so a call site added tomorrow is covered without an edit here.
extends "res://tests/test_framework.gd"

## The two the palette says interface text is drawn in. A third colour on a
## label is either a mistake or something that has to be argued for here.
const TEXT_KEYS: Array[String] = ["text_primary", "text_muted"]


func _saved() -> Array:
    return [SaUI.shared_theme, SaTheme.palette_id]


func _restore(saved: Array) -> void:
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme


## The gate runs `res://tests/run_all.tscn` rather than the app, so nothing has
## built the shared theme yet. Built here and put back, the way `test_ui_font`
## and `test_color_space_dialog_floor` do.
func _fresh_theme() -> Theme:
    SaUI.init_global_theme(null)
    return SaUI.shared_theme


func test_the_shared_theme_carries_the_palettes_text_colour() -> void:
    var saved := _saved()
    SaTheme.use_named("default")
    var theme := _fresh_theme()
    assert_not_null(theme, "init_global_theme leaves a theme behind")
    for cls: String in SaThemeDefaults.COLORS:
        var keys: Dictionary = SaThemeDefaults.COLORS[cls]
        for color_name: String in keys:
            assert_true(theme.has_color(color_name, cls), "%s carries %s" % [cls, color_name])
            assert_eq(
                theme.get_color(color_name, cls),
                SaTheme.palette.get(keys[color_name]),
                "%s/%s is the palette's %s" % [cls, color_name, keys[color_name]]
            )
    _restore(saved)


## The whole reason the defect exists: a control that asked for nothing.
##
## Inside the tree rather than beside it, because a detached Control has no
## theme owner: `get_theme_color` on one answers `ThemeDB`'s default whatever
## is on its `theme`, and the first draft of this test read Godot's own white
## for the palette's and passed on a Label for that reason alone.
func test_an_unstyled_label_under_the_theme_reads_the_palette() -> void:
    var saved := _saved()
    SaTheme.use_named("default")
    var theme := _fresh_theme()
    var host := Node.new()
    host.name = "D12ThemeOwnerHost"
    EventBus.add_child(host)
    var root := Control.new()
    root.theme = theme
    host.add_child(root)
    var label := Label.new()
    root.add_child(label)
    assert_eq(
        label.get_theme_color("font_color"),
        SaTheme.palette.text_primary,
        "A Label nobody touched is drawn in the palette's text colour"
    )

    var button := Button.new()
    root.add_child(button)
    assert_eq(button.get_theme_color("font_color"), SaTheme.palette.text_primary, "and so is a Button")

    var field := LineEdit.new()
    root.add_child(field)
    assert_eq(field.get_theme_color("font_color"), SaTheme.palette.text_primary, "and a LineEdit's text")
    var box := field.get_theme_stylebox("normal") as StyleBoxFlat
    assert_not_null(box, "and its ground is a box the palette holds")
    if box != null:
        assert_eq(box.bg_color, SaTheme.palette.bg_input, "at the palette's input colour, not the engine's grey")
    host.free()
    _restore(saved)


## A default that does not follow a switch would be the same bug with a
## different constant in it.
func test_the_default_follows_a_theme_switch() -> void:
    var saved := _saved()
    SaTheme.use_named("default")
    var theme := _fresh_theme()
    var dark := theme.get_color("font_color", "Label")
    var dark_ground := (theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat).bg_color

    SaTheme.use_named("paper")
    var light := theme.get_color("font_color", "Label")
    var light_ground := (theme.get_stylebox("normal", "LineEdit") as StyleBoxFlat).bg_color

    assert_eq(light, SaTheme.palette.text_primary, "The switch wrote Paper White's text colour onto the theme")
    assert_true(dark != light, "which is not the colour the dark palette left there")
    assert_eq(light_ground, SaTheme.palette.bg_input, "and the field's ground followed as a bound box")
    assert_true(dark_ground != light_ground, "rather than staying where the dark palette put it")
    _restore(saved)


## `bind_font` is what the hint lines under Preferences rows use, and the whole
## point of a theme default is that it is a default.
func test_an_override_still_beats_the_default() -> void:
    var saved := _saved()
    SaTheme.use_named("default")
    var theme := _fresh_theme()
    var host := Node.new()
    host.name = "D12OverrideHost"
    EventBus.add_child(host)
    var root := Control.new()
    root.theme = theme
    host.add_child(root)
    var label := Label.new()
    root.add_child(label)
    SaTheme.bind_font(label, "text_muted")
    assert_eq(label.get_theme_color("font_color"), SaTheme.palette.text_muted, "A bound font colour wins over the theme")

    SaTheme.use_named("paper")
    assert_eq(label.get_theme_color("font_color"), SaTheme.palette.text_muted, "and still wins after a switch")
    host.free()
    _restore(saved)


## The test the section asked for: a real Preferences window, walked.
func test_no_label_in_preferences_is_drawn_outside_the_palette() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree")
    if tree == null:
        return
    var saved := _saved()
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaTheme.use_named("paper")
    _fresh_theme()

    var host := Node.new()
    host.name = "D12PreferencesHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()

    var allowed: Array[Color] = []
    for key: String in TEXT_KEYS:
        allowed.append(SaTheme.palette.get(key))

    var strays: Array[String] = []
    var read := 0
    for node: Node in _every(window):
        var text := node as Label
        if text == null or text.text.strip_edges().is_empty():
            continue
        read += 1
        if not allowed.has(text.get_theme_color("font_color")):
            strays.append("%s: %s" % [text.text.left(30), text.get_theme_color("font_color")])
    # Or the walk found nothing and the assertion under it is vacuous, which is
    # how a test of this shape goes quietly green after the window is rebuilt.
    assert_true(read > 10, "The walk read the page's labels: %d of them" % read)
    assert_eq(strays, [] as Array[String], "Every label in Preferences is drawn in a colour the palette holds")

    window.hide()
    host.free()
    tree.root.gui_embed_subwindows = was_embedding
    _restore(saved)


func _every(root: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child: Node in root.get_children(true):
        out.append(child)
        out.append_array(_every(child))
    return out
