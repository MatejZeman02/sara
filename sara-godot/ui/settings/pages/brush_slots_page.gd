## Preferences > Brush Slots: which preset each of the ten chords loads.
##
## The slots live only in the settings, rather than as a row of thumbnails on
## the tool options bar or a page in the presets docker, and nothing goes on a
## bar.
##
## Ten rows of the same shape, each a dropdown over the preset store and a Clear
## button. `SaChoiceButton` rather than the engine's dropdown, which is gone
## from every page and dialog, and which suits this row better anyway: a row's
## value is the preset name itself, so the handler writes what it was handed
## instead of counting into a list. A slot whose preset has been deleted keeps
## its name as a row of its own, marked missing, instead of being quietly
## emptied by a painter opening the page.
##
## Declared onto `SaSettingsPage` rather than built by hand. Two controls in one
## row is a custom row, so every slot stays exactly the box it was, and only
## `setup_page`, `section`, `note` and `row` are the layer's.
##
## **What a right click with a brush opens is the last row**, Brush Presets or
## the pop-up palette, the palette being these ten slots on a ring round a
## colour wheel. It stands where the palette's on and off switch stood, which
## existed only because a right click had to open one of the two.
class_name SaBrushSlotsPage
extends SaSettingsPage

## The first row of every dropdown: a slot with nothing in it.
const NOTHING: String = "Nothing"

## What a stored name the store does not hold reads as.
const MISSING_SUFFIX: String = " (missing)"

## How wide a slot's dropdown is, in logical pixels.
##
## Named here because `SaChoiceButton` sets `clip_text`, which keeps the label
## out of the control's minimum size, and `SaSettingsRows.row` gives a control
## that is not a slider `SIZE_SHRINK_BEGIN`. A dropdown that only ever sits
## alone in a row is saved by the row's own width, but this one shares a box
## with a Clear button and shrank to its arrow, ten empty squares down the page.
## `SaChoiceButton.MIN_WIDTH` would be the place for this and is applied
## nowhere, which is a defect of that file rather than of this one. It is the
## narrowest a dropdown goes, since a preset name longer than it widens it.
const PICKER_WIDTH: int = 180

## Each slot's dropdown, in slot order. Public so the capture door and the suite
## read a row back without walking the tree for it.
var pickers: Array[SaChoiceButton] = []

## Each slot's Clear button, in slot order, dimmed while its slot holds nothing,
## because clearing an empty slot does nothing. Public for the same reason
## [member pickers] is.
var clear_buttons: Array[Button] = []

## Each slot's line under its hint, "Also on Slot 1." in the accent, hidden
## while no other slot holds its preset. Public for the same reason [member
## pickers] is.
##
## A line of its own rather than words added to the hint, because the hint is
## one `Label` bound to `text_muted`, so an accent there would colour the
## chord sentence with it, and the chord is not what is wrong with the row.
var twin_notes: Array[Label] = []

## The preset library the rows are filled from. A constructor argument because a
## private member is written by its own class only, and the suite needs a store
## of its own: a page reading the real `user://brush_presets` in a test would
## offer whatever the last suite left there and would have to write into it to
## have anything to pick.
var _store: SaPresetStore = null

## Each slot's declared row, in slot order, kept so the twin lines can go under
## the hints the page draws once `super()` has realized it.
var _slot_rows: Array[SaPageRow] = []

## What the right click's choice binds to, the skeleton's own preference rather
## than a property of `SaSettings`.
var _right_click := SaRightClickDocker.new()


func _init(store: SaPresetStore = null) -> void:
    _store = store
    super()
    for row in _slot_rows:
        twin_notes.append(_add_twin_note(row))
    _mark_twins()


func build(ui: SaPage) -> void:
    var rows := ui.section(tr("Brush Slots"))
    rows.note(
        tr(
            (
                "Ten presets you can pick with a key. The list belongs to you, not to a shortcut profile. "
                + "An empty slot does nothing, and a slot whose preset was deleted loads the default brush "
                + "and says which slot it was."
            )
        )
    )
    var names := _preset_names()
    for slot in range(1, SaBrushSlotCommands.COUNT + 1):
        _add_row(rows, slot, names)
    var opens := [
        {"id": SaRightClickDocker.PRESETS, "label": tr("Brush Presets")},
        {"id": SaRightClickDocker.PALETTE, "label": tr("Pop-up palette")},
    ]
    rows.choice("Right click with a brush opens", opens, _right_click, ^"opens").named(&"brush_right_click").explain(
        _right_click_hint()
    )


