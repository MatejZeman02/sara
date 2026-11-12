## What a hand used in one session: every shortcut, button, menu row, docker,
## tool switch and stroke, every colour set, Tool Options value, preset pick and
## layer pick, and how far the pointer travelled, counted into one JSON file
## under the data root's `usage` folder and answered to the door's `usage` step.
##
## **Off unless asked.** `--usage-tally` after `--` on the command line, or a
## `usage` step, switches it on, so a painter's ordinary run writes nothing.
## It never leaves the machine: the file is the whole of what it keeps, one per
## session, named by the time the tally started and written at every tenth
## count and when the app quits.
##
## **The hooks are static and cost one test while it is off.** The router, the
## menus, the dockers and the tool machine call them whether it is on or not,
## and each returns at `current == null`. Buttons and windows need no hook of
## their own: the tally follows every node the tree adds, the way the shortcut
## router follows every window, and counts a button's `pressed` whichever
## button it is.
##
## **A motion costs two sums.** The pointer's travel is read off each window's
## input signal, which an event reaches before the GUI does, and a mouse event
## adds the distance from the last one to one of two floats, the one for while
## a stroke is down or the one for while it is not. No dictionary is touched and
## nothing is allocated there, so the counting never shows in the FPS row. The
## distance is in logical units, the window's own pixels divided by its final
## scale, and a jump from one window to another is not travel the tally can
## measure, so it counts none.
##
## **How a tool switch was made** is read off what the hand did in the same
## event. A shortcut, a menu row and a button each name themselves as the
## source, and a switch takes the source named in its own event, whichever of
## the two came first: the toolbox switches the tool in its own `pressed`
## handler, which may run before or after the tally's. A button names the
## docker or dialog it sits in, so the toolbox's switches read the toolbox
## docker's registered id, since `core` names no class of the interface. A
## switch nothing claims by the next event, a pen button's or a scenario's, is
## `other`.
##
## **A tool held on a key or a pen button is a detour, not a switch.** The tool
## machine says which tool a hold puts in the hand before it swaps, through
## [method hold], so Alt held for the eyedropper and let go counts no switch
## either way, and neither does an Alt+Backspace fill. Counted as switches,
## every Alt would count twice, once into the held tool and once back. A hold
## during which its tool
## acted, a colour picked under Alt, counts one use of that tool with [constant
## HELD] as its source, however often it acted.
##
## **The four kinds a hand makes inside a docker are counted where the hand made
## them**: a colour set by how, a Tool Options value by option and by the bar or
## the docker, a preset pick by its picker, and a layer pick by its row or a
## chord. Each hook sits in the control's own handler of a press, the end of a
## drag or an Enter, never in the setter behind it, so an undo, a scenario's
## setter and a value a script writes count nothing. A step that fires a
## control's own signal to stand in for a hand, as the harness's control walker
## does, counts as the hand it stands in for. A Tool Options slider writes its value at
## every motion of a drag, so a value counts once for each press, and a press is
## a button's, a finger's or a key's that is not a modifier, because Shift
## pressed during a drag makes the drag fine rather than starting another.
class_name SaUsageTally
extends Node

## The command line flag that switches the tally on at boot.
const FLAG := "--usage-tally"
## The folder under the data root the session files go in.
const FOLDER := "usage"
## A count every this many, the file is written again.
const FLUSH_EVERY: int = 10
## The longest a button's words are kept, so a button that shows a long value
## does not become a long key.
const WORDS_KEPT: int = 40

## How a docker was shown or hidden: a menu row, a chord or its own close box
## toggle it, and a summon chord borrows it under the pointer or sends it back.
const SHOWN := &"shown"
const HIDDEN := &"hidden"
const SUMMONED := &"summoned"

## Where a tool switch came from, beside the name of the docker, bar or dialog
## whose button made it.
const SHORTCUT := &"shortcut"
const MENU := &"menu"
const OTHER := &"other"
## How a tool that no switch put in the hand was used: held on a key or a pen
## button, and acting while it was held.
const HELD := &"held"

## How a colour was set: on the picker's area, on its ring or the hue bar that
## does the ring's job, from a kept swatch or a recent chip, typed as hex, or on
## a row of numbers or the disc's lightness slider.
const SQUARE := &"square"
const RING := &"ring"
const SWATCH := &"swatch"
const HEX := &"hex"
const SLIDER := &"slider"

