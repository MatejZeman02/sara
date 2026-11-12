## Which rows of the layers list are picked: the set, the active row, the
## anchor a Shift click measures from, and the one attached filter whose panel
## is open.
##
## Cut out of `layer_list.gd` as the index arithmetic that reads nothing of a
## row but whether it is a filter's. The list tells it each row as it is built,
## `row_added`, and empties it with `reset`, so it holds no reference to the
## list and none to a row. What it says back is `style_moved`, the indices whose
## look changed, and `filter_picked`, and the list restyles and relays from
## those.
class_name SaLayerPick
extends RefCounted

## The rows whose style a change moved, each index once.
signal style_moved(indices: Array[int])
## Another record was picked, or null when the pick was taken back.
signal filter_picked(record: SaAttachedFilter)

## The active row, the one a single-layer action reads, and the whole set around
## it. The set always holds the active row, so an action that reads the set and
## one that reads the active layer agree when only one row is picked, which is
## every gesture that is not a Ctrl or a Shift click.
var selected_idx: int = -1
var selection: Array[int] = []

## Where a Shift click measures from. The last row picked without Shift, which
## is what every list in every program anchors on.
var anchor: int = -1

## The one attached filter that is picked, or null. Its own mark rather than a
## share of `selection`, because the active layer stays the active layer while a
## filter's panel is open: the painter keeps painting under it. Kept by record
## and not by index, so it survives a rebuild.
var selected_record: SaAttachedFilter = null

## Whether the last plain press landed on a row of a set of several and kept the
## set for the drag it may begin, so the release lets the rest go.
var _held: bool = false

## One entry per row of the list, true where the row is a filter's.
var _filter_rows: Array[bool] = []


## *on_style* hears `style_moved` and *on_filter* `filter_picked`, for the list
## that holds this pick, so the list connects them without reaching in twice.
func _init(on_style: Callable = Callable(), on_filter: Callable = Callable()) -> void:
    if on_style.is_valid():
        style_moved.connect(on_style)
    if on_filter.is_valid():
        filter_picked.connect(on_filter)


## The list built one more row, a filter's or a layer's.
func row_added(is_filter: bool) -> void:
    _filter_rows.append(is_filter)


## The list dropped its rows. The picked record stays, because it is kept by
## record so that it survives exactly this.
func reset() -> void:
    _filter_rows.clear()
    selected_idx = -1
    selection.clear()
    anchor = -1


## One row, and nothing else. The plain click, and what the docker calls after
## it has rebuilt the list.
func select(idx: int) -> void:
    # A filter's row is picked by its record, never into the layer set, which is
    # what a right press on one would otherwise do.
    if _is_filter(idx):
        return
    anchor = idx
    _set_selection([idx] if idx >= 0 else [], idx)


## Ctrl click: the row joins the set, or leaves it if it was already in.
## Removing the active row hands the active mark to whatever is left.
##
## The anchor follows the active row rather than the clicked one, so a shift
## click after a removal ranges from a row that is still in the set.
func select_extra(idx: int) -> void:
    if idx < 0 or idx >= _filter_rows.size():
        return
    var wanted := selection.duplicate()
    if wanted.has(idx):
        wanted.erase(idx)
        var left: int = wanted[-1] if not wanted.is_empty() else -1
        anchor = left
        _set_selection(wanted, left)
        return
    anchor = idx
    wanted.append(idx)
    _set_selection(wanted, idx)


## Shift click: everything from the anchor to *idx*, the anchor included, and
## **the active row does not move**.
##
## The range is based on the active layer, not on the last row clicked. A
## shift click that marked the clicked row active would reach the document, the
## docker would rebuild its rows, and `restore` would put the anchor back at
## the row just clicked, so the range's base would walk forward with every
## shift click. Leaving the active row alone closes that loop at its source:
## the anchor and the active row are the same row, and a rebuild that
## re-derives one from the other cannot move either.
func select_to(idx: int) -> void:
    if idx < 0 or idx >= _filter_rows.size():
        return
    var from: int = anchor if anchor >= 0 else idx
    var wanted: Array[int] = []
    for i in range(mini(from, idx), maxi(from, idx) + 1):
        wanted.append(i)
    _set_selection(wanted, from)


## A left press on a layer's row, and the row that is active after it, which is
## what the list announces. Ctrl adds one row, Shift takes the run to it, and a
## plain press is the one row it always was. Any of the three hands the pick
## back from a filter.
##
## The active row is not always the pressed one: a shift click leaves it where
## it was, and a ctrl click that removes it hands the mark to another.
##
## A Ctrl click while a filter holds the pick never takes a row out of the set.
## The set is drawn as the target then, not lit, so a Ctrl click that toggled
## the target row out would take a row the painter never saw picked, leave
## nothing lit, and let the minus fall back on the active layer unseen. That
## click keeps the row in and makes it active, and the set is lit again with
## the filter's row dark.
##
## *for_drag* is the list's own press, which arms a drag. A plain press on a row
## of a set of several then keeps the set, the pressed row made active, so a
## drag carries every picked row, and `let_go` at a release that dragged nothing
## leaves the pressed row alone, as a plain click does.
func press(idx: int, ctrl: bool, shift: bool, for_drag: bool = false) -> int:
    var from_filter := selected_record != null
    pick_filter(null)
    _held = false
    if for_drag and not ctrl and not shift and not from_filter and selection.size() > 1 and selection.has(idx):
        _held = true
        anchor = idx
        _set_selection(selection.duplicate(), idx)
    elif ctrl and from_filter and selection.has(idx):
        anchor = idx
        _set_selection(selection.duplicate(), idx)
    elif ctrl:
        select_extra(idx)
    elif shift:
        select_to(idx)
    else:
        select(idx)
    return selected_idx


