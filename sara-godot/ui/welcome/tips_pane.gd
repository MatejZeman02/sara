## The Tips pane of the welcome window: one short tip at a time, with Previous
## and Next and a counter under it. The first three teach a painter new to
## digital painting how to make a mark, choose its colour and add a layer to
## paint on, each a sentence to act on with the window open beside the
## painting. The rest show what Sara does that a painter coming from Krita or
## Photoshop would not find alone.
##
## **A tip that names a command shows its key as bound today.** The sentence
## never carries the key, and the line under it asks the command registry, or
## the input map for a key that lives there, so a painter who rebound the key
## on the Keyboard Shortcuts page reads the new one rather than the one Sara
## shipped with.
##
## **The pane opens on the tip after the last one shown**, which it keeps in
## `SaSettings.last_tip_shown` by id, so a painter who meets the window at
## every start reads them all in turn. Shown means this pane was on screen, the
## way the News pane counts its notes seen: a window put away without its Tips
## tab ever chosen moves nothing on, and the same tip waits for the next open.
@tool
class_name WelcomeTipsPane
extends VBoxContainer

## The labels and buttons, by name, so a test or a walker finds them without
## knowing where they sit in the pane.
const TITLE: String = "TipTitle"
const TEXT: String = "TipText"
const CHORD: String = "TipChord"
const COUNTER: String = "TipCounter"
const PREVIOUS: String = "TipPrevious"
const NEXT: String = "TipNext"

## The command registry a tip's key is read from. Found on `Main` the first time
## a tip is drawn after it exists, and set by a suite that builds its own. Null
## before the boot is done, when only the input map answers.
var commands: SaCommandRegistry

## Every tip, in the order Next walks them.
var tips: Array[Dictionary] = []

## Which of them is on screen.
var current: int = 0

var _title: Label
var _text: Label
var _chord: Label
var _counter: Label


func _init() -> void:
    name = "Tips"
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    tips = _tips()

    _title = SaMake.label(self, TITLE)
    SaSettingsRows.size_label(_title, SaSettingsRows.HEADING_SCALE)
    SaSettingsRows.embolden(_title)
    _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaMake.separator(self, "Rule")

    _text = SaMake.label(self, TEXT)
    _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _chord = SaSettingsRows.hint_label("")
    _chord.name = CHORD
    add_child(_chord)

    # The buttons sit at the pane's foot whatever the tip's length, so a long
    # tip does not move Next out from under the pointer that pressed it.
    var spacer := Control.new()
    spacer.name = "Spacer"
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(spacer)

    var row := SaMake.row(self, "TipButtons", SaTheme.GAP)
    var previous := SaMake.button(row, PREVIOUS, tr("Previous"), tr("The tip before this one"))
    previous.pressed.connect(step.bind(-1))
    _counter = SaMake.label(row, COUNTER)
    _counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    var next := SaMake.button(row, NEXT, tr("Next"), tr("The tip after this one"))
    next.pressed.connect(step.bind(1))
    open_on_next()


## The tips themselves, each a title and one or two sentences, every string
## through `tr` so a translated build translates them. `command` is the command
## or input map action whose key the line under the tip shows, and `key` is what
## that line says when the map binds nothing, for the one key the router reads
## by itself.
##
## Built in the pane rather than read from a file, so the suite can hold that
## every string here is a `tr` call.
func _tips() -> Array[Dictionary]:
    return [
        {
            "id": &"make_a_mark",
            "title": tr("Make a mark"),
            "text":
            tr("The first button in the Toolbox is the Brush. Pick it, then drag on the canvas, and the Brush makes a mark."),
            "command": &"tool_brush",
        },
        {
            "id": &"choose_a_colour",
            "title": tr("Choose a colour"),
            "text":
            tr("In the Colour Picker docker, the ring picks a hue and the square its shade. The next mark has that colour."),
            "command": &"docker_summon_color_selector",
        },
        {
            "id": &"add_a_layer",
            "title": tr("Add a layer to paint on"),
            "text": tr("The plus button (Add a paint layer) in the Layers docker adds a layer. A mark goes on the layer picked."),
            "command": &"layer_new_paint",
        },
        {
            "id": &"docker_alt_drag",
            "title": tr("Move a docker from anywhere on it"),
            "text": tr("Hold Alt and drag anywhere on a docker to move it, or drag with the right button to resize it."),
        },
        {
            "id": &"docker_alt_double_click",
            "title": tr("A docker's own settings"),
            "text":
            tr("Hold Alt and double-click a docker to open its line in Preferences, where you can hide or reorder its parts."),
        },
        {
            "id": &"top_menu_bar",
            "title": tr("A menu bar of your own"),
            "text":
            tr("In Preferences > Layouts and dockers, the top bar's Customize... button orders the menus and hides any of them."),
            "command": &"edit_preferences",
        },
        {
            "id": &"summoned_docker",
            "title": tr("A docker under the pointer"),
            "text":
            tr("Each docker has a key that shows it under the pointer until the pointer leaves it. This one calls Layers."),
            "command": &"docker_summon_layers",
        },
        {
            "id": &"popup_palette",
            "title": tr("The pop-up palette"),
            "text":
            tr("Turn on Pop-up palette in Preferences > Brushes, and this key shows your brush slots round a colour wheel."),
            "command": &"docker_summon_palette",
        },
        {
            "id": &"brush_slots",
            "title": tr("Ten brushes a key away"),
            "text":
            tr("Preferences > Brushes puts a preset in each of ten slots, and each slot has a key. This key picks slot 1."),
            "command": &"brush_slot_1",
        },
        {
            "id": &"soft_proof",
            "title": tr("Proof the canvas"),
            "text":
            tr("The canvas proof shows the painting as another screen or a print would show it, and changes no pixel of it."),
            "command": &"view_soft_proof",
        },
        {
            "id": &"shape_check",
            "title": tr("Check the shapes"),
            "text":
            tr("Shape check draws the canvas as flat blocks at a few steps of lightness, so the silhouette reads on its own."),
            "command": &"view_shape_check",
        },
        {
            "id": &"undo_history",
            "title": tr("Go back to any step"),
            "text": tr("The Undo History docker lists every step, and a click on one takes the painting back to it."),
            "command": &"docker_undo",
        },
        {
            "id": &"recent_presets",
            "title": tr("The brushes you just used"),
            "text": tr("The Recent Presets docker keeps the presets you painted with last, newest first, a click away."),
            "command": &"docker_summon_history",
        },
        {
            "id": &"tab_hides_the_dockers",
            "title": tr("Only the painting"),
            "text": tr("This key hides every docker but the pinned ones, and pressing it again brings them back."),
            "command": &"toggle_dockers",
            "key": MainDockers.FOCUS_MODE_KEY,
        },
        {
            "id": &"maximise_docker",
            "title": tr("A docker as large as the window"),
            "text": tr("This key maximizes the focused docker. Press it again to restore it."),
            "command": &"docker_maximise",
        },
    ]


