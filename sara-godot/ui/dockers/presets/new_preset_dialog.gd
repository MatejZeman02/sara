## New preset...: a preset made from the defaults of an engine the painter picks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The brush engine is chosen in a dialog, because a painter who deletes every
## preset has nothing left to fork, while most new presets are forks. Forking is
## Save as... from the preset in hand. This is the other door: one row per registered engine, a name, and Create, which
## writes that engine's defaults under the name and puts the preset in the hand.
##
## **Every engine the registry knows, whatever the tool in hand.** The bar's own
## list of engines is the shown tool's, so with the lasso in hand it is none and
## with the Brush it leaves out an engine no Brush paints. A preset of each engine
## is what an emptied library has to be able to get back, so the list is every
## engine a registered tool declares, once each, in registration order.
##
## **Hosted on the bar's preset group**, the node the delete question is hosted
## on and for its reason: it outlives the docker that asked, and it is the group
## whose store is written and whose `load_preset` selects. One dialog per group,
## built on the first ask and kept, so the docker's button and the cell menu in
## either chooser open the same window.
##
## Beside the Brush Presets docker, whose button opens it. Public, because the
## cell menu in
## `ui/presets` opens it as well.
@tool
class_name SaNewPresetDialog
extends SaDialogWindow

## The node name the dialog is kept under on the bar's preset group, so the next
## ask finds it rather than building a second.
const NODE_NAME: String = "NewPresetDialog"

## The registry the engines are read from. Handed in by a suite, and otherwise
## null and looked up on the main scene at each open, the way the cell menu finds
## its converters, so a module loaded after the dialog was built is offered.
var _tools: SaToolRegistry = null

## The bar's preset group the dialog writes through, set at each open.
var _presets: ToolOptionsPresets = null

## The engines on offer as the last open listed them, each `{engine, label,
## script}`, in the order their rows stand.
var _engines: Array[Dictionary] = []

## One radio row per engine, in the order of [member _engines].
var _rows: Array[CheckBox] = []

## The name a pick put in the field, so a pick after it renames only a name the
## painter has not typed over.
var _offered_name: String = ""

var _engine_column: VBoxContainer = null
var _name_field: LineEdit = null
var _status: Label = null
var _create_button: Button = null


func _init(tools: SaToolRegistry = null) -> void:
    _tools = tools
    _init_dialog(NODE_NAME, tr("New Preset"), Vector2i(360, 260), Vector2i(300, 220))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    SaMake.label(column, "EngineLabel", tr("Engine"))
    _engine_column = SaMake.column(column, "Engines", 4)

    SaMake.label(column, "NameLabel", tr("Name"))
    _name_field = SaMake.line_edit(column, "NameField", "", tr("The new preset's name"))
    _name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Unbound, because `text_submitted` hands the text and `create` reads the
    # field itself, the shape New Module's field has for the same reason.
    _name_field.text_submitted.connect(_on_create_pressed.unbind(1))
    first_focus = _name_field

    _status = SaMake.label(column, "StatusLabel")
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD
    _status.visible = false
    SaTheme.bind_font(_status, "text_muted")

    var buttons := pinned_buttons(column)
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    _create_button = SaMake.button(buttons, "CreateButton", tr("Create"))
    _create_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    _create_button.pressed.connect(_on_create_pressed)
    default_button = _create_button


## Opens the dialog of the bar's preset group in *node*'s tree, building it on
## the first ask, and answers it, or null in a tree with no bar to write through.
static func open_from(node: Node) -> SaNewPresetDialog:
    var presets := ToolOptionsPresets.in_tree(node)
    if presets == null:
        return null
    var dialog := presets.get_node_or_null(NODE_NAME) as SaNewPresetDialog
    if dialog == null:
        dialog = SaNewPresetDialog.new()
        presets.add_child(dialog)
    dialog.open(presets)
    return dialog


## Lists the engines afresh, picks the one in hand when it is among them, offers
## a free name for it and shows the window.
func open(presets: ToolOptionsPresets) -> void:
    _presets = presets
    _engines = registered_engines(_tool_registry())
    for row: CheckBox in _rows:
        _engine_column.remove_child(row)
        row.queue_free()
    _rows.clear()
    var group := ButtonGroup.new()
    for entry: Dictionary in _engines:
        var row := SaMake.check_box(_engine_column, "Engine_" + String(entry["engine"]), String(entry["label"]))
        row.button_group = group
        row.tooltip_text = tr("Start from the %s engine's own defaults.") % String(entry["label"])
        row.pressed.connect(_on_engine_picked.bind(_rows.size()))
        _rows.append(row)
    _offered_name = ""
    _name_field.text = ""
    _say("" if not _engines.is_empty() else tr("No engine is registered, so there is nothing to start a preset from"))
    _create_button.disabled = _engines.is_empty()
    var in_hand := _engines.map(func(entry: Dictionary) -> StringName: return entry["engine"]).find(presets.preset_engine())
    pick(maxi(in_hand, 0))
    if is_inside_tree():
        popup_centered()
        _name_field.select_all()


