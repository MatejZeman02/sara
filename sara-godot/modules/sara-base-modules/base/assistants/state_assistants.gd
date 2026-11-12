## The Assistants tool: a drag on empty canvas places a ruler or a parallel
## ruler from the press to the release, and a press places a vanishing point
## where the release lets it go. A drag on a handle moves that handle, and a
## drag on a ruler between its handles moves the whole ruler. An ellipse is
## placed by a drag along one axis, its third handle sets the other, and a
## drag on its curve moves it whole. Each is one history step, laid at the
## release. Delete Assistant on the tool's options takes the assistant last
## placed or moved away, Delete All every assistant, each one step as well. The
## Concentric switch is the picked ellipse's own, and an ellipse placed next
## takes it as it stands.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The assistant moves on the canvas while the hand drags it, written into the
## document with no step, and the release writes the one step from what the
## press found to what the release leaves. Escape puts back what the press
## found, and so does a switch of tools with the pen down.
extends ToolState

## How near a handle or the ruler a press has to land to take it, in screen
## pixels, the gradient's reach.
const HANDLE_REACH: float = 10.0
## How long a drag on empty canvas has to be to place a ruler or a parallel
## ruler, in screen pixels. A click places neither, and places a vanishing
## point.
const SHORTEST: float = 4.0

## What a drag moves.
## C is an ellipse's third handle, the end of its other axis.
enum Drag { NONE, NEW, A, B, C, WHOLE }
## What a press on empty canvas places, the Assistant row's choices.
enum Shape { RULER, VANISHING, PARALLEL, ELLIPSE }

## The shape each choice writes into the document's entry.
const SHAPE_NAMES: Array[StringName] = [SaAssistants.RULER, SaAssistants.VANISHING, SaAssistants.PARALLEL, SaAssistants.ELLIPSE]
## Each shape's history steps, written out so the message template finds them.
const PLACE_STEPS: Dictionary[StringName, String] = {
    SaAssistants.RULER: "Place Ruler",
    SaAssistants.VANISHING: "Place Vanishing Point",
    SaAssistants.PARALLEL: "Place Parallel Ruler",
    SaAssistants.ELLIPSE: "Place Ellipse",
}
const MOVE_STEPS: Dictionary[StringName, String] = {
    SaAssistants.RULER: "Move Ruler",
    SaAssistants.VANISHING: "Move Vanishing Point",
    SaAssistants.PARALLEL: "Move Parallel Ruler",
    SaAssistants.ELLIPSE: "Move Ellipse",
}

## The Snap switch and Show Assistants, which the machine hands the tool as its
## shared settings and the options bar writes.
var settings: Resource = null
## What a press on empty canvas places, a [enum Shape], which the options bar
## writes.
var shape: int = Shape.RULER
## Whether the picked ellipse holds strokes to the ellipses inside and around
## it, and so whether the next placed ellipse will. Turning it writes the
## picked ellipse as one step.
var concentric: bool = false:
    set(value):
        concentric = value
        _make_concentric(value)

var _drag: Drag = Drag.NONE
## The assistant the drag moves, by its place in the document's list.
var _index: int = -1
## The assistant Delete Assistant takes, by its place in the list, or -1 for
## none.
var _picked: int = -1
## The list as the press found it, which the release's step undoes to.
var _before: Array = []
var _press_at: Vector2 = Vector2.ZERO
var _from: SaAssistants.Guide = null
## The ellipse a drag on one took or places, in place of [member _from].
var _ellipse: SaAssistants.Ellipse = null


func handle_input(event: InputEvent) -> void:
    var doc := document()
    if doc == null:
        return
    var key := event as InputEventKey
    if key != null:
        if key.pressed and key.keycode == KEY_ESCAPE and _drag != Drag.NONE:
            _cancel(doc)
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(doc, get_document_mouse_position())
        elif _drag != Drag.NONE:
            _release(doc, get_document_mouse_position())
        return
    if event is InputEventMouseMotion and _drag != Drag.NONE:
        _move(doc, get_document_mouse_position())


