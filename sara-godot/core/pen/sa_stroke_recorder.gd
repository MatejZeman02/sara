## Writes every pointer reading of a painting session to a JSON lines file,
## the training data the learned cursor lead is fitted on.
##
## One line per event, as the window received it and in logical pixels:
## the time since the session started in microseconds, the position, the
## pressure, the tilt, whether the pen is inverted, the buttons held, the
## window's size and the canvas view's rectangle at that moment. A header
## line first says when and on what the session ran, the display driver, the
## screen, the refresh rate and the prediction setting, because a recording
## with the prediction on is a different data set from one without.
##
## A `z` line goes in before the first reading and again whenever the canvas
## moved under the pen: the six numbers of the transform that takes a document
## texel to a window pixel, as `Node2D.get_global_transform` lays them out. A
## reader inverts the last one before a reading to find the texel the pen
## touched, which is what a replay into a document needs and what the lead
## does not. It is written on change rather than per reading because a session
## moves the view a few hundred times and the pen a quarter of a million.
##
## Switched on by `--record-strokes=<folder>` on the command line or by
## `SARA_RECORD_STROKES=<folder>` in the environment, a file per session
## named by the clock, so a painter turns it on for one sitting and the
## build ships with nothing running. The file is flushed every `FLUSH_EVERY` lines so a session that dies keeps what it had.
##
## The recording is the painter's data and lives outside the repository, in a folder the training script reads.
##
## **The running recorder is reachable from outside the canvas**, as
## [member running], which this class writes when its file opens and clears
## when that file closes. The one recorder is the main canvas's own and
## private, and a part of Sara with a line of its own for the session log, the
## Stats docker's numbers at each idle stop, reaches it there
## rather than through `render`. Such a line is a kind of its own, written by
## [method note_numbers], and the training script passes over any kind but its
## readings.
##
## **The log's strokes are counted as they are written**, in [member tally],
## the session numbers the Stats docker shows: how many strokes, how many a
## minute and the mean pressure inside them. A count kept beside the file
## rather than a reading of it, because a stop would otherwise read a quarter of
## a million lines back each time, and kept from the lines themselves, so it
## holds what the file holds. A stroke is what the training script reads as one.
##
## **Every stroke has a tool and a layer.** A line of the
## kind [constant TOOL] goes in when the tool in hand changes and one of the
## kind [constant LAYER] when the active layer does or is renamed, each on
## change only, as the `z` line is, and one of each before the first reading.
## The recorder listens itself, to `EventBus.tool_changed` and to the main
## canvas's document, which it reads by name off the main scene as
## `SaIdleClock` does, so the canvas that makes it hands it nothing. A tool is
## named as the toolbox names it, the Brush for one of its engines, and a layer
## as the layers docker shows it, which is why a rename is a line: a layer is
## made active under the name Godot gave it and renamed a moment later. The
## tally then times each stroke from its press to its release and gives that
## time to the tool and the layer in hand at the press, so a pause counts for
## nothing.
class_name SaStrokeRecorder
extends RefCounted


