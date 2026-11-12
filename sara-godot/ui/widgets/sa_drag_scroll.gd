## A press and drag on a scroll's content moves the content with the pointer, as
## its scroll bar does, wherever the press landed on nothing with a drag of its
## own. A short press stays a click. A fast drag moves the content further than
## the pointer and a flick lets it glide on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The engine's `ScrollContainer` follows a drag only on a touch screen, and
## only one that reaches the container itself, which a press on a button or a
## tile never does: the viewport stops a mouse event at the first control whose
## filter is `MOUSE_FILTER_STOP`. So this reads the pointer in `_input`, ahead of
## the GUI pass, and moves the bars itself.
##
## Which press may scroll: the control the press lands on, and every one above
## it up to the scroll, has no drag of its own. A `Range`, a text field, a tree,
## a split's divider, a tab bar, a nested scroll, a control whose script answers
## `_get_drag_data`, one marked with [constant OWN_DRAG_META] and a landed-on
## control whose script reads `_gui_input` keep the press for themselves.
##
## The click is called off once the pointer has travelled [constant DRAG_THRESHOLD].
## The release still goes through, because a release the GUI pass never saw
## leaves the viewport's mouse focus on the pressed control, so a `BaseButton` on
## the way up is set disabled and back, the engine's way of forgetting a press.
## A control that picks on its own release reads the travel itself, as the preset
## tile in `brush_preset_cells.gd` does. Any press inside the scroll stops a
## glide where it stands and one on the content takes no focus, since a painter
## stopping a list does not mean to pick what is under it. The speed and the
## glide are tuned by the constants below.
##
## Attached by a filter on the tree, as [SaScrollPace] is, so a docker built
## later by a module scrolls by a drag without naming this. The node joins as an
## internal child, so a docker that counts its scroll's children still counts one.
class_name SaDragScroll
extends Node

## The travel, in the window's own pixels, past which a press is a drag.
const DRAG_THRESHOLD: float = 6.0

## A control a host marks with this meta, to any value, keeps a press and drag
## that lands on it or on anything inside it.
const OWN_DRAG_META := &"sa_own_drag"

## The meta a scroll carries once it has its helper, so a scroll that leaves the
## tree and enters again is served once.
const TAKEN_META := &"sa_drag_scroll"

## The buttons a wheel reports its notches as.
const WHEEL_BUTTONS: Array[MouseButton] = [
    MOUSE_BUTTON_WHEEL_UP,
    MOUSE_BUTTON_WHEEL_DOWN,
    MOUSE_BUTTON_WHEEL_LEFT,
    MOUSE_BUTTON_WHEEL_RIGHT,
]

## Up to this speed, in the window's pixels a second, a drag moves the content
## one for one. A careful drag to place a row runs at well under it, a reach
## for the list's far end at several times it.
const CALM_SPEED: float = 300.0
## The speed past [constant CALM_SPEED] at which the gain has grown by one,
## the gain growing with the square of the excess. At 250 with no top a flick
## of 150 pixels in 60 milliseconds is multiplied 78 times and crosses all 76
## stock presets, 5738 pixels, before the pen lifts. At 500 a drag at 600 pixels
## a second moves the list 1.4 times as far as the pointer.
const GAIN_SPEED: float = 500.0
## The pointer's travel, in the window's pixels, over which the gain's top grows
## by one. A flick of 150 pixels is multiplied at most 2.5 times, and a drag of
## a third of the stock presets' 6000 pixels as much as twenty times, which is
## the long drag that carries the list to its end.
const GAIN_TRAVEL: float = 100.0
## How far back, in seconds, the pointer's speed is read, and the latest
## report before it besides, so a slow pen's speed always spans two reports.
## At 0.08 a flick's speed was diluted by the still moment after the press,
## and a pen held still for this long before the release reads as still.
const SPEED_WINDOW: float = 0.05
## The glide's time constant, in seconds: a glide runs on about this many
## seconds' worth of its starting speed in all, and at 0.35 a flick's glide
## eases out in under a second.
const GLIDE_TAU: float = 0.35
## The most a glide runs on, as a multiple of the pointer's travel since the
## press. A flick of 150 pixels glides at most 600, so it moves the 76 stock
## presets about a sixth of their length in all.
const GLIDE_SHARE: float = 4.0
## Below this speed, in the window's pixels a second, a glide stops.
const GLIDE_STOP: float = 20.0
## The shortest span a speed is read over, in seconds, so reports that came in
## one frame do not read as a leap.
const SHORTEST_SPAN: float = 0.008