func reset() -> void:
    var doc := document()
    if _drag != Drag.NONE and doc != null:
        _cancel(doc)
    _drag = Drag.NONE


func get_cursor_radius() -> float:
    return -1.0


## Takes the assistant last placed or moved out of the document as one step, and
## answers how many went, for the options bar's button.
func delete_picked() -> int:
    var doc := document()
    var list := SaAssistants.entries(doc)
    if doc == null or _picked < 0 or _picked >= list.size():
        return 0
    var after := list.duplicate(true)
    after.remove_at(_picked)
    _picked = -1
    SaAssistants.commit(doc, "Delete Assistant", list, after)
    return 1


## Takes every assistant out of the document as one step.
func delete_all() -> int:
    var doc := document()
    var list := SaAssistants.entries(doc)
    if doc == null or list.is_empty():
        return 0
    _picked = -1
    SaAssistants.commit(doc, "Delete All Assistants", list, [])
    return list.size()


func capture_report(_tool_name: StringName, _active: bool) -> Dictionary:
    return {
        "assistants":
        {
            "entries": SaAssistants.entries(document()),
            "picked": _picked,
            "snap": _snap(),
            "shape": shape,
            "concentric": concentric
        }
    }


func _snap() -> bool:
    return settings != null and bool(settings.get("snap"))


## The press: a handle, a ruler's line or an ellipse's curve, or empty
## canvas, which begins a new assistant of the [member shape] in hand. The
## list is walked by its entries, so a place found is the entry's own whatever
## shapes stand before it.
func _press(doc: SaDocument, at: Vector2) -> void:
    _before = SaAssistants.entries(doc).duplicate(true)
    _press_at = at
    var reach := HANDLE_REACH / maxf(surface.view.get_zoom() if surface != null and surface.view != null else 1.0, 0.01)
    _drag = Drag.NONE
    # The handles before the lines, and the assistant drawn last first, so a
    # handle on another assistant's line is still the handle a press takes.
    for index in range(_before.size() - 1, -1, -1):
        var guide := SaAssistants.Guide.of(_before[index])
        if guide != null:
            if at.distance_to(guide.a) <= reach:
                _take(index, guide, Drag.A)
                return
            if at.distance_to(guide.b) <= reach:
                _take(index, guide, Drag.B)
                return
            continue
        var ellipse := SaAssistants.Ellipse.of(_before[index])
        if ellipse == null:
            continue
        var handles := ellipse.handles()
        for handle in handles.size():
            if at.distance_to(handles[handle]) <= reach:
                _take_ellipse(index, ellipse, [Drag.A, Drag.B, Drag.C][handle])
                return
    for index in range(_before.size() - 1, -1, -1):
        var guide := SaAssistants.Guide.of(_before[index])
        if guide != null and guide.segment_distance(at) <= reach:
            _take(index, guide, Drag.WHOLE)
            return
        var ellipse := SaAssistants.Ellipse.of(_before[index])
        if ellipse != null and ellipse.holds() and ellipse.distance(at) <= reach:
            _take_ellipse(index, ellipse, Drag.WHOLE)
            return
    var list := _before.duplicate(true)
    var named := SHAPE_NAMES[clampi(shape, 0, SHAPE_NAMES.size() - 1)]
    if named == SaAssistants.ELLIPSE:
        var placed_ellipse := SaAssistants.Ellipse.placed(at, at, concentric)
        list.append(placed_ellipse.entry())
        _take_ellipse(list.size() - 1, placed_ellipse, Drag.NEW)
    else:
        var placed := SaAssistants.Guide.new(at, at, named)
        list.append(placed.entry())
        _take(list.size() - 1, placed, Drag.NEW)
    SaAssistants.keep(doc, list)


func _take(index: int, ruler: SaAssistants.Guide, drag: Drag) -> void:
    _index = index
    _drag = drag
    _ellipse = null
    _from = SaAssistants.Guide.new(ruler.a, ruler.b, ruler.shape)


