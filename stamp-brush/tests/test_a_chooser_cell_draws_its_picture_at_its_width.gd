## A chooser cell draws its picture across the cell, not twenty pixels wide (d24).
##
## The claim was a shot: the Brush Presets docker drew every thumbnail at about
## a quarter of its cell, in the corner. The cause is the theme `SaUI` writes,
## which caps every `Button`'s icon at `BASE_ICON_SIZE`, and a cell is a `Button`
## with `expand_icon` on, whose expanded picture the cap applies to as well.
##
## `test_preset_thumbs.gd` reads the PNG before any button draws it,
## so it could not see this. These cases build the chooser under a host carrying
## the cap the way the root window does, and read what the cell's button resolves.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke or dab through the real paint path.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d24_chooser_cell_icon")

## The share of its cell a picture has to span, which is the bar the thumbnail suite holds too.
const SPAN: float = 0.75

var _saved_icon_size: int = 48
var _saved_tip: bool = false


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    _saved_tip = SaSettings.preset_thumb_tip
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    SaSettings.preset_thumb_tip = _saved_tip
    ScratchFolder.clear(scratch_dir)


## A host carrying the icon cap `SaUI.init_global_theme` writes for every
## `Button`, so a cell resolves its constants the way it does in the docker.
##
## In the tree, because a theme on a detached parent reaches none of its
## children: the first cut of this built the host bare and a plain button under
## it read no cap at all, which would have left every case below green on the
## unfixed chooser. On an autoload rather than the root, which is busy readying
## the runner and refuses the child.
func _themed_host() -> VBoxContainer:
    var theme := Theme.new()
    theme.set_constant("icon_max_width", "Button", SaUI.px(SaUI.BASE_ICON_SIZE))
    var host := VBoxContainer.new()
    host.theme = theme
    host.custom_minimum_size = Vector2(float(SaUI.px(420)), 0.0)
    host.size = Vector2(float(SaUI.px(420)), 600.0)
    EventBus.add_child(host)
    return host


func _drop(host: Control) -> void:
    EventBus.remove_child(host)
    host.free()


## A finished chooser under the themed host, every cell carrying its picture.
func _chooser_in(host: Control) -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    chooser.capture_finish()
    return chooser


## How wide `Button` draws an expanded icon on *button*: the picture fitted into
## the content box at its own aspect, then held to `icon_max_width` when that is
## above zero. The button's declared size stands in for its laid out one, which is
## what a cell set to shrink is given.
func _drawn_width(button: Button, cap: int) -> float:
    var style := button.get_theme_stylebox("normal")
    var box := button.custom_minimum_size
    if style != null:
        box -= style.get_minimum_size()
    var picture := button.icon.get_size()
    var width := picture.x * box.y / picture.y
    width = minf(width, box.x)
    if cap > 0:
        width = minf(width, float(cap))
    return width


## The control: a plain button under the host reads the cap, so the host is
## carrying what the root window carries and the cases below are not green
## because no theme reached them.
func test_the_host_caps_a_plain_button() -> void:
    var host := _themed_host()
    var plain := Button.new()
    host.add_child(plain)
    assert_eq(plain.get_theme_constant("icon_max_width"), SaUI.px(SaUI.BASE_ICON_SIZE), "A plain button is capped at 20")
    _drop(host)


## Every cell is uncapped, in both choices and at both ends the claim was shot at.
func test_no_cell_takes_the_themes_icon_cap() -> void:
    for tip: bool in [true, false]:
        for icon: int in [SaBrushPresetsChooser.MAX_ICON, 48]:
            SaSettings.preset_icon_size = icon
            SaSettings.preset_thumb_tip = tip
            var host := _themed_host()
            var chooser := _chooser_in(host)
            assert_true(chooser.grid.get_child_count() > 0, "The grid has cells")
            for cell: Node in chooser.grid.get_children():
                var button := cell.get_node("Icon") as Button
                assert_eq(
                    button.get_theme_constant("icon_max_width"),
                    0,
                    "%s at %d, tip %s, is not capped" % [cell.name, icon, str(tip)]
                )
            _drop(host)


## The proof the filing asks for: a cell's picture is drawn across the cell. The
## same rule with the theme's cap put back draws it at a quarter, which is the
## shot the claim measured, so the rule is not green whatever it is handed.
func test_a_cell_draws_its_picture_at_its_width() -> void:
    for tip: bool in [true, false]:
        SaSettings.preset_icon_size = SaBrushPresetsChooser.MAX_ICON
        SaSettings.preset_thumb_tip = tip
        var host := _themed_host()
        var chooser := _chooser_in(host)
        for cell: Node in chooser.grid.get_children():
            var button := cell.get_node("Icon") as Button
            assert_not_null(button.icon, "%s carries its picture" % cell.name)
            if button.icon == null:
                continue
            var width := button.custom_minimum_size.x
            var drawn := _drawn_width(button, button.get_theme_constant("icon_max_width"))
            assert_true(drawn >= width * SPAN, "%s, tip %s, draws %.1f of %.1f" % [cell.name, str(tip), drawn, width])
            var capped := _drawn_width(button, SaUI.px(SaUI.BASE_ICON_SIZE))
            assert_true(capped < width * SPAN, "and the theme's cap would have drawn %.1f" % capped)
        _drop(host)
