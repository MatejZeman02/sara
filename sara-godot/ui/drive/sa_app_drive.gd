## What a bound control drives in the running app, the drive the app hands
## the context: the values a slider names read and set by that name, a brush
## preset chosen by its stored name, a filter's command run by its key, and
## what a click on a control would bind.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The app's [SaControlDrive], so the MIDI bindings ask `SaContext.drive` and
## name no window of the app, which is what lets them live in a module rather
## than in `ui`. Nothing in it is MIDI's.
##
## A binding outlives the slider it was made on, since a filter's dialog and
## the brush editor come and go, so it keeps the name and this finds the value
## again. The names are the ones `FactorSlider.value_name` lists, written by the
## builders a module's sliders go through as well: the options bar and the
## brush editor's `ToolOptionControls`, `SaDialog.for_filter` handed the
## registry's key by the filter's own window, a Preferences page's slider row
## and the layer's opacity row. Nothing here keeps a list of its own, which is
## the point of the name (hard rule 6, built-ins use the public door).
##
## Two kinds of name and two ways of finding the value:
##
## - **A tool's option and the active layer's opacity are read off the model**,
##   the tool's settings through its `SaOptionSpec` and the layer through
##   `SaLayerOps`, so they move with no slider on screen. An option can be
##   moved while its tool is registered, and the opacity while a layer is
##   active.
## - **A filter's option and a Preferences value are moved through the slider
##   on screen that carries the name**, the way a hand moves it, so the
##   dialog's preview runs again and the page writes the setting by its own
##   path. A filter's option can be moved only while that filter's dialog is
##   open, since the value belongs to the dialog until Apply. A Preferences
##   value only while its page is open, because the range is the page's
##   declaration and a setting keeps none of its own.
##
## A value is read and written in its own units: a tool's option as the tool
## keeps it, the brush's size a fraction of the canvas, and the rest as its
## slider holds it. [method read_ratio] and [method write_ratio] are the same
## across the range a drag of its slider covers, geometric where the slider's
## drag is, which is what a fader is.
##
## **What a click can bind**, walking up from the control under the press: a
## slider that names its value is a dial, a brush preset's cell is that
## preset, a filter's row in the Filters docker is that filter, and any other
## button the widget maker made is that button, kept by the name it was made under.
class_name SaAppDrive
extends SaControlDrive

## The start of a tool option's name, `tool/<tool>/<key>`.
const TOOL_PREFIX := "tool/"

## The active layer's opacity, whichever layer that is when the control moves.
const LAYER_OPACITY := &"layer/opacity"

## `func() -> ToolMachine`, the machine whose tools and canvas the values are
## read off. A callable, as the brush slot commands take it, because the
## machine is built after whoever builds this.
var _tool_machine_provider: Callable = Callable()

## The slider on screen last found carrying a name, so a control turning a
## filter's option walks the tree once rather than at every message.
var _live: WeakRef = null


## *tool_machine_provider* answers the machine the values are read off, the
## main canvas's when none is given.
func _init(tool_machine_provider: Callable = Callable()) -> void:
    _tool_machine_provider = tool_machine_provider if tool_machine_provider.is_valid() else main_tool_machine


## The made control called *control_name* under *under*, the app's window when
## *under* is null, or null. One shown on screen wins over one that is not,
## because a screen built once and hidden again keeps its controls, and a
## caller means the one the painter sees.
func find_control(control_name: String, under: Node = null) -> Control:
    if under == null:
        var tree := Engine.get_main_loop() as SceneTree
        under = tree.root if tree != null else null
    return find_made(under, control_name)


## What [method find_control] does under a node the caller names, static so the
## harness's walker reads it with no app built, as a suite's walker does.
static func find_made(under: Node, control_name: String) -> Control:
    if under == null or control_name.is_empty():
        return null
    var hidden: Control = null
    for node in under.find_children(control_name, "Control", true, false):
        var control := node as Control
        if SaMake.kind_of(control) < 0 or control.is_queued_for_deletion():
            continue
        if control.is_visible_in_tree():
            return control
        if hidden == null:
            hidden = control
    return hidden


