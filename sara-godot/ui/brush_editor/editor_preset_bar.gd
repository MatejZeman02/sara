## The brush editor's preset controls: the name, the three writes over it, the
## reset, the close and the dirty indicator with the ticker that keeps it
## honest.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A class of its own rather than members of the window**: a label and a name
## field, five buttons, a dirty label and a timer, and the save, the rename, the
## reset and the dirty tick over `SaBrushEditorSession`. Those are one job, what the
## brush is stored as and whether the painter's settings still match it, and
## the window's job is where the controls sit. So they are this class's, with the
## session they write through, and the window holds one and asks it.
##
## **The name above, every button below.** The name and the dirty indicator sit
## in the dashboard across the top, and Close, Reset, Rename, Save As and Save
## in the one row of buttons every dialog has at its foot, the way out first and
## the default last, rather than the writes standing in the dashboard and Reset
## and Close in a bar of their own. The window
## hands this the dashboard's box and the row `pinned_buttons` made, and this
## fills both.
##
## **A `Node`, for the ticker.** The timer is a child of this, started and
## stopped with the window's visibility, and every control here connects to a
## method on a `Node`, which costs no reference: the reference ring a
## `RefCounted` handler can form cannot close.
##
## What a write moved beyond the controls here is the window's to redraw, so
## this says so through signals and never names the window.
class_name SaBrushEditorPresetBar
extends Node

## A preset was written from this bar, under *stored_name*. The window redraws
## its thumbnail and passes the name on to whoever lists presets.
signal preset_written(stored_name: String)

## Reset put the settings back to the stored preset, so the page and the strip
## are showing values that have just moved.
signal settings_reset

## The ticker read the settings again. *moved* is true when the dirty state
## changed with this reading, which is what tells the window a setting moved
## somewhere it cannot hear.
signal ticked(moved: bool)

## How often the indicator re-reads the settings while the window is open. Four
## times a second: a painter dragging a slider on the bar sees the label follow
## without the window costing a comparison every frame.
const DIRTY_TICK_SECONDS: float = 0.25

## The least width of a button in the row, the one every dialog's row gives
## its buttons, so five words of different lengths read as one row of keys.
const BUTTON_WIDTH: int = 90

## How much of the dashboard's width the description box takes against the
## name's column, which is one.
const DESCRIPTION_SHARE: float = 2.0

var preset_label: Label
## The engine of the settings in the editor, "Stamp" or "Noise", as plain text
## beside the preset's name. Here once, rather than under each cell of the
## presets docker, where it came and went with a pick and moved the cells.
var engine_label: Label
var preset_name_edit: LineEdit
var rename_button: Button
var save_button: Button
var save_as_button: Button
var reset_button: Button
var close_button_bottom: Button
var dirty_label: Label

## What the preset lays and what it is for, typed by the painter. The same text
## is the first line of the preset's tooltip in the Brush Presets docker and
## what the door lists beside its name. An edit marks the brush changed, as a
## moved slider does, and Save writes it into the preset's file.
var description_edit: TextEdit

## The preset the settings were loaded from and whether they still match it.
## Replaced whole by [method bind], because a different tool or a different
## preset is a different session.
var session: SaBrushEditorSession = SaBrushEditorSession.new(null, null, "")

var _dirty_timer: Timer = null

## Whether the name field was opened by Rename rather than Save As, which is the
## whole difference between the two once a name is typed: the field and its
## Return are shared.
var _renaming: bool = false


func _init() -> void:
    name = "PresetBar"
    _dirty_timer = Timer.new()
    _dirty_timer.name = "DirtyTicker"
    _dirty_timer.wait_time = DIRTY_TICK_SECONDS
    _dirty_timer.timeout.connect(tick)
    add_child(_dirty_timer)


## The ticker runs while the window it sits in is showing and not otherwise.
func _ready() -> void:
    var window := get_window()
    if window != null and not window.visibility_changed.is_connected(_on_visibility):
        window.visibility_changed.connect(_on_visibility)
    _on_visibility()


