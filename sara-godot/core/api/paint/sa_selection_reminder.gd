## Tells the painter, once, that a selection they seem to have forgotten is on.
##
## An empty selection paints everywhere, but a painter who strokes while a
## selection is active and lays nothing inside it sees the pen do nothing. The
## status line says why through `SaStrokeNote`, in a corner a painter watching the
## pen does not look at, so this puts the same fact in the notice at the
## canvas's bottom centre with the way out, Select None and its key.
##
## Once per selection. The selection told about is kept, and its `changed`
## signal, which every new, grown, cut or dropped selection emits, arms the
## reminder again. A stroke that lays any paint inside says nothing and leaves
## the reminder as it was, so the painter who has just been told and goes on
## painting outside on purpose is not told twice.
##
## Not for a stroke that lands near the selection, where the notice would only
## annoy. A painter who sweeps just past the edge
## knows the selection is there, so the reminder speaks only when the stroke's
## painted bounds lie farther from the selection's bounds than [method margin],
## and a stroke inside that margin leaves it armed for one clearly away.
##
## In `core`, so it names no `ui`: the line goes out on `EventBus.corner_notice`,
## which `SaMessage` shows as the notice.
class_name SaSelectionReminder
extends RefCounted

## The line, with the chord Select None answers to now.
const LINE := "A selection is on and this stroke fell outside it. Select None (%s) drops it."

## The line when Select None has no key, which a painter can unbind.
const LINE_NO_KEY := "A selection is on and this stroke fell outside it. Select None in the Select menu drops it."

## The command whose key the line names, read from the shortcut store.
const SELECT_NONE := &"select_none"

## How near is near, in logical pixels on screen at the zoom the stroke ended
## at, because near is what the painter sees.
const NEAR_ON_SCREEN := 96.0

## The selections the reminder spoke about and that have not changed since,
## by their instance id, each held weakly so a closed document's selection is
## not kept alive by it. One for every document, because a word spoken about
## one document's selection says nothing about another's. A selection with no
## entry, or a reference gone dead, is armed.
static var _told_for: Dictionary[int, WeakRef] = {}


## Called at a stroke's end with whether the status line's reason for it is
## that every dab fell outside the selection, the stroke's *painted* bounds in
## document pixels and the *near* margin in document pixels. Speaks when
## *document*'s selection is active, holds something, lies farther than *near*
## from *painted* and has not been spoken about since it changed.
static func after_stroke(document: SaDocument, outside: bool, painted: Rect2i = Rect2i(), near: float = 0.0) -> void:
    if not outside or document == null or document.selection == null:
        return
    var selection := document.selection
    if not selection.active or selection.editing:
        return
    var box := selection.bounds
    if box.size.x <= 0 or box.size.y <= 0:
        return
    if distance(painted, box) <= near:
        return
    var id := selection.get_instance_id()
    var told: WeakRef = _told_for.get(id, null)
    if told != null and told.get_ref() == selection:
        return
    for gone: int in _told_for.keys():
        if _told_for[gone].get_ref() == null:
            _told_for.erase(gone)
    _told_for[id] = weakref(selection)
    var arm := _arm.bind(id)
    if not selection.changed.is_connected(arm):
        selection.changed.connect(arm, CONNECT_ONE_SHOT)
    EventBus.corner_notice.emit(line())


## The margin in document pixels for a stroke ended at *zoom*, screen pixels
## per document pixel, with a brush *diameter* in document pixels: the larger
## of [constant NEAR_ON_SCREEN] turned into document pixels and the diameter.
static func margin(zoom: float, diameter: float) -> float:
    var on_canvas := NEAR_ON_SCREEN / zoom if zoom > 0.0 else NEAR_ON_SCREEN
    return maxf(on_canvas, diameter)


## The gap in document pixels between rectangles *a* and *b*, zero where they
## touch or overlap. An empty *a*, a stroke that painted nothing, is never near.
static func distance(a: Rect2i, b: Rect2i) -> float:
    if a.size.x <= 0 or a.size.y <= 0:
        return INF
    var gap_x := maxi(0, maxi(b.position.x - a.end.x, a.position.x - b.end.x))
    var gap_y := maxi(0, maxi(b.position.y - a.end.y, a.position.y - b.end.y))
    return Vector2(gap_x, gap_y).length()


## The sentence, translated, with the first chord Select None answers to.
static func line() -> String:
    var chords := SaShortcutStore.chords_for(SELECT_NONE)
    if chords.is_empty():
        return TranslationServer.translate(LINE_NO_KEY)
    return TranslationServer.translate(LINE) % chords[0]


## The selection with the instance id *id* changed, so the next stroke outside
## it is worth a word again.
static func _arm(id: int) -> void:
    _told_for.erase(id)