## Where a Tool Options value was set: on the bar, in the docker, or on a page of
## the brush editor, which builds its rows from the same specs.
const BAR := &"bar"
const DOCKER := &"docker"
const BRUSH_EDITOR := &"brush_editor"

## The picker a preset was picked in, the brush editor's fold being the fourth.
const BRUSH_PRESETS := &"brush_presets"
const RECENT_PRESETS := &"recent_presets"
const PALETTE := &"palette"

## How a layer was picked: a press on its row, or a chord, which is a shortcut
## that ran one of the two commands making the next row the active layer.
const ROW := &"row"
const CHORD := &"chord"
const LAYER_CHORDS: Array[StringName] = [&"layer_select_above", &"layer_select_below"]

## Every kind the `usage` step answers a line for, in the order it answers them.
const KINDS: Array[String] = [
    "shortcuts", "buttons", "menus", "dockers", "tools", "strokes", "colors", "options", "presets", "layers", "travel"
]

## The running tally, or null while it is off. One for every document, because
## it counts what the painter's hands did in this session of Sara, whichever
## document they did it in.
static var current: SaUsageTally = null

## The file this session writes, and when the tally started.
var path: String = ""
var started: String = ""
## Every count since the start or the last reset, the travel aside.
var events: int = 0

## The tool registry a switch's or a stroke's tool is read against, so the Brush's
## engines count as the Brush. Null reads the main scene's, and a suite with no
## main scene hands its own.
var tools: SaToolRegistry = null

var _tree: SceneTree = null
var _since_flush: int = 0

## command id -> { chord -> count }
var _shortcuts: Dictionary = {}
## holder path -> { button -> count }
var _buttons: Dictionary = {}
## menu -> { row -> count }
var _menus: Dictionary = {}
## docker id -> { shown, hidden or summoned -> count }
var _dockers: Dictionary = {}
## tool -> { source -> count }
var _tools: Dictionary = {}
## tool -> strokes
var _strokes: Dictionary = {}
## square, ring, swatch, hex or slider -> count
var _colors: Dictionary = {}
## option -> { bar, docker or brush_editor -> count }
var _options: Dictionary = {}
## picker -> count
var _presets: Dictionary = {}
## row or chord -> count
var _layers: Dictionary = {}

var _travel_painting: float = 0.0
var _travel_idle: float = 0.0
var _stroking: bool = false
var _last_window: int = 0
var _last_point: Vector2 = Vector2.ZERO

## One more for every event a watched window hears, which is what ties a tool
## switch to the press or the key that made it.
var _serial: int = 0
var _source: StringName = &""
var _source_serial: int = -1
var _source_frame: int = -1
var _pending_tool: String = ""
## The tool the last switch landed on, as a painter knows it.
var _last_tool: String = ""
var _pending_serial: int = -1
var _pending_frame: int = -1

## The tool a held key or pen button has in the hand, as a painter knows it,
## empty while nothing is held, and whether it acted during this hold.
var _holding: String = ""
var _hold_used: bool = false

## One more for every press a watched window hears, and the option, the surface
## and the press the last Tool Options value was counted for, so the motions of
## one drag count once.
var _presses: int = 0
var _option_counted: StringName = &""
var _option_surface: StringName = &""
var _option_press: int = -1


## A tally for *tree*, writing into *folder*. Use [method start], which keeps
## one per process.
func _init(tree: SceneTree, folder: String) -> void:
    _tree = tree
    name = "SaUsageTally"
    started = Time.get_datetime_string_from_system(false, true)
    path = _free_path(folder, started.replace(":", "-").replace(" ", "T"))
    _tree.node_added.connect(_on_node_added)
    _watch_window(_tree.root)
    for node: Node in _tree.root.find_children("*", "Window", true, false):
        _watch_window(node as Window)
    for node: Node in _tree.root.find_children("*", "BaseButton", true, false):
        _watch_button(node as BaseButton)
    EventBus.tool_changed.connect(_on_tool_changed)


# --- Switching it on and off ---------------------------------------------------


