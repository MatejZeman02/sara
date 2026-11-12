## The colour space picker as a window of its own, which a place that asks for
## a colour space with a single row opens from that row's "Custom..." entry.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to `ui/color_space/picker`: the hosts reach it through
## `SaColorSpaceRow`, which opens it and stores what it answers. File > New and
## Image > Colour Space show the picker's rows on their own page instead,
## because the rows fit there and a window would add two clicks.
##
## The page scrolls and the buttons stay under it, as in every dialog, so a
## short host never puts Use out of reach.
@tool
class_name SaColorSpacePickerDialog
extends SaDialogWindow

## Use was pressed with the rows on *space*.
signal answered(space: SaColorSpace)

## The size asked for, and the floor, in logical units. The rows want about
## 420 wide, and the drawing under them scrolls.
const DEFAULT_SIZE: Vector2i = Vector2i(640, 620)
const FLOOR_SIZE: Vector2i = Vector2i(440, 320)
const SEPARATION: int = 10

## The rows and the space they add up to, bound through the page as `picker`.
var picker := SaColorSpacePicker.new()
## The picker's rows, realized into the scrolling column.
var page: SaPage = null
## The drawing of what the rows add up to, under them.
var browser: SaColorSpaceBrowser = null
var use_button: Button = null
var cancel_button: Button = null
## What the host takes of the space, shown only when it takes less than all.
var _note_label: Label = null
## Why a profile file was refused, or empty.
var _status_label: Label = null


func _init() -> void:
    _init_dialog("ColorSpacePickerDialog", tr("Colour Space"), DEFAULT_SIZE, FLOOR_SIZE)
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SEPARATION)
    var scroll := SaMake.scroll(column, "PickerScroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = scroll
    var body := SaMake.column(scroll, "Page", SEPARATION)
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var rows := SaMake.column(body, "PickerRows")
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(rows)
    page.row_changed.connect(func(key: StringName, _value: Variant) -> void: picker.row_changed(key))
    picker.moved.connect(_on_moved)
    browser = picker.make_browser()
    browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(browser)

    _note_label = SaMake.label(
        column,
        "NoteLabel",
        tr("The display and the proof take the gamut and the white point. The tone curve stays the display's own.")
    )
    _note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _note_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    SaTheme.bind_font(_note_label, "text_muted")
    _note_label.visible = false
    _status_label = SaMake.label(column, "StatusLabel")
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    var buttons := pinned_buttons(column)
    cancel_button = SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    use_button = SaMake.button(buttons, "UseButton", tr("Use"), tr("Use the colour space the rows above add up to."))
    use_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    use_button.pressed.connect(_use)
    default_button = use_button


## Every row of the picker but the depth, which belongs to the document and
## not to a choice of colours.
func _declare(ui: SaPage) -> void:
    ui.section("")
    picker.declare_picked(ui, self, &"picker", "Colour space", false)
    picker.declare_details(ui, self, &"picker")


## Puts the rows on *space*, and says the curve is set aside when the host
## takes only the *gamut_only* part of it.
func configure(space: SaColorSpace, gamut_only: bool) -> void:
    picker.show_space(space if space != null else SaColorSpace.srgb())
    _note_label.visible = gamut_only


func _on_moved() -> void:
    if page != null:
        page.refresh()
    if _status_label != null:
        _status_label.text = picker.profile_problem


func _use() -> void:
    answered.emit(picker.selected_space())
    hide()


## The rows, the buttons and whether each lies inside the window, for the dump.
static func capture_state(root: Window) -> Dictionary:
    var dialog := root.find_child("ColorSpacePickerDialog", true, false) as SaColorSpacePickerDialog
    if dialog == null or not dialog.visible:
        return {}
    var scale := SaUI.window_scale(dialog)
    var inner := Rect2(Vector2.ZERO, Vector2(dialog.size) / (scale if scale > 0.0 else 1.0))
    var buttons: Dictionary = {}
    for button: Button in [dialog.cancel_button, dialog.use_button]:
        var rect := Rect2(button.global_position, button.size)
        buttons[String(button.name)] = {"rect": SaReportShapes.rect(rect), "inside": inner.encloses(rect)}
    return {
        "window": SaReportShapes.rect(inner),
        "buttons": buttons,
        "note_shown": dialog._note_label.visible,
        "status": dialog._status_label.text,
        "picker": dialog.picker.capture_state(),
    }
