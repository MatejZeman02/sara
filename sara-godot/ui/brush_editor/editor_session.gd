## What the brush editor is editing, against what it was loaded from: the stored
## preset, the dirty comparison and the three writes over it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An instance rather than a page of statics, and the fields are its own,
## rather than the window's beside its labels and buttons. Answering "are these
## two the same brush" and building a dashboard are two jobs: one is a layout,
## the other is a rule about a `.tres` on disk. This is the second.
##
## **Rebuilt rather than rebound.** `bind_tool` constructs a fresh session for
## whatever tool it was handed, because a session is what the window is editing
## and a different tool is a different thing to edit. That is also the privates
## rule read straight: everything here is set in `_init` and written afterwards
## only by this class.
##
## The preset bar keeps the label, the name field and the buttons, and asks
## this for the sentence to draw and the name to show. Nothing here knows a
## `Control` exists.
##
## **The comparison is this class's statics**. They were `SaPresetDiff`, a file
## of their own cut out of the window when it passed a line count, and this
## session was the only thing that called them. "Are these two the same brush"
## is the question a session answers, so it answers it here.
class_name SaBrushEditorSession
extends RefCounted

## What the dirty indicator says. Strings rather than a coloured dot, because a
## dump reads text and a screenshot reads either.
##
## **Three states, not two**. "Unsaved changes" is a sentence about the
## painter's work, and it needs a preset for the work to be unsaved against. An
## editor opened on a tool that has loaded none has nothing on the left of the
## comparison, and saying the brush has unsaved changes there tells a painter
## who opened the window to look at a page that they are about to lose
## something. `NO_PRESET_TEXT` is the state the window already had and never
## said.
const CLEAN_TEXT: String = "Saved"
const DIRTY_TEXT: String = "Unsaved changes"
const NO_PRESET_TEXT: String = "No preset"

## The live settings resource the painter is moving, or null for a window bound
## to a tool that carries none.
var settings: Resource = null

## Where presets are read from and written to.
var preset_store: SaPresetStore = null

## The preset the settings were last loaded from or saved as, empty for none.
var preset_name: String = ""

## The settings as the stored preset holds them, for the dirty comparison.
##
## A copy taken at the last load, save or reset rather than the file itself. The
## file would be a `.tres` parsed off disk four times a second, which is what the
## window's ticker would have cost.
var _stored: Resource = null

## What the preset says it lays and what it is for, as the editor's text box
## holds it, which a write puts in the file. Written by the preset bar as the
## painter types, and a public field for that reason.
var description: String = ""

## The description as the stored preset holds it, for the dirty comparison.
var _stored_description: String = ""


func _init(brush_settings: Resource, store: SaPresetStore, loaded_preset: String = "") -> void:
    settings = brush_settings
    preset_store = store
    preset_name = loaded_preset
    _take_stored()


## Whether the live settings differ from the stored preset.
##
## A comparison rather than a flag, because a flag has to be set from every path
## that can change a setting and the two surfaces outside the editor can both
## change one while it is open. The bar has no "an option moved" signal to listen
## to: `EventBus.tool_options_moved` reads like one and is emitted by the
## transform tool alone.
func is_dirty() -> bool:
    if settings == null:
        return false
    if _stored == null:
        return true
    return description != _stored_description or not settings_match(_stored, settings)


## The three states of the indicator, as the label reads them.
##
## The name rather than `_stored` is what says whether a preset is loaded. A
## named preset whose file will not load is a different thing entirely, and it
## reads as dirty, which is the honest answer: the window cannot show that the
## settings match a file it could not open.
##
## `is_dirty()` is untouched and still answers true here, because the save path
## and the ticker both read it and a window with no preset does have something
## worth saving. What was wrong was the sentence, not the boolean.
func dirty_text() -> String:
    if preset_name.is_empty():
        return NO_PRESET_TEXT
    return DIRTY_TEXT if is_dirty() else CLEAN_TEXT


## Whether Save can write without asking for a name.
func has_preset() -> bool:
    return not preset_name.is_empty()