## Switches the tally on for *tree*, or answers the one already running. Null
## without a tree. *folder* is where the file goes, the data root's `usage`
## folder unless a suite names one of its own.
static func start(tree: SceneTree, folder: String = "") -> SaUsageTally:
    if current != null:
        return current
    if tree == null or tree.root == null:
        return null
    current = SaUsageTally.new(tree, folder if not folder.is_empty() else SaDataRoot.path(FOLDER))
    # Deferred, because the root refuses a child while it is readying one, and
    # in the tree only so the quit's exit reaches it and writes the file.
    current._join.call_deferred()
    return current


## Switches the tally on when *args*, the user half of the command line, hold
## the flag. Nothing happens, and nothing is written, otherwise.
static func start_if_asked(tree: SceneTree, args: PackedStringArray) -> void:
    if args.has(FLAG):
        start(tree)


## Writes the file one last time and switches the tally off. Freeing it takes
## every connection it made with it.
static func stop() -> void:
    if current == null:
        return
    var tally := current
    current = null
    tally._settle()
    tally._write()
    if tally.is_inside_tree():
        tally.queue_free()
    else:
        tally.free()


func _join() -> void:
    if not is_inside_tree() and _tree != null and _tree.root != null:
        _tree.root.add_child(self)


func _exit_tree() -> void:
    _settle()
    _write()


# --- The hooks -----------------------------------------------------------------


## A shortcut ran *command_id*, and *event* is the chord that ran it. One of
## [constant LAYER_CHORDS] is a layer picked by a chord as well.
static func shortcut(command_id: StringName, event: InputEvent) -> void:
    if current == null:
        return
    current._bump(current._shortcuts, String(command_id), chord_of(event))
    current._note(SHORTCUT)
    if command_id in LAYER_CHORDS:
        current._bump_one(current._layers, String(CHORD))


## A key reached the tool machine, where a tool's own key, Enter committing a
## transform, can hand the tool back and so switch it from the keyboard although
## no command ran. A held tool's swap counts no switch whatever the key, which
## [method hold] sees to.
static func note_key() -> void:
    if current != null:
        current._note(SHORTCUT)


## A held key or pen button has *tool_name* in the hand in place of the
## permanent tool *permanent*, or holds nothing when *tool_name* is empty. The
## tool machine says so whenever it weighs which tool to hold, before any swap,
## so the swap a hold makes is read as a detour and counts no switch, in or back.
static func hold(tool_name: StringName, permanent: StringName) -> void:
    if current != null:
        current._hold(String(tool_name), String(permanent))


## The hand set a colour, *how* one of [constant SQUARE], [constant RING],
## [constant SWATCH], [constant HEX] and [constant SLIDER].
static func color_set(how: StringName) -> void:
    if current != null:
        current._bump_one(current._colors, String(how))


## The hand set the Tool Options value *option* on *surface*, one of [constant
## BAR], [constant DOCKER] and [constant BRUSH_EDITOR]. Called at every write a
## control makes, the motions of a drag included, and counted once a press.
static func option_set(option: StringName, surface: StringName) -> void:
    if current != null:
        current._option_set(option, surface)


## The hand picked a preset in *picker*, one of [constant BRUSH_PRESETS],
## [constant RECENT_PRESETS], [constant PALETTE] and [constant BRUSH_EDITOR].
static func preset_picked(picker: StringName) -> void:
    if current != null:
        current._bump_one(current._presets, String(picker))


## The hand picked a layer, *how* being [constant ROW] for a press on its row. A
## chord's pick is counted by [method shortcut], which knows which command ran.
static func layer_picked(how: StringName) -> void:
    if current != null:
        current._bump_one(current._layers, String(how))


## A row of the menu *menu* was chosen, *row* being its command or its words.
static func menu_row(menu: String, row: String) -> void:
    if current == null:
        return
    current._bump(current._menus, menu, row)
    current._note(MENU)


## The docker *docker_id* was shown, hidden or summoned, *how* one of [constant
## SHOWN], [constant HIDDEN] and [constant SUMMONED].
static func docker(docker_id: String, how: StringName) -> void:
    if current == null:
        return
    current._bump(current._dockers, docker_id, String(how))