## The release of a plain press that `press` held the set for and that dragged
## nothing: the pressed row, active since the press, is picked alone. Answers
## that row, which the list announces as a press so every list on the document
## follows, or -1 when the press held nothing.
func let_go() -> int:
    if not _held:
        return -1
    _held = false
    select(selected_idx)
    return selected_idx


## A press with Ctrl on a layer's own thumbnail, *picture* `&"layer"`, makes
## the layer's alpha the selection: Ctrl replaces it, Ctrl and
## Shift add to it, Ctrl and Alt take from it, and all three keep what both
## hold, `SaSelectOpaque` doing the work. Answers whether the press was that one, and then the list goes no
## further: the picked rows, the active layer and the brush's target stay as
## they were and no drag is armed, whether or not the layer held any paint.
##
## Anywhere else on the row, the mask's thumbnail included, and on a group's
## row, the answer is false and the press is the row's as it always was.
static func select_opaque(document: SaDocument, layer: SaLayer, picture: StringName, ctrl: bool, shift: bool, alt: bool) -> bool:
    if not ctrl or picture != &"layer" or document == null or not SaSelectOpaque.takes(layer):
        return false
    SaSelectOpaque.new(document).select(layer, SaSelection.mode_for_press(SaSelection.Mode.REPLACE, shift, alt))
    return true


## The rows an eye or a lock pressed on row *idx* acts on: every picked row when
## *idx* is among them, and its own row otherwise. The rest of the set follows
## the pressed row, so a mixed set lands on one state.
##
## Two returns rather than a ternary, because a ternary hides the literal from
## the compiler and an untyped `Array` cannot fill an `Array[int]` at runtime.
## A one-liner would raise on every eye of a row outside the set, and that eye
## could not be clicked.
func acted_on(idx: int) -> Array[int]:
    if selection.has(idx):
        return selected_indices()
    return [idx]


## Whether row *idx* is lit: a filter's row by *record*, the one its row
## draws, and a layer's row by the set while no filter is picked.
##
## A filter's pick leaves the layer set as it is, so a filter's row and the
## active layer's row lit alike would read as two picked rows. While a filter
## is picked, a layer's row of the set is the target instead, `is_target`,
## drawn apart from a lit row.
func is_lit(idx: int, record: SaAttachedFilter) -> bool:
    if _is_filter(idx):
        return record == selected_record
    return selected_record == null and selection.has(idx)


## Whether row *idx* is a layer the painter keeps painting under while a
## filter's panel is open: a row of the set, which the pick of a filter does not
## light.
func is_target(idx: int) -> bool:
    return selected_record != null and not _is_filter(idx) and selection.has(idx)


## Whether row *idx* is the active one of several, which is drawn apart from
## the rest of the set. One picked row alone has nothing to stand apart from.
func leads(idx: int) -> bool:
    return idx == selected_idx and selection.size() > 1


## Every picked row, lowest first. The docker reads this rather than the rows.
func selected_indices() -> Array[int]:
    var out := selection.duplicate()
    out.sort()
    return out


## Puts the set back after a rebuild, from the indices the list found the
## picked layers at and the row of the active one.
##
## A set without the active layer is a set the operation replaced, a duplicate
## or a group, and it collapses to the active row. Adding the new active layer
## to the old set instead makes Duplicate duplicate twice, the set growing by
## one on every rebuild.
func restore(wanted: Array[int], active: int) -> void:
    if active >= 0 and not wanted.has(active):
        wanted = [active]
    anchor = active
    _set_selection(wanted, active)


## Picks *record*, or nothing for null, and says so. One record at a time.
func pick_filter(record: SaAttachedFilter) -> void:
    if record == selected_record:
        return
    selected_record = record
    # The filters' rows and the set's, which a pick turns from lit to target
    # and back.
    var moved: Array[int] = []
    for i in _filter_rows.size():
        if _filter_rows[i] or selection.has(i):
            moved.append(i)
    style_moved.emit(moved)
    filter_picked.emit(record)


func _is_filter(idx: int) -> bool:
    return idx >= 0 and idx < _filter_rows.size() and _filter_rows[idx]


func _set_selection(wanted: Array, active: int) -> void:
    var touched: Array[int] = selection.duplicate()
    touched.append(selected_idx)
    touched.append(active)
    selection.clear()
    for entry: Variant in wanted:
        var i := int(entry)
        # A filter's row is never part of the layer set, so a Shift run that
        # crosses one leaves it out.
        if i >= 0 and i < _filter_rows.size() and not selection.has(i) and not _filter_rows[i]:
            selection.append(i)
    if active >= 0 and active < _filter_rows.size() and not selection.has(active):
        selection.append(active)
    selected_idx = active
    touched.append_array(selection)
    var moved: Array[int] = []
    for i in touched:
        if i >= 0 and i < _filter_rows.size() and not moved.has(i):
            moved.append(i)
    style_moved.emit(moved)
