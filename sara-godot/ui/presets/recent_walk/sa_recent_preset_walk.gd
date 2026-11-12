## Ctrl+R, a walk back through the recent presets that works the way Alt+Tab
## walks the windows.
##
##
## **The list is the Recent Presets docker's.** It is the one record of the
## order of visits, so the walk reads it there rather than keeping a second one
## that could part from it. The first press loads the second row, each further R
## while Ctrl is held the row behind, wrapping past the last to the first. Every
## step loads its preset through the bar, so the bar, the cursor and the next
## stroke show it at once.
##
## **The order holds still while Ctrl is held.** A load is a visit and the
## docker moves a visit to the top, so a walk that loaded as it went would have
## reshuffled the list under the painter at every press. The docker is told the
## walk began and only lights the row a load reaches, and on Ctrl's release the
## preset reached goes to the top with every other row where it was. A single
## Ctrl+R and release is then the swap `brush_preset_previous` makes.
##
## **Where the painter is shows in two places.** The docker lights the row
## reached when it is open, and when it is not a small list of the same names
## stands beside the pointer with the reached one drawn pressed, and goes when
## Ctrl is let go.
##
## **The release is read off the keyboard's state each frame**, not off a
## release event. A release can land in any of Sara's windows, a docker's
## included, or in none when the window loses focus, and Godot clears its
## pressed keys on a focus loss, so the state is the one place that always says
## the walk is over.
class_name SaRecentPresetWalk
extends CanvasLayer

## The command's id. `brush_` and not `preset_`, for the reason
## `ToolOptionsPresets.register_previous` gives: the Keyboard Shortcuts page
## files a row under the section its prefix names.
const COMMAND := &"brush_preset_recent_walk"

## The walk's node under the event bus, one for the session, built on the first
## press.
const NODE_NAME := "RecentPresetWalk"

## Above the canvas and the bar, so the list beside the pointer is never under
## them.
const LAYER: int = 90

## Whether a walk is under way. Written by `step` and `finish`.
var _walking: bool = false

## The docker's list as it stood when the walk began, most recent first.
## Written by `step`.
var _order: PackedStringArray = PackedStringArray()

## Where in `_order` the walk stands. Written by `step`.
var _index: int = 0

## The preset in hand when the walk began, and the one it has reached. Written
## by `step` and `finish`.
var _start: String = ""
var _reached: String = ""

## The list beside the pointer. Written by `_init`.
var _shown: Shown = null


func _init() -> void:
    name = NODE_NAME
    layer = LAYER
    _shown = Shown.new()
    add_child(_shown)
    set_process(false)