## Goes out with true when the content starts to follow a drag or to glide, and
## with false when it stands again.
signal busy_changed(busy: bool)

## The scroll this moves.
var _scroll: ScrollContainer = null
## Whether a press is armed and where it landed.
var _armed: bool = false
var _origin := Vector2.ZERO
## The control the press landed on, whose click the drag calls off.
var _pressed: Control = null
## Whether the travel has passed the threshold, which is when the bars follow.
var dragging: bool = false
## The pointer's recent places and the clock's reading at each, in seconds,
## oldest first, which the speed is read from.
var _trail: Array[Vector3] = []
## The pointer's path since the press, in the window's pixels, which bounds the
## gain and the glide.
var _travel: float = 0.0
## The content's speed while it glides, in the window's pixels a second, and
## zero when it stands.
var glide := Vector2.ZERO
## Whether the content follows a drag or glides, which is what
## [signal busy_changed] last said.
var busy: bool = false


func _init(scroll: ScrollContainer) -> void:
    _scroll = scroll
    name = "DragScroll"
    set_process(false)


## Every scroll *tree* holds from here on, and every one it holds already, that
## *wanted* answers true for, scrolls with a press and drag.
static func install(tree: SceneTree, wanted: Callable) -> void:
    if tree == null:
        return
    var take_wanted := _take_if.bind(wanted)
    tree.node_added.connect(take_wanted)
    if tree.root != null:
        for node: Node in tree.root.find_children("*", "ScrollContainer", true, false):
            take_wanted.call(node)


static func _take_if(node: Node, wanted: Callable) -> void:
    var scroll := node as ScrollContainer
    if scroll != null and not scroll.has_meta(TAKEN_META) and bool(wanted.call(scroll)):
        take(scroll)


## Gives *scroll* its helper, once. Added on the next idle moment, because the
## tree is still adding the scroll when its `node_added` arrives.
static func take(scroll: ScrollContainer) -> SaDragScroll:
    if scroll.has_meta(TAKEN_META):
        return scroll.get_meta(TAKEN_META) as SaDragScroll
    var helper := SaDragScroll.new(scroll)
    scroll.set_meta(TAKEN_META, helper)
    if scroll.is_inside_tree():
        scroll.add_child.call_deferred(helper, false, Node.INTERNAL_MODE_BACK)
    else:
        scroll.add_child(helper, false, Node.INTERNAL_MODE_BACK)
    return helper


func _exit_tree() -> void:
    _stop_gliding()
    _let_go()


func _input(event: InputEvent) -> void:
    if _takes_over_a_glide(event):
        _stop_gliding()
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            var stopped := _stopped_a_glide(button.position)
            _arm(button.position)
            if stopped:
                get_viewport().set_input_as_handled()
        else:
            _release(button.position)
        return
    var motion := event as InputEventMouseMotion
    if motion == null or not _armed:
        return
    # A release over another window never reaches this one, so a motion with
    # the button up ends the press it left. `Input` is asked rather than the
    # event's mask, which a pushed motion carries as zero.
    if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and motion.button_mask == 0:
        _let_go()
        return
    var last := Vector2(_trail[-1].x, _trail[-1].y)
    _note(motion.position)
    _travel += motion.position.distance_to(last)
    var travel := motion.position - _origin
    if not dragging and travel.length() >= DRAG_THRESHOLD:
        dragging = true
        _call_off_click()
        _follow(travel)
        _say_busy()
    elif dragging:
        _follow((motion.position - last) * gain(_speed().length(), _travel))
    if dragging:
        get_viewport().set_input_as_handled()


