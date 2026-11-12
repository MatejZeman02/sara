## The preset chooser counts its columns once per width.
##
## `refresh()` took the count from `size.x`, the width the control had grown to,
## and the grid's own minimum width is what had grown it. So the grid fed itself:
## more columns, a wider host, more columns. Measured on the running app, before
## the fix, the same icon
## size gave `cols=4` then `cols=6` in one session, 30 gave 8 then 10, and a drag
## of the slider from 80 down to 30 ended at 12 columns for six presets. After
## it, 49 readings over seven icon sizes carry one count each.
##
## The width now comes from `get_parent_area_size()`, the room the parent
## container has for this control, and the pitch is measured off a cell rather
## than guessed at `icon + 8`, so `columns * pitch` is never more than the width
## it was counted against.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke through the real paint path, which is
## what `ui/presets/tests/test_preset_chooser.gd` needs one for too.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_chooser_columns")

var _saved_icon_size: int = 48


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


## A chooser inside a host of a fixed width, which is the shape both real hosts
## have: the bar's popup gives it a 300 logical unit column and the docker gives it the
## docker's own width.
func _hosted(host_width: int = 300) -> Array:
    var host := VBoxContainer.new()
    host.custom_minimum_size = Vector2(float(SaUI.px(host_width)), 0.0)
    host.size = Vector2(float(SaUI.px(host_width)), 400.0)

    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return [host, chooser]


## The regression. Six refreshes at one icon size, one column count, which is the
## clause the filing asks for and the thing the old arithmetic could not do.
func test_one_icon_size_gives_one_column_count() -> void:
    for icon: int in [30, 48, 80]:
        var pair := _hosted()
        var chooser: SaBrushPresetsChooser = pair[1]
        SaSettings.preset_icon_size = icon
        chooser.refresh()
        var first: int = chooser.grid.columns
        for _i in 5:
            chooser.refresh()
            assert_eq(chooser.grid.columns, first, "Icon %d still counts %d columns" % [icon, first])
        (pair[0] as Node).free()


## The drag a painter makes, from the ceiling to the floor, which is fifty
## refreshes on the real slider. The count it ends on is the count a fresh
## chooser at that size gives, rather than whatever the walk down left behind.
func test_a_drag_down_ends_where_a_fresh_chooser_starts() -> void:
    var fresh := _hosted()
    SaSettings.preset_icon_size = 30
    (fresh[1] as SaBrushPresetsChooser).refresh()
    var alone: int = (fresh[1] as SaBrushPresetsChooser).grid.columns
    (fresh[0] as Node).free()

    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    for icon: int in [80, 70, 60, 50, 40, 30]:
        SaSettings.preset_icon_size = icon
        chooser.refresh()
    assert_eq(chooser.grid.columns, alone, "The drag ends on the %d a fresh chooser gives" % alone)
    (pair[0] as Node).free()


## The grid never asks its host for more room than the count was made against,
## which is the property that makes the ratchet impossible rather than merely
## absent from one measurement.
func test_the_grid_never_asks_for_more_than_it_was_given() -> void:
    for icon: int in [30, 48, 80]:
        var pair := _hosted()
        var chooser: SaBrushPresetsChooser = pair[1]
        SaSettings.preset_icon_size = icon
        chooser.refresh()
        var given: float = chooser._host_width()
        var asked: float = chooser.grid.get_combined_minimum_size().x
        assert_true(asked <= given + 0.5, "At icon %d the grid asks %.1f of %.1f" % [icon, asked, given])
        (pair[0] as Node).free()


## Six presets have no use for eleven columns, which is the second half of the
## clamp and the one a very wide docker would otherwise show.
func test_the_count_never_passes_the_number_of_cells() -> void:
    var pair := _hosted(2000)
    var chooser: SaBrushPresetsChooser = pair[1]
    SaSettings.preset_icon_size = 30
    chooser.refresh()
    assert_eq(chooser.grid.columns, chooser.visible_names().size(), "A very wide host gives one column per cell")
    (pair[0] as Node).free()


## A name longer than its picture does not widen its cell past the name column,
## which is one width for the whole grid taken from the names and the font
## (the name column). `text_overrun_behavior` decides how a too-long name is drawn
## and leaves the box as wide as the whole name, which is where the widening
## came from, so the name still wraps and asks for the column and not itself.
func test_a_long_name_does_not_widen_a_cell() -> void:
    SaSettings.preset_icon_size = 30
    var pair := _hosted()
    var chooser: SaBrushPresetsChooser = pair[1]
    var column := chooser.name_width()
    for cell: Node in chooser.grid.get_children():
        var label := cell.get_node("Name") as Label
        assert_true(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "The name wraps rather than being allowed to set the width")
        assert_true(
            label.get_combined_minimum_size().x <= column + 0.5,
            "and asks for the name column's width, %.1f of %.1f" % [label.get_combined_minimum_size().x, column]
        )
    (pair[0] as Node).free()
