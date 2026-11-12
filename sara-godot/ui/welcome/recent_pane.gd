## The Recent pane of the welcome window: New and Open across its top, then the
## recovery row and the grid of recent documents, with nothing in either of
## them yet. It carries no title of its own, because the tab above it already
## says "Recent".
##
## **New and Open lead the pane, large**, because a painter who opens Sara for
## the first time looks for where to start, and two small buttons at the
## window's foot under a pane of one sentence did not say it. They stand at
## least as tall as the window's tab bar, at a larger text than the pane's. The
## pane lays them out and the window says what a press does, since the window
## is what knows the boot and the document flow.
##
## The two containers are named here because two classes fill one each and
## neither reads the other's file: the recovery offer goes in `RecoveryRow` and
## the ten thumbnails in `RecentGrid`. They are created empty by this row so the
## window opens with its three panes rather than with one.
##
## **An empty list offers to open a file across the pane**, in a block this
## pane lays beside the cards rather than in one of their cells, and the cards'
## grid decides which of the two shows. The block is the "Open a file" action
## with the sentence that says what fills the list under it, small, because a
## pane that only said nothing had been opened left the painter to find the
## way on. `RecentGrid` is a column for the same reason: it was a grid of
## four around the one scroll of cards, a grid gives its empty columns a share
## of the width, and the line wrapped a word or two to a row in a quarter of
## the pane.
@tool
class_name WelcomeRecentPane
extends VBoxContainer

## The shortest the actions stand, in logical units, which is taller than the
## tab bar at every Font size because their text grows with it.
const ACTION_HEIGHT := 44.0

## How much larger than the pane's text the actions' words are.
const ACTION_TEXT := 1.25

## The width the action an empty list shows keeps at the least, so it reads as
## the one thing to do rather than as a word.
const LONE_ACTION_WIDTH := 240.0

## Where the offer goes to open the last session's recovery copy.
var recovery_row: VBoxContainer

## Where the ten recent documents go, each a thumbnail and a date, with the
## line an empty list shows in their place.
var recent_grid: VBoxContainer

## The two actions across the top of the pane and the one an empty list shows,
## laid out here and wired by the window.
var new_button: Button
var open_button: Button
var open_a_file: Button


## *booting* is true for the pane of a welcome window `SaBoot` built, and is
## handed to both rows, which hold what they open until the boot is done.
func _init(booting: bool = false) -> void:
    name = "Recent"
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    var actions := SaMake.row(self, "Actions", SaTheme.GAP)
    var new_tip := tr("A fresh document, at the size, depth and colour space you pick")
    new_button = _action(actions, "NewButton", tr("New"), new_tip)
    open_button = _action(actions, "OpenButton", tr("Open", "open a document"), tr("Open a Sara document (.sad) or a picture."))
    recovery_row = SaMake.column(self, "RecoveryRow")
    recovery_row.add_child(WelcomeRecoveryRow.new(booting))
    recent_grid = SaMake.column(self, "RecentGrid")
    recent_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Before the cards, because a reader of the column takes its last child for
    # the grid. Only one of the two shows, so the order is not seen.
    var empty := SaMake.column(recent_grid, "RecentEmpty", SaTheme.GAP)
    empty.alignment = BoxContainer.ALIGNMENT_CENTER
    empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
    open_a_file = _action(empty, "OpenAFile", tr("Open a file"), tr("Open a Sara document (.sad) or a picture."))
    open_a_file.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    open_a_file.custom_minimum_size.x = SaUI.pxf(LONE_ACTION_WIDTH)
    var empty_text := tr("Nothing opened yet. A document you open or save is listed here.")
    var hint := SaMake.label(empty, "RecentEmptyHint", empty_text)
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    recent_grid.add_child(WelcomeRecentGrid.new(null, booting, empty))


## Tells the grid to forget the card chosen while the boot runs, for the
## window, which is put away before the boot has finished.
func drop_held_choice() -> void:
    for child in recent_grid.get_children():
        if child is WelcomeRecentGrid:
            child.drop_held_choice()


## A large action in *parent*, the shape New, Open and Open a file share.
static func _action(parent: Node, node_name: String, text: String, tooltip: String) -> Button:
    var made := SaMake.button(parent, node_name, text, tooltip)
    made.custom_minimum_size.y = SaUI.pxf(ACTION_HEIGHT)
    made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaUI.size_text(made, ACTION_TEXT)
    return made
