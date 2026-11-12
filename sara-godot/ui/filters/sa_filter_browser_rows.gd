## The order a search lists the filters it found in, and the double click on a
## browser's row, which the Filters browser and the Filter menu's search both
## stand on.
##
## **The order.** Each found row carries its `SaFilterMenu.rank`, the rows
## of a section are listed strongest first and a section whose best row is
## weaker comes after one whose best is stronger. Listed in the section's own
## order alone, "levels" put Equalize, found by its sentence, above Levels in
## Tone, and the first row a painter took added the wrong adjustment. Rows of
## one rank keep their section's order and sections of one best rank the
## registry's, so "blur" lists as the registry has it. Bucketed by rank rather than
## sorted, because `sort_custom` keeps no order among equals.
##
## **The double click** selects the row and presses what the browser's own
## button presses, Add Layer in the layer kind browser and Open in the Filters
## docker. A single click still only selects, which the row's `pressed` does.
class_name SaFilterBrowserRows
extends RefCounted


## *found*, sections in the registry's order, each a dictionary whose "rows"
## are its found rows in its own order and whose "ranks" are their ranks,
## answered in the order the search lists them. Every other field of a section
## is carried as it came.
static func order(found: Array[Dictionary]) -> Array[Dictionary]:
    var by_best: Dictionary[int, Array] = {}
    for section: Dictionary in found:
        var ranks: Array = section["ranks"]
        if ranks.is_empty():
            continue
        var sorted := section.duplicate()
        sorted["rows"] = _by_rank(section["rows"], ranks)
        sorted["ranks"] = _by_rank(ranks, ranks)
        var best: int = sorted["ranks"][0]
        if not by_best.has(best):
            by_best[best] = []
        by_best[best].append(sorted)
    var out: Array[Dictionary] = []
    for best: int in range(SaFilterMenu.RANK_STARTS, SaFilterMenu.RANK_NONE, -1):
        for section: Dictionary in by_best.get(best, []):
            out.append(section)
    return out


## *rows* listed by their *ranks*, strongest first, each rank in the order it
## came, and a row ranked none left out.
static func _by_rank(rows: Array, ranks: Array) -> Array:
    var out: Array = []
    for wanted: int in range(SaFilterMenu.RANK_STARTS, SaFilterMenu.RANK_NONE, -1):
        for at: int in rows.size():
            if int(ranks[at]) == wanted:
                out.append(rows[at])
    return out


## Makes a double click on *row* call *select* and then *open*, the way a
## press on the row and then on the browser's button would. The press goes on
## to the row as well and *open* waits for the end of the frame, so the
## release still finds the row on screen and its own `pressed` selects it
## again, which changes nothing, before the window the open answers with
## stands over it.
static func open_on_double_click(row: Button, select: Callable, open: Callable) -> void:
    row.gui_input.connect(func(event: InputEvent) -> void: _on_row_input(event, select, open))


static func _on_row_input(event: InputEvent, select: Callable, open: Callable) -> void:
    var click := event as InputEventMouseButton
    if click == null or not click.pressed or not click.double_click or click.button_index != MOUSE_BUTTON_LEFT:
        return
    select.call()
    open.call_deferred()