## How many times the pointer's step the content moves at *speed*, in the
## window's pixels a second, once the pointer has come *travel* pixels since
## the press: one up to [constant CALM_SPEED] and growing with the square of the
## excess past it, to a top of one more for each [constant GAIN_TRAVEL] of
## travel.
static func gain(speed: float, travel: float) -> float:
    var excess := maxf(speed - CALM_SPEED, 0.0) / GAIN_SPEED
    return minf(1.0 + excess * excess, 1.0 + travel / GAIN_TRAVEL)


func _now() -> float:
    return Time.get_ticks_usec() / 1000000.0


## Adds *at* to the trail and drops what is older than the speed's window,
## keeping the latest place before it so a slow pen's speed spans two reports.
func _note(at: Vector2) -> void:
    var now := _now()
    _trail.append(Vector3(at.x, at.y, now))
    while _trail.size() > 2 and now - _trail[1].z > SPEED_WINDOW:
        _trail.pop_front()


## The pointer's speed over the trail, zero when it has one place or its places
## all came within a moment.
func _speed() -> Vector2:
    if _trail.size() < 2:
        return Vector2.ZERO
    var first := _trail[0]
    var last := _trail[-1]
    var span := maxf(last.z - first.z, SHORTEST_SPAN)
    return Vector2(last.x - first.x, last.y - first.y) / span


## Arms a press at *at*, in the window's pixels, when it lands inside the scroll,
## off its bars, on nothing with a drag of its own, and the scroll has room to
## move.
func _arm(at: Vector2) -> void:
    _let_go()
    if not _scroll.is_visible_in_tree() or not _scroll.get_global_rect().has_point(at):
        return
    for bar: ScrollBar in [_scroll.get_v_scroll_bar(), _scroll.get_h_scroll_bar()]:
        if bar.visible and bar.get_global_rect().has_point(at):
            return
    if not _can_move():
        return
    var landed := _control_at(_scroll, at)
    if landed == null or _keeps_its_drag(landed):
        return
    _armed = true
    _pressed = landed
    _origin = at
    _travel = 0.0
    _trail = [Vector3(at.x, at.y, _now())]


func _let_go() -> void:
    _armed = false
    dragging = false
    _pressed = null
    _trail.clear()
    _say_busy()


## Ends a press at *at*. A drag whose pointer still moved past the calm speed
## within the speed's window hands its speed, at its gain, to a glide. A slower
## one stays where it was let go, so a row placed with care is not carried off.
func _release(at: Vector2) -> void:
    if dragging and not _trail.is_empty():
        _travel += at.distance_to(Vector2(_trail[-1].x, _trail[-1].y))
        _note(at)
        var now := _now()
        var moving := _trail.size() >= 2 and now - _trail[-2].z <= SPEED_WINDOW
        var speed := _speed() if moving else Vector2.ZERO
        if speed.length() > CALM_SPEED:
            glide = speed * gain(speed.length(), _travel)
            glide = glide.limit_length(GLIDE_SHARE * _travel / GLIDE_TAU)
            set_process(true)
    _let_go()


## Stops a glide that a press at *at* lands on, and answers whether it did so on
## the content rather than on a bar, which is when the press is the painter's
## finger on the list and not a click on what is under it.
func _stopped_a_glide(at: Vector2) -> bool:
    if glide == Vector2.ZERO or not _scroll.get_global_rect().has_point(at):
        return false
    _stop_gliding()
    for bar: ScrollBar in [_scroll.get_v_scroll_bar(), _scroll.get_h_scroll_bar()]:
        if bar.visible and bar.get_global_rect().has_point(at):
            return false
    return true