## Adds the name, the name field and the dirty indicator to *strip*, the
## dashboard across the top of the window, one above the other, and the
## description's box beside them.
func build_name_controls(strip: HBoxContainer) -> void:
    var stack := SaMake.column(strip, "PresetNameColumn", SaTheme.GAP_TIGHT)
    stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stack.alignment = BoxContainer.ALIGNMENT_CENTER

    # The name and its engine on one line. The field Save As and Rename open
    # takes the name's place in the same row, so the engine stays beside it.
    var line := SaMake.row(stack, "PresetNameRow")
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preset_label = SaMake.label(line, "PresetName")
    preset_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    preset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Cut short with an ellipsis, so a long preset name lifts no floor (d34).
    preset_label.text_overrun_behavior = SaTheme.TEXT_CUT

    # Swapped in where the label is, the way the tool options bar's own name
    # field is, so Save As and Rename are one control rather than a dialog.
    # Return writes, and Escape or a press anywhere else puts it away, the rule
    # of the Brush Presets panel's own Save as... field.
    preset_name_edit = SaMake.line_edit(line, "PresetNameEdit")
    preset_name_edit.visible = false
    preset_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    preset_name_edit.tooltip_text = tr("Press Enter to save, Escape to cancel.")
    preset_name_edit.text_submitted.connect(write_named)
    preset_name_edit.focus_exited.connect(_on_name_focus_exited)
    preset_name_edit.gui_input.connect(_on_name_gui_input)

    engine_label = SaMake.label(line, "EngineName")
    engine_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    SaTheme.bind_font(engine_label, "text_muted")

    dirty_label = SaMake.label(stack, "DirtyLabel")
    # Not `CLEAN_TEXT`, which would be a window claiming a preset is saved before
    # it has read one. `sync_dirty()` corrects it a few lines later, and a build
    # that ever stops calling it should read the honest state.
    dirty_label.text = tr(SaBrushEditorSession.NO_PRESET_TEXT)
    dirty_label.text_overrun_behavior = SaTheme.TEXT_CUT
    dirty_label.set_meta(SaUI.FONT_SCALE_META, 0.85)
    dirty_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
    # Beside the name, in the dashboard's own height, so the sentence is read
    # with the brush it describes and the pages below keep every unit they had.
    # A box that wraps and scrolls, since a description is a sentence or three
    # and never a single line to run along.
    description_edit = TextEdit.new()
    description_edit.name = "DescriptionEdit"
    description_edit.placeholder_text = tr("What this brush lays and what it is for")
    description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    description_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    description_edit.size_flags_stretch_ratio = DESCRIPTION_SHARE
    description_edit.text_changed.connect(_on_description_changed)
    strip.add_child(description_edit)


## Fills *row*, the dialog's row of buttons, with Close, Reset, Rename, Save As
## and Save: the way out first, then the one that puts the brush back, then the
## three that write it, the default last where Enter's button is in every other
## dialog.
##
## *close* is what Close does, handed over because closing is the window's.
func build_buttons(row: HBoxContainer, close: Callable) -> void:
    close_button_bottom = _button(row, "CloseButtonBottom", "Close")
    close_button_bottom.pressed.connect(close)
    reset_button = _button(row, "ResetButton", "Reset")
    reset_button.pressed.connect(reset)
    rename_button = _button(row, "RenameButton", "Rename")
    rename_button.pressed.connect(begin_rename)
    save_as_button = _button(row, "SaveAsButton", "Save As")
    save_as_button.pressed.connect(begin_save_as)
    save_button = _button(row, "SaveButton", "Save")
    save_button.pressed.connect(save)


func _button(row: HBoxContainer, node_name: String, text: String) -> Button:
    var button := SaMake.button(row, node_name, tr(text))
    button.custom_minimum_size.x = float(SaUI.px(BUTTON_WIDTH))
    return button


## A fresh session over *settings* and *store*, loaded from *loaded_preset*.
func bind(settings: Resource, store: SaPresetStore, loaded_preset: String) -> void:
    session = SaBrushEditorSession.new(settings, store, loaded_preset)
    _sync_preset_name()
    sync_dirty()


## A preset was stored by some surface, the top bar's Save As among them, and
## the bar takes its name when what was stored is the brush it is editing.
## Answers whether it did. The session decides, because it owns
## the comparison.
func adopt(settings: Resource, stored_name: String) -> bool:
    var adopted := SaBrushEditorSession.adopting(settings, session.preset_store, stored_name)
    if adopted == null:
        return false
    session = adopted
    _sync_preset_name()
    sync_dirty()
    return true


