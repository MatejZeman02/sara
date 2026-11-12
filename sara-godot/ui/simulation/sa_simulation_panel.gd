## The simulation's controls in Tool Options: Play, Pause, Step, Reset, the
## speed in steps a second and the step count, and below them the domain the pattern grows
## inside, the canvas or the rectangle a selection lies in, set by the Canvas
## and Selection buttons. Under the title, a document opened without the
## module its rule needs says which module that is. They are shown through
## `ToolOptionsDocker.show_filter_panel` while the active layer carries a
## simulation, and taken away when it does not.
##
## This node is the follower, which Main adds once. Every frame it reads the
## active layer of the primary easel, shows the panel or takes it away, and
## runs [method SaSimulation.play_frame] for that layer. A simulation plays
## only while its layer is active, so choosing another layer pauses it. The
## panel never covers an attached filter's: one picked in the Layers docker
## stays until something clears it, and the simulation's comes back the frame
## after.
##
## A rule written as a pixel function has a slider per scalar `uniform` line
## under the speed, which writes the record's parameter of that name, so the
## next step reads it.
##
## The model, the play state, the speed, the count in steps and the pause at
## the press of a stroke, is in `core/layers/simulation`. Only the
## controls are here, because `core` never names a widget.
##
## The follower also registers File > Export Frames..., a row the File menu
## shows while the document holds a simulation, and owns the
## dialog it opens, `SaSimulationFramesDialog`, which writes the run as
## numbered pictures through [SaSimulation.Frames].
class_name SaSimulationPanel
extends Node

## The follower's name, which the state dump finds it by.
const NODE_NAME := "SimulationFollower"
## File > Export Frames..., which the File menu shows only while it is enabled.
const FRAMES_COMMAND := &"file_export_frames"