## Takes *ellipse* for a drag, picked at once so the Concentric row shows its
## switch. The row is written while the drag holds, which writes no step.
func _take_ellipse(index: int, ellipse: SaAssistants.Ellipse, drag: Drag) -> void:
    _index = index
    _drag = drag
    _from = null
    _ellipse = ellipse
    _picked = index
    concentric = ellipse.concentric


## The assistant as the drag has it at *at*, written with no step. A
## vanishing point's one handle moves whatever the drag took.
func _move(doc: SaDocument, at: Vector2) -> void:
    var by := at - _press_at
    if _ellipse != null:
        _write(doc, _moved_ellipse(by).entry())
        return
    var moved := SaAssistants.Guide.new(_from.a, _from.b, _from.shape)
    if moved.shape == SaAssistants.VANISHING:
        moved = SaAssistants.Guide.new(_from.a + by, _from.a + by, moved.shape)
    else:
        _moved(moved, by)
    _write(doc, moved.entry())


## Writes *entry* in place of the assistant the drag holds, with no step.
func _write(doc: SaDocument, entry: Dictionary) -> void:
    var list := SaAssistants.entries(doc).duplicate(true)
    if _index >= 0 and _index < list.size():
        list[_index] = entry
        SaAssistants.keep(doc, list)


## The ellipse the drag in hand makes of the one it took, moved by *by*.
func _moved_ellipse(by: Vector2) -> SaAssistants.Ellipse:
    match _drag:
        Drag.NEW:
            return SaAssistants.Ellipse.placed(_ellipse.a, _ellipse.b + by, concentric)
        Drag.A, Drag.B, Drag.C:
            var handle := [Drag.A, Drag.B, Drag.C].find(_drag)
            return _ellipse.with_handle(handle, _ellipse.handles()[handle] + by)
    return _ellipse.shifted(by)


## Moves *moved*'s handles by *by* as the drag in hand asks, a two handled
## assistant's.
func _moved(moved: SaAssistants.Guide, by: Vector2) -> void:
    match _drag:
        Drag.NEW, Drag.B:
            moved.b = _from.b + by
        Drag.A:
            moved.a = _from.a + by
        Drag.WHOLE:
            moved.a = _from.a + by
            moved.b = _from.b + by


## The release lays the drag as one step, and a click on empty canvas lays
## nothing but a vanishing point.
func _release(doc: SaDocument, at: Vector2) -> void:
    _move(doc, at)
    var drag := _drag
    _drag = Drag.NONE
    var zoom := maxf(surface.view.get_zoom() if surface != null and surface.view != null else 1.0, 0.01)
    var kind_of := SaAssistants.ELLIPSE if _ellipse != null else _from.shape
    if drag == Drag.NEW and kind_of != SaAssistants.VANISHING and at.distance_to(_press_at) * zoom < SHORTEST:
        SaAssistants.keep(doc, _before)
        return
    var after := SaAssistants.entries(doc)
    _picked = _index
    if after == _before:
        return
    SaAssistants.commit(doc, PLACE_STEPS[kind_of] if drag == Drag.NEW else MOVE_STEPS[kind_of], _before, after)


## Writes the Concentric switch onto the picked ellipse as one step, and
## nothing when no ellipse is picked, a drag holds, or it already says so.
func _make_concentric(rings: bool) -> void:
    var doc := document()
    var list := SaAssistants.entries(doc)
    if doc == null or _drag != Drag.NONE or _picked < 0 or _picked >= list.size():
        return
    var ellipse := SaAssistants.Ellipse.of(list[_picked])
    if ellipse == null or ellipse.concentric == rings:
        return
    ellipse.concentric = rings
    var after := list.duplicate(true)
    after[_picked] = ellipse.entry()
    SaAssistants.commit(doc, "Concentric Ellipse" if rings else "Plain Ellipse", list, after)


## Puts back what the press found.
func _cancel(doc: SaDocument) -> void:
    _drag = Drag.NONE
    SaAssistants.keep(doc, _before)
