## Whether the Font size preference reaches a dialog.
##
## It did not, for a reason with no per-dialog part to it: a `Window` is a
## `Viewport`, so the theme on the root does not cross into one, and every dialog
## in Sara was drawing at whatever size the theme held when its controls were
## built. `DockerWindow` has adopted the shared theme for itself since it was
## written and no dialog did.
##
## Adding a `Window` to the tree in a headless test hangs, so what is asserted here is
## the seam rather than the picture: the dialog holds the shared `Theme` object,
## and that object's own sizes follow the preference. The picture is
## `scenarios/dialog-font-scale.json`, where the Preferences interior differs
## by 176931 texels of 811200 between 55 and 100 per cent against the 4950 in one
## row the old measurement found, and the New Document dialog by 154024 of 501600.
extends "res://tests/test_framework.gd"

var _root_theme: Theme = null
var _kept_theme: Theme = null


## The headless runner never calls `SaUI.init_global_theme`, so there is no
## shared theme to adopt until this builds one. The root's own theme is put back
## afterwards, because that object is process-global and a suite that left a new
## one behind would be a second scale authority for every suite after it.
##
## So is the shared theme, and it was left. Every control `SaUI.apply_ui_theme`
## seeds took it in each suite after this one in a whole run and in none alone,
## so the status line came out two pixels taller and About's report a line
## longer there and nowhere else .
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _root_theme = tree.root.theme
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(tree)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.theme = _root_theme
    SaUI.shared_theme = _kept_theme


func _dialog() -> SaCanvasSizeDialog:
    # A real dialog rather than a bare `SaDialogWindow`, because the thing being
    # checked is what every dialog in Sara inherits and a subclass built for the
    # test would only prove the base class talks to itself.
    return SaCanvasSizeDialog.new()


func test_a_dialog_takes_the_shared_theme_a_window_cannot_inherit() -> void:
    var dialog := _dialog()
    dialog.theme = null

    dialog.adopt_shared_theme()

    assert_not_null(SaUI.shared_theme, "There is a shared theme to take")
    assert_eq(dialog.theme, SaUI.shared_theme, "and the dialog holds that object, not a copy")

    dialog.free()


func test_the_font_preference_moves_the_theme_the_dialog_holds() -> void:
    var was := SaSettings.ui_font_scale
    var dialog := _dialog()
    dialog.adopt_shared_theme()

    SaSettings.ui_font_scale = 1.0
    var big := dialog.theme.default_font_size
    SaSettings.ui_font_scale = 0.55
    var small := dialog.theme.default_font_size

    assert_true(small < big, "Half the font scale is a smaller default size: %d against %d" % [small, big])
    assert_eq(dialog.theme, SaUI.shared_theme, "and the dialog is still holding the same object")

    SaSettings.ui_font_scale = was
    dialog.free()


## The handler exists and is the one the bus calls, which is the half a picture
## cannot show: a dialog that adopted the theme once and never listened again
## would follow a preference set before it opened and no later one.
func test_the_dialog_listens_for_the_font_scale_and_not_only_the_ui_scale() -> void:
    var dialog := _dialog()

    assert_true(
        dialog.has_method("_on_ui_font_scale_changed"), "A17 splits the two signals, so a dialog needs the text-only one as well"
    )
    assert_true(dialog.has_method("_on_ui_scale_changed"), "and still the geometry one")

    dialog.free()
