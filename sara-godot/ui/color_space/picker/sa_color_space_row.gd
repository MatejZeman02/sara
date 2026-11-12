## One row that asks for a colour space, listing the presets, the spaces the
## painter saved in the picker, and a last entry, "Custom...", which opens the
## picker as a dialog and takes the space it gives.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The second facade of `ui/color_space/picker`, for the places that ask with a
## single row rather than a page: Import Fit's Read the picture as, Preferences
## > Display's Display profile and Proof gamut, and the Minimap's proof. Each
## keeps its row and its entries and hands the rest here, so a saved space and
## a custom one reach every row the same way.
##
## Two ways to hold the answer. Built with two settings keys, the row is the
## setting: [member chosen] reads the profile key, and a saved or custom space
## is written to the custom key by value, its gamut and white, and the profile
## key set to `custom`. By value, so a saved space renamed or deleted later
## leaves the screen as it was. Built with none, the row holds a list of spaces
## and the id chosen, and a space the dialog gives joins the list.
@tool
class_name SaColorSpaceRow
extends RefCounted

## [member chosen] reads differently, or the list moved. The page a row is
## bound on re-reads it on this, the way it re-reads `SaSettings`.
signal changed(property: StringName)

## The host's row moved to *id* by the dialog, in a row that holds its list.
signal answered(id: String)

## The last entry, which opens the dialog rather than naming a space.
const ASK_ID := "custom_ask"
const ASK_LABEL := "Custom..."
## A saved space's entry is this and its name.
const SAVED_PREFIX := "saved:"
## The entry of a space held by value that no saved space is, and in a row
## that holds its list, of the space the dialog gave last.
const CUSTOM_ID := SaSettingsValues.DISPLAY_PROFILE_CUSTOM
const CUSTOM_LABEL := "Custom"
## The dialog's answer in a row that holds its list, which may list a custom
## space of its own already, the one a `.sad` carried.
const PICKED_ID := "picked"

## The setting that names the choice and the one that holds a space by value,
## or empty for a row that holds its list.
var _profile_key: StringName = &""
var _custom_key: StringName = &""
## The entries before the saved spaces, `{"id", "label"}`, and for a row that
## holds its list each its `"space"` as well.
var _base: Array = []
## The dialog's last answer, in a row that holds its list, or null.
var _picked: SaColorSpace = null
## The entry a row that holds its list is on, which [method take] goes back to
## when "Custom..." is picked and the dialog has not answered.
var _last: String = ""
## Whether the dialog takes the gamut and white alone, as the display does.
var _gamut_only: bool = false
## The page row this row's entries are listed on, weak because that row holds
## this one as its target. Or the button, for a host with no page.
var _row: WeakRef = null
var _button: SaChoiceButton = null

## The entry the row is on. For a settings row, the profile key's id, a saved
## space's entry when the space held by value is one, and Custom otherwise.
## Setting it is what a pick does, "Custom..." included.
var chosen: String:
    get:
        if _profile_key.is_empty():
            return _last
        var id := String(SaSettings.get(_profile_key))
        if id != CUSTOM_ID:
            return id
        var held := space()
        for record: Dictionary in SaColorSpacePicker.Saved.listed():
            if same_gamut(record[SaColorSpacePicker.Saved.SPACE], held):
                return SAVED_PREFIX + String(record[SaColorSpacePicker.Saved.NAME])
        return CUSTOM_ID
    set(val):
        take(val)


## A row whose *profile_key* and *custom_key* name the settings it is, or
## with both empty one that holds a list given by [method fill]. *base* is the
## entries before the saved spaces, `{"id", "label"}` each, for a settings row.
func _init(profile_key: StringName = &"", custom_key: StringName = &"", base: Array = []) -> void:
    _profile_key = profile_key
    _custom_key = custom_key
    _base = base.duplicate(true)
    _gamut_only = not profile_key.is_empty()
    SaSettings.changed.connect(_on_settings_changed)


## Declares the row on *ui*'s last section under *title*, bound to [member
## chosen], and keeps it to list the entries on as they change.
func declare(ui: SaPage, title: String) -> SaPageRow:
    var row := ui.sections[-1].choice(title, choices(), self, ^"chosen")
    attach(row)
    return row


## Keeps *row*, a host's own row of these entries, to list them on as they
## change and to open the dialog over its control.
func attach(row: SaPageRow) -> void:
    _row = weakref(row)


## Lists the entries on *button*, for a host with no page, and keeps them there
## and opens the dialog over it.
func show_on(button: SaChoiceButton) -> void:
    _button = button
    button.set_choices(choices())


## The row's entries: the base, the saved spaces by name, Custom while a space
## held by value or the dialog's answer is no saved one, and "Custom...".
func choices() -> Array:
    var out: Array = _base.map(func(entry: Dictionary) -> Dictionary: return {"id": entry["id"], "label": entry["label"]})
    for record: Dictionary in SaColorSpacePicker.Saved.listed():
        var saved_name := String(record[SaColorSpacePicker.Saved.NAME])
        out.append({"id": SAVED_PREFIX + saved_name, "label": saved_name})
    if _profile_key.is_empty() and _picked != null:
        out.append({"id": PICKED_ID, "label": SaPage.translated(CUSTOM_LABEL)})
    elif not _profile_key.is_empty() and chosen == CUSTOM_ID:
        out.append({"id": CUSTOM_ID, "label": SaPage.translated(CUSTOM_LABEL)})
    out.append({"id": ASK_ID, "label": SaPage.translated(ASK_LABEL)})
    return out