## Shows the tip at *index*, wrapped into the list, and remembers it once the
## pane is on screen.
func show_tip(index: int) -> void:
    current = posmod(index, tips.size())
    var tip: Dictionary = tips[current]
    _title.text = String(tip["title"])
    _text.text = String(tip["text"])
    var chord := chord_of(tip)
    _chord.text = tr("Key: %s") % chord if not chord.is_empty() else ""
    _chord.visible = not chord.is_empty()
    _counter.text = tr_n("%d of %d", "%d of %d", tips.size()) % [current + 1, tips.size()]
    if is_visible_in_tree():
        SaSettings.last_tip_shown = String(tip["id"])


## One tip on, or back with -1, wrapping at either end. Previous and Next.
func step(by: int) -> void:
    show_tip(current + by)


## The tip after the one `SaSettings.last_tip_shown` names, or the first when
## it names none this build carries.
func open_on_next() -> void:
    var last := -1
    for i: int in tips.size():
        if String(tips[i]["id"]) == SaSettings.last_tip_shown:
            last = i
    show_tip(last + 1)


## The key *tip*'s command answers to now, or "" for a tip that names none.
##
## The registry first, then the input map, the order `SaMenu.chorded` reads
## them in, because Focus Mode's toggle is an action in the map with no entry
## in the registry.
func chord_of(tip: Dictionary) -> String:
    var command := StringName(tip.get("command", &""))
    if String(command).is_empty():
        return ""
    var registry := _command_registry()
    var chord := ""
    if registry != null and registry.has(command):
        chord = registry.chord_text(command)
    else:
        chord = SaMenu.action_chord(command)
    return chord if not chord.is_empty() else String(tip.get("key", ""))


## The command registry, found on `Main` on first use and kept, the way the
## Layers docker's buttons find theirs. A rebind announces itself on its
## `changed`, which redraws the tip so the line under it follows.
func _command_registry() -> SaCommandRegistry:
    if commands == null and is_inside_tree() and get_tree().current_scene != null:
        var registries := get_tree().current_scene.get("registries") as SaRegistries
        commands = registries.commands if registries != null else null
    if commands != null and not commands.changed.is_connected(_redraw):
        commands.changed.connect(_redraw)
    return commands


func _redraw() -> void:
    show_tip(current)


func _ready() -> void:
    var host := get_window()
    if host != null:
        host.visibility_changed.connect(_on_host_visibility)


## The tab came to the front, which is when the tip on it counts as shown.
func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
        show_tip(current)


## The window was opened again, so the pane moves on to the next tip.
func _on_host_visibility() -> void:
    var host := get_window()
    if host != null and host.visible:
        open_on_next()


## Puts the pane in front, the way the other panes' `reveal` does, for the shot
## a scenario takes.
func reveal() -> void:
    var tab := SaWelcomeWindow.tab_of(self)
    var tabs := tab.get_parent() as TabContainer
    if tabs != null:
        tabs.current_tab = tabs.get_tab_idx_from_control(tab)


## Walks the welcome tips: the pane's door, reached through `{"tips":...}`.
##
## `{"tips": {"step": 1}}` brings the pane to the front and walks that many
## tips on, a negative number back, and the line says which tip is on screen
## and the key under it either way.
static func capture_pane(root: Node, spec: Dictionary) -> String:
    var pane := root.find_child("Tips", true, false) as WelcomeTipsPane
    if pane == null:
        return "SaCapture: the welcome window is not open"
    pane.reveal()
    if spec.has("step"):
        pane.step(int(spec["step"]))
    var tip: Dictionary = pane.tips[pane.current]
    return (
        "SaCapture: tips pane %s, '%s', key '%s', counter '%s', last shown %s"
        % [tip["id"], pane._title.text, pane.chord_of(tip), pane._counter.text, SaSettings.last_tip_shown]
    )