## The strokes of a log and the pressure inside them, counted line by line by
## the rule `scripts/train_cursor_lead.py` reads a stroke by: the left button's
## press to its release, holding at least [constant LEAST_READINGS] motions. A
## second press before a release starts the stroke again, as it does there, and
## a stroke too short to count adds nothing, its readings and its time included.
##
## A stroke's painting time is its release's `t` less its press's, and it goes
## to the tool and the layer the log named last before the press, each by the
## `id` its line carries. A tool or a layer is listed under the name its last
## line gave it, so a renamed layer is one layer under its new name.
class Tally:
    extends RefCounted

    ## The button a stroke is drawn with, as the log writes it under `btn`.
    const LEFT := 1

    ## The fewest motions a stroke holds, the training script's `MIN_EVENTS`.
    const LEAST_READINGS := 10

    ## The strokes counted so far.
    var strokes: int = 0

    ## The motions inside those strokes, and their pressures added up.
    var readings: int = 0
    var pressure_sum: float = 0.0

    ## The painting time of those strokes in microseconds, in all, then by the
    ## `id` of the tool and of the layer each was painted with.
    var painting_usec: int = 0
    var tool_usec: Dictionary[String, int] = {}
    var layer_usec: Dictionary[int, int] = {}

    ## The name the last line about each tool and each layer gave it, by `id`.
    var tool_names: Dictionary[String, String] = {}
    var layer_names: Dictionary[int, String] = {}

    ## The tool and the layer the log named last, empty and 0 before it names one.
    var _tool: String = ""
    var _layer: int = 0

    ## Whether a press opened a stroke not released yet, and what its motions
    ## add, its press's time and what was in hand at it, held until the release
    ## says whether it counts.
    var _open: bool = false
    var _held_readings: int = 0
    var _held_pressure: float = 0.0
    var _held_since: int = 0
    var _held_tool: String = ""
    var _held_layer: int = 0

    ## Counts *line*, one line of the log as the recorder writes it, by its kind
    ## `k`. Any kind but a press, a release, a motion, a tool and a layer is
    ## passed over.
    func take(line: Dictionary) -> void:
        var kind: String = line.get("k", "")
        var button: int = line.get("btn", 0)
        var at: int = line.get("t", 0)
        if kind == TOOL:
            var tool: String = line.get("id", "")
            var tool_name: String = line.get("name", tool)
            _tool = tool
            tool_names[tool] = tool_name
        elif kind == LAYER:
            var layer: int = line.get("id", 0)
            var layer_name: String = line.get("name", "")
            _layer = layer
            layer_names[layer] = layer_name
        elif kind == "d" and button == LEFT:
            _open = true
            _held_readings = 0
            _held_pressure = 0.0
            _held_since = at
            _held_tool = _tool
            _held_layer = _layer
        elif kind == "u" and button == LEFT:
            if _open and _held_readings >= LEAST_READINGS:
                strokes += 1
                readings += _held_readings
                pressure_sum += _held_pressure
                var spent := maxi(at - _held_since, 0)
                painting_usec += spent
                tool_usec[_held_tool] = tool_usec.get(_held_tool, 0) + spent
                layer_usec[_held_layer] = layer_usec.get(_held_layer, 0) + spent
            _open = false
        elif kind == "m" and _open:
            var pressure: float = line.get("p", 0.0)
            _held_readings += 1
            _held_pressure += pressure

    ## The mean pressure of the motions inside the strokes counted, 0 before
    ## the first.
    func mean_pressure() -> float:
        return pressure_sum / float(readings) if readings > 0 else 0.0

    ## Where the painting time went by tool, the longest first, each a
    ## dictionary of its `name`, its `usec` and its `share` of the painting time.
    func by_tool() -> Array[Dictionary]:
        return _spent(tool_usec, tool_names)

    ## Where the painting time went by layer, as [method by_tool] has it.
    func by_layer() -> Array[Dictionary]:
        return _spent(layer_usec, layer_names)

    func _spent(usec: Dictionary, names: Dictionary) -> Array[Dictionary]:
        var out: Array[Dictionary] = []
        for id: Variant in usec:
            var time: int = usec[id]
            var named: String = names.get(id, "")
            var share := float(time) / float(painting_usec) if painting_usec > 0 else 0.0
            out.append({"name": named, "usec": time, "share": share})
        out.sort_custom(_longer)
        return out

    ## Whether *a* goes before *b*: the longer first, and by name at a tie.
    static func _longer(a: Dictionary, b: Dictionary) -> bool:
        var a_usec: int = a["usec"]
        var b_usec: int = b["usec"]
        var a_name: String = a["name"]
        var b_name: String = b["name"]
        return a_usec > b_usec or (a_usec == b_usec and a_name < b_name)


