## A theme switch tells the shared theme's windows once.
##
## Every colour written into a `Theme` and every change of a box it holds emits
## the theme's `changed`, and a window wearing the theme answers each emission
## with a deferred walk of its tree. A switch writes hundreds of them, and an
## open Preferences spent 14 to 44 seconds in one frame on the walks. The switch
## hushes the theme and announces once, which is what this counts.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"
var _saved_shared: Theme = null
var _heard: int = 0


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_shared = SaUI.shared_theme
    _heard = 0


func after_each() -> void:
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared


func _on_changed() -> void:
    _heard += 1


func test_a_switch_emits_the_shared_themes_changed_once() -> void:
    # The runner is not the app, so nothing has built the shared theme yet.
    # Built here and put back, the way `test_theme_defaults` does.
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var shared := SaUI.shared_theme
    shared.changed.connect(_on_changed)
    SaTheme.use_named("photoshop")
    shared.changed.disconnect(_on_changed)
    assert_eq(_heard, 1, "One `changed` for the whole switch, not one per colour and box")
    assert_false(shared.is_blocking_signals(), "and the theme is left speaking afterwards")
    var photoshop := load(SaTheme.PALETTES["photoshop"]) as SaPalette
    var box := shared.get_stylebox("normal", "Button") as StyleBoxFlat
    assert_not_null(box, "The theme holds a push button's box")
    if box != null:
        assert_eq(box.bg_color, photoshop.button_normal, "The hushed writes still landed in the theme's boxes")