## Whether *id* is an entry of the row.
func has(id: String) -> bool:
    return choices().any(func(entry: Dictionary) -> bool: return entry["id"] == id)


## The space the row is on: for a settings row the one the settings give, the
## display's or the proof's, and for a row that holds its list the entry's.
func space() -> SaColorSpace:
    if _profile_key == &"display_profile":
        return SaSettings.display_profile_space()
    if not _profile_key.is_empty():
        return SaSettings.proof_profile_space()
    return space_of(_last)


## The space the entry *id* names, sRGB for none, in a row that holds its list.
## A saved space comes back as Custom, the id a document's header takes.
func space_of(id: String) -> SaColorSpace:
    if id == PICKED_ID and _picked != null:
        return _picked
    if id.begins_with(SAVED_PREFIX):
        var saved := _saved(id.trim_prefix(SAVED_PREFIX))
        if saved != null:
            return saved
    for entry: Dictionary in _base:
        if entry["id"] == id and entry.get("space") is SaColorSpace:
            return entry["space"]
    return SaColorSpace.srgb()


## Gives a row that holds its list *spaces* under *labels*, each entry by its
## space's id, and answers the entries to list. The dialog's last answer stays
## in the list.
func fill(spaces: Array[SaColorSpace], labels: Array) -> Array:
    _base.clear()
    for i in spaces.size():
        _base.append({"id": String(spaces[i].id), "label": String(labels[i]), "space": spaces[i]})
    relist()
    return choices()


## Picks *id*. "Custom..." opens the dialog on the space the row is on and leaves
## the row where it was until the dialog answers. Answers the entry the row is
## on after the pick, which a host that holds the id itself puts back.
func take(id: String) -> String:
    if id == ASK_ID:
        ask(_control(), space(), _on_answered, _gamut_only)
        # The control already shows "Custom...", so it is told to read again.
        changed.emit.call_deferred(&"chosen")
        return chosen
    if _profile_key.is_empty():
        _last = id
        return id
    if id.begins_with(SAVED_PREFIX):
        var saved := _saved(id.trim_prefix(SAVED_PREFIX))
        if saved != null:
            _write(saved)
    elif id != CUSTOM_ID or not (SaSettings.get(_custom_key) as Dictionary).is_empty():
        SaSettings.set(_profile_key, id)
    return chosen


## Opens the picker as a dialog over *host*, on *shown*, and calls *answer*
## with the space it gives once Use is pressed. *gamut_only* says under the
## rows that the host takes the gamut and the white alone.
static func ask(host: Node, shown: SaColorSpace, answer: Callable, gamut_only: bool = false) -> SaColorSpacePickerDialog:
    if host == null or not is_instance_valid(host) or not host.is_inside_tree():
        return null
    var dialog := SaColorSpacePickerDialog.new()
    dialog.configure(shown, gamut_only)
    dialog.answered.connect(answer)
    # One window per ask, gone once it is closed either way.
    dialog.visibility_changed.connect(
        func() -> void:
            if not dialog.visible:
                dialog.queue_free()
    )
    host.add_child(dialog)
    dialog.popup_centered()
    return dialog


## The dialog a row opened under *root*, its rect, buttons and rows, for the
## dump, or empty while none is shown.
static func capture_dialog(root: Window) -> Dictionary:
    return SaColorSpacePickerDialog.capture_state(root)


## Whether *a* and *b* have the same three primaries and white, which is all
## the display and the proof take of a space.
static func same_gamut(a: SaColorSpace, b: SaColorSpace) -> bool:
    if a == null or b == null or not a.white.is_equal_approx(b.white) or a.primaries.size() != b.primaries.size():
        return false
    for i in a.primaries.size():
        if not a.primaries[i].is_equal_approx(b.primaries[i]):
            return false
    return true


func _on_answered(given: SaColorSpace) -> void:
    if _profile_key.is_empty():
        _picked = given
        _last = PICKED_ID
        relist()
        answered.emit(_last)
        return
    _write(given)


## The settings row on *given* by value: the gamut and white first, so the
## view that hears the profile key change reads the new space.
func _write(given: SaColorSpace) -> void:
    SaSettings.set(_custom_key, given.to_header())
    SaSettings.set(_profile_key, CUSTOM_ID)


## The control the row is drawn as, which the dialog opens over.
func _control() -> Control:
    var row: SaPageRow = _row.get_ref() as SaPageRow if _row != null else null
    if row != null and row.control != null and is_instance_valid(row.control):
        return row.control
    return _button if _button != null and is_instance_valid(_button) else null


func _saved(saved_name: String) -> SaColorSpace:
    for record: Dictionary in SaColorSpacePicker.Saved.listed():
        if String(record[SaColorSpacePicker.Saved.NAME]) == saved_name:
            return record[SaColorSpacePicker.Saved.SPACE]
    return null


## Gives the page row or the button the entries as they now stand.
func relist() -> void:
    var listed := choices()
    var row: SaPageRow = _row.get_ref() as SaPageRow if _row != null else null
    if row != null:
        # Already the page's own shape, an id and a label each.
        row.choices = listed
        if row.control != null and is_instance_valid(row.control):
            (row.control as SaChoiceButton).set_choices(row.choices)
    if _button != null and is_instance_valid(_button):
        _button.set_choices(listed)


func _on_settings_changed(key: StringName) -> void:
    if key == &"saved_color_spaces" or (not _profile_key.is_empty() and key in [_profile_key, _custom_key]):
        relist()
        changed.emit(&"chosen")