## One slot: its dropdown, its Clear button and the chord in the hint.
func _add_row(rows: SaPageSection, slot: int, names: PackedStringArray) -> void:
    var stored := SaBrushSlotCommands.preset_for(slot)
    var choices: Array = [{"id": "", "label": tr(NOTHING)}]
    var offered := false
    for preset_name: String in names:
        choices.append({"id": preset_name, "label": preset_name})
        offered = offered or preset_name == stored
    if not offered and not stored.is_empty():
        choices.append({"id": stored, "label": stored + tr(MISSING_SUFFIX)})
    var box := SaMake.row(null, "BrushSlotRow%d" % slot, 6)
    var picker := SaMake.choice(box, "BrushSlot%d" % slot, choices)
    picker.custom_minimum_size.x = SaUI.px(PICKER_WIDTH)
    picker.ask_for_its_words()
    picker.select_value(stored)
    picker.choice_picked.connect(_on_slot_chosen.bind(slot))
    pickers.append(picker)
    var clear := SaMake.button(box, "BrushSlotClear%d" % slot, tr("Clear", "clear a brush slot"))
    clear.pressed.connect(_on_clear_pressed.bind(slot))
    clear.disabled = stored.is_empty()
    clear_buttons.append(clear)
    var label := tr_n("Slot %d", "Slot %d", slot) % slot
    _slot_rows.append(rows.custom(label, box).named(StringName("slot_%d" % slot)).explain(_hint_for(slot)))


## The accent line under *row*'s hint, in the column `SaSettingsRows.row` gives
## the title and the hint, and at the hint's size so it reads as part of it.
func _add_twin_note(row: SaPageRow) -> Label:
    var note := SaMake.label(null, "Twin", "")
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaSettingsRows.size_label(note, SaSettingsRows.HINT_SCALE)
    SaTheme.bind_font(note, "accent_primary")
    note.visible = false
    row.line.get_node(^"Labels").add_child(note)
    return note


## "Ctrl+Alt+3 loads this preset.", read from the InputMap rather than from the
## table this ships with, so a rebound chord is what the row says.
func _hint_for(slot: int) -> String:
    var action := SaBrushSlotCommands.command_id(slot)
    var keys := SaShortcutRows.keys_for(action) if InputMap.has_action(action) else ""
    if keys.is_empty():
        return tr("This slot has no shortcut. Set one in Preferences > Keyboard shortcuts.")
    return tr("%s loads this preset.") % keys


## What the row's choice does, and the palette's summon chord, read from the
## InputMap the way a slot's hint is, so a rebound summon is what the row says.
func _right_click_hint() -> String:
    var opens := tr("It opens under the pointer, and a second right click closes it.")
    var action := SaAppCommands.summon_id(&"docker_palette")
    var keys := SaShortcutRows.keys_for(action) if InputMap.has_action(action) else ""
    if keys.is_empty():
        return opens
    return opens + " " + tr("%s shows the pop-up palette, these ten slots round a colour wheel, either way.") % keys


## The preset names the chord will look for: the store the tool options bar
## holds when there is one, because that is the library a chord reads and a
## page offering names no chord could load would be lying.
func _preset_names() -> PackedStringArray:
    if _store == null:
        var presets := SaBrushSlotCommands.preset_box()
        _store = presets.preset_store if presets != null else SaPresetStore.new()
    return _store.list_names()


## A row was pressed. The value is the preset name the row stands for, which is
## why nothing here counts rows or reads a label back.
##
## A preset another slot already holds still goes in, because a painter may
## want it twice, and the corner says where it already was, because ten slots
## are few and a twin is almost always a slip.
func _on_slot_chosen(preset_name: Variant, slot: int) -> void:
    SaBrushSlotCommands.fill(slot, String(preset_name))
    clear_buttons[slot - 1].disabled = String(preset_name).is_empty()
    _mark_twins()
    var twins := twins_of(slot)
    if not twins.is_empty():
        SaMessage.notice(
            (
                tr_n(
                    '"%s" was already on %s, and Slot %d loads it too.', '"%s" was already on %s, and Slot %d loads it too.', slot
                )
                % [String(preset_name), _slots_named(twins), slot]
            )
        )


