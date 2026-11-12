## The rows of Preferences > Keyboard Shortcuts under its Profile section, a
## column per group of commands, and the building of them: all at once, or on a
## page's first opening a slice a frame.
##
## All of them in one frame held 331 to 423 ms on every open when timed. A
## probe in the running app split the first open's 418 ms into 75 ms declaring
## and drawing the 312 rows, 175 ms of their two thousand or so controls
## entering the tree and about 120 ms of layout. The window keeps the page once
## built (`SaSettingsKeptPages`), so only the first opening pays, and this
## spreads that one over the frames after it: the first slices with the page,
## the rest under [constant FRAME_BUDGET_USEC] a frame.
##
## A group is drawn in parts of [constant PART_ROWS] rows, each a declared page
## of its own realized into a host of its own, because a declared page draws all
## its rows into its host at once. The first part carries the group's heading
## and the parts after it none, stacked in the group's column at the gap the
## rows of one section keep, so a group reads as one section.
##
## A page built off the tree, which is how the search indexes it and how a suite
## reads one, is built whole at once, since no frame would ever draw the rest.
class_name SaShortcutGroups
extends VBoxContainer

## What the door and the suites find the rows under.
const NODE_NAME := &"ShortcutRows"

## How many rows one part of a group holds.
const PART_ROWS := 8

## How long the parts built in one frame may take, entering the tree included.
## Layout comes after, about half as much again, so a frame of the fill stays
## near 25 ms on the machine it was timed on.
const FRAME_BUDGET_USEC := 6000

## The share of a spread fill built before the page enters the tree, building
## alone, which entering and layout make about five times as long in the frame
## the page opens in.
const FIRST_BUDGET_USEC := 3000

## Every part built so far, in order, each a declared page.
var parts: Array[SaPage] = []

## Each group's column by its title, what a search hides a group by.
var columns: Dictionary[String, VBoxContainer] = {}

## The groups still to build: `[title, row declarations, rows done]` each.
var _waiting: Array = []

## Called with the parts each slice built, and whether the fill is done.
var _built: Callable


func _init(built: Callable) -> void:
    name = NODE_NAME
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _built = built
    set_process(false)


## Builds a column per group of *groups*, `[title, [declaration, ...]]` each, a
## declaration being called with the section a row goes in. What was here goes.
## *spread* builds a first slice now and the rest a slice a frame once this is
## in the tree, and otherwise everything is built before this returns.
func fill(groups: Array, spread: bool) -> void:
    var live := is_inside_tree()
    for child: Node in get_children():
        remove_child(child)
        if live:
            child.queue_free()
        else:
            child.free()
    parts.clear()
    columns.clear()
    _waiting = []
    for group: Array in groups:
        _waiting.append([String(group[0]), group[1], 0])
    if spread:
        _build_within(FIRST_BUDGET_USEC)
        set_process(not _waiting.is_empty())
    else:
        fill_now()


## Builds every part still waiting, at once. What a door landing on a row of
## the page needs, and what a caller reading the whole page asks for.
func fill_now() -> void:
    set_process(false)
    _build_within(-1)


## Whether parts are still waiting to be built.
func is_filling() -> bool:
    return not _waiting.is_empty()


func _process(_delta: float) -> void:
    _build_within(FRAME_BUDGET_USEC)
    if _waiting.is_empty():
        set_process(false)


## Builds parts until *budget* microseconds have gone, at least one, or every
## part when *budget* is negative, and hands what it built to the page.
func _build_within(budget: int) -> void:
    if _waiting.is_empty():
        return
    var start := Time.get_ticks_usec()
    var made: Array[SaPage] = []
    while not _waiting.is_empty():
        made.append(_build_part(_waiting[0]))
        if int(_waiting[0][2]) >= (_waiting[0][1] as Array).size():
            _waiting.pop_front()
        if budget >= 0 and Time.get_ticks_usec() - start >= budget:
            break
    _built.call(made, _waiting.is_empty())
    if is_inside_tree():
        _widen_column(made)


## The Preferences column above the page measured again when a row of *made*,
## the parts that just arrived, has a title wider than the column the window
## measured before the row was there. A measure walks the whole page and sorts
## every row again, so it runs only then.
func _widen_column(made: Array[SaPage]) -> void:
    var walk := get_parent()
    while walk != null and not walk is Window and not walk.has_meta(SaSettingsRows.COLUMN_META):
        walk = walk.get_parent()
    if walk == null or walk is Window:
        return
    var column := int(walk.get_meta(SaSettingsRows.COLUMN_META))
    if column >= SaUI.px(SaSettingsRows.COLUMN_MAX):
        return
    for part: SaPage in made:
        for declared in part.rows():
            var title := declared.line.get_node_or_null(^"Labels/Title") as Label
            if title != null and ceili(SaSettingsRows.text_width(title)) > column:
                SaSettingsRows.measure(walk as Control)
                return


## The next part of *group*, declared, realized into a host of its own and
## added to the group's column, which the group's first part makes.
func _build_part(group: Array) -> SaPage:
    var title := String(group[0])
    var declarations: Array = group[1]
    var first := int(group[2])
    var slice := declarations.slice(first, first + PART_ROWS)
    group[2] = first + slice.size()
    var column: VBoxContainer = columns.get(title)
    if column == null:
        column = SaMake.column(null, "Group", SaTheme.GAP)
        add_child(column, true)
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        columns[title] = column
    var heading := title if first == 0 else ""
    var part := SaPage.new(
        func(ui: SaPage) -> void:
            var block := ui.section(heading)
            for declare: Callable in slice:
                declare.call(block)
    )
    part.declare_rows()
    var host := VBoxContainer.new()
    host.name = "Part"
    part.realize(host)
    column.add_child(host, true)
    parts.append(part)
    return part