## The controls for one layer's simulation. Every button calls the facade or
## runs a command, so a click, a chord and the door take the same path.
class Controls:
    extends VBoxContainer

    ## A rule a module registered from a pixel function, preloaded by path as
    ## the file asks.
    const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

    ## The `uniform` types a slider stands for.
    const SLID_TYPES: Array[String] = ["float", "int", "uint"]

    ## The layer whose simulation the panel shows. Written by its constructor.
    var layer: SaLayer = null
    var _registries: SaRegistries = null
    var _title: Label = null
    var _needs: Label = null
    var _play: Button = null
    var _pause: Button = null
    var _speed: FactorSlider = null
    var _count: Label = null
    var _domain: Label = null
    var _selection: Button = null
    ## The slider of each of a pixel rule's uniforms, by the uniform's name.
    var _parameters: Dictionary[String, FactorSlider] = {}

    func _init(shown_layer: SaLayer, registries: SaRegistries) -> void:
        name = "SimulationPanel"
        layer = shown_layer
        _registries = registries
        size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _title = SaMake.label(self, "SimulationTitle")
        _title.text_overrun_behavior = SaTheme.TEXT_CUT
        # Shown only for a rule whose module is not loaded, a document opened
        # from a file that kept the record as data, and saying which module.
        _needs = SaMake.label(self, "SimulationNeeds")
        _needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var buttons := SaMake.row(self, "SimulationButtons")
        _play = SaMake.button(buttons, "SimulationPlay", tr("Play"), tr("Step the layer on its own at the speed below."))
        _pause = SaMake.button(buttons, "SimulationPause", tr("Pause"), tr("Stop at the current step."))
        var step := SaMake.button(buttons, "SimulationStep", tr("Step"), tr("Run the rule once."))
        var reset := SaMake.button(buttons, "SimulationReset", tr("Reset"), tr("Go back to what was last painted, at step 0."))
        for each: Button in [_play, _pause, step, reset]:
            each.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _play.pressed.connect(func() -> void: SaSimulation.play(layer))
        _pause.pressed.connect(func() -> void: SaSimulation.pause(layer))
        step.pressed.connect(func() -> void: _registries.commands.execute(SaSimulation.STEP_COMMAND))
        reset.pressed.connect(func() -> void: _registries.commands.execute(SaSimulation.RESET_COMMAND))
        var record := SaSimulation.record_of(layer)
        var speed: float = record.speed if record != null else SaSimulation.DEFAULT_SPEED
        _speed = SaMake.slider(self, "SimulationSpeed", SaSimulation.SLOWEST, SaSimulation.FASTEST, 1.0, speed)
        _speed.decimal_places = 0
        _speed.prefix = "%s: " % tr("Speed")
        _speed.suffix = " %s" % tr("steps/s")
        _speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _speed.value_changed.connect(_speed_moved)
        var found: SaSimulation.Rule = _registries.simulation_rules.find(record.rule) if record != null else null
        if found is PixelFunction.Rule:
            _sliders_for(found as PixelFunction.Rule, record.params)
        _count = SaMake.label(self, "SimulationCount")
        _domain = SaMake.label(self, "SimulationDomain")
        _domain.text_overrun_behavior = SaTheme.TEXT_CUT
        var domain_row := SaMake.row(self, "SimulationDomainButtons")
        var canvas := SaMake.button(
            domain_row, "SimulationGrowOnCanvas", tr("Canvas"), tr("Let the pattern grow anywhere on the canvas.")
        )
        _selection = SaMake.button(
            domain_row,
            "SimulationGrowInSelection",
            tr("Selection"),
            tr("Keep the pattern inside the rectangle around the selection.")
        )
        for each: Button in [canvas, _selection]:
            each.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        canvas.pressed.connect(func() -> void: SaSimulation.grow_inside_canvas(layer))
        _selection.pressed.connect(func() -> void: SaSimulation.grow_inside_selection(_document(), layer))
        refresh()

    ## The title, the count, which of Play and Pause can be pressed, the domain
    ## and whether a selection can set it, read from the record again.
    func refresh() -> void:
        var record := SaSimulation.record_of(layer)
        if record == null:
            return
        var found := _registries.simulation_rules.find(record.rule)
        var rule_label: String = tr(found.label) if found != null else String(record.rule)
        _title.text = tr("%s on %s") % [rule_label, layer.name]
        _needs.text = SaSimulation.missing(layer, _registries.simulation_rules)
        _needs.visible = not _needs.text.is_empty()
        var said: String = (
            tr_n("Step %d, playing", "Step %d, playing", record.steps)
            if record.playing
            else tr_n("Step %d, paused", "Step %d, paused", record.steps)
        )
        _count.text = said % record.steps
        _play.disabled = record.playing
        _pause.disabled = not record.playing
        if not is_equal_approx(_speed.value, record.speed):
            _speed.set_value_no_signal(record.speed)
        _domain.text = _domain_text(record.domain)
        _selection.disabled = not SaSimulation.selected_box(_document()).has_area()

    ## What the panel shows, for the state dump.
    func report() -> Dictionary:
        return {
            "title": _title.text,
            "needs": _needs.text,
            "count": _count.text,
            "play_enabled": not _play.disabled,
            "pause_enabled": not _pause.disabled,
            "speed": _speed.value,
            "parameters": _parameter_values(),
            "buttons": _buttons(),
            "domain": _domain.text,
            "selection_enabled": not _selection.disabled,
        }

    ## The text of each button in the row, in order.
    func _buttons() -> Array[String]:
        var out: Array[String] = []
        for each in find_child("SimulationButtons", false, false).get_children():
            out.append((each as Button).text)
        return out

    ## The domain as the row says it: the canvas, or the rectangle's size and
    ## where it starts, in document pixels.
    func _domain_text(domain: Rect2i) -> String:
        if not domain.has_area():
            return tr("Area: the whole canvas")
        return tr("Area: %s × %s px at %s, %s") % [domain.size.x, domain.size.y, domain.position.x, domain.position.y]

    ## The document of the primary easel, the one the selection is read from.
    func _document() -> SaDocument:
        var easel: SaEasel = _registries.context.get_easel()
        return easel.document if easel != null else null

    ## A slider per scalar uniform of *found*, opening at its value in the
    ## record's *params*, over the range its line declared widened to that
    ## value. A uniform of another type keeps the value its line declared, with
    ## no widget.
    func _sliders_for(found: PixelFunction.Rule, params: Dictionary) -> void:
        for raw: Variant in found.uniforms:
            var field := SaTyped.strings(raw)
            var type_name := SaTyped.text_at(field, "type", "")
            if not type_name in SLID_TYPES or SaTyped.int_at(field, "length", 0) != 0:
                continue
            var key := SaTyped.text_at(field, "name", "")
            var declared := SaTyped.float_at(field, "default", 0.0)
            var value := SaTyped.real(params.get(key, declared), declared)
            var whole := type_name != "float"
            var stride := SaTyped.float_at(field, "step", 0.0)
            stride = maxf(roundf(stride), 1.0) if whole else (stride if stride > 0.0 else 0.01)
            var low := minf(SaTyped.float_at(field, "minimum", 0.0), value)
            var high := maxf(SaTyped.float_at(field, "maximum", 1.0), value)
            var made := SaMake.slider(self, "SimulationParameter_%s" % key, low, high, stride, value)
            made.decimal_places = 0 if whole else 2
            made.prefix = "%s: " % SaPixelFilter.title_for(key)
            made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            made.value_changed.connect(_parameter_moved.bind(key, whole))
            _parameters[key] = made

    ## Each slider's value by the uniform's name, for the state dump.
    func _parameter_values() -> Dictionary[String, float]:
        var out: Dictionary[String, float] = {}
        for key: String in _parameters:
            out[key] = _parameters[key].value
        return out

    func _parameter_moved(moved: float, key: String, whole: bool) -> void:
        var record := SaSimulation.record_of(layer)
        if record == null:
            return
        if whole:
            record.params[key] = roundi(moved)
        else:
            record.params[key] = moved

    func _speed_moved(moved: float) -> void:
        var record := SaSimulation.record_of(layer)
        if record != null:
            record.speed = clampf(moved, SaSimulation.SLOWEST, SaSimulation.FASTEST)


