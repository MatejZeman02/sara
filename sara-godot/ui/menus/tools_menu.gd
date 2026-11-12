## The Tools menu: every registered tool, with its chord, the Edit Brush... row
## and the stabilizer's modes.
##
## A painter who does not know the tools' letters would have the toolbox and
## nothing else. So the rows are read off `SaToolRegistry` on every open rather than listed here, and
## a module's tool is in the menu the next time it opens after it registers, with
## no line added to this file.
##
## **Built on every open, so nothing here listens for a registration.** The bar
## calls `populate()` before it shows any menu, and a list read at that moment
## is already the list the registry holds.
##
## **The chord is whatever the tool's own action carries**, not a table of its
## own: every descriptor names its own `activate_action`, the gradient, the
## crop, the transform and the marquee among them, and the router's generic
## loop over the registry answers every one. A row shows the keys that action has in the input map and
## nothing when it has none, so a rebinding on the Shortcuts page is what the
## menu prints the next time it opens.
##
## **Edit Brush... is a command's row, not a tool's.** The brush editor was named
## by no menu, so at 1920 by 1080 the top bar's overflow held it alone and a
## painter who hid the bar's button had the chord and nothing else to find it
## by. It sits under the tool rows, because it edits the brush the first of them
## puts in hand, and `add_command` draws it from the command, so its words, its
## chord and its sentence are the ones the Keyboard Shortcuts page lists and a
## rebinding there is what the row prints next.
##
## **The stabilizer rows write the setting the Tool Options docker writes.** The
## modes are read from the `stabilizer_mode` spec the tool declares, so the names
## and the values are the tool's and not a second copy, and the write goes through
## `ToolOptionControls.write_spec` and then `tool_options_moved`, which is how the
## docker and the bar follow a write they did not make.
class_name SaToolsMenu
extends SaMenu

## Where the tool rows start, clear of every hand-assigned id on the bar.
const TOOL_ROW_BASE: int = 1100

## Where the stabilizer rows start.
const STABILIZER_ROW_BASE: int = 1200

## The Edit Brush... row, clear of both bases above and of the 1100 to 1299
## they span.
const EDIT_BRUSH_ROW: int = 1300

## The command the row above runs.
const EDIT_BRUSH_COMMAND := &"edit_brush"

## The option key whose choices the stabilizer section offers.
const STABILIZER_KEY := &"stabilizer_mode"

## The machine whose tools are listed and switched. Null means the main canvas's,
## found at the moment it is needed. A test hands a bound machine in here, because
## a menu built on a detached bar has no canvas to find.
var machine: ToolMachine = null

## Row id -> tool id, rebuilt with the rows, because a module unloading takes its
## tool and therefore its row with it.
var _tool_rows: Dictionary = {}


func _add_items() -> void:
    _tool_rows.clear()
    var tools := _machine()
    if tools == null or tools.registry == null:
        add_item(tr("No tools are registered"), TOOL_ROW_BASE, true)
        # A row says what it is even when it is the one saying nothing is there.
        # A bar with no canvas under it, which a test builds, lands here.
        set_item_tooltip(TOOL_ROW_BASE, tr("There is no canvas to take tools from, so there is nothing to switch to."))
        return

    add_heading(tr("Tools"))
    var row_id := TOOL_ROW_BASE
    for descriptor: SaToolDescriptor in tools.registry.list_tools():
        var label := tr(descriptor.display_name) if not descriptor.display_name.is_empty() else String(descriptor.id).capitalize()
        add_item(label, row_id, false, chord_for(descriptor), descriptor.icon_name)
        # A shipped tool's line is a whole sentence, so a language with cases
        # can decline its name. A module's own tool reads the generic one.
        if SaWholeSentences.TOOL_SWITCHES.has(descriptor.display_name):
            set_item_tooltip(row_id, tr(SaWholeSentences.TOOL_SWITCHES[descriptor.display_name]))
        else:
            set_item_tooltip(row_id, tr("Switches to the %s tool.") % label)
        _tool_rows[row_id] = descriptor.id
        row_id += 1

    # A bar no registry is bound to has no command to draw, and a line with no
    # row under it is not drawn either, so the two are asked for together.
    if _descriptor(EDIT_BRUSH_COMMAND) != null:
        add_separator()
        add_command(EDIT_BRUSH_ROW, EDIT_BRUSH_COMMAND)
    _add_stabilizer_rows(tools)