const FLAG := "--record-strokes"
const ENV_VAR := "SARA_RECORD_STROKES"
const FLUSH_EVERY := 256

## The kind of the line [method note_numbers] writes, the Stats docker's
## numbers at an idle stop.
const NUMBERS := "s"

## The kind of the line naming the tool in hand, by `id` and under `name`.
const TOOL := "tool"

## The kind of the line naming the active layer, by the number the log gives
## it under `id`, 1 for the first layer it names, and under `name`.
const LAYER := "layer"

## The recorder whose file is open, or null while nothing is recorded. Written
## by this class alone: set when a file opens and cleared when it closes.
static var running: SaStrokeRecorder = null

## Where the lines go. Empty when the file could not be opened.
var path: String = ""

## Lines written after the header, for the corner notice and the tests.
var lines: int = 0

## The strokes written so far and the pressure inside them.
var tally := Tally.new()

var _file: FileAccess
var _t0_usec: int = 0

## What the log's clock reads, in microseconds: `Time.get_ticks_usec` unless a
## suite handed a clock of its own to [method _init].
var _clock: Callable = Callable(Time, &"get_ticks_usec")
var _since_flush: int = 0
var _transform: Transform2D = Transform2D.IDENTITY
var _transform_written: bool = false

## The tool the log named last, by the id the toolbox knows it by, empty
## before the first.
var _tool_id: String = ""

## The document whose active layer the log follows, the layer it named last,
## its number and the name it was given then. Numbers by instance id, the next
## one being the count so far plus one.
var _document: SaDocument = null
var _layer: SaLayer = null
var _layer_number: int = 0
var _layer_name: String = ""
var _layer_numbers: Dictionary[int, int] = {}


## The folder named by the flag in *args* or, when the flag is absent, by
## *env*. Empty when neither names one. The flag takes `=folder` or the next
## argument, and the raw list and the user half of the command line are both
## searched by the caller, the way the settings folder is found.
static func folder_from(args: PackedStringArray, env: String) -> String:
    for i in args.size():
        var arg := args[i]
        if arg.begins_with(FLAG + "="):
            return arg.substr(FLAG.length() + 1)
        if arg == FLAG and i + 1 < args.size():
            return args[i + 1]
    return env


## The folder the running process asked for, or empty.
static func requested_folder() -> String:
    var folder := folder_from(OS.get_cmdline_args(), "")
    if folder.is_empty():
        folder = folder_from(OS.get_cmdline_user_args(), OS.get_environment(ENV_VAR))
    return folder


## Opens `<folder>/<date>-<time>.jsonl` and writes the header line, *session*
## being what the caller knows about the run: the display driver, the screen,
## the refresh rate and the prediction setting. *clock*, when valid, is what
## the log's clock reads in microseconds, for a suite that plays minutes of a
## session in a moment. The canvas hands none.
func _init(folder: String, session: Dictionary[String, Variant], clock: Callable = Callable()) -> void:
    if clock.is_valid():
        _clock = clock
    var absolute := ProjectSettings.globalize_path(folder)
    var made := DirAccess.make_dir_recursive_absolute(absolute)
    if made != OK:
        SaProblems.report("SaStrokeRecorder", TranslationServer.translate("Could not make the recording folder %s.") % absolute)
        return
    var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("T", "-")
    var candidate := absolute.path_join(stamp + ".jsonl")
    _file = FileAccess.open(candidate, FileAccess.WRITE)
    if _file == null:
        SaProblems.report(
            "SaStrokeRecorder", TranslationServer.translate("Could not open %s for the stroke recording.") % candidate
        )
        return
    path = candidate
    _t0_usec = _clock.call()
    var header := session.duplicate()
    header["started"] = Time.get_datetime_string_from_system(false, false)
    header["format"] = 2
    _file.store_line(JSON.stringify(header))
    running = self
    EventBus.tool_changed.connect(_on_tool_changed)
    _find_main()