## Writes the live settings under *wanted* through the store, and answers the
## name it landed under, or `""` when nothing was written.
##
## Save and Save As, and never Rename. Save hands the loaded name, so the file
## is written over. Save As hands a typed one, and the loaded preset, its file
## and its star stay as they were while the session moves to the new name. A
## typed name that is the loaded one is a Save, and one that is another
## preset's writes over that preset, as the store does from every surface.
##
## Through `SaPresetStore.save_preset` and nothing else, which is the whole of
## "no second copy of that logic": the sanitising, the excluded colour and the
## tags all stay where the store put them.
func write(wanted: String) -> String:
    if preset_store == null or settings == null:
        return ""
    # A name that differs from a stored one only in case is that preset, so
    # the write lands on its file and never beside it, see `SaPresetNames`.
    var taken := preset_store.taken_as(wanted)
    var metadata := {SaPresetStore.DESCRIPTION_META: description}
    var stored := preset_store.save_preset(wanted if taken.is_empty() else taken, settings, PackedStringArray(), metadata)
    if stored.is_empty():
        return ""
    preset_name = stored
    _take_stored()
    return stored


## Rename: writes under *text* and, when another name was loaded, removes the old
## file and moves its star to the new name. Answers the name it landed under. The
## write comes before the delete, so a failed one leaves the painter the preset
## they had. Save As is [method write], because a copy deletes nothing.
##
## **A rename that changes only case moves the file.** On a folder that ignores
## case the write lands in the old file and the delete after it removes the
## preset, so "Pencil" to "pencil" is `SaPresetNames.move_case` and never a
## write and a delete. The settings in hand are written over it after the move,
## as any rename writes them.
func write_named(text: String) -> String:
    var was := preset_name
    if preset_store != null and SaPresetNames.only_case(was, text):
        var moved := SaPresetNames.move_case(preset_store, was, text)
        if moved.is_empty():
            return ""
        SaSettings.rename_preset_favorite(was, moved)
        preset_name = moved
        return write(moved)
    var stored := write(text)
    if not stored.is_empty() and not was.is_empty() and was != stored and preset_store != null:
        preset_store.delete_preset(was)
        SaSettings.rename_preset_favorite(was, stored)
    return stored


## Puts the settings back to what the stored preset holds, leaving the preset
## alone, and answers whether it did. The opposite of Save, and the reason a
## painter can move a curve to see what it does.
func reset() -> bool:
    if preset_store == null or settings == null or preset_name.is_empty():
        return false
    preset_store.apply_preset(preset_name, settings)
    _take_stored()
    return true


## A session on *stored_name*, when the store now holds exactly the live
## *brush_settings*, or null when it holds some other brush.
##
## What the brush editor asks when a preset was saved by a surface that is not
## the editor. The top bar's Save As writes the store and says so on
## `EventBus.preset_store_changed`, and until now nothing told the editor, which
## kept saying "No preset" over a brush the bar had just named. A save announces
## only a name, and the importer and the presets docker write the store too, so
## the rule is the store's own contents rather than who spoke: a name whose
## preset matches what the painter is holding is the preset they are on, and a
## name whose preset does not is somebody else's brush.
static func adopting(brush_settings: Resource, store: SaPresetStore, stored_name: String) -> SaBrushEditorSession:
    if brush_settings == null or store == null or stored_name.is_empty():
        return null
    var candidate := SaBrushEditorSession.new(brush_settings, store, stored_name)
    return null if candidate.is_dirty() else candidate


## Takes the copy `is_dirty` compares against. Called wherever the session and
## the stored preset are known to agree, which is a load, a save and a reset.
func _take_stored() -> void:
    _stored = null
    _stored_description = ""
    if preset_store == null or preset_name.is_empty():
        description = ""
        return
    _stored = preset_store.load_preset(preset_name)
    _stored_description = preset_store.about_for(preset_name)
    description = _stored_description


# --- Whether two brushes are the same -----------------------------------------


## True when every stored property of *a* reads the same on *b*.
##
## The same property walk `SaPresetStore.copy_settings` does, so a field the save
## does not carry cannot make the window read dirty forever. A field the
## resource's script names in `STROKE_WRITTEN_KEYS` is skipped too, because a
## stroke rewrites it at every dab and a brush that painted once would read
## changed with nothing moved. `SaBrushTip` names its diameter,
## fades and spacing there.
static func settings_match(a: Resource, b: Resource) -> bool:
    if a == null or b == null:
        return a == b
    var script := a.get_script() as Script
    var stroke_written: Array = script.get_script_constant_map().get("STROKE_WRITTEN_KEYS", []) if script != null else []
    for property: Dictionary in a.get_property_list():
        var usage: int = property["usage"]
        if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_STORAGE):
            continue
        var key: String = property["name"]
        if SaPresetStore.EXCLUDED_KEYS.has(key) or stroke_written.has(key) or not (key in b):
            continue
        if not values_match(a.get(key), b.get(key)):
            return false
    return true


