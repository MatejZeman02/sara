## The Gradient row of the brush editor's Colour Dynamics page, which edits the
## preset's own ramp.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The bar is the base module's, reached through the door.** The gradient tool
## already has a ramp editor, with its stops, its swatch popup and the capture
## door a scenario drives. A second one here would be a
## second idea of what editing a stop means, and naming that one would be this
## module seeing past the door into another. So the base module registers the
## control under the role [constant SaColorPage.RAMP_ROLE], and this row asks the
## tool's role registry for the script behind it and builds that. Every call on
## it is by name, because the type is the base module's and not the door's.
##
## **The value is the tool's `tip_loaded`, as the tip preview's is.** A binder
## is handed a value and nothing else, and this row needs the tool behind it
## twice, for its role registry and for its settings, which the field's value
## alone could not give it. The signal's object is the tool. An edit sets
## `gradient` on the settings to a fresh array and then calls the write the
## factory was given with the same signal, which sets nothing and is what marks
## the preset dirty and asks for a preview, as a write does for any row.
##
## **Empty shows the painter's pair and stays empty.** A preset with no ramp of
## its own reads the colour to the background colour, by the settings' own rule,
## and the row draws that while the pair moves under it. Nothing is written until
## a hand edits a stop, so opening the page leaves an old preset as it was.
##
## **No library row.** The control's library offers the gradient tool's stock
## ramps, which follow that tool's colours and do nothing without it, so the row
## hides it rather than show a list whose top half is dead.
class_name SaGradientRow
extends VBoxContainer

## The control the role gave, or null before the first bind and on a machine
## where nothing answers the role.
var editor: Control = null

## The write the factory was handed, which tells the editor a row changed.
var _write: Callable = Callable()

## The tool behind the row, whose role registry the control comes from and whose
## `tip_loaded` the write is handed back.
var _tool: Object = null

## The tool's settings, held rather than copied, so a preset loaded under the row
## is what the next sync reads.
var _settings: SaStampBrushSettings = null

## What the row says on a machine with no ramp control registered.
var _missing: Label = null


func _init(write: Callable = Callable()) -> void:
    name = "GradientRow"
    _write = write
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _missing = Label.new()
    _missing.name = "NoRampControl"
    _missing.text = tr("No module brings a gradient editor, so this preset's gradient cannot be edited here.")
    _missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _missing.visible = false
    SaTheme.bind_font(_missing, "text_muted")
    add_child(_missing)
    # In `_init`, for the reason the ramp control gives: a row a test builds
    # detached never enters a tree, and it should follow the pair all the same.
    EventBus.color_picked.connect(_on_pair_moved)
    EventBus.background_color_changed.connect(_on_pair_moved)


## Points the row at the tool behind *loaded*, the tool's own `tip_loaded`. The
## binder calls it on every sync, so it rebinds the control only when the ramp
## it holds differs from the one the settings say, which keeps the selected stop
## under the hand.
func follow(loaded: Variant) -> void:
    var tool: Object = (loaded as Signal).get_object() if loaded is Signal else null
    if tool != _tool:
        _tool = tool
        _settings = tool.get("settings") as SaStampBrushSettings if tool != null else null
    if editor == null:
        _build_editor()
    _show()


## Builds the control the role names, once.
func _build_editor() -> void:
    var roles: Object = _tool.get("roles") if _tool != null else null
    var script: Script = roles.call("script_for", SaColorPage.RAMP_ROLE) as Script if roles != null else null
    _missing.visible = script == null
    if script == null:
        return
    editor = script.new() as Control
    if editor == null:
        return
    var library := editor.get_node_or_null(^"LibraryRow") as Control
    if library != null:
        library.visible = false
    editor.connect(&"ramp_changed", _on_ramp_edited)
    add_child(editor)


func _show() -> void:
    if editor == null or _settings == null:
        return
    var wanted := _settings.gradient_ramp()
    var held: Variant = editor.get("ramp")
    if held is SaColorRamp and (held as SaColorRamp).to_array() == wanted.to_array():
        return
    editor.call("bind_ramp", wanted)


## The pair moved, which only a row showing the pair redraws for. Deferred, so the
## module has written the new colour onto the settings before the row reads it.
func _on_pair_moved(_color: Color) -> void:
    if _settings != null and _settings.gradient.is_empty():
        _show.call_deferred()


## A hand edited a stop. The whole ramp lands on the settings as a fresh array,
## since the preset store shares an array it copies and an edit in place would
## reach every copy, and then the write says a row changed.
func _on_ramp_edited() -> void:
    var held: Variant = editor.get("ramp")
    if held is not SaColorRamp or _settings == null:
        return
    _settings.gradient = (held as SaColorRamp).to_array()
    if _write.is_valid():
        _write.call(_tool.get("tip_loaded"))


## The capture door, which the brush editor's `widget` step finds by this name
## and which the control answers.
func capture_option_edit(spec: Dictionary) -> String:
    if editor == null:
        return "SaCapture: gradient row has no ramp control"
    return String(editor.call("capture_option_edit", spec))


## What the row shows and what the field holds, for the editor's dump.
func capture_option_report() -> Dictionary:
    var shown: Dictionary = editor.call("stop_report") if editor != null else {}
    var held: Array = _settings.gradient.duplicate(true) if _settings != null else []
    return {"ramp": shown, "gradient": held, "follows_pair": held.is_empty()}
