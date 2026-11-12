## The tab strip over the Reference docker's boards: one tab per board, the plus
## that adds pictures, the menu a right click on the strip opens, the rename a
## double click on a tab opens, and the row the docker's own buttons stand in.
##
## The strip owns the `TabBar` and nothing about the boards themselves. It is
## told what the boards are through `sync` and says what the painter did
## through five signals, so the docker is the one place a board is added,
## picked, renamed or closed, and the bar never disagrees with the list.
##
## **The plus adds pictures**, because that is what a painter presses it for.
## A new board is the strip's right click
## menu, New Board beside Rename and Close, and a double click on the empty part
## of the strip, as a browser opens a tab.
##
## **The docker's buttons share this row**, as icons in `buttons` right of the
## add button, which the docker fills and answers, so the board under the row
## takes the rest of the docker. A row of their own wraps to two at the
## column's 310. What the board holds is said by the showing tab's tooltip,
## through `describe`, rather than by a label under the row.
class_name ReferenceTabs
extends HBoxContainer

## The painter picked a tab.
signal board_selected(index: int)
## The painter pressed the close on a tab.
signal board_closed(index: int)
## The painter renamed a tab through the dialog and confirmed it.
signal board_renamed(index: int, board_name: String)
## The painter asked for another board, from the menu or a double click on the
## empty strip.
signal board_added
## The painter pressed the plus, which asks for pictures for the board showing.
signal pictures_wanted

## The rows of the strip's right click menu.
const NEW_BOARD: StringName = &"new_board"
const RENAME_BOARD: StringName = &"rename_board"
const CLOSE_BOARD: StringName = &"close_board"

## Logical height of the add button, so it matches the docker's other buttons.
const BUTTON_H: int = 22

## The least the bar is given beside the buttons, so one tab's title shows on
## a docker dragged to its floor rather than the bar folding to nothing.
const BAR_MIN_W: int = 64

## The gap between the docker's buttons, tighter than the row's own, so the
## five read as one group beside the tabs.
const BUTTON_GAP: int = 2

## The bar, read by a test that counts the tabs and reads their titles.
var bar: TabBar

## The row the docker's buttons stand in, which the docker fills.
var buttons: HBoxContainer

## The right click's menu over the strip, and the tab it was opened over.
var menu: SaChoicePopup
var _menu_for: int = -1

## Whether `sync` is writing the bar, so its `tab_changed` is not read back as
## the painter picking a tab.
var _syncing: bool = false


func _init() -> void:
    name = "TabRow"
    bar = TabBar.new()
    bar.name = "Tabs"
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.custom_minimum_size = Vector2(SaUI.px(BAR_MIN_W), 0)
    bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
    bar.focus_mode = Control.FOCUS_NONE
    bar.tab_changed.connect(_on_tab_changed)
    bar.tab_close_pressed.connect(func(index: int) -> void: board_closed.emit(index))
    bar.gui_input.connect(_on_bar_input)
    add_child(bar)

    var add := SaMake.button(self, "AddPicturesButton", "+", tr("Add pictures to this board"))
    add.focus_mode = Control.FOCUS_NONE
    add.custom_minimum_size = Vector2(0, SaUI.px(BUTTON_H))
    add.size_flags_horizontal = Control.SIZE_SHRINK_END
    add.pressed.connect(func() -> void: pictures_wanted.emit())

    buttons = SaMake.row(self, "ButtonRow", BUTTON_GAP)

    menu = SaChoicePopup.new()
    menu.name = "BoardMenu"
    add_child(menu)
    menu.chosen.connect(_on_menu_chosen)


## The bar shows a tab for each of *names*, with *current* showing.
func sync(names: PackedStringArray, current: int) -> void:
    _syncing = true
    while bar.tab_count > names.size():
        bar.remove_tab(bar.tab_count - 1)
    while bar.tab_count < names.size():
        bar.add_tab("")
    for i in range(names.size()):
        bar.set_tab_title(i, names[i])
    if bar.tab_count > 0:
        bar.current_tab = clampi(current, 0, bar.tab_count - 1)
    _syncing = false


## The tab at *index* says *text* on hover: the chosen picture's path, or how
## many pictures the board holds.
func describe(index: int, text: String) -> void:
    if index >= 0 and index < bar.tab_count:
        bar.set_tab_tooltip(index, text)


func _on_tab_changed(index: int) -> void:
    if not _syncing:
        board_selected.emit(index)


## A double click on a tab renames it, through a small dialog, since a
## `TabBar` has no editing of its own, and one on the empty part of the strip
## is a new board. A right click anywhere on the strip opens its menu.
func _on_bar_input(event: InputEvent) -> void:
    var click := event as InputEventMouseButton
    if click == null or not click.pressed:
        return
    var index := bar.get_tab_idx_at_point(click.position)
    if click.button_index == MOUSE_BUTTON_RIGHT:
        open_menu(index, Vector2(SaPopupRect.at_press(click, bar)))
    elif click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
        if index >= 0:
            open_rename(index)
        else:
            board_added.emit()


## The strip's menu at *at*, in the space `SaPopupRect.at_press` answers in,
## for the tab at *index*, or for the tab showing when the press was on the empty strip.
func open_menu(index: int, at: Vector2) -> void:
    fill_menu(index)
    menu.open_under(bar, at)


## The menu's rows, without opening it, the half a suite runs outside the tree.
## Rename and Close act on the tab under the press or the one showing, and are
## dimmed while there is no tab at all.
func fill_menu(index: int) -> void:
    _menu_for = index if index >= 0 else bar.current_tab
    var none := _menu_for < 0 or _menu_for >= bar.tab_count
    menu.clear()
    menu.add_row(NEW_BOARD, tr("New Board"))
    menu.add_row(RENAME_BOARD, tr("Rename"), false, false, "", "", none)
    menu.add_row(CLOSE_BOARD, tr("Close"), false, false, "", "", none)


func _on_menu_chosen(id: StringName) -> void:
    match id:
        NEW_BOARD:
            board_added.emit()
        RENAME_BOARD:
            open_rename(_menu_for)
        CLOSE_BOARD:
            if _menu_for >= 0 and _menu_for < bar.tab_count:
                board_closed.emit(_menu_for)
    _menu_for = -1


## The rename dialog for the tab at *index*, open and with its field holding the
## keys and its whole text selected, so the painter types the new name and
## presses Enter. Null when there is no such tab or the strip is not in a tree.
##
## Public so a scenario reaches the dialog the double click opens, which the
## harness has no gesture for. The focus and the selection are
## deferred, because a `grab_focus()` in the frame `popup_centered()` runs is
## thrown away when the popup takes the focus for itself.
func open_rename(index: int) -> AcceptDialog:
    if index < 0 or index >= bar.tab_count or not is_inside_tree():
        return null
    var dialog := AcceptDialog.new()
    dialog.name = "RenameBoardDialog"
    dialog.title = tr("Rename board")
    var field := LineEdit.new()
    field.name = "BoardName"
    field.text = bar.get_tab_title(index)
    field.custom_minimum_size = Vector2(SaUI.px(200), 0)
    dialog.add_child(field)
    dialog.register_text_enter(field)
    dialog.confirmed.connect(func() -> void: board_renamed.emit(index, field.text))
    dialog.visibility_changed.connect(
        func() -> void:
            if not dialog.visible:
                dialog.queue_free()
    )
    get_window().add_child(dialog)
    dialog.popup_centered()
    field.grab_focus.call_deferred()
    field.select_all.call_deferred()
    return dialog