## Whether a file is open and lines are being written.
func is_recording() -> bool:
    return _file != null


## Appends one line for a motion or a button event, *window_size* being the
## window's size and *view* the canvas view's rectangle, both in logical
## pixels, and *canvas_to_window* the transform from document texels to those
## pixels, written as a line of its own when it differs from the last one
## written. Any other event is ignored.
func record(event: InputEvent, window_size: Vector2, view: Rect2, canvas_to_window: Transform2D) -> void:
    if _file == null:
        return
    if _tool_id.is_empty() or _layer_number == 0:
        _find_main()
    if not _transform_written or canvas_to_window != _transform:
        _transform = canvas_to_window
        _transform_written = true
        _store(
            {
                "k": "z",
                "t": elapsed_usec(),
                "m":
                [
                    canvas_to_window.x.x,
                    canvas_to_window.x.y,
                    canvas_to_window.y.x,
                    canvas_to_window.y.y,
                    canvas_to_window.origin.x,
                    canvas_to_window.origin.y,
                ],
            }
        )
    var line: Dictionary[String, Variant] = {}
    var motion := event as InputEventMouseMotion
    var button := event as InputEventMouseButton
    if motion != null:
        line["k"] = "m"
        line["x"] = motion.position.x
        line["y"] = motion.position.y
        line["p"] = motion.pressure
        line["tx"] = motion.tilt.x
        line["ty"] = motion.tilt.y
        line["inv"] = motion.pen_inverted
        line["b"] = motion.button_mask
    elif button != null:
        line["k"] = "d" if button.pressed else "u"
        line["x"] = button.position.x
        line["y"] = button.position.y
        line["btn"] = button.button_index
    else:
        return
    line["t"] = elapsed_usec()
    line["w"] = [window_size.x, window_size.y]
    line["v"] = [view.position.x, view.position.y, view.size.x, view.size.y]
    _store(line)
    tally.take(line)


## The time on the log's clock, in microseconds since the session started, as
## every line carries it under `t`.
func elapsed_usec() -> int:
    var now: int = _clock.call()
    return now - _t0_usec


## The strokes of [member tally] a minute, over the session from its first line
## to now, pauses included. 0 before a moment has passed.
func strokes_a_minute() -> float:
    var minutes := float(elapsed_usec()) / 60e6
    return float(tally.strokes) / minutes if minutes > 0.0 else 0.0


## Appends one line of the kind [constant NUMBERS]: the time on the log's
## clock, as every reading carries it, *numbers* under `n`, each by its name,
## and under `l` the title each is shown under, by the same name. Flushed at
## once, because one comes a stop and a session that dies should keep the
## last. Nothing while no file is open.
func note_numbers(numbers: Dictionary, titles: Dictionary = {}) -> void:
    if _file == null:
        return
    _store({"k": NUMBERS, "t": elapsed_usec(), "n": numbers, "l": titles})
    _file.flush()
    _since_flush = 0


## Follows *document*'s active layer from now on and writes a line for the one
## active now. The recorder finds the main canvas's document itself, and a
## suite, which has no main scene, hands one here. Nothing for the document
## already followed, for null, or while no file is open.
func follow(document: SaDocument) -> void:
    if _file == null or document == null or document == _document:
        return
    _let_go()
    _document = document
    _document.active_layer_changed.connect(_on_layer_changed)
    _on_layer_changed(_document.active_layer)