## Saves over the loaded preset, or asks for a name when there is none.
func save() -> String:
    if not session.has_preset():
        begin_save_as()
        return ""
    return _wrote(session.write(session.preset_name))


## Swaps the name field in, empty, so the next Return writes a new preset and
## leaves the loaded one where it is.
func begin_save_as() -> void:
    _renaming = false
    _open_name_field("")


## Swaps the name field in, prefilled, so the next Return writes over the loaded
## name and the old file goes.
func begin_rename() -> void:
    _renaming = true
    _open_name_field(session.preset_name)


func _open_name_field(prefill: String) -> void:
    preset_name_edit.text = prefill
    preset_name_edit.visible = true
    preset_label.visible = false
    if preset_name_edit.is_inside_tree():
        preset_name_edit.grab_focus()
        preset_name_edit.select_all()


## Writes the settings under *text*, the name field's own handler: a copy after
## Save As and a rename after Rename.
##
## **Save As is a copy and never a rename.** Both buttons open this field, and
## a rename called for either would make Save As on Pencil write the new preset
## and delete `Pencil.tres`. A copy is `SaBrushEditorSession.write`, which
## keeps the old file and its star and puts the editor on the new name. Typing
## the loaded name after Save As is then a plain Save.
##
## A name another preset already has is saved over, which is what
## `SaPresetStore.save_preset` does from every surface, and the notice says so,
## because neither button asks first.
##
## **A Rename onto another preset's name asks first**, through
## `SaPresetReplace`, with Cancel the default, because a rename also deletes the
## preset it started from. Save As keeps writing over and saying so.
##
## A name that comes out empty once it is made fit for a file name writes
## nothing and keeps the field open, so the painter can type one.
func write_named(text: String) -> void:
    if SaPresetStore.sanitize_name(text).is_empty():
        return
    var renaming := _renaming
    _renaming = false
    _hide_name_field()
    if renaming and _replaces_another(text):
        SaPresetReplace.ask(self, session.preset_store, text, session.preset_name, _write_as.bind(true))
        return
    _write_as(text, renaming)


## The write [method write_named] decided on, a rename or a copy under *text*.
func _write_as(text: String, renaming: bool) -> void:
    var was := session.preset_name
    var replaced := _replaces_another(text)
    var landed := session.write_named(text) if renaming else session.write(text)
    var stored := _wrote(landed, was if renaming and was != landed else "")
    if not stored.is_empty() and replaced:
        EventBus.corner_notice.emit(tr("Saved over the preset '%s'") % stored)
    _hide_name_field()


## Puts the name field away and writes nothing: the preset's name comes back,
## and the next Return belongs to whichever button opens the field again.
## Escape and a press anywhere else both land here, and the editor stays open.
func close_name_field() -> void:
    _renaming = false
    if preset_name_edit == null or not preset_name_edit.visible:
        return
    _hide_name_field()
    _sync_preset_name()


func _hide_name_field() -> void:
    preset_name_edit.visible = false
    preset_label.visible = true
    if preset_name_edit.has_focus():
        preset_name_edit.release_focus()


## A press anywhere else in the editor puts the field away. The engine moves
## the keyboard only to a control that takes it, so a press on a page's label
## or its empty space would leave the field open and holding the keys. So the
## press is read here, before any control hears it, and passed on untouched:
## a press on Save or a slider still does what it does.
func _input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or preset_name_edit == null:
        return
    if not preset_name_edit.is_visible_in_tree():
        return
    var local := preset_name_edit.make_input_local(press) as InputEventMouseButton
    if not Rect2(Vector2.ZERO, preset_name_edit.size).has_point(local.position):
        close_name_field()


## The field let go of the keyboard, which is how a press on another control
## and the router's Escape both arrive: the router releases a focused text box
## before the box hears the key, so the close follows the focus rather than
## the key.
##
## **Not while the field's own right-click menu is up.** The menu takes the
## keyboard while it shows, and closing the field under it would take the menu
## with it. Its first Escape shuts the menu alone, as Godot's own does, and
## the field keeps the keyboard it gets back.
func _on_name_focus_exited() -> void:
    if preset_name_edit.is_menu_visible():
        return
    close_name_field()


## Escape puts the field away and stops there, for a host with no router in
## front of the field, which is every suite that builds this bar on its own.
func _on_name_gui_input(event: InputEvent) -> void:
    if not SaShortcutKeys.is_escape(event):
        return
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo():
        return
    close_name_field()
    preset_name_edit.accept_event()