## Whether *event* is a wheel notch or a pan over the scroll while it glides,
## which scrolls the list by a hand of its own.
func _takes_over_a_glide(event: InputEvent) -> bool:
    if glide == Vector2.ZERO:
        return false
    var button := event as InputEventMouseButton
    var wheel := button != null and button.button_index in WHEEL_BUTTONS
    var pan := event as InputEventPanGesture
    if not wheel and pan == null:
        return false
    var at: Vector2 = button.position if wheel else pan.position
    return _scroll.is_visible_in_tree() and _scroll.get_global_rect().has_point(at)


func _stop_gliding() -> void:
    glide = Vector2.ZERO
    set_process(false)
    _say_busy()


## Sends [signal busy_changed] when the content has started or stopped moving
## since it last said.
func _say_busy() -> void:
    var now := dragging or glide != Vector2.ZERO
    if now != busy:
        busy = now
        busy_changed.emit(busy)


func _process(delta: float) -> void:
    var before := _bars()
    _follow(glide * delta)
    glide *= exp(-delta / GLIDE_TAU)
    if glide.length() < GLIDE_STOP or _bars() == before:
        _stop_gliding()


func _bars() -> Vector2:
    return Vector2(_scroll.get_h_scroll_bar().value, _scroll.get_v_scroll_bar().value)


## Whether either enabled axis has more content than it shows.
func _can_move() -> bool:
    var down := _scroll.get_v_scroll_bar()
    var across := _scroll.get_h_scroll_bar()
    var tall := _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and down.max_value > down.page
    var wide := _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and across.max_value > across.page
    return tall or wide


## The content follows the pointer: a step up by *travel* shows what was below.
## The bars clamp to their ends, so a drag back from an end moves at once. The
## values are floats, as [SaScrollPace] keeps them, so a slow pen's fractions
## are not rounded away.
func _follow(travel: Vector2) -> void:
    if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
        _scroll.get_h_scroll_bar().value -= travel.x
    if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
        _scroll.get_v_scroll_bar().value -= travel.y


## Every button between the pressed control and the scroll forgets the press,
## so its release fires nothing.
func _call_off_click() -> void:
    var node: Node = _pressed
    while node != null and node != _scroll:
        var button := node as BaseButton
        if button != null and not button.disabled:
            button.disabled = true
            button.disabled = false
        node = node.get_parent()


## Whether the press on *landed*, or anything above it up to the scroll, is a
## drag that control answers itself.
func _keeps_its_drag(landed: Control) -> bool:
    if landed != _scroll and landed.has_method(&"_gui_input"):
        return true
    var node: Node = landed
    while node != null and node != _scroll:
        if _drags_itself(node):
            return true
        node = node.get_parent()
    return false


static func _drags_itself(node: Node) -> bool:
    if node.has_meta(OWN_DRAG_META) or node.has_method(&"_get_drag_data"):
        return true
    return (
        node is Range
        or node is LineEdit
        or node is TextEdit
        or node is Tree
        or node is SplitContainer
        or node is TabBar
        or node is GraphEdit
        or node is ScrollContainer
    )


## The control the GUI pass would hand a press at *at*: the last drawn, deepest
## shown control whose rectangle holds it and whose filter does not let it
## through, under *parent*. *parent* itself when none of its children takes it.
static func _control_at(parent: Control, at: Vector2) -> Control:
    var children := parent.get_children()
    for i in range(children.size() - 1, -1, -1):
        var child := children[i] as Control
        if child == null or not child.visible or child.top_level:
            continue
        if not child.get_global_rect().has_point(at):
            continue
        var found := _control_at(child, at)
        if found != null:
            return found
    if parent.mouse_filter == Control.MOUSE_FILTER_IGNORE:
        return null
    return parent
