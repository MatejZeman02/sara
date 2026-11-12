## Draws a layer list's rows again keeping every row that still stands, for
## every change the keeper draws: a group folded or opened, a layer made active,
## added, deleted or dropped, and a reorder.
##
## Building a row is its eye, its picture, its locks and the theme bound to
## each, a few milliseconds a row, and a new row's picture waits out the
## thumbnail's interval, so building every row of the stack on a fold makes
## the fold slow and its pictures late. Here a
## row whose layer or filter is still drawn is moved to its
## new place and renumbered, so only the rows a fold brings back or a new layer
## asks for are built, their pictures drawn at once, and every other picture
## stays as it was. A layer moved into or out of a group keeps its row,
## indented again.
##
## The keeper decides what is drawn, as it does for a rebuild, and takes the
## pick and the fold marks over afterwards. This file owns the rows' order.
class_name SaLayerRowReuse
extends RefCounted


## Makes *list*'s rows the ones *wanted* names, top first, and answers whether
## it could. An entry is `[layer, depth]` for a layer's row and `[record, node,
## title, depth]` for a filter's, *depth* being the node's own and -1 for the
## document's root. A row open for renaming answers false, because the field
## belongs to the row it was opened on, and the keeper builds every row again.
## The pick is emptied, its rows counted again, for the keeper to fill. Every
## row built anew is added to *fresh*, for the keeper to connect.
static func rebuild(
    list: SaLayerList, wanted: Array, fresh: Array = [], worn: Array = [], stood: Dictionary = {}, matched: Array = []
) -> bool:
    if list.renaming_row() != -1:
        return false
    var standing := stood.duplicate() if not stood.is_empty() else standing_rows(list)
    var known := not stood.is_empty() and matched.size() == wanted.size()
    var leaving: Array[SaRowFrame] = []
    for row: SaRowFrame in list.rows:
        if row.record == null and not row.has_layer():
            leaving.append(row)
    var built: Array[SaRowFrame] = []
    for index in wanted.size():
        var entry: Array = wanted[index]
        var row: SaRowFrame = matched[index] if known else standing_row(standing, entry)
        if row != null:
            standing.erase(entry[0])
            if entry.size() == 2 and row.indent_depth != entry[1]:
                row.reindent(entry[1])
            if row.lit or row.target:
                worn.append(row)
        else:
            var built_from := Time.get_ticks_usec()
            row = _build(list, entry)
            # The row's own build is counted against the pictures' share, so a
            # part of a deep open's rows draws only what the frame has left,
            # and the rest of its pictures in the frames after.
            SaLayerThumbnail.spend(Time.get_ticks_usec() - built_from)
            fresh.append(row)
            # A new picture waits out the thumbnail's interval before it draws,
            # which would leave an opened group's rows bare for a moment.
            SaLayerThumbnail.settle_new(row)
        built.append(row)
    leaving.append_array(standing.values())
    # The last first, since a child taken from the end moves no sibling, and
    # the 756 rows an open let go of in their own order cost 27 ms.
    leaving.sort_custom(func(a: SaRowFrame, b: SaRowFrame) -> bool: return a.get_index() > b.get_index())
    for row: SaRowFrame in leaving:
        let_go(list, row)
    _place(list, built, fresh)
    list.picked.reset()
    for row: SaRowFrame in built:
        list.picked.row_added(row is SaFilterRowView)
    return true


## The rows of *list* that still draw something, by the layer or the record
## each draws. A row whose layer was freed is not among them.
static func standing_rows(list: SaLayerList) -> Dictionary:
    var standing := {}
    for row: SaRowFrame in list.rows:
        if row.record != null or row.has_layer():
            standing[row.record if row.record != null else (row.layer as Object)] = row
    return standing


## Draws the look of *worn*, the rows [method rebuild] kept lit or as the
## target, for the pick the keeper has just put back. The pick restyles only
## the rows it touched, and a kept row may still wear the look of the pick
## before the fold, which only a row drawn lit or as the target can.
## The whole sync since *since*, in [method Time.get_ticks_usec], is counted
## against the pictures' share of the frame, so a frame that built hundreds of
## rows, or refreshed the rows a step touched, leaves the pictures to the
## frames after rather than drawing them on top.
static func restyle(worn: Array, since: int) -> void:
    for row: SaRowFrame in worn:
        if is_instance_valid(row):
            row.style(SaLayerList.Drop.NONE)
    SaLayerThumbnail.spend(Time.get_ticks_usec() - since)


## The row of *standing* that can draw *entry*, or null when none can and the
## entry's row is built anew.
static func standing_row(standing: Dictionary, entry: Array) -> SaRowFrame:
    var row: SaRowFrame = standing.get(entry[0])
    if row == null:
        return null
    # A layer's entry is asked here rather than through [method _fits], because
    # a sync asks it of every row and the call was a third of the asking.
    if entry.size() == 2:
        return row if row.record == null and row.is_group == (entry[0] as SaLayer).is_group else null
    return row if _fits(row, entry) else null


