## The Brush Presets search field reads its whole placeholder.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The docker at 310 wide once showed "Search pre", at 1920 by 1080 and
## at 1280 by 1024. The row's Size slider was meant to ask for 90 logical pixels
## and asked for 170, because the slider writes its own minimum from
## `preferred_width` whenever it refits and the chooser had written the minimum
## itself, so the write was gone when the slider entered the tree.
##
## The chooser is a real one in the tree under the app's theme, laid out at 310
## wide at scale 1, and the text is measured the way the control draws it: the
## field's font and size for the placeholder, inside the field's content box.
## What a painter sees is
## `scenarios/the-brush-presets-search-field-reads-its-whole-placeholder.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

## The width the Brush Presets docker opens at, in logical pixels.
const DOCKER_WIDTH := 310.0

## Never the real `user://brush_presets`, for `test_preset_chooser.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_d96_search_field")

var _saved_icon_size: int = 48


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


## A chooser in the tree under a host of *width*, themed the way a docker's
## contents are, with its search row laid out. A container outside the tree
## never sorts its children, which is why the host is on the event bus.
func _laid_out(width: float) -> Control:
    var host := Control.new()
    EventBus.add_child(host)
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    host.add_child(chooser)
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    SaUI.apply_ui_theme(chooser)
    chooser.size = Vector2(width, 400.0)
    chooser.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var row := chooser.search_field.get_parent() as Container
    row.size = Vector2(width, row.get_combined_minimum_size().y)
    row.notification(Container.NOTIFICATION_SORT_CHILDREN)
    return host


func _chooser_of(host: Control) -> SaBrushPresetsChooser:
    return host.get_child(0) as SaBrushPresetsChooser


## The width a text takes in a control's font, as the control draws it.
func _drawn(control: Control, text: String) -> float:
    var font := control.get_theme_font(&"font")
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size(&"font_size")).x


## The clause: the placeholder fits inside the field's content box.
func test_the_placeholder_fits_the_field_at_the_dockers_default_width() -> void:
    var host := _laid_out(DOCKER_WIDTH)
    var field := _chooser_of(host).search_field
    assert_eq(field.text, "", "The field is empty, so its placeholder is what it draws")
    assert_eq(field.placeholder_text, "Search presets", "and the placeholder is the whole phrase")
    var content := field.size.x - field.get_theme_stylebox(&"normal").get_minimum_size().x
    var needs := _drawn(field, field.placeholder_text)
    assert_true(content > 0.0, "The field has been laid out, %.1f wide" % field.size.x)
    assert_true(needs <= content, "The placeholder takes %.1f of the %.1f the field's content box has" % [needs, content])
    host.free()


## The slider still sits on the row beside the field, and its text is whole.
func test_the_size_slider_stays_on_the_row_with_its_text_whole() -> void:
    var host := _laid_out(DOCKER_WIDTH)
    var chooser := _chooser_of(host)
    var slider := chooser.size_slider
    assert_eq(slider.get_parent(), chooser.search_field.get_parent(), "The slider is on the search field's row")
    assert_eq(slider.prefix, "Size: ", "and its text still says Size")
    var text := slider.text_width()
    assert_true(slider.size.x >= text, "and its own width holds its widest text, %.1f of %.1f" % [text, slider.size.x])
    host.free()


## The cause rather than the symptom: the slider asks for the 90 the chooser
## wrote, or for its text if that is wider, and never for the 170 of a slider
## alone on a row.
func test_the_slider_asks_for_its_text_and_no_more() -> void:
    var host := _laid_out(DOCKER_WIDTH)
    var slider := _chooser_of(host).size_slider
    var wanted := maxf(float(SaUI.px(90)), slider.text_width() + float(DockerUtils.px(FactorSlider.TEXT_PADDING)))
    assert_almost_eq(slider.get_combined_minimum_size().x, wanted, 0.5, "The slider asks for %.1f" % wanted)
    var alone := float(SaUI.px(SaUI.BASE_FACTOR_SLIDER_W))
    assert_true(slider.get_combined_minimum_size().x < alone, "which is short of the %.0f of a slider alone on a row" % alone)
    host.free()


## The field takes the row less the slider and the gap, at a docker narrower
## than the default as well, so nothing else on the row holds a share of it.
func test_the_field_gets_what_the_slider_leaves() -> void:
    var host := _laid_out(280.0)
    var chooser := _chooser_of(host)
    var field := chooser.search_field
    var slider := chooser.size_slider
    var row := field.get_parent() as Container
    var separation := float(row.get_theme_constant(&"separation"))
    assert_almost_eq(field.size.x, 280.0 - separation - slider.size.x, 0.5, "The field takes the row less the slider and the gap")
    host.free()