## The keys *descriptor*'s activate action has, as the Shortcuts page prints them,
## or empty for a tool with no action or an action with no keys.
static func chord_for(descriptor: SaToolDescriptor) -> String:
    var action := descriptor.activate_action
    if String(action).is_empty() or not InputMap.has_action(action):
        return ""
    return SaKeyLabels.column(SaCommandRegistry.format_events(InputMap.action_get_events(action), 1))


## The stabilizer's modes as a choice of one, the mode the owning tool is set to
## marked and no box on any row, each row
## saying what its mode does in the words of the choice's own `tooltip`. Left out
## entirely when no registered tool declares a stabilizer, rather than drawn empty.
func _add_stabilizer_rows(tools: ToolMachine) -> void:
    var owner := stabilizer_owner(tools)
    if owner.is_empty():
        return
    var spec: SaOptionSpec = owner["spec"]
    var current: Variant = ToolOptionControls.read_spec(spec, owner["tool"])
    add_separator()
    add_heading(tr(spec.label))
    for index in spec.choices.size():
        var choice: Dictionary = spec.choices[index]
        add_choice_item(tr(String(choice["label"])), STABILIZER_ROW_BASE + index, STABILIZER_KEY, choice["id"] == current)
        set_item_tooltip(STABILIZER_ROW_BASE + index, tr(String(choice.get("tooltip", ""))))


## The tool whose stabilizer the rows write, and its spec, or empty.
##
## The rule the tool options bar's `owner_of` uses: the active tool when it
## declares the option, and otherwise the first painting tool that does. So with
## the eyedropper active the menu still moves the brush's stabilizer, which is the
## one the bar and the docker are showing.
static func stabilizer_owner(tools: ToolMachine) -> Dictionary:
    if tools == null:
        return {}
    var candidates: Array[StringName] = [tools.active_tool_name]
    for id: StringName in tools.registered_tools.keys():
        var descriptor := tools.get_descriptor(id)
        if descriptor != null and descriptor.is_painting and not candidates.has(id):
            candidates.append(id)
    for id: StringName in candidates:
        var descriptor := tools.get_descriptor(id)
        var tool := tools.get_tool(id)
        if descriptor == null or tool == null:
            continue
        for spec: SaOptionSpec in descriptor.options:
            if spec != null and spec.key == STABILIZER_KEY:
                return {"spec": spec, "tool": tool, "id": id}
    return {}


func on_id_pressed(id: int) -> void:
    # A command's row runs through the registry, the way every other menu's does,
    # and needs no machine: the brush editor asks the bar which tool it shows.
    if not command_at(id).is_empty():
        super(id)
        return
    var tools := _machine()
    if tools == null:
        return
    if _tool_rows.has(id):
        # The Brush's row picks the engine it last painted with, as its button does.
        tools.set_active_tool(tools.registry.picked(_tool_rows[id]) if tools.registry != null else _tool_rows[id])
        return
    var index := id - STABILIZER_ROW_BASE
    var owner := stabilizer_owner(tools)
    if owner.is_empty():
        return
    var spec: SaOptionSpec = owner["spec"]
    if index < 0 or index >= spec.choices.size():
        return
    if ToolOptionControls.write_spec(spec, spec.choices[index]["id"], owner["tool"]):
        EventBus.tool_options_moved.emit()
    # A choice row leaves the menu open, so the mark moves with the pick rather
    # than waiting for the next populate with the old mode still marked.
    mark_choice(id)


## The machine to list, handed in or found on the front document's canvas.
func _machine() -> ToolMachine:
    if machine != null:
        return machine
    if not in_tree():
        return null
    var canvas := SaCanvasView.front_canvas()
    return canvas.tool_machine() if canvas != null else null
