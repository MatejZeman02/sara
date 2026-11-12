## The paper's colour popup is opaque.
##
## With a Paper layer active, the first Colours swatch
## would open a picker whose lower half was translucent, so "Swatches" overprinted
## "Tooth" and the layer rows showed through the RGB sliders. A probe through
## this suite read both halves of the cause. The engine opens a `PopupPanel` as
## a transparent window, and the shared theme held no `PopupPanel` box, so the
## popup drew the engine's own, whose ground is `(0.1, 0.1, 0.1, 0.6)`. The
## upper half of a picker draws grounds of its own and the lower half does not,
## which is why only that half let the docker through.
##
## The suite builds the rows under a window flagged the way a docker is, and
## reads the swatch's popup in every shipped palette: its window draws no
## transparency, and the box it resolves is the shared theme's and opaque. A
## popup panel built by hand, as the colour ramp and the palette filter build
## theirs, resolves the same box.
extends "res://tests/test_framework.gd"


func _saved() -> Array:
    return [SaUI.shared_theme, SaTheme.palette_id]


func _restore(saved: Array) -> void:
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme


## A window flagged as `docker_window.gd` flags a docker, with a `Control`
## wearing the shared theme in it, which is what gives the popup a theme owner
## to resolve through.
func _docker_like() -> Window:
    var window := Window.new()
    window.name = "S51DockerLike"
    window.borderless = true
    window.transparent = true
    window.transparent_bg = true
    window.visible = false
    EventBus.add_child(window)
    var root := Control.new()
    root.theme = SaUI.shared_theme
    window.add_child(root)
    return window


func _assert_opaque(popup: PopupPanel, what: String) -> void:
    var box := popup.get_theme_stylebox(&"panel") as StyleBoxFlat
    assert_true(box != null, "%s: the popup resolves a flat box" % what)
    if box == null:
        return
    assert_true(box == SaUI.shared_theme.get_stylebox(&"panel", &"PopupPanel"), "%s: the box is the shared theme's" % what)
    assert_eq(box.bg_color.a, 1.0, "%s: its ground is opaque" % what)


func test_the_swatch_popup_is_opaque_in_every_shipped_palette() -> void:
    var saved := _saved()
    for palette_id: String in SaTheme.PALETTES:
        SaTheme.use_named(palette_id)
        SaUI.init_global_theme(null)
        var window := _docker_like()
        var rows := SaGroundRows.new()
        window.get_child(0).add_child(rows)
        assert_eq(rows.swatches.size(), 2, "%s: the rows hold both swatches" % palette_id)
        for key: String in rows.swatches:
            var popup := (rows.swatches[key] as ColorPickerButton).get_popup()
            var what := "%s, %s" % [palette_id, key]
            assert_false(popup.transparent, "%s: the popup's window draws no transparency" % what)
            assert_false(popup.transparent_bg, "%s: nor a transparent ground" % what)
            _assert_opaque(popup, what)
        window.free()
    _restore(saved)


## The colour ramp's stop and the palette filter's chip each build a
## `PopupPanel` by hand, and the box is what makes them opaque as well.
func test_a_popup_panel_built_by_hand_resolves_the_same_box() -> void:
    var saved := _saved()
    SaTheme.use_named("paper")
    SaUI.init_global_theme(null)
    var window := _docker_like()
    var popup := PopupPanel.new()
    window.get_child(0).add_child(popup)
    _assert_opaque(popup, "a hand-built popup")
    window.free()
    _restore(saved)