## Through the main window's dockers, the closed one holding *control*
## toggled open by its index, so the layout store, the menu's checkmark and the
## usage tally follow as they do for a row press.
func bring_out(control: Control) -> bool:
    if control == null or control.is_visible_in_tree():
        return control != null
    var main := _main()
    var dockers: MainDockers = main.get("dockers") as MainDockers if main != null else null
    if dockers == null:
        return false
    var config := dockers.get_docker_config()
    for index in config.size():
        var node: Window = config[index]["node"] as Window
        if not node.visible and node.is_ancestor_of(control):
            dockers.toggle_docker(index)
            break
    return control.is_visible_in_tree()


## The name of the value *control* moves, empty when it moves nothing
## nameable: a `FactorSlider`'s own, or the one a Preferences row's slider
## carries as a meta.
static func name_of(control: Control) -> StringName:
    var slider := control as FactorSlider
    if slider != null:
        return slider.value_name
    if control != null and control.has_meta(SaPage.VALUE_NAME_META):
        return StringName(control.get_meta(SaPage.VALUE_NAME_META))
    return &""


## Whether the value named *value_name* can be moved now.
func can_move(value_name: StringName) -> bool:
    return _target(value_name) != null


## The ends a drag of the value's slider reaches, bottom then top, or two NaNs
## when it cannot be moved now. The soft ceiling where the slider has one, as a
## drag stops there, and a typed [method write] goes on to the hard one.
func range_of(value_name: StringName) -> Vector2:
    var target := _target(value_name)
    return Vector2(target.bottom, target.top) if target != null else Vector2(NAN, NAN)


## Where the value stands, or NaN when it cannot be moved now.
func read(value_name: StringName) -> float:
    var target := _target(value_name)
    return target.read() if target != null else NAN