## Whether writing under *text* lands on a preset other than the loaded one,
## with case folded, so "pencil" over a stored "Pencil" counts.
func _replaces_another(text: String) -> bool:
    var store := session.preset_store
    var taken := store.taken_as(text) if store != null else ""
    return not taken.is_empty() and taken.to_lower() != session.preset_name.to_lower()


## Redraws what a write moved here and tells the window, then answers the name
## the session landed on so a caller can return it.
##
## The signal is emitted here rather than from the session, because a session is
## a comparison against a file and has no business knowing that a bar exists.
##
## **After the whole write, and not between its halves.** A rename is a write
## and then a delete, and a signal between the two has the bar re-read the
## store while the renamed-away preset is still on disk and draw a row for a
## file gone a moment later. A listener is told once, when the store holds what
## the bar says it holds.
##
## **And on the bus, as every other surface that writes the store**, or the
## presets docker keeps its rim on the preset the editor left and the history
## keeps a renamed-away name. Announced after `preset_written`, because
## the window's answer to it is what moves the bar's preset, and the docker
## marks the cell the bar is on when it rebuilds. *removed* is the name a rename
## deleted, or empty.
func _wrote(stored: String, removed: String = "") -> String:
    if stored.is_empty():
        return ""
    _sync_preset_name()
    sync_dirty()
    preset_written.emit(stored)
    if not removed.is_empty():
        EventBus.preset_store_changed.emit(removed, false)
    EventBus.preset_store_changed.emit(stored, true)
    return stored


## Puts the settings back to what the stored preset holds, leaving the preset
## alone. The opposite of Save, and the reason a painter can move a curve to see
## what it does.
func reset() -> void:
    if not session.reset():
        return
    _sync_description()
    settings_reset.emit()
    sync_dirty()


## The name and its engine, and Rename and Reset dimmed with none, the
## session's reset check.
##
## The engine is the one the settings in the editor are for, which is the
## loaded preset's, since a load puts the brush on its preset's engine. Read
## off the settings, so an unsaved brush names its engine as well, and through
## the store, which is the presets package's door. Settings that declare no
## engine take no presets and show none.
func _sync_preset_name() -> void:
    _sync_description()
    preset_label.text = session.preset_name if session.has_preset() else tr("Unsaved brush")
    var engine := SaPresetStore.preset_engine_of(session.settings)
    engine_label.text = "" if String(engine).is_empty() else SaPresetStore.engine_label(engine)
    engine_label.visible = not engine_label.text.is_empty()
    rename_button.disabled = not session.has_preset()
    reset_button.disabled = rename_button.disabled


## The box shows the session's description, a stock one in the painter's
## language. Written only when it differs, so a redraw after a save leaves the
## caret where the painter left it.
func _sync_description() -> void:
    if description_edit == null:
        return
    var shown := SaPresetStore.description_said(session.description)
    if description_edit.text != shown:
        description_edit.text = shown


## The painter typed in the box. The session holds what a write puts in the
## file, and the indicator follows at once rather than on the next tick. A text
## that is the shown form of the stored one is no edit, so a stock sentence
## shown in another language is kept as the catalogue's and not as its
## translation.
func _on_description_changed() -> void:
    if description_edit.text == SaPresetStore.description_said(session.description):
        return
    session.description = description_edit.text
    sync_dirty()


## Whether the live settings differ from the stored preset. The save path, the
## ticker and the dump all read it here.
func is_dirty() -> bool:
    return session.is_dirty()


## The sentence the indicator draws, which is three states rather than two.
func dirty_text() -> String:
    return session.dirty_text()


func sync_dirty() -> void:
    if dirty_label == null:
        return
    dirty_label.text = tr(session.dirty_text())


## The ticker's reading, and its handler: the indicator follows a setting moved
## on the bar, where there is no signal that says an option changed, so a
## comparison four times a second is what it can have.
##
## A `Timer` rather than `_process`, because the answer is worth four readings a
## second and not sixty, and rather than a signal because there is none to
## listen to.
func tick() -> void:
    var was := is_dirty()
    sync_dirty()
    ticked.emit(is_dirty() != was)


func _on_visibility() -> void:
    var window := get_window()
    if window != null and window.visible:
        _dirty_timer.start()
    else:
        _dirty_timer.stop()