## Reads the main canvas's tool machine and document by name off the main
## scene, since core never names the canvas classes, and writes what differs
## from what the log named last. Nothing in a suite, which has no main scene.
func _find_main() -> void:
    var main_node := _main_scene()
    if main_node == null:
        return
    var surface: Object = main_node.get(&"main_canvas")
    if surface == null or not ("tool_machine" in surface and "canvas" in surface):
        return
    var machine: Object = surface.get(&"tool_machine")
    if machine != null:
        var in_hand: Variant = machine.get(&"active_tool_name")
        var registry: SaToolRegistry = machine.get(&"registry")
        _hold_tool(StringName(str(in_hand)) if in_hand != null else &"", registry)
    var canvas: Object = surface.get(&"canvas")
    var document: SaDocument = canvas.get(&"document") if canvas != null else null
    follow(document)


## A tool machine switched tools. The main canvas's own machine is read rather
## than the one announced, because the scratchpad's machine announces on the
## same signal, and a suite with no main scene takes *tool_name* as it is.
func _on_tool_changed(tool_name: String) -> void:
    if _main_scene() != null:
        _find_main()
    else:
        _hold_tool(StringName(tool_name), null)


## Sara's main scene, the one with a main canvas, or null in a suite.
static func _main_scene() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    return main_node if main_node != null and "main_canvas" in main_node else null


## Writes a line naming the tool *tool_id* is known as, under the name the
## toolbox gives it, unless it is the one the log named last. *registry* is
## the main canvas's, and without one, in a suite, the id is the name.
func _hold_tool(tool_id: StringName, registry: SaToolRegistry) -> void:
    if _file == null or tool_id.is_empty():
        return
    var known := SaToolRegistry.tool_in(registry, tool_id)
    if String(known) == _tool_id:
        return
    _tool_id = String(known)
    var descriptor := registry.get_descriptor(known) if registry != null else null
    var shown := descriptor.display_name if descriptor != null and not descriptor.display_name.is_empty() else _tool_id
    _note({"k": TOOL, "t": elapsed_usec(), "id": _tool_id, "name": shown})


## The active layer changed: the log follows *layer*'s renames from now on and
## names it.
func _on_layer_changed(layer: SaLayer) -> void:
    if _layer != null and is_instance_valid(_layer) and _layer.renamed.is_connected(_name_layer):
        _layer.renamed.disconnect(_name_layer)
    _layer = layer
    if _layer != null:
        _layer.renamed.connect(_name_layer)
    _name_layer()


## Writes a line naming the active layer by its number and its name, unless the
## log named it so last. Nothing while there is no active layer, which only a
## document being reset has.
func _name_layer() -> void:
    if _file == null or _layer == null or not is_instance_valid(_layer):
        return
    var number: int = _layer_numbers.get_or_add(_layer.get_instance_id(), _layer_numbers.size() + 1)
    var shown := String(_layer.name)
    if number == _layer_number and shown == _layer_name:
        return
    _layer_number = number
    _layer_name = shown
    _note({"k": LAYER, "t": elapsed_usec(), "id": number, "name": shown})


## Stores *line* and counts it.
func _note(line: Dictionary[String, Variant]) -> void:
    _store(line)
    tally.take(line)


## Stops hearing the document and its active layer.
func _let_go() -> void:
    if _layer != null and is_instance_valid(_layer) and _layer.renamed.is_connected(_name_layer):
        _layer.renamed.disconnect(_name_layer)
    _layer = null
    if _document != null and is_instance_valid(_document) and _document.active_layer_changed.is_connected(_on_layer_changed):
        _document.active_layer_changed.disconnect(_on_layer_changed)
    _document = null


func _store(line: Dictionary[String, Variant]) -> void:
    _file.store_line(JSON.stringify(line))
    lines += 1
    _since_flush += 1
    if _since_flush >= FLUSH_EVERY:
        _file.flush()
        _since_flush = 0


## Flushes and closes the file, and stops hearing the tool and the layer. Safe
## to call twice.
func close() -> void:
    if _file == null:
        return
    _file.flush()
    _file.close()
    _file = null
    if running == self:
        running = null
    if EventBus.tool_changed.is_connected(_on_tool_changed):
        EventBus.tool_changed.disconnect(_on_tool_changed)
    _let_go()