## Whether *row* can draw *entry*: the same kind of row, and for a filter the
## same node, title and indent. A layer's row at another indent is kept and
## indented again.
static func _fits(row: SaRowFrame, entry: Array) -> bool:
    if entry.size() == 2:
        var layer: SaLayer = entry[0]
        return row.record == null and row.is_group == layer.is_group
    var filter_row := row as SaFilterRowView
    return (
        filter_row != null
        and filter_row.node == entry[1]
        and filter_row.filter_title == String(entry[2])
        and row.indent_depth == int(entry[3]) + SaFilterRowView.EXTRA_DEPTH
    )


## A new row for *entry*, added at the bottom of *list* and moved into place by
## [method _place].
static func _build(list: SaLayerList, entry: Array) -> SaRowFrame:
    if entry.size() == 2:
        var layer: SaLayer = entry[0]
        list.add_item(layer.shown_name(), int(entry[1]), layer.is_group, layer)
    else:
        list.add_filter_item(entry[0], entry[1], String(entry[2]), int(entry[3]))
    return list.rows[-1]


## Puts *rows* in the list in their order. Only a row whose place changed, or
## one *fresh* to the list, is moved and renamed, because a rename tells every
## node of the row its path changed, 4 us a row, and a layer added to the
## large test document's 593 rows renamed every one of them twice. A row takes a
## passing name first only where its new one is still another's.
static func _place(list: SaLayerList, rows: Array[SaRowFrame], fresh: Array) -> void:
    list.rows.clear()
    list.rows.append_array(rows)
    var moved: Array[int] = []
    for i: int in rows.size():
        var row := rows[i]
        if row.get_index() != i:
            list.vbox.move_child(row, i)
        if row.row_index != i or fresh.has(row):
            moved.append(i)
    # A layer added shifts the rows under it down, which the bottom one first
    # renames into a free name each, and one deleted shifts them up, which the
    # top one first does. What either order leaves is named twice.
    var left: Array[int] = []
    for i: int in moved:
        left.push_front(i)
    for order in 2:
        var still: Array[int] = []
        for i: int in left:
            var holder := list.vbox.get_node_or_null(NodePath(_name_at(rows[i], i)))
            if holder != null and holder != rows[i]:
                still.append(i)
            else:
                rows[i].renumber(i)
        still.reverse()
        left = still
    for i: int in left:
        rows[i].name = "%s_moving_%d" % [String(rows[i].name).get_slice("_", 0), i]
    for i: int in left:
        rows[i].renumber(i)


## The name *row* takes at *index*, as [method SaRowFrame.renumber] gives it.
static func _name_at(row: SaRowFrame, index: int) -> String:
    return "%s_%d" % [String(row.name).get_slice("_", 0), index]


## Takes *row* out of *list* at once and frees it a share a frame after,
## [Reaper]. Freed at the frame's end, the 756 rows an open of a large test document
## let go of held that frame for 0.2 s.
static func let_go(list: SaLayerList, row: Node) -> void:
    # A list outside the tree has no frames to free a share in, so its rows go
    # at the frame's end as they always did.
    if not list.is_inside_tree():
        if row.get_parent() != null:
            row.get_parent().remove_child(row)
        row.queue_free()
        return
    var reaper := list.get_node_or_null(NodePath(Reaper.NAME)) as Reaper
    if reaper == null:
        reaper = Reaper.new()
        reaper.name = Reaper.NAME
        list.add_child(reaper, false, Node.INTERNAL_MODE_BACK)
    reaper.take(row)


## The rows a list let go of, freed as many a frame as [constant BUDGET_USEC]
## holds. Held outside the tree, since a row moved under another node leaves
## the tree and enters it again, which cost 27 ms for a large test document's rows.
## A child of the list, so a row still waiting goes with the list.
class Reaper:
    extends Node

    const NAME := "LetGoRows"
    ## What freeing rows may spend in a frame, in microseconds.
    const BUDGET_USEC := 4000

    var _rows: Array[Node] = []

    func _init() -> void:
        set_process(false)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            for row in _rows:
                if is_instance_valid(row):
                    row.free()
            _rows.clear()

    ## Takes *row* out of the tree, to be freed in a frame to come.
    func take(row: Node) -> void:
        if row.get_parent() != null:
            row.get_parent().remove_child(row)
        _rows.append(row)
        set_process(true)

    func _process(_delta: float) -> void:
        var began := Time.get_ticks_usec()
        var traced := SaFrameTrace.now()
        while not _rows.is_empty() and Time.get_ticks_usec() - began < BUDGET_USEC:
            var row: Node = _rows.pop_back()
            if is_instance_valid(row):
                row.free()
        SaFrameTrace.spent("rows let go", traced)
        if _rows.is_empty():
            set_process(false)
