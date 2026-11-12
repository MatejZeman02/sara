## The toolbox's tools as views another docker can hold: one button per tool
## that puts the tool in the hand and is lit while it is there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What a composed docker can hold is exactly the registered layout elements,
## and the toolbox's elements are one per tool, "Brush Tool" to "Transform
## Tool", while its buttons are one per group with a flyout. So a view is the
## tool and not the group: a composed docker that holds the eraser holds a
## button for the eraser, not the paint group's face. A view is a second view
## of the same state, which here is the tool in the hand, so the button picks through the machine the canvas paints with and
## lights from what that machine holds, and the toolbox lights beside it.
##
## Registered through `SaSettings.register_layout_element`, the call a module
## makes for an element of its own. Its own file rather
## than more of `toolbox_docker.gd`, because it owns the views and not the
## docker's buttons, and called
## from `SaToolBoxGrid.register_options`, which the docker already calls once
## when it is built.
class_name SaToolBoxViews
extends RefCounted

## The Preferences category the toolbox's elements are filed under.
const CATEGORY: String = SaDockerIds.TOOLBOX


## Registers a view of every tool element the toolbox lists, through the door
## a module uses.
##
## *machines* answers the machine a view picks through and reads. Left empty,
## it is the main canvas's, found when the view needs it, which is every caller
## but a suite with a machine of its own. A second call replaces the first, so
## a suite puts the shipped views back by calling this with nothing.
static func register(machines: Callable = Callable()) -> void:
    var source := machines
    if not source.is_valid():
        source = func() -> ToolMachine: return main_machine()
    for element: String in tool_elements():
        var builder := func() -> Control: return ToolView.new(element, source)
        SaSettings.register_layout_element(CATEGORY, element, element, false, "", builder)


## The toolbox's elements that are tools: its shipped order without the drag
## bar and the grip, which are where things go.
static func tool_elements() -> Array[String]:
    var out: Array[String] = []
    for element: String in SaSettingsLayout.DEFAULT_ORDERS[CATEGORY]:
        if not SaSettings.ELEMENT_PLACES.has(element):
            out.append(element)
    return out


## The machine the front document paints with, or null before there is one.
## Read off the front surface whatever window the view sits in, so a view in a
## floating docker drives the same canvas the toolbox does.
static func main_machine() -> ToolMachine:
    var canvas := SaCanvasView.front_canvas()
    return canvas.tool_machine() if canvas != null else null


## One tool's view. A button rather than a face that changes, because the
## element is one tool, and lit by the toggle style the toolbox's own buttons
## use, so a painter reads the two the same way.
class ToolView:
    extends Button

    ## The layout element this view stands for, "Eraser Tool".
    var element: String = ""

    ## Answers the machine this view picks through, or null.
    var _machines: Callable

    func _init(for_element: String, machines: Callable) -> void:
        element = for_element
        _machines = machines
        name = for_element.replace(" ", "")
        set_meta(SaMake.KIND_META, SaMake.Kind.TOGGLE)
        toggle_mode = true
        SaTheme.make_toggle(self)
        var side := SaUI.px(SaToolBoxSize.shown_size)
        custom_minimum_size = Vector2(side, side)
        text = element.trim_suffix(" Tool")
        pressed.connect(_pick)
        EventBus.tool_changed.connect(_on_tool_changed)
        EventBus.docker_layout_changed.connect(sync)
        sync()

    ## On a change of locale as well, so the tooltip's tool name is in the
    ## language set now and not the one the view was built in.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_TRANSLATION_CHANGED:
            sync()

    ## The machine this view drives, or null when there is none yet.
    func machine() -> ToolMachine:
        return _machines.call() as ToolMachine if _machines.is_valid() else null

    ## The tool this view puts in the hand, or an empty id when the machine
    ## holds none that the element names. Matched the way the toolbox matches
    ## a row to a tool, by the id or the label, because the element names and
    ## the tool ids differ for some tools.
    func tool_id() -> StringName:
        var held := machine()
        if held == null or held.registry == null:
            return &""
        for descriptor: SaToolDescriptor in held.registry.list_tools():
            if SaToolBoxGrid.entry_matches(element, descriptor):
                return descriptor.id
        return &""

    ## Puts the tool in the hand, under the engine the Brush last painted with
    ## for the Brush, as the toolbox's own button does.
    func _pick() -> void:
        var held := machine()
        var id := tool_id()
        if held != null and held.registered_tools.has(id):
            held.set_active_tool(held.registry.picked(id))
        sync()

    func _on_tool_changed(_tool_name: String) -> void:
        sync()

    ## Lights the button while its tool is in the hand, and shows the tool's
    ## icon and chord. Read off the machine rather than the signal's name, since
    ## the scratchpad's machine announces on the same bus. A brush engine lights
    ## the Brush's view, the tool it paints as.
    func sync() -> void:
        var side := SaUI.px(SaToolBoxSize.shown_size)
        custom_minimum_size = Vector2(side, side)
        var held := machine()
        var id := tool_id()
        disabled = id == &""
        if held == null or id == &"":
            set_pressed_no_signal(false)
            # The toolbox's elements are its shipped tools, each with its whole
            # sentence, so a language with cases can decline the tool's name.
            tooltip_text = ""
            if SaWholeSentences.TOOL_NOT_LOADED.has(element):
                tooltip_text = tr(SaWholeSentences.TOOL_NOT_LOADED[element])
            return
        var descriptor := held.registry.get_descriptor(id)
        if descriptor.icon_name != "":
            SaUI.set_button_icon(self, descriptor.icon_name, descriptor.display_name)
        tooltip_text = _tooltip(descriptor)
        var in_hand := SaToolRegistry.tool_in(held.registry, held.active_tool_name)
        set_pressed_no_signal(in_hand == id)

    ## The tool's name and the keys its action has, "Eraser (E)", which is what
    ## the toolbox's own button says for a tool on its face.
    static func _tooltip(descriptor: SaToolDescriptor) -> String:
        var named: String = TranslationServer.translate(descriptor.display_name)
        var action := descriptor.activate_action
        if String(action).is_empty() or not InputMap.has_action(action):
            return named
        var chord := SaCommandRegistry.format_events(InputMap.action_get_events(action), 1)
        return named if chord.is_empty() else "%s (%s)" % [named, chord]