var _registries: SaRegistries = null
var _docker: ToolOptionsDocker = null
## The instance ids of the active layer, when it carries a simulation, and of
## its record, so a record put on in its place is told apart, and neither is
## held alive or read once freed.
var _layer_id: int = 0
var _record_id: int = 0
var _panel: Controls = null
## The Export Frames dialog, built at its first opening.
var _frames: SaSimulationFramesDialog = null


func _init(registries: SaRegistries, docker: ToolOptionsDocker) -> void:
    name = NODE_NAME
    _registries = registries
    _docker = docker
    _register_frames_command()


func _process(delta: float) -> void:
    var easel := _easel()
    var document: SaDocument = easel.document if easel != null else null
    var held: SaLayer = document.active_layer if document != null else null
    var record := SaSimulation.record_of(held)
    if record == null:
        held = null
    var layer_id: int = held.get_instance_id() if held != null else 0
    var record_id: int = record.get_instance_id() if record != null else 0
    if layer_id != _layer_id or record_id != _record_id:
        _let_go()
        _layer_id = layer_id
        _record_id = record_id
    if held == null:
        return
    var shown := _shown()
    if shown == null and _docker._filter_panel == null:
        _panel = Controls.new(held, _registries)
        _docker.show_filter_panel(_panel)
        shown = _panel
    SaSimulation.play_frame(document, held, _registries.simulation_rules, SaSimulation.window_of(easel), delta)
    if shown != null:
        shown.refresh()


## The record of the active layer and what the panel shows, for the state
## dump: empty when no layer with a simulation is active. `frames` is the
## Export Frames dialog's own report once it has been opened, whichever layer
## is active.
func report() -> Dictionary:
    var easel := _easel()
    var layer: SaLayer = easel.document.active_layer if easel != null and easel.document != null else null
    var out := SaSimulation.describe(layer)
    if not out.is_empty():
        var shown := _shown()
        out["panel"] = shown.report() if shown != null else {}
    if _frames != null:
        out["frames"] = _frames.report()
    return out


## File > Export Frames... as a command, so the File menu draws its row from
## the registry as it draws Export's, and the door runs it by name. Enabled
## while the primary easel's document holds a simulation, which is when the
## File menu shows the row at all.
func _register_frames_command() -> void:
    var commands := _registries.commands if _registries != null else null
    if commands == null or commands.has(FRAMES_COMMAND):
        return
    var command := SaCommandDescriptor.create(FRAMES_COMMAND, "Export frames of a simulation", open_frames)
    command.label = "Export Frames..."
    command.category = &"file"
    command.sentence = (
        "The simulation run as numbered pictures, one every so many steps, each named by the step it shows so the "
        + "files sort. Shown while a layer carries a simulation."
    )
    command.enabled = has_frames
    commands.register(command, &"sara-skeleton")


## Whether the primary easel's document holds a simulation to export.
func has_frames() -> bool:
    var easel := _easel()
    return easel != null and SaSimulation.simulated_layer(easel.document) != null


## Opens the Export Frames dialog on the primary easel, building it the first
## time. False, and nothing opened, while no layer carries a simulation.
func open_frames() -> bool:
    if not has_frames() or not is_inside_tree():
        return false
    if _frames == null:
        _frames = SaSimulationFramesDialog.new(_registries)
        add_child(_frames)
    _frames.open_for(_easel())
    return true


## The primary easel, the one the panel follows.
func _easel() -> SaEasel:
    return _registries.context.get_easel()


## The state dump's line: the follower's [method report], found by name and
## called untyped, so this static func never casts to its own class.
static func capture_state(root: Window) -> Dictionary:
    var follower := root.find_child(NODE_NAME, true, false)
    if follower == null or not follower.has_method("report"):
        return {}
    return follower.call("report")


## The panel, when it is the one Tool Options shows now.
func _shown() -> Controls:
    if _panel != null and is_instance_valid(_panel) and _docker._filter_panel == _panel:
        return _panel
    return null


## Pauses the layer the follower held, if its record is still the one it
## played, and takes its panel away. Play runs only while the layer is active.
func _let_go() -> void:
    var layer := instance_from_id(_layer_id) as SaLayer
    var record := SaSimulation.record_of(layer)
    if record != null and record.get_instance_id() == _record_id:
        SaSimulation.pause(layer)
    if _shown() != null:
        _docker.clear_filter_panel()
    _panel = null