## Sets the value to *value*, held to its hard range. True when there was a
## value to set.
##
## *merge* is handed to a value that is an undo step, a layer's opacity for one,
## so a turn of a control opens a step and the rest of the turn folds into it.
## The bindings decide it and everything else passes the default.
func write(value_name: StringName, value: float, merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
    var target := _target(value_name)
    return target != null and target.write(value, merge)


## Where the value stands across its range, nought at the bottom and one at
## the top, or NaN when it cannot be moved now.
func read_ratio(value_name: StringName) -> float:
    var target := _target(value_name)
    return target.ratio_of(target.read()) if target != null else NAN


## Sets the value *ratio* of the way across its range. True when there was a
## value to set. *merge* as [method write].
func write_ratio(value_name: StringName, ratio: float, merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
    var target := _target(value_name)
    return target != null and target.write(target.at_ratio(clampf(ratio, 0.0, 1.0)), merge)


## Whether the bar's preset store holds *preset*.
func has_preset(preset: String) -> bool:
    var presets := SaBrushSlotCommands.preset_box()
    return presets != null and presets.preset_store != null and presets.preset_store.has_preset(preset)


## Loads *preset* as a press on its cell does, through the bar's preset group,
## which holds the one store.
func choose_preset(preset: String) -> bool:
    if not has_preset(preset):
        return false
    return SaBrushSlotCommands.preset_box().load_preset(preset)


## Whether the main scene's filter registry holds *key*.
func has_filter(key: StringName) -> bool:
    var registries := _registries()
    return registries != null and registries.filters != null and registries.filters.get_filter(key) != null


## Runs the command of the filter registered under *key*, the one its menu row
## and its chord run, which opens its dialog.
func run_filter(key: StringName) -> bool:
    if not has_filter(key):
        return false
    var registries := _registries()
    return registries.commands.execute(SaFilterRegistry.command_for(key, registries.filters.get_filter(key)))


## What a click on *control* binds, `{kind, target, label}`, walking up from it
## to the first control that names something, or empty when none does. Up to
## the window and no further, so a click on a docker's empty corner is not
## taken for whatever the docker sits in.
func target_of(control: Control) -> Dictionary:
    var node: Node = control
    while node != null and not (node is Window):
        var at := node as Control
        if at != null:
            var value_name := name_of(at)
            if not String(value_name).is_empty():
                return {"kind": DIAL, "target": String(value_name), "label": dial_label(at, value_name)}
            if at.has_meta(SaBrushPresetsChooser.PRESET_META):
                var preset := String(at.get_meta(SaBrushPresetsChooser.PRESET_META))
                return {"kind": PRESET, "target": preset, "label": preset}
            if at.has_meta(SaFilterBrowser.FILTER_META):
                var row := at as Button
                var key := String(at.get_meta(SaFilterBrowser.FILTER_META))
                return {"kind": FILTER, "target": key, "label": row.text if row != null else key}
        node = node.get_parent()
    return _button_target(control)


## A button the click is on or inside, after the three kinds above had their
## turn, so a cell's picture button is still its preset. Empty for one that
## [method find_control] could not find again by name, since a binding to it
## would not survive a restart.
func _button_target(control: Control) -> Dictionary:
    var node: Node = control
    while node != null and not (node is Window):
        var button := node as BaseButton
        if button != null and SaMake.kind_of(button) >= 0 and not button.is_queued_for_deletion():
            var target := _button_name(button)
            if not target.is_empty():
                return {"kind": BUTTON, "target": target, "label": _button_label(button)}
        node = node.get_parent()
    return {}


## The name that finds *button* again: its own where no other made control
## carries it, else the holder's, a slash and its own.
func _button_name(button: BaseButton) -> String:
    if _made_named(button.name) == 1:
        return String(button.name)
    var holder := _holder_of(button)
    return "%s/%s" % [holder.name, button.name] if holder != null else ""


## The words a painter reads for *button*: its text, else its tooltip, else its name.
static func _button_label(button: BaseButton) -> String:
    var text: String = (button as Button).text.strip_edges() if button is Button else ""
    if text.is_empty():
        text = button.tooltip_text.strip_edges()
    return text if not text.is_empty() else String(button.name)


## The button a [method _button_name] answer finds, or null.
func _button_named(target: String) -> BaseButton:
    var parts := target.split("/", true, 1)
    if parts.size() == 2:
        var tree := Engine.get_main_loop() as SceneTree
        var holders: Array[Node] = tree.root.find_children(parts[0], "", true, false) if tree != null else []
        for holder: Node in holders:
            var inside := find_control(parts[1], holder) as BaseButton
            if inside != null:
                return inside
        return null
    return find_control(target) as BaseButton


## Presses the button as a click does, a toggle flipping and then announcing
## the press like any other, and a disabled button left alone.
func press_button(target: String) -> bool:
    var button := _button_named(target)
    if button == null or button.disabled:
        return false
    if button.toggle_mode:
        button.button_pressed = not button.button_pressed
    button.pressed.emit()
    return true


## What a press in *window* at *point* binds. The control is the one drawn
## under the point, found by the note mode's hit test, the deepest one the GUI
## would pick, because an injected press need not have moved the hover first.
## Only where a window has none of its own to name, a menu's, it is the control
## the window belongs to, so a preset in the bar's popup is that preset rather
## than the popup's button.
func target_at(window: Window, point: Vector2) -> Dictionary:
    var under := SaNoteMode.control_under(window, point)
    return target_of(under if under != null else SaNoteMode.control_at(window, point))


## The made control under the point, or the nearest made one holding it, that
## [method find_control] finds again by its name, so a step that names it aims
## at it and at no namesake. A control the canvas holds is not named, since a
## press there is a stroke. A holder is named only while its centre, where a
## step naming it aims, still falls on the control pressed: a row of the
## toolbox's flyout is a container no step can name, inside the flyout's
## column, and naming the column aimed the replay at another row, so
## such a press names nothing and the step keeps its point.
func control_name_at(window: Window, point: Vector2) -> String:
    var inner := _embedded_under(window, point)
    if inner != null:
        return control_name_at(inner, inner.get_final_transform().affine_inverse() * (point - Vector2(inner.position)))
    var canvas := SaCanvasView.front_canvas()
    var found := ""
    var node: Node = SaNoteMode.control_at(window, point)
    var pressed: Control = null
    while node != null and not (node is Window):
        var control := node as Control
        if control != null and control == canvas:
            return ""
        if control != null and SaMake.kind_of(control) >= 0 and find_control(control.name) == control:
            if pressed != null and not pressed.get_global_rect().has_point(control.get_global_rect().get_center()):
                return found
            if _made_named(control.name) == 1:
                return String(control.name)
            found = String(control.name) if found.is_empty() else found
        if control != null and pressed == null:
            pressed = control
        node = node.get_parent()
    return found


## [method control_name_at]'s name when it is the only made control carrying
## it. Otherwise the made control pressed with the nearest node above it that
## the root finds by its own name and under which the control's name finds it,
## the `in` a scenario's click goes under: a row of a menu is a button called
## `Label` like every other row's, which its name alone cannot aim at.
func control_aim_at(window: Window, point: Vector2) -> Dictionary:
    var inner := _embedded_under(window, point)
    if inner != null:
        return control_aim_at(inner, inner.get_final_transform().affine_inverse() * (point - Vector2(inner.position)))
    var named := control_name_at(window, point)
    if not named.is_empty() and _made_named(named) == 1:
        return {"control": named}
    var made := _made_pressed(window, point)
    var holder := _holder_of(made)
    if holder != null:
        return {"control": String(made.name), "in": String(holder.name)}
    return {} if named.is_empty() else {"control": named}


## The deepest made control drawn under *point* of *window* or holding what
## is, null on the canvas, where none is, or where its centre, which a step
## aims at, falls off the control pressed.
static func _made_pressed(window: Window, point: Vector2) -> Control:
    var canvas := SaCanvasView.front_canvas()
    var under := SaNoteMode.control_under(window, point)
    var node: Node = under if under != null else SaNoteMode.control_at(window, point)
    var pressed: Control = null
    while node != null and not (node is Window):
        var control := node as Control
        if control != null and control == canvas:
            return null
        if control != null and SaMake.kind_of(control) >= 0 and not control.is_queued_for_deletion():
            if pressed != null and not pressed.get_global_rect().has_point(control.get_global_rect().get_center()):
                return null
            return control
        if control != null and pressed == null:
            pressed = control
        node = node.get_parent()
    return null


## The nearest node above *control* that no other node is named after and
## under which [method find_control] finds *control* by its own, or null. A
## name found first only while a list keeps its order, a preset cell's `Icon`,
## is no holder, and neither is one the engine made up, `@VBoxContainer@12`.
func _holder_of(control: Control) -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    if control == null or tree == null:
        return null
    var node := control.get_parent()
    while node != null and node != tree.root:
        var holder_name := String(node.name)
        if not holder_name.begins_with("@") and tree.root.find_children(holder_name, "", true, false).size() == 1:
            if find_control(String(control.name), node) == control:
                return node
        node = node.get_parent()
    return null


## How many made controls in the whole tree carry *control_name*. A preset's
## cell button is one of a hundred called `Icon`, and the first of them is
## found by the name only while the list keeps its order, so a name only one
## control carries, the cell's own, is the better aim.
static func _made_named(control_name: StringName) -> int:
    var tree := Engine.get_main_loop() as SceneTree
    var count := 0
    for node in tree.root.find_children(String(control_name), "Control", true, false) if tree != null else []:
        if SaMake.kind_of(node as Control) >= 0 and not node.is_queued_for_deletion():
            count += 1
    return count


## The front canvas, or a control inside it, is what the hit test finds there.
func is_canvas_at(window: Window, point: Vector2) -> bool:
    if _embedded_under(window, point) != null:
        return false
    var canvas := SaCanvasView.front_canvas()
    var under := SaNoteMode.control_under(window, point)
    return canvas != null and under != null and (under == canvas or canvas.is_ancestor_of(under))


## The window *window* embeds that is drawn over *point*, a docker, a dialog or
## an open menu, where the press goes before the window itself hears it, or
## null.
static func _embedded_under(window: Window, point: Vector2) -> Window:
    if window == null or not window.is_embedding_subwindows():
        return null
    var stack := window.get_embedded_subwindows()
    for i in range(stack.size() - 1, -1, -1):
        var inner := stack[i]
        if inner.visible and not inner.mouse_passthrough and Rect2(Vector2(inner.position), Vector2(inner.size)).has_point(point):
            return inner
    return null


## Through the inverse of the transform `SaScenarioStroke.to_root` carries a
## document stroke out by.
func document_point(point: Vector2) -> Vector2:
    var canvas := SaCanvasView.front_canvas()
    if canvas == null:
        return Vector2(NAN, NAN)
    return canvas.get_global_transform_with_canvas().affine_inverse() * point


func active_tool() -> StringName:
    var machine := main_tool_machine()
    return machine.active_tool_name if machine != null else &""


## Through `SaSadSave` with *owns* off, so the copy never becomes the
## document's own file.
func save_copy(document: SaDocument, path: String, then: Callable) -> bool:
    if document == null or path.is_empty():
        return false
    SaSadFile.save_in_background(document, path, 0, null, false, then)
    return true


## Through the transform [method document_point] inverts.
func window_point(point: Vector2) -> Vector2:
    var canvas := SaCanvasView.front_canvas()
    if canvas == null:
        return Vector2(NAN, NAN)
    return canvas.get_global_transform_with_canvas() * point


func is_front(document: SaDocument) -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    var front := SaDocuments.front_in(tree.current_scene) if tree != null else null
    return document != null and front != null and front.get_document() == document


## A tab of `SaDocumentTabs.add_document`, the one File > New opens, filled
## the way File > Open fills one, and left untitled rather than marked saved.
func open_copy(path: String, then: Callable) -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    var tabs := SaDocumentTabs.in_tree(tree)
    if tabs == null or not FileAccess.file_exists(path):
        return false
    var surface := tabs.add_document()
    if surface == null or surface.get_document() == null:
        return false
    var document := surface.get_document()
    SaExport.open_sad(document, path, func(error: Error) -> void: then.call(_settled(error, surface), document))
    return true


func load_copy(document: SaDocument, path: String, then: Callable) -> bool:
    var surface := _surface_of(document)
    if surface == null or not FileAccess.file_exists(path):
        return false
    SaExport.open_sad(document, path, func(error: Error) -> void: then.call(_settled(error, surface)))
    return true


## The composite after the export's own flush, so a part the window left
## unshown is in it too.
func picture(document: SaDocument) -> Image:
    var surface := _surface_of(document)
    return _composited(surface.easel) if surface != null else null


## In an easel of its own that is in no tree and is freed before the answer,
## made at a size of its own that the file's replaces.
func picture_of(path: String) -> Image:
    if not FileAccess.file_exists(path):
        return null
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var picture_read: Image = null
    if SaExport.load_sad(easel.document, path, easel.compositor) == OK:
        easel.resize_output(easel.document.canvas_size)
        picture_read = _composited(easel)
    easel.free()
    return picture_read


## *error*, once a file opened into *surface*'s document has been fitted to
## its canvas and its history taken away, as File > Open does after a `.sad`.
static func _settled(error: Error, surface: SaSurface) -> Error:
    var document := surface.get_document()
    if error != OK or document == null:
        return error
    var canvas := SaCanvasView.canvas_of(surface)
    if canvas != null:
        canvas.resize_canvas(document.canvas_size)
    if document.undo_redo != null:
        document.undo_redo.clear_history()
    if document.history != null:
        document.history.reset()
    return error


static func _composited(easel: SaEasel) -> Image:
    if easel == null or easel.document == null:
        return null
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    SaExport.flush_for_export(easel)
    return SaExport.get_texture_image_float(easel.output)


static func _surface_of(document: SaDocument) -> SaSurface:
    var tree := Engine.get_main_loop() as SceneTree
    var held: Object = tree.current_scene.get("documents") if tree != null and tree.current_scene != null else null
    return (held as SaDocuments).surface_of(document) if held is SaDocuments and document != null else null


## What a dial is called on the page: the words its slider shows before its
## number and, for a tool's option, the tool, since three brushes each have a
## Size. A slider with no words in front is called by its name.
static func dial_label(control: Control, value_name: StringName) -> String:
    if value_name == LAYER_OPACITY:
        return TranslationServer.translate("Layer opacity")
    var slider := control as FactorSlider
    var shown := slider.prefix.strip_edges().trim_suffix(":").strip_edges() if slider != null else ""
    var text := String(value_name)
    if shown.is_empty():
        return text
    if text.begins_with(TOOL_PREFIX):
        return "%s (%s)" % [shown, text.get_slice("/", 1)]
    var window := control.get_window()
    if window != null and window.get_parent() != null and not window.title.is_empty():
        return "%s (%s)" % [shown, window.title]
    return shown


## The main canvas's machine, which a dial on a tool's option or the layer's
## opacity is read off, or null in a host with no main scene.
static func main_tool_machine() -> ToolMachine:
    var main := _main()
    if main == null or not main.has_method("get_tool_machine"):
        return null
    return main.call("get_tool_machine") as ToolMachine


static func _main() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.current_scene if tree != null else null


static func _registries() -> SaRegistries:
    var main := _main()
    return main.get("registries") as SaRegistries if main != null and "registries" in main else null


## The value named *value_name* as it stands now, or null when it cannot be
## moved now. Asked afresh at every call, because a tool, a layer and a dialog
## can each be gone by the next message.
func _target(value_name: StringName) -> Target:
    var text := String(value_name)
    if text.is_empty():
        return null
    if value_name == LAYER_OPACITY:
        return _layer_opacity()
    if text.begins_with(TOOL_PREFIX):
        return _tool_option(text)
    var control := _live_control(value_name)
    if control is FactorSlider:
        return LiveSlider.new(control as FactorSlider)
    if control is Range:
        return LiveRange.new(control as Range)
    return null


func _machine() -> ToolMachine:
    return _tool_machine_provider.call() as ToolMachine if _tool_machine_provider.is_valid() else null


## `tool/<tool>/<key>`. The key is after the last stroke, so a tool id with a
## stroke of its own still reads whole.
func _tool_option(text: String) -> Target:
    var machine := _machine()
    var cut := text.rfind("/")
    if machine == null or cut <= TOOL_PREFIX.length():
        return null
    var tool_id := StringName(text.substr(TOOL_PREFIX.length(), cut - TOOL_PREFIX.length()))
    var key := StringName(text.substr(cut + 1))
    var tool := machine.get_tool(tool_id)
    var descriptor := machine.get_descriptor(tool_id)
    if tool == null or descriptor == null:
        return null
    for spec: SaOptionSpec in descriptor.options:
        if spec.key != key or not (spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT):
            continue
        return ToolOption.new(spec, tool) if ToolOptionControls.read_spec(spec, tool) != null else null
    return null


func _layer_opacity() -> Target:
    var machine := _machine()
    var document := machine.surface.get_document() if machine != null and machine.surface != null else null
    if document == null or document.active_layer == null:
        return null
    return LayerOpacity.new(document, document.active_layer)


## The slider on screen carrying *value_name*, or null when none is shown.
## Hidden counts as gone, because a dialog closed by Cancel keeps its page
## until the next filter opens and a painter cannot see what it would move.
func _live_control(value_name: StringName) -> Control:
    var held: Control = _live.get_ref() as Control if _live != null else null
    if _shows(held, value_name):
        return held
    _live = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return null
    for node: Node in tree.root.find_children("*", "Control", true, false):
        var control := node as Control
        if _shows(control, value_name):
            _live = weakref(control)
            return control
    return null


static func _shows(control: Control, value_name: StringName) -> bool:
    if control == null or not control.is_inside_tree() or control.is_queued_for_deletion():
        return false
    return control.is_visible_in_tree() and name_of(control) == value_name


## One value found by its name: the range a drag of its slider covers, whether
## that drag is geometric, and the read and the write each kind does its own way.
class Target:
    var bottom: float = 0.0
    var top: float = 1.0
    var geometric: bool = false

    func read() -> float:
        return NAN

    ## Sets the value, a value that is an undo step folding the rest of a turn
    ## into the step *merge* opens.
    func write(_value: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
        return false

    ## The value *ratio* of the way from `bottom` to `top`, the sum
    ## `FactorSlider.value_at_ratio` does for a drag.
    func at_ratio(ratio: float) -> float:
        if geometric and bottom > 0.0 and top > bottom:
            return bottom * pow(top / bottom, ratio)
        return lerpf(bottom, top, ratio)

    ## [method at_ratio] turned round, held to nought and one.
    func ratio_of(value: float) -> float:
        if geometric and bottom > 0.0 and top > bottom:
            return clampf(log(maxf(value, bottom) / bottom) / log(top / bottom), 0.0, 1.0)
        return clampf((value - bottom) / (top - bottom), 0.0, 1.0) if top > bottom else 0.0


## A tool's option, written to the tool as the bar writes it. Every surface
## showing it reads it again on `tool_options_moved`, as after the brackets.
class ToolOption:
    extends Target
    var _spec: SaOptionSpec
    var _tool: ToolState

    func _init(spec: SaOptionSpec, tool: ToolState) -> void:
        _spec = spec
        _tool = tool
        bottom = spec.min_value
        var soft := spec.soft_max > spec.min_value and spec.soft_max < spec.max_value
        top = spec.soft_max if soft else spec.max_value
        geometric = spec.logarithmic

    func read() -> float:
        return float(ToolOptionControls.read_spec(_spec, _tool))

    func write(value: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
        var held := clampf(value, _spec.min_value, _spec.max_value)
        var written: Variant = held
        if _spec.kind == SaOptionSpec.Kind.INT:
            written = int(roundf(held))
        if not ToolOptionControls.write_spec(_spec, written, _tool):
            return false
        EventBus.tool_options_moved.emit()
        return true


## The active layer's opacity, set as the row's slider sets it, so a turn is
## the one folded undo step a drag is.
class LayerOpacity:
    extends Target
    var _document: SaDocument
    var _layer: SaLayer

    func _init(document: SaDocument, layer: SaLayer) -> void:
        _document = document
        _layer = layer

    func read() -> float:
        return _layer.opacity

    func write(value: float, merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
        SaLayerOps.new(_document).set_opacity(_layer, value, merge)
        return true


## A `FactorSlider` on screen, moved as the control walker moves one: the
## slider's own rounding and range, then the signal a drag fires.
class LiveSlider:
    extends Target
    var _slider: FactorSlider

    func _init(slider: FactorSlider) -> void:
        _slider = slider
        bottom = slider.drag_min()
        top = slider.drag_max()
        geometric = slider.logarithmic

    func read() -> float:
        return _slider.value

    func write(value: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
        var held := clampf(_slider.quantized(value), _slider.min_value, _slider.max_value)
        if absf(held - _slider.value) > FactorSlider.COMMIT_TOLERANCE:
            _slider.set_value_no_signal(held)
            _slider.value_changed.emit(_slider.value)
        return true


## A Preferences row's `HSlider`, moved as `SaPageRow.drive` moves it, in the
## units it shows.
class LiveRange:
    extends Target
    var _range: Range

    func _init(shown: Range) -> void:
        _range = shown
        bottom = shown.min_value
        top = shown.max_value
        geometric = shown.exp_edit

    func read() -> float:
        return _range.value

    func write(value: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
        var before := _range.value
        _range.set_value_no_signal(value)
        if not is_equal_approx(before, _range.value):
            _range.value_changed.emit(_range.value)
        return true