## An event reached the active tool *tool_name*. A left press, or a first
## finger, begins a stroke of that tool and a release ends it. Called for every
## event the tool sees, motions included, so it allocates nothing.
static func tool_input(event: InputEvent, tool_name: StringName) -> void:
    if current == null:
        return
    var button := event as InputEventMouseButton
    var touch := event as InputEventScreenTouch
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        current._pressed(button.pressed, tool_name)
    elif touch != null and touch.index == 0:
        current._pressed(touch.pressed, tool_name)


# --- What the door and the file read -------------------------------------------


## Everything counted so far, as the file holds it and the door answers it.
func report() -> Dictionary:
    _settle()
    return {
        "started": started,
        "file": ProjectSettings.globalize_path(path),
        "events": events,
        "shortcuts": _shortcuts.duplicate(true),
        "buttons": _buttons.duplicate(true),
        "menus": _menus.duplicate(true),
        "dockers": _dockers.duplicate(true),
        "tools": _tools.duplicate(true),
        "strokes": _strokes.duplicate(true),
        "colors": _colors.duplicate(true),
        "options": _options.duplicate(true),
        "presets": _presets.duplicate(true),
        "layers": _layers.duplicate(true),
        "travel": {"painting": snappedf(_travel_painting, 0.1), "not_painting": snappedf(_travel_idle, 0.1)},
    }


## Zeroes every count and the travel and writes the empty file, so the door and
## the file agree from here on. The file and its name stay the session's.
func reset() -> void:
    _shortcuts.clear()
    _buttons.clear()
    _menus.clear()
    _dockers.clear()
    _tools.clear()
    _strokes.clear()
    _colors.clear()
    _options.clear()
    _presets.clear()
    _layers.clear()
    _hold_used = false
    _option_press = -1
    _travel_painting = 0.0
    _travel_idle = 0.0
    events = 0
    _since_flush = 0
    _pending_tool = ""
    _write()


## Answers what a hand has used: since the tally was switched on, one verdict line
## for each of the ten kinds and the travel, each its counts as JSON, under a line
## naming the file they are kept in, `{"usage": ""}`. `{"usage": "reset"}` zeroes
## the counts first. Either switches the tally on when it is off, which is the
## other way in beside `--usage-tally`, and the door's answer carries the same
## counts whole under `usage`.
##
## The ten are `shortcuts`, `buttons`, `menus`, `dockers`, `tools` and `strokes`,
## then `colors`, a colour set by `square`, `ring`, `swatch`, `hex` or `slider`,
## `options`, a Tool Options value set by option on the `bar`, in the `docker` or
## in the `brush_editor`, `presets`, a preset pick by the picker it was made in,
## and `layers`, a layer pick by a press on its `row` or a `chord`. A tool held
## on a key or a pen button counts no switch, and a hold in which it acted counts
## one use of it under `tools` with `held` as its source.
static func capture(tree: SceneTree, what: String) -> String:
    var tally := start(tree)
    if tally == null:
        return "SaCapture: usage, no tree to count in"
    if what == "reset":
        tally.reset()
    elif not what.is_empty():
        return 'SaCapture: usage takes "" or "reset", not \'%s\'' % what
    var counts := tally.report()
    var head := "SaCapture: usage, %d counted since %s, kept in %s" % [counts["events"], counts["started"], counts["file"]]
    var lines := PackedStringArray([head])
    for kind: String in KINDS:
        lines.append("SaCapture: usage %s %s" % [kind, JSON.stringify(counts[kind])])
    return "\n".join(lines)


## The chord *event* is, as a painter reads it: `Ctrl+S`, `F1`, `]`.
static func chord_of(event: InputEvent) -> String:
    var key := event as InputEventKey
    if key != null:
        return SaCommandRegistry.key_text(key)
    return event.as_text() if event != null else ""


## The docker, bar or dialog *button* sits in: the nearest window above it
## other than the main one, a list included, and failing that the piece of the
## main scene that holds it, the title bar or a canvas overlay.
static func holder_of(button: Node) -> Node:
    var tree := button.get_tree()
    if tree == null:
        return null
    var scene := tree.current_scene
    var walk := button.get_parent()
    while walk != null and walk != tree.root:
        if walk is Window:
            return walk
        if walk.get_parent() == scene or walk.get_parent() == tree.root:
            return walk
        walk = walk.get_parent()
    return tree.root