## Registers the walk on Ctrl+R, in the brush's category beside the swap.
##
## **The Krita profile keeps Ctrl+R for its Rectangular Selection tool**, so its
## table gives the command no chord, the row stays on the page to be bound.
static func register(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(COMMAND, "Walk back through the recent presets", _step_in_tree)
    var chord := InputEventKey.new()
    chord.keycode = KEY_R
    chord.ctrl_pressed = true
    command.default_events = [chord]
    command.category = &"brush"
    command.sentence = (
        "Load the preset used before this one, and each further R while Ctrl is held the one behind it. "
        + "Letting go of Ctrl puts the one reached at the top of Recent Presets."
    )
    # A walk ends when Ctrl is let go, which a pick in the search never holds.
    command.show_in_search = false
    ctx.register_command(command)


## The session's walk, built the first time and kept under the event bus.
##
## Under the bus rather than the root, because the root refuses a child while it
## is still setting up its own, which is the whole of a boot and of a suite run,
## and the bus is in the tree from the first frame.
static func in_tree() -> SaRecentPresetWalk:
    var walk := EventBus.get_node_or_null(NODE_NAME) as SaRecentPresetWalk
    if walk == null:
        walk = SaRecentPresetWalk.new()
        EventBus.add_child(walk)
    return walk


## The command's handler. It declines the key when there is nothing to walk, so
## Ctrl+R is not swallowed with nothing done.
static func _step_in_tree() -> bool:
    return in_tree().step()


## One press of R: begins a walk when none is under way and loads the next row.
## A row whose preset does not load is passed over. Answers whether a walk is
## under way after it.
func step() -> bool:
    var presets := ToolOptionsPresets.in_tree(self)
    var docker := HistoryDocker.in_tree(self)
    if presets == null or docker == null:
        return false
    if not _walking:
        if docker.entries.size() < 2:
            return false
        _order = docker.entries.duplicate()
        _start = presets.selected_preset
        _reached = ""
        # The preset in hand is the top row, so the first press reaches the
        # second. A hand of no preset, New's defaults, starts at the top row.
        _index = 0 if _order[0] == _start else -1
        _walking = true
        docker.begin_walk()
        set_process(true)
    for _tried in _order.size():
        _index = (_index + 1) % _order.size()
        if presets.load_preset(_order[_index]):
            _reached = _order[_index]
            _show(docker)
            return true
    if _reached.is_empty():
        finish()
        return false
    return true


## Ends the walk: the reached preset goes to the top of the docker's list, and
## the preset the walk began on is the one the swap goes back to, as it would be
## after a single step.
func finish() -> void:
    if not _walking:
        return
    _walking = false
    set_process(false)
    _shown.visible = false
    var docker := HistoryDocker.in_tree(self)
    if docker != null:
        docker.end_walk(_reached)
    var presets := ToolOptionsPresets.in_tree(self)
    if presets != null and not _start.is_empty() and _reached != _start:
        presets.previous_preset = _start


## Ends the walk once neither Ctrl nor its Mac stand-in is down. Public so a
## suite can ask without waiting out a frame, as `HistoryDocker.take_pictures`
## is.
func poll() -> void:
    if _walking and not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
        finish()


func _process(_delta: float) -> void:
    poll()


## Shows where the walk stands: the docker lights its row on its own, and the
## list beside the pointer stands in for it when the docker is not open.
func _show(docker: HistoryDocker) -> void:
    if docker.visible:
        _shown.visible = false
        return
    _shown.list(_order, _index)
    _shown.near(get_viewport().get_mouse_position(), get_viewport().get_visible_rect())
    _shown.visible = true


## The small list beside the pointer: the names of the walk, most recent first,
## with the reached one drawn as a pressed button. It takes no input, so a press
## goes through it to the canvas.
class Shown:
    extends PanelContainer

    ## How far from the pointer the list stands, in logical pixels, so the
    ## pointer does not hide the first name.
    const OFFSET: int = 18

    ## The widest a name is drawn, in logical pixels.
    const WIDTH: int = 220

    var rows: VBoxContainer = null

    func _init() -> void:
        name = "RecentPresetWalkList"
        visible = false
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        var margin := SaMake.margin(self, "Margin", SaUI.BASE_MARGIN)
        margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rows = SaMake.column(margin, "Rows", 2)
        rows.mouse_filter = Control.MOUSE_FILTER_IGNORE

    ## Rebuilds the rows for *order*, lighting the one at *index*.
    func list(order: PackedStringArray, index: int) -> void:
        for child in rows.get_children():
            rows.remove_child(child)
            child.queue_free()
        for at in order.size():
            var row := SaMake.button(rows, "Row_" + order[at], order[at])
            row.mouse_filter = Control.MOUSE_FILTER_IGNORE
            row.focus_mode = Control.FOCUS_NONE
            row.alignment = HORIZONTAL_ALIGNMENT_LEFT
            row.clip_text = true
            row.custom_minimum_size = Vector2(SaUI.px(WIDTH), 0)
            row.toggle_mode = true
            row.button_pressed = at == index
            row.flat = at != index

    ## Stands below and right of *pointer*, kept inside *area*.
    func near(pointer: Vector2, area: Rect2) -> void:
        reset_size()
        var at := pointer + Vector2(SaUI.px(OFFSET), SaUI.px(OFFSET))
        at.x = clampf(at.x, area.position.x, maxf(area.position.x, area.end.x - size.x))
        at.y = clampf(at.y, area.position.y, maxf(area.position.y, area.end.y - size.y))
        position = at
