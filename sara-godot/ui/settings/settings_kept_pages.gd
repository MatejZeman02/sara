## The Preferences pages built once and kept, each in a column of its own beside
## the window's page column, hidden while another page shows.
##
## Keyboard shortcuts is two thousand or so controls, and building it and adding
## it to the tree held a frame of 331 to 423 ms on every open. A page taken out
## of the tree and added again costs two thirds of a fresh one, so a kept page
## never leaves it: its column is hidden, and shown again on the next open.
## Which pages are kept is [constant SaBuiltinPages.KEPT_PAGES].
##
## The window's `content_container` is whichever column shows, so everything
## that reads the open page through it, the row report, a note's place and the
## suites, reads that page alone. The shown column stands first under the
## margin, so a walk of the pane in tree order meets it before a hidden one.
##
## **A kept page enters the tree a few sections a frame** the first time it
## opens, [constant SLICE_NODES] controls a frame, the window's column measured
## again after each. Canvas and colour's 400 or so controls entering at once
## were 47 ms of a 120 ms frame on its first open, spread over the page's ten
## sections with none much dearer than another.
##
## A kept page goes when what it shows may have changed under it: a reset, a
## switch of language or of the font size, a page coming or going, a chord set
## somewhere else, and a tool, filter or command a module brought or took away.
## The page on screen is kept through a chord it set itself.
class_name SaSettingsKeptPages
extends RefCounted

## How many controls a first opening adds to the tree in one frame, the first
## section always. About 20 ms of entering on the machine it was timed on.
const SLICE_NODES := 120
## Marks a column kept off the screen, whose rows the search passes over, since
## the search walks the whole pane and would otherwise mark a row of a page that
## is not open.
const HIDDEN_META := &"sa_kept_hidden"

## The window's own column, which holds every page that is not kept and is
## emptied when a kept page shows.
var plain: VBoxContainer

## The column on screen, `plain` or a kept page's.
var shown: VBoxContainer

## Where the columns stand, the window's `ContentMargin`.
var _margin: Control

## The window, for the three registries the Keyboard shortcuts page names a
## command from.
var _registries: Callable

## Each kept page's column, by its title in the sidebar.
var _columns: Dictionary[String, VBoxContainer] = {}

## How many kept columns were made, for a suite counting builds.
var made: int = 0

## The page a first opening is still adding, and its sections still off the
## tree, in order.
var _arriving: Control = null
var _waiting: Array[Node] = []
## Every section of the arriving page in the page's order, so one a landing
## brought early and the ones after it each find their place.
var _order: Array[Node] = []


## *registries* hands back the registries the window holds as a page opens,
## since one the window was handed after it was built is in hand only then.
func _init(margin: Control, plain_column: VBoxContainer, registries: Callable) -> void:
    _registries = registries
    _margin = margin
    plain = plain_column
    shown = plain_column
    EventBus.shortcuts_changed.connect(drop_hidden)
    # A kept page was measured at the font it was built at.
    EventBus.ui_font_scale_changed.connect(drop_hidden.unbind(1))


## Frees the sections a page never received when the window goes before it
## had all arrived, since a node off the tree is never freed by anyone else.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        for child: Node in _waiting:
            if is_instance_valid(child):
                child.free()


## Whether the page titled *title* is built once and kept.
static func keeps(title: String) -> bool:
    return SaBuiltinPages.KEPT_PAGES.has(title)


## The column the page titled *title* was kept in, or null when it has none
## yet or is no kept page.
func column_of(title: String) -> VBoxContainer:
    var column: VBoxContainer = _columns.get(title)
    return column if is_instance_valid(column) else null


## The column a page titled *title* is drawn in: a new kept one when *fresh*
## is a page just built that is kept, and the plain one otherwise.
func column_for(title: String, fresh: bool) -> VBoxContainer:
    return make_column(title) if fresh and keeps(title) else plain


## A new, empty column for the page titled *title*, hidden until it is brought
## forward. The registries the page reads its names from are heard from now on.
func make_column(title: String) -> VBoxContainer:
    var column := SaMake.column(_margin, "Kept" + title.to_pascal_case(), 10)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.visible = false
    _columns[title] = column
    made += 1
    for registry: Object in _registries.call():
        if registry != null and not registry.is_connected(&"changed", drop_hidden):
            registry.connect(&"changed", drop_hidden)
    return column


## Shows *column* in place of the one on screen and hands it back. A kept
## column that goes off screen is hidden, and the plain one is emptied, its
## page freed a frame later the way a page has always been, because the request
## that switched may come from a press inside it.
func bring_forward(column: VBoxContainer) -> VBoxContainer:
    if column != plain:
        _empty_plain()
    if shown != column:
        shown.visible = false
        shown.set_meta(HIDDEN_META, true)
    column.visible = true
    column.remove_meta(HIDDEN_META)
    shown = column
    if column.get_index() != 0:
        _margin.move_child(column, 0)
    return column