## The name a switch *button* made is put down to: the nearest window above it
## that is not a list, which is the docker a flyout hangs off, and failing that
## the holder's.
static func maker_of(button: Node) -> String:
    var tree := button.get_tree()
    var walk := button.get_parent()
    while walk != null and tree != null and walk != tree.root:
        if walk is Window and not (walk is Popup):
            return String(walk.name)
        walk = walk.get_parent()
    var holder := holder_of(button)
    return String(holder.name) if holder != null else String(OTHER)


## What the tally calls *button*: its node name, and its words beside it when it
## shows any. An engine-made name, `@Button@123`, says nothing and is its class.
static func button_label(button: BaseButton) -> String:
    var own := String(button.name)
    if own.begins_with("@"):
        own = button.get_class()
    var words := (button as Button).text.strip_edges() if button is Button else ""
    if words.is_empty() or words == own:
        return own
    if words.length() > WORDS_KEPT:
        words = words.left(WORDS_KEPT)
    return '%s "%s"' % [own, words]


# --- Inside --------------------------------------------------------------------


func _on_node_added(node: Node) -> void:
    if node is BaseButton:
        _watch_button(node as BaseButton)
    elif node is Window:
        _watch_window(node as Window)


## The unbound method is asked, because a connection is compared without its
## bound arguments: a button that leaves the tree and comes back is connected
## once.
func _watch_button(button: BaseButton) -> void:
    if button != null and not button.pressed.is_connected(_on_button_pressed):
        button.pressed.connect(_on_button_pressed.bind(button))


func _watch_window(window: Window) -> void:
    if window != null and not window.window_input.is_connected(_on_window_input):
        window.window_input.connect(_on_window_input.bind(window))


func _on_button_pressed(button: BaseButton) -> void:
    if not is_instance_valid(button) or not button.is_inside_tree():
        return
    var holder := holder_of(button)
    var where := String(_tree.root.get_path_to(holder)) if holder != null else ""
    _bump(_buttons, where, button_label(button))
    _note(StringName(maker_of(button)))


## Every event every watched window hears, before its GUI does. An embedded
## window hears what its embedder has already heard, so only a window of its own
## is read.
func _on_window_input(event: InputEvent, window: Window) -> void:
    if window.is_embedded():
        return
    _serial += 1
    if event.is_pressed() and not event.is_echo() and not _is_modifier(event):
        _presses += 1
    if not _pending_tool.is_empty() and _pending_serial != _serial:
        _settle()
    var mouse := event as InputEventMouse
    if mouse == null:
        return
    var at := mouse.position
    var id := window.get_instance_id()
    if id == _last_window:
        var scale := window.get_final_transform().get_scale().x
        var step := at.distance_to(_last_point) / (scale if scale > 0.0 else 1.0)
        if _stroking:
            _travel_painting += step
        else:
            _travel_idle += step
    _last_window = id
    _last_point = at
    # A release the tool never saw, off the canvas or out of the window, still
    # ends the stroke, after its own last stretch was counted as painting.
    var button := event as InputEventMouseButton
    if _stroking and button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
        _stroking = false


