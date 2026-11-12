## The top bar arranged on the bar itself: a right click on an element opens a
## small menu to hide it, move it, show a hidden one or open the Elements… page,
## and a press and drag with Ctrl held lifts it and seats it somewhere else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The other way is Preferences, Layouts and dockers, the top bar's section,
## Elements…, a list eighteen rows deep, so arranging on the bar itself is what
## lets a painter delete an element or drop it between two others in one move.
##
## **Every change is a write of the setting and nothing else.** A hide is
## `set_element_visible`, a drop is `set_layout_order`, and the bar lays itself
## out again on `profile_changed` as it does for the Elements… page, so the page,
## the overflow and the profile read one thing. Edit is never offered Hide,
## the rule `set_element_visible` keeps.
##
## **The lifted element is the element itself, made `top_level`.** A container
## leaves a top level child out of its sorting and its minimum size, so the rest
## of the row closes up around it without anything being reparented, and the
## element drawn faint under the pointer is the real control rather than a
## picture of one. A spacer as wide as the element is the gap, put between the
## two elements the pointer is over, so the place it lands shows before the
## release.
##
## **Heard in `_input`, before the controls.** A plain press and a plain drag go
## on to the control as before, and only a press with Ctrl held, a right press
## on an element, and everything while an element is lifted are taken here and
## marked handled, so a slider is never moved by the press that lifts it.
##
## **Handed the bar's parts, not the bar.** The row of titles, the titles by
## name, the rows' boxes, two questions it asks of the rows, which controls
## they hold and which box holds the first row's controls, and one of the bar,
## whether a menu is open, so the arranger reads what it moves and nothing
## more, and names no file of the bar's folder. The menu it opens is
## `ElementMenu` below, a list of its own that says what was chosen.
##
## `@tool` because [ElementMenu] extends [SaChoicePopup], which carries it, and
## the editor's language server warns MISSING_TOOL on a subclass that drops it.
@tool
class_name SaTopBarArrange
extends Node

## The category the bar's order and switches are stored under.
const CATEGORY := "TopMenuBar"

## The one element a profile can never hide, `SaSettingsLayout`'s rule.
const NEVER_HIDDEN := "Edit"

## How far a Ctrl press travels, in logical pixels, before it lifts the element,
## so a Ctrl click that does not mean to move anything moves nothing.
const LIFT_SLOP := 4.0

## How faint the lifted element is drawn.
const LIFTED_ALPHA := 0.55

## Above everything else on the bar, so the lifted element is drawn over the
## rows it crosses.
const LIFTED_Z := 100

## The right click menu.
var menu: ElementMenu

## The bar's row of menu titles, and menu name -> its title.
var _menu_bar: HBoxContainer
var _titles: Dictionary
## The bar's first row and its second, the boxes a pointer is over.
var _main_row: Control
var _second_row: Control
## The rows' controls, element -> control, and row number -> the box holding
## that row's controls, asked each time because the first row's box comes with
## the tool options bar.
var _tool_elements: Callable
var _row_container: Callable
## Whether one of the bar's own menus is open, when a right press is the menu's.
var _a_menu_is_open: Callable

## The element a Ctrl press landed on and where, before it travels far enough
## to lift.
var _armed: String = ""
var _armed_at := Vector2.ZERO

## The lifted element, its control and the spacer that is the gap, or "" while
## nothing is lifted.
var lifted: String = ""
var _lifted_node: Control = null
var gap: Control = null
## Where the pointer took the element, from its top left corner.
var _grab := Vector2.ZERO
## Whether the lift is a held drag, which seats on the release, rather than the
## menu's Move, which seats on the next press.
var _held: bool = false
## What the lifted control had before the lift, given back when it is seated.
var _kept_modulate := Color.WHITE
var _kept_z: int = 0


func _init(
    menu_bar: HBoxContainer,
    titles: Dictionary,
    main_row: Control,
    second_row: Control,
    tool_elements: Callable,
    row_container: Callable,
    a_menu_is_open: Callable
) -> void:
    name = "TopBarArrange"
    _menu_bar = menu_bar
    _titles = titles
    _main_row = main_row
    _second_row = second_row
    _tool_elements = tool_elements
    _row_container = row_container
    _a_menu_is_open = a_menu_is_open
    menu = ElementMenu.new()
    add_child(menu)
    menu.move_asked.connect(_on_move_asked)


