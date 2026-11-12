## The presets grid follows its host's width and its theme's font without a
## rebuild.
##
## The note is "first opening of the presets looks like this, after any action,
## the spacing gets fixed", with two columns spread over a docker with room for
## five and the buttons under the grid pushed out of sight. `refresh` counted
## the columns once, at boot, inside a hidden window whose containers sort
## nothing, and declared each name's floor from the engine's font because the
## docker had no theme yet. Any action rebuilt the grid against the real width
## and the real font, which is what "gets fixed" was.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d1_presets_first_show")

var _saved_icon_size: int = 48


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    SaSettings.preset_icon_size = 48
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


## A chooser in a host that declares its width, the shape `test_chooser_columns.gd`
## builds, so the two suites count against the same number. In the tree, under
## an autoload the way `test_a_move_keeps_the_row.gd` puts a docker there,
## because a `resized` signal and a theme notification reach nothing outside it.
func _hosted(host_width: int) -> Array:
    var host := VBoxContainer.new()
    host.custom_minimum_size = Vector2(float(host_width), 0.0)
    host.size = Vector2(float(host_width), 400.0)
    EventBus.add_child(host)
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return [host, chooser]


## The first show: the grid was counted against a narrow host and the host then
## grew to the width the painter sees. The count follows the width, and the
## cells are the ones that were built, so nothing was rebuilt to get there. A
## hundred wide holds one cell of 48, and six hundred holds every shipped one.
func test_a_wider_host_recounts_without_a_rebuild() -> void:
    var pair := _hosted(100)
    var host: VBoxContainer = pair[0]
    var chooser: SaBrushPresetsChooser = pair[1]
    var narrow: int = chooser.grid.columns
    var cells := chooser.grid.get_children()
    host.custom_minimum_size.x = 600.0
    host.size.x = 600.0
    chooser.size.x = 600.0
    var wide: int = chooser.grid.columns
    assert_true(wide > narrow, "The wider host counts more columns, %d over %d" % [wide, narrow])
    assert_eq(chooser._columns_that_fit(), wide, "and the count is the one a fresh count gives")
    assert_eq(chooser.grid.get_children(), cells, "with the cells it had, not new ones")
    host.free()


## The floor a name declares is two lines of the font the theme gives it, so a
## theme that arrives after the cells were built moves the floor with it.
func test_the_name_floor_follows_the_theme() -> void:
    var pair := _hosted(300)
    var host: VBoxContainer = pair[0]
    var chooser: SaBrushPresetsChooser = pair[1]
    var label := chooser.grid.get_child(0).get_node("Name") as Label
    var before := label.custom_minimum_size.y
    var bigger := Theme.new()
    bigger.default_font_size = label.get_theme_font_size("font_size") * 2
    chooser.theme = bigger
    var font := label.get_theme_font("font")
    var expected := font.get_height(bigger.default_font_size) * float(SaBrushPresetsChooser.NAME_LINES)
    assert_true(
        label.custom_minimum_size.y > before,
        "The floor grew with the font, %.1f over %.1f" % [label.custom_minimum_size.y, before]
    )
    assert_almost_eq(label.custom_minimum_size.y, expected, 0.5, "and it is two lines of the new font")
    assert_almost_eq(label.custom_minimum_size.y, chooser._name_height(), 0.5, "which is what a cell built now would declare")
    host.free()