## Whether *event* is a modifier key, which changes what the next press means
## rather than being one.
static func _is_modifier(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null:
        return false
    var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
    return code == KEY_SHIFT or code == KEY_CTRL or code == KEY_ALT or code == KEY_META


## A press begins a stroke, and the first a held tool makes is the one use its
## hold counts, however often the tool acts before it is let go.
func _pressed(down: bool, tool_name: StringName) -> void:
    if down and not _stroking:
        _stroking = true
        var key := _known_as(String(tool_name))
        _bump_one(_strokes, key)
        if key == _holding and not _hold_used:
            _hold_used = true
            _switched(key, HELD)
    elif not down:
        _stroking = false


## A switch between the Brush's engines is a preset chosen rather than a tool,
## so it lands on the tool the last switch did and counts as none, and so does
## the swap into a held tool, which [method _hold] heard first, and the swap that
## hands the permanent tool back.
func _on_tool_changed(tool_name: String) -> void:
    var known := _known_as(tool_name)
    if known == _last_tool or known == _holding:
        return
    _last_tool = known
    _settle()
    if not _source.is_empty() and _is_now(_source_serial, _source_frame):
        _switched(known, _source)
        return
    _pending_tool = known
    _pending_serial = _serial
    _pending_frame = Engine.get_process_frames()


## A hold of *tool_name* began, in place of *permanent*, or the hold ended when
## *tool_name* is empty.
##
## A tally switched on in the middle of a session has heard no switch yet, so a
## hold takes the permanent tool as the last one, or the swap back would count
## as a switch to it. A held tool the painter made the permanent one while
## holding it, I pressed under Alt, stays in the hand with no swap to announce
## it, so the end of that hold is the switch.
func _hold(tool_name: String, permanent: String) -> void:
    var known := _known_as(tool_name) if not tool_name.is_empty() else ""
    if known == _holding:
        return
    var ended := _holding
    _holding = known
    _hold_used = false
    var kept := _known_as(permanent) if not permanent.is_empty() else ""
    if _last_tool.is_empty():
        _last_tool = kept
    if known.is_empty() and not ended.is_empty() and ended == kept:
        _on_tool_changed(permanent)


## *option* on *surface* is counted unless the press that counted it last is
## still the one writing it.
func _option_set(option: StringName, surface: StringName) -> void:
    if _option_press == _presses and option == _option_counted and surface == _option_surface:
        return
    _option_press = _presses
    _option_counted = option
    _option_surface = surface
    _bump(_options, String(option), String(surface))


## *source* is what the hand did in this event, and a switch the event already
## made without one is put down to it.
func _note(source: StringName) -> void:
    _source = source
    _source_serial = _serial
    _source_frame = Engine.get_process_frames()
    if not _pending_tool.is_empty() and _is_now(_pending_serial, _pending_frame):
        var tool_name := _pending_tool
        _pending_tool = ""
        _switched(tool_name, source)


## A switch nobody claimed in its own event was made some other way.
func _settle() -> void:
    if _pending_tool.is_empty():
        return
    var tool_name := _pending_tool
    _pending_tool = ""
    _switched(tool_name, OTHER)


## *tool_name* as a painter knows it, the Brush for one of its engines, so the
## counts put either engine's switches and strokes under the Brush. Read off
## [member tools], or the main scene's tool registry, the way a generated layer
## finds its layer types, because `core` holds no machine. With neither, the
## name it was handed.
func _known_as(tool_name: String) -> String:
    var registry := tools
    if registry == null:
        var main: Node = _tree.current_scene if _tree != null else null
        var held: Variant = main.get("registries") if main != null and "registries" in main else null
        var registries: SaRegistries = held if held is SaRegistries else null
        registry = registries.tools if registries != null else null
    return String(registry.tool_of(StringName(tool_name))) if registry != null else tool_name


func _is_now(serial: int, frame: int) -> bool:
    return serial == _serial and frame == Engine.get_process_frames()


func _switched(tool_name: String, source: StringName) -> void:
    _bump(_tools, tool_name, String(source))


func _bump(table: Dictionary, outer: String, inner: String) -> void:
    var counts: Dictionary = table.get(outer, {})
    var count: int = counts.get(inner, 0)
    counts[inner] = count + 1
    table[outer] = counts
    _counted()


func _bump_one(table: Dictionary, key: String) -> void:
    var count: int = table.get(key, 0)
    table[key] = count + 1
    _counted()


func _counted() -> void:
    events += 1
    _since_flush += 1
    if _since_flush >= FLUSH_EVERY:
        _write()


func _write() -> void:
    _since_flush = 0
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_warning("SaUsageTally: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
        return
    file.store_string(JSON.stringify(_report_unsettled(), "\t"))
    file.close()


## The report without settling a switch still waiting for its source, which a
## write in the middle of that event must not decide.
func _report_unsettled() -> Dictionary:
    var pending := _pending_tool
    _pending_tool = ""
    var out := report()
    _pending_tool = pending
    return out


## *stem*.json in *folder*, or the first of *stem*-2.json and on that no earlier
## session took, so two sessions started in one second keep a file each.
static func _free_path(folder: String, stem: String) -> String:
    var candidate := folder.path_join(stem + ".json")
    var n := 2
    while FileAccess.file_exists(candidate):
        candidate = folder.path_join("%s-%d.json" % [stem, n])
        n += 1
    return candidate