## Adds *page*, fresh, to the column on screen: its first sections now and the
## rest a slice a frame after, the column measured again after each slice. The
## window measures it after this returns.
func arrive(page: Control) -> void:
    finish_arriving()
    if shown == plain:
        plain.add_child(page)
        return
    var budget := SLICE_NODES
    var first := true
    _order = page.get_children()
    for child: Node in _order:
        var cost := _cost(child)
        if not _waiting.is_empty() or (not first and cost > budget):
            page.remove_child(child)
            _waiting.append(child)
        else:
            budget -= cost
        first = false
    shown.add_child(page)
    if not _waiting.is_empty():
        _arriving = page
        # A window off the tree, a suite's, has no frames to arrive in.
        if not page.is_inside_tree():
            finish_arriving()
            return
        page.get_tree().process_frame.connect(_next_slice)


## Whether a page is still arriving.
func is_arriving() -> bool:
    return not _waiting.is_empty()


## Every section still waiting added now, for a door landing on a row of one,
## and a suite that reads the whole page.
func finish_arriving() -> void:
    if _waiting.is_empty():
        return
    _add_slice(-1)


## The waiting section holding *line*, a row a door landed on, added now in
## its place, so the landing finds it in the tree. The sections before it and
## after it still arrive a slice a frame, each in its own place. The window
## measures the column after this.
func arrive_through(line: Node) -> void:
    if not is_instance_valid(_arriving):
        return
    for child: Node in _waiting:
        if child == line or child.is_ancestor_of(line):
            _waiting.erase(child)
            _place(child)
            break
    if _waiting.is_empty():
        _stop_arriving()


## Adds *child* to the arriving page after every section that comes before it
## on the page and is there already.
func _place(child: Node) -> void:
    var at := 0
    for other: Node in _order:
        if other == child:
            break
        if other.get_parent() == _arriving:
            at += 1
    _arriving.add_child(child)
    _arriving.move_child(child, at)


## Brings in what an open lands on and answers whether it brought anything: the
## rows when a search is typed, and otherwise the row keyed *row* when the shown
## page has not drawn it into the tree yet. A page still arriving has declared
## a row before it has drawn it.
func land(row: StringName, searching: bool) -> bool:
    if not searching:
        var line := _row_line(row)
        if row.is_empty() or (line != null and line.is_inside_tree()):
            return false
    bring_in(row, searching)
    return true


## What a landing needs on screen before it marks: the section holding the row
## keyed *row* when the page declared it, and otherwise, or when a search is
## typed and *everything* is asked for, every section. The rows a page as big
## as Keyboard shortcuts builds a slice a frame are built now only when the row
## is still not there, or for *everything*.
func bring_in(row: StringName, everything: bool) -> void:
    var line := _row_line(row)
    if line != null and not everything:
        arrive_through(line)
    else:
        finish_arriving()
    line = _row_line(row)
    if everything or line == null or not line.is_inside_tree():
        for node: Node in shown.find_children("*", "", true, false):
            if node.has_method(&"fill_now"):
                node.call(&"fill_now")


func _row_line(row: StringName) -> Node:
    return SaSettingsSearch.row_line(shown, row) if not row.is_empty() else null


func _next_slice() -> void:
    _add_slice(SLICE_NODES)


func _add_slice(budget: int) -> void:
    if not is_instance_valid(_arriving):
        _stop_arriving()
        return
    var first := true
    while not _waiting.is_empty() and (budget < 0 or first or _cost(_waiting[0]) <= budget):
        var child: Node = _waiting.pop_front()
        budget -= _cost(child)
        _place(child)
        first = false
    var column := _arriving.get_parent() as Control
    if column != null:
        SaSettingsRows.measure(column)
    if _waiting.is_empty():
        _stop_arriving()


## The controls *node* adds to the tree, itself and everything under it.
static func _cost(node: Node) -> int:
    return 1 + node.find_children("*", "", true, false).size()


## Lets go of a page that went before it had all arrived, freeing what never
## reached it, since a node off the tree is never freed by anyone else.
func _stop_arriving() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null and tree.process_frame.is_connected(_next_slice):
        tree.process_frame.disconnect(_next_slice)
    for child: Node in _waiting:
        child.free()
    _waiting.clear()
    _order.clear()
    _arriving = null


## Every kept column but the one on screen goes, freed a frame later.
func drop_hidden() -> void:
    for title: String in _columns.keys():
        var column := _columns[title]
        if column != shown:
            _columns.erase(title)
            if is_instance_valid(_arriving) and column.is_ancestor_of(_arriving):
                _stop_arriving()
            _free(column)


## Every kept column goes, the one on screen as well, which hands the screen
## back to the plain column, which it hands back for the caller to draw the
## page in again.
func drop_all() -> VBoxContainer:
    if shown != plain:
        bring_forward(plain)
    drop_hidden()
    return plain


func _empty_plain() -> void:
    for child: Node in plain.get_children():
        plain.remove_child(child)
        child.call_deferred("free")


static func _free(column: Node) -> void:
    if not is_instance_valid(column):
        return
    if column.get_parent() != null:
        column.get_parent().remove_child(column)
    column.call_deferred("free")