## Two settings values, compared by what they hold rather than by identity.
##
## Everything a preset carries has to be reachable through this, and three of the
## kinds Sara stores are not comparable with `==` after a load:
##
## - A `Resource` field is a different object after `copy_settings` duplicated
##   it, so the hardness and the flow would read as changed the instant they were
##   saved.
## - A `Dictionary` whose values are Resources compares its values by identity,
##   which is what `SaCurveOption.sensors` is. That one cost a debugging pass:
##   nine of the ten curve options matched and the tenth did not, because only
##   `opacity_option` had a sensor in its dictionary and every other one was
##   empty.
## - An `Array` for the same reason, which nothing stores today and which is one
##   line here and a surprise later.
##
## Two values of different kinds are a difference and never a cast. The stamp
## brush's `hardness` is a `GammaFloat` and the noise brush's a
## float, so a comparison that paired a stamp preset with noise settings sent a
## float to [method settings_match] as a `Resource` and stopped the script. An
## int against a float is one kind here, because a preset written by hand can
## carry `1` where the settings hold `1.0`.
static func values_match(left: Variant, right: Variant) -> bool:
    if not _same_kind(left, right):
        return false
    if left is Curve or right is Curve:
        return curves_match(left as Curve, right as Curve)
    if left is Resource or right is Resource:
        return settings_match(left as Resource, right as Resource)
    if left is Dictionary and right is Dictionary:
        var a_dict := left as Dictionary
        var b_dict := right as Dictionary
        if a_dict.size() != b_dict.size():
            return false
        for key: Variant in a_dict:
            if not b_dict.has(key) or not values_match(a_dict[key], b_dict[key]):
                return false
        return true
    if left is Array and right is Array:
        var a_list := left as Array
        var b_list := right as Array
        if a_list.size() != b_list.size():
            return false
        for i in a_list.size():
            if not values_match(a_list[i], b_list[i]):
                return false
        return true
    return left == right


## Whether *left* and *right* can be compared at all: the same Variant type,
## with an int and a float counted as one number, and two objects only when
## both are `Curve`s or neither is. A null object stays comparable with an
## object, which [method settings_match] already answers as a difference.
static func _same_kind(left: Variant, right: Variant) -> bool:
    var left_type := typeof(left)
    var right_type := typeof(right)
    var numbers := [TYPE_INT, TYPE_FLOAT]
    if numbers.has(left_type) and numbers.has(right_type):
        return true
    if left_type == TYPE_NIL or right_type == TYPE_NIL:
        return left_type == right_type or left_type == TYPE_OBJECT or right_type == TYPE_OBJECT
    if left_type != right_type:
        return false
    if left_type == TYPE_OBJECT and left != null and right != null:
        return (left is Curve) == (right is Curve) and (left is Resource) == (right is Resource)
    return true


## Two `Curve`s, compared by the shape they hold.
##
## [method settings_match] above walks `PROPERTY_USAGE_SCRIPT_VARIABLE`, which a
## `Curve` has none of: its points live in the engine's own `_data` and its range
## in `_limits`, both storage and neither a script variable. So two curves of
## different shapes came back matching, and the brush editor's dirty indicator
## would have gone on saying "no changes" after the painter redrew a falloff. It
## stayed hidden while no `Curve` on a settings resource had a control.
##
## Narrow on purpose: `Curve` is the one engine resource a preset carries today,
## and comparing any script-less `Resource` by its storage list would drag in
## `resource_path` and `resource_name`, which differ between a loaded preset and
## a built one without the brush being different. Whoever stores the second
## engine resource widens this and says which fields count.
static func curves_match(a: Curve, b: Curve) -> bool:
    if a == null or b == null:
        return a == b
    if a.point_count != b.point_count or a.min_value != b.min_value or a.max_value != b.max_value:
        return false
    for index in a.point_count:
        if a.get_point_position(index) != b.get_point_position(index):
            return false
        if a.get_point_left_tangent(index) != b.get_point_left_tangent(index):
            return false
        if a.get_point_right_tangent(index) != b.get_point_right_tangent(index):
            return false
    return true