func _input(event: InputEvent) -> void:
    if not lifted.is_empty():
        _while_lifted(event)
        return
    var button := event as InputEventMouseButton
    if button != null:
        _on_button(button)
        return
    var motion := event as InputEventMouseMotion
    if motion != null and not _armed.is_empty():
        get_viewport().set_input_as_handled()
        if _armed_at.distance_to(motion.position) > LIFT_SLOP:
            var element := _armed
            _armed = ""
            lift(element, _armed_at, true)
            hover(motion.position)


## A right press on an element opens the menu, and a left press with Ctrl held
## arms the lift. Every other press goes on to the control.
func _on_button(button: InputEventMouseButton) -> void:
    if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and not _armed.is_empty():
        # A Ctrl click that never travelled: nothing moves, and the control
        # never had the press, so it has no release to hear either.
        _armed = ""
        get_viewport().set_input_as_handled()
        return
    if not button.pressed or _a_menu_is_open.call():
        return
    var element := element_at(button.position)
    if element.is_empty():
        return
    # A right press while the left button holds a slider is that slider's
    # cancel, `FactorSlider`'s rule, and not a menu.
    if button.button_index == MOUSE_BUTTON_RIGHT and (button.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
        get_viewport().set_input_as_handled()
        open_menu(element, SaPopupRect.at_window_point(_menu_bar.get_window(), button.position))
    elif button.button_index == MOUSE_BUTTON_LEFT and button.ctrl_pressed:
        get_viewport().set_input_as_handled()
        _armed = element
        _armed_at = button.position


## Everything while an element is lifted is the lift's: a motion moves it and
## the gap, a release of a held drag or a press after Move seats it, and
## Escape or the right button puts it back.
func _while_lifted(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key != null:
        if key.pressed and key.keycode == KEY_ESCAPE:
            get_viewport().set_input_as_handled()
            put_back()
        return
    if not event is InputEventMouse:
        return
    get_viewport().set_input_as_handled()
    var motion := event as InputEventMouseMotion
    if motion != null:
        hover(motion.position)
        return
    var button := event as InputEventMouseButton
    if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
        put_back()
    elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed != _held:
        hover(button.position)
        drop()


## The element whose control is under *at*, a menu title or a tool control on
## either row, or "" for none. A control in the overflow list is in a window of
## its own and never under a point of the bar.
func element_at(at: Vector2) -> String:
    var names := _names_of()
    for control: Control in names:
        if (
            control.is_visible_in_tree()
            and control.get_window() == _menu_bar.get_window()
            and control.get_global_rect().has_point(at)
        ):
            return names[control]
    return ""


## The control *element* stands for on the bar, or null.
func control_of(element: String) -> Control:
    if _titles.has(element):
        return _titles[element]
    return (_tool_elements.call() as Dictionary).get(element) as Control


## Control -> the element it stands for, for every element on the bar, the
## titles first.
func _names_of() -> Dictionary:
    var out := {}
    for m_name: String in _titles:
        out[_titles[m_name]] = m_name
    var elements: Dictionary = _tool_elements.call()
    for element: String in elements:
        if elements[element] != null:
            out[elements[element]] = element
    return out


## Fills the right click menu for *element* and opens it at *at*, the press in
## the space `SaPopupRect` measures in, as every right-click menu opens,
## or under the element when no point is given, which is how a suite asks.
func open_menu(element: String, at: Variant = null) -> void:
    menu.fill(element, hidden_elements())
    var anchor := control_of(element)
    if not menu.is_inside_tree() or anchor == null or not anchor.is_inside_tree():
        return
    var where: Variant = null
    if at is Vector2i:
        where = Vector2(at as Vector2i)
    menu.open_under(anchor, where)


## The elements the bar holds that the profile hides, in the profile's order.
func hidden_elements() -> Array[String]:
    var out: Array[String] = []
    var names := _names_of().values()
    for element: Variant in SaSettings.get_layout_order(CATEGORY):
        var named := String(element)
        if names.has(named) and not SaSettings.get_element_visible(CATEGORY, named):
            out.append(named)
    return out


## The menu's Move: the element is lifted where it stands and follows the
## pointer until the next press.
func _on_move_asked(element: String) -> void:
    var control := control_of(element)
    if control != null:
        lift(element, control.get_global_rect().get_center(), false)
        hover(get_viewport().get_mouse_position())


## Lifts *element* off its row: drawn faint where the pointer at *at* took it,
## the row closed up behind it and a gap where it stood. *held* says the lift
## is a drag, which seats on the release.
func lift(element: String, at: Vector2, held: bool) -> void:
    var node := control_of(element)
    if node == null or not lifted.is_empty():
        return
    menu.hide()
    lifted = element
    _held = held
    _lifted_node = node
    var rect := node.get_global_rect()
    _grab = at - rect.position
    _kept_modulate = node.modulate
    _kept_z = node.z_index
    gap = Control.new()
    gap.name = "TopBarArrangeGap"
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    gap.custom_minimum_size = Vector2(rect.size.x, 0.0)
    var parent := node.get_parent()
    parent.add_child(gap)
    parent.move_child(gap, node.get_index())
    node.top_level = true
    node.global_position = rect.position
    node.size = rect.size
    node.modulate = Color(_kept_modulate, _kept_modulate.a * LIFTED_ALPHA)
    node.z_index = LIFTED_Z


## The containers the lifted element may land in, each with the box that says
## which row the pointer is on: the titles' row for a title, and the two rows
## of tool controls for a control.
func _targets() -> Array[Array]:
    if _titles.has(lifted):
        return [[_menu_bar, _main_row]]
    var out: Array[Array] = [[_row_container.call(1), _main_row]]
    if _second_row.visible:
        out.append([_row_container.call(2), _second_row])
    return out


## Moves the lifted element under the pointer at *at* and opens the gap between
## the two elements it is over, or takes the gap away while the pointer is off
## the bar, where a release puts the element back.
func hover(at: Vector2) -> void:
    if _lifted_node == null:
        return
    _lifted_node.global_position = at - _grab
    var target := _target_at(at)
    if target == null:
        if gap.get_parent() != null:
            gap.get_parent().remove_child(gap)
        return
    var before := _element_after(target, at)
    if gap.get_parent() != target:
        if gap.get_parent() != null:
            gap.get_parent().remove_child(gap)
        target.add_child(gap)
    # A child's index counts the gap while it stands before that child, so the
    # place asked for is one less then.
    var wanted := before.get_index() if before != null else _after_last(target)
    target.move_child(gap, wanted - 1 if gap.get_index() < wanted else wanted)


func _target_at(at: Vector2) -> Container:
    for pair: Array in _targets():
        var row := pair[1] as Control
        if row.is_visible_in_tree() and row.get_global_rect().has_point(at):
            return pair[0] as Container
    return null


## The element *target* holds that a drop at *at* goes in front of: the first
## whose middle is right of the pointer.
func _element_after(target: Container, at: Vector2) -> Control:
    for control in _elements_in(target):
        if control.get_global_rect().get_center().x > at.x:
            return control
    return null


## The index just past the last element *target* holds, or its end when it
## holds none.
func _after_last(target: Container) -> int:
    var held := _elements_in(target)
    return held[held.size() - 1].get_index() + 1 if not held.is_empty() else target.get_child_count()


## The shown elements in *target*, left to right, the lifted one and the gap
## left out.
func _elements_in(target: Container) -> Array[Control]:
    var out: Array[Control] = []
    var names := _names_of()
    for child in target.get_children():
        var control := child as Control
        if control != null and control != _lifted_node and names.has(control) and control.visible:
            out.append(control)
    return out


## The elements either side of the gap, the one before it and the one after,
## each "" where the gap is at that end of its row.
func _either_side() -> Array[String]:
    var target := gap.get_parent() if gap != null else null
    var out: Array[String] = ["", ""]
    if target == null:
        return out
    var names := _names_of()
    for control in _elements_in(target as Container):
        if control.get_index() < gap.get_index():
            out[0] = names[control]
        elif out[1].is_empty():
            out[1] = names[control]
    return out


## Seats the lifted element in the gap, and writes the order the bar then
## reads. With no gap, the pointer off the bar, it goes back where it was.
func drop() -> void:
    if lifted.is_empty():
        return
    if gap.get_parent() == null:
        put_back()
        return
    var second: bool = gap.get_parent() == _row_container.call(2)
    var side := _either_side()
    var element := lifted
    _settle()
    SaSettings.set_layout_order(CATEGORY, order_with(element, side[1], side[0], second))


## The stored order with *element* moved in front of *next*, or after
## *previous* when nothing follows it on its row, or at the head of the second
## row, just after the sentinel, when *second* and the row holds nothing else,
## or just before it on the first row.
static func order_with(element: String, next: String, previous: String, second: bool) -> Array:
    var order := SaSettings.get_layout_order(CATEGORY)
    order.erase(element)
    var at := order.find(next) if not next.is_empty() else -1
    if at < 0 and not previous.is_empty() and order.has(previous):
        at = order.find(previous) + 1
    if at < 0:
        var sentinel := order.find(SaSettings.ROW_SENTINEL)
        at = order.size() if sentinel < 0 else sentinel + (1 if second else 0)
    order.insert(at, element)
    return order


## Puts the lifted element back where it was, the order untouched.
func put_back() -> void:
    _settle()


## Ends the lift: the element joins its row again where it stood, drawn as it
## was, and the gap goes away.
func _settle() -> void:
    if _lifted_node != null and is_instance_valid(_lifted_node):
        _lifted_node.top_level = false
        _lifted_node.modulate = _kept_modulate
        _lifted_node.z_index = _kept_z
    if gap != null:
        if gap.get_parent() != null:
            gap.get_parent().remove_child(gap)
        gap.free()
    gap = null
    _lifted_node = null
    lifted = ""
    _held = false


## What the lift is doing, for a capture: the lifted element, whether the gap
## is on the bar and the elements either side of it.
func report() -> Dictionary:
    if lifted.is_empty():
        return {"lifted": ""}
    return {"lifted": lifted, "gap_on_bar": gap.get_parent() != null, "gap_between": _either_side()}


## The right click menu: Hide, Move, Show with the hidden elements beside it,
## and Arrange the Top Bar..., which opens the Elements… page. Hide and Show write
## the setting themselves, and Move is the arranger's, asked through
## `move_asked`.
class ElementMenu:
    extends SaChoicePopup

    ## Move was chosen for *element*.
    signal move_asked(element: String)

    const HIDE := &"hide"
    const MOVE := &"move"
    const SHOW := &"show"
    const ARRANGE := &"arrange"

    ## The list of hidden elements the Show row opens.
    var show_list := SaChoicePopup.new(true, false)

    ## The element the menu was opened on, and what was hidden then.
    var element: String = ""
    var _hidden: Array[String] = []

    func _init() -> void:
        super(true, false)
        name = "TopBarArrangeMenu"
        chosen.connect(_on_chosen)
        branched.connect(_on_branched)
        SaPutAway.join(self)
        show_list.name = "TopBarShowList"
        add_child(show_list)
        show_list.chosen.connect(_on_show_chosen)
        SaPutAway.join(show_list)

    ## The rows for *on*, with *hidden* the elements the Show row lists. Hide is
    ## absent on Edit, and Show is greyed while nothing is hidden.
    func fill(on: String, hidden: Array[String]) -> void:
        element = on
        _hidden = hidden
        clear()
        if on != NEVER_HIDDEN:
            add_row(HIDE, tr("Hide"))
        add_row(MOVE, tr("Move"))
        add_branch_row(SHOW, tr("Show"), "", hidden.is_empty())
        add_gap()
        add_row(ARRANGE, tr("Arrange the Top Bar..."))
        _fill_show_list()

    func _fill_show_list() -> void:
        show_list.clear()
        for hidden_one: String in _hidden:
            show_list.add_row(StringName(hidden_one), SaSettings.translated_element_title(CATEGORY, hidden_one))

    func _on_chosen(id: StringName) -> void:
        match id:
            HIDE:
                set_shown(element, false)
            MOVE:
                move_asked.emit(element)
            ARRANGE:
                # Deferred, for the reason `DockerDragHandle._open_settings_page`
                # gives: a window taking focus inside input handling
                # desynchronises the engine's popup bookkeeping.
                EventBus.settings_row_requested.emit.call_deferred(SaSettingsWindow.internal_title_for(CATEGORY), &"")

    func _on_branched(id: StringName) -> void:
        if id == SHOW:
            _fill_show_list()
            open_child(show_list, id)

    func _on_show_chosen(id: StringName) -> void:
        set_shown(String(id), true)

    ## Shows or hides *which* through the setting, which the bar answers.
    static func set_shown(which: String, shown: bool) -> void:
        if which == NEVER_HIDDEN and not shown:
            return
        SaSettings.set_element_visible(CATEGORY, which, shown)