## Every engine a registered tool declares, once each and in registration order:
## `{engine, label, script}`, the script being the settings class whose new
## instance is that engine's defaults. A tool that declares none takes no
## presets and is left out, which is how `ToolOptionsPresets` reads one.
static func registered_engines(tools: SaToolRegistry) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if tools == null:
        return out
    var seen: Dictionary = {}
    for descriptor: SaToolDescriptor in tools.list_descriptors():
        var settings := descriptor.shared_settings
        var engine := descriptor.preset_engine
        if String(engine).is_empty():
            engine = SaPresetStore.preset_engine_of(settings)
        var script := settings.get_script() as Script if settings != null else null
        if String(engine).is_empty() or seen.has(engine) or script == null:
            continue
        seen[engine] = true
        out.append({"engine": engine, "label": SaPresetStore.engine_label(engine), "script": script})
    return out


## Picks the engine at *index* in the list, and moves the name with it while the
## field still holds the name the last pick offered. Answers whether there was
## such an engine.
func pick(index: int) -> bool:
    if index < 0 or index >= _rows.size():
        return false
    _rows[index].button_pressed = true
    if _name_field.text == _offered_name:
        _offered_name = _free_name(tr("New %s preset") % String(_engines[index]["label"]))
        _name_field.text = _offered_name
    return true


## The engine whose row is down, or empty with none.
func picked_engine() -> StringName:
    var index := _picked_index()
    return _engines[index]["engine"] if index >= 0 else &""


## Where the row that is down stands in the list, or -1 with none.
func _picked_index() -> int:
    for index: int in _rows.size():
        if _rows[index].button_pressed:
            return index
    return -1


## Create: writes the picked engine's defaults under the typed name, tells the
## bar's list and every grid, and loads the preset so the brush holds it and its
## cell is marked. Answers the stored name, or "" with the dialog left open and
## the line under the field saying why.
##
## **A name already taken is refused**, never written over. A new preset that
## replaced one of the same name would be a delete nobody was asked about, the
## one act in this docker that asks first.
func create() -> String:
    var typed := _name_field.text
    var stored_name := SaPresetStore.sanitize_name(typed)
    var index := _picked_index()
    if _presets == null or index < 0:
        return ""
    if stored_name.is_empty():
        _say(tr("A preset needs a name."))
        return ""
    if _presets.preset_store.has_preset(stored_name):
        _say(tr("'%s' is taken. Choose another name, or load it and use Save As...") % stored_name)
        return ""
    var script: Script = _engines[index]["script"]
    var stored := _presets.preset_store.save_preset(stored_name, script.new() as Resource)
    if stored.is_empty():
        _say(tr("'%s' could not be saved") % typed)
        return ""
    # The bar's list, then every grid through the announcement a save makes, and
    # only then the load, so the cell the load marks is already built.
    _presets.refresh()
    EventBus.preset_store_changed.emit(stored, true)
    _presets.load_preset(stored)
    hide()
    return stored


## What a dump reads about the dialog: the engines on offer, the one picked, the
## name and the line under it.
func dialog_report() -> Dictionary:
    return {
        "open": visible,
        "engines": _engines.map(func(entry: Dictionary) -> String: return String(entry["engine"])),
        "labels": _rows.map(func(row: CheckBox) -> String: return row.text),
        "picked": String(picked_engine()),
        "name": _name_field.text,
        "said": _status.text if _status.visible else "",
        "create_disabled": _create_button.disabled,
    }


## Drives the open dialog from a scenario, `{"pick": "noise", "name": "Grain",
## "create": true}`, each key in that order, and answers its report with what
## Create stored. An engine the dialog does not offer is a loud failure.
func capture_dialog(spec: Dictionary) -> String:
    if spec.has("pick"):
        var wanted := StringName(String(spec["pick"]))
        var at := _engines.map(func(entry: Dictionary) -> StringName: return entry["engine"]).find(wanted)
        if not pick(at):
            return "SaCapture: new preset dialog pick failed, no engine '%s'" % wanted
    if spec.has("name"):
        _name_field.text = String(spec["name"])
    var stored := create() if bool(spec.get("create", false)) else ""
    return "SaCapture: new preset dialog %s stored='%s'" % [JSON.stringify(dialog_report()), stored]


## The handed registry, or the running app's, or null in a host with neither.
func _tool_registry() -> SaToolRegistry:
    if _tools != null:
        return _tools
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.registries
    return registries.tools if registries != null else null


## *wanted*, or *wanted* numbered from 2 while the store holds it.
func _free_name(wanted: String) -> String:
    var candidate := wanted
    var number := 2
    while _presets != null and _presets.preset_store.has_preset(candidate):
        candidate = "%s %d" % [wanted, number]
        number += 1
    return candidate


func _on_engine_picked(index: int) -> void:
    pick(index)


func _on_create_pressed() -> void:
    create()


## Puts *text* on the line under the field, or hides it for "".
func _say(text: String) -> void:
    _status.text = text
    _status.visible = not text.is_empty()