func _on_clear_pressed(slot: int) -> void:
    pickers[slot - 1].select_value("")
    SaBrushSlotCommands.fill(slot, "")
    clear_buttons[slot - 1].disabled = true
    _mark_twins()


## Writes every slot's twin line again from what the slots hold now. Every row
## rather than the one pressed, because a pick or a clear in one row makes or
## ends a twin in another.
func _mark_twins() -> void:
    for slot in range(1, twin_notes.size() + 1):
        var twins := twins_of(slot)
        var note := twin_notes[slot - 1]
        note.text = tr("Also on %s.") % _slots_named(twins) if not twins.is_empty() else ""
        note.visible = not twins.is_empty()


## The other slots that hold *slot*'s preset, in slot order, and none for an
## empty slot, since two empty slots are not a twin.
static func twins_of(slot: int) -> Array[int]:
    var out: Array[int] = []
    var held := SaBrushSlotCommands.preset_for(slot)
    if held.is_empty():
        return out
    for other in range(1, SaBrushSlotCommands.COUNT + 1):
        if other != slot and SaBrushSlotCommands.preset_for(other) == held:
            out.append(other)
    return out


## "Slot 1", "Slots 1 and 5" or "Slots 1, 5 and 7".
func _slots_named(slots: Array[int]) -> String:
    if slots.size() == 1:
        return tr_n("Slot %d", "Slot %d", slots[0]) % slots[0]
    var first := PackedStringArray()
    for slot: int in slots.slice(0, slots.size() - 1):
        first.append(str(slot))
    return tr_n("Slots %s and %d", "Slots %s and %d", slots.size()) % [", ".join(first), slots[slots.size() - 1]]


## Fills or clears a brush slot: it fills a slot through the page with
## `{"brush_slot": {"slot": 3, "preset": "Sketch"}}`, and presses its Clear
## button with `{"brush_slot": {"slot": 3, "clear": true}}`. Answers with every
## slot, so one step says what the page holds.
##
## Through the page rather than through the settings key, because what matters
## is that a painter can fill a slot: the page is an embedded subwindow, which
## an injected click does not route into and Wayland will not place a pointer
## over.
static func capture_slot(tree: SceneTree, spec: Dictionary) -> String:
    var found: SaBrushSlotsPage = null
    for node in tree.root.find_children("*", "SaBrushSlotsPage", true, false):
        if not node.is_queued_for_deletion():
            found = node as SaBrushSlotsPage
    if found == null:
        return "SaCapture: no open Brush Slots page"
    var slot := int(spec.get("slot", 0))
    if slot >= 1 and slot <= found.pickers.size():
        if bool(spec.get("clear", false)):
            found._on_clear_pressed(slot)
        elif spec.has("preset"):
            found.choose(slot, String(spec["preset"]))
    var answer := "SaCapture: brush slots [%s]" % ", ".join(found.slot_names())
    var twins := found.twin_lines()
    return answer + ", " + ", ".join(twins) if not twins.is_empty() else answer


## Picks *preset_name* in *slot*'s dropdown the way a painter does, and says
## whether the row offered it.
func choose(slot: int, preset_name: String) -> bool:
    var picker := pickers[slot - 1]
    var index := picker.choice_values().find(preset_name)
    return picker.pick_row(index) if index >= 0 else false


## What each slot holds, in slot order, with an empty slot as "-".
func slot_names() -> PackedStringArray:
    var out := PackedStringArray()
    for slot in range(1, pickers.size() + 1):
        var stored := SaBrushSlotCommands.preset_for(slot)
        out.append(stored if not stored.is_empty() else "-")
    return out


## Every twin line on show, "Slot 3: Also on Slot 1.", so a step says what the
## accent says.
func twin_lines() -> PackedStringArray:
    var out := PackedStringArray()
    for slot in range(1, twin_notes.size() + 1):
        if twin_notes[slot - 1].visible:
            out.append("Slot %d: %s" % [slot, twin_notes[slot - 1].text])
    return out
