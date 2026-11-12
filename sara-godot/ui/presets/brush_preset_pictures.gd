## The presets chooser's pictures still to come, drawn a few events a frame.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `brush_presets_chooser.gd` for the reason `SaBrushPresetStars` is: the
## chooser owns a grid and which filters it is under, `SaPresetThumbs` owns what
## a picture is, and this owns the queue in between and how much of a frame it
## may take. The chooser queues a name for every cell whose cached picture is
## stale and shows each picture this says is drawn.
##
## **The pictures under way are advanced a share a frame**, rather than a
## whole stroke each in a frame of its own. A fresh profile has no picture
## cached, and one stroke a frame drew the shipped presets at up to some
## hundreds of milliseconds apiece after Ready, frames the trail logs as a
## stall with no hand on the pen.
## **A picture whose tip is a file waits for the file.** A picture paints a dab,
## and a dab binds its tip, so a pipe preset's picture on a fresh profile would
## load the whole pipe inside that dab's frame, and a large shipped tip costs
## tens of milliseconds there. So the tip is loaded the way a chosen preset's
## is, `SaTipCache.load_ahead`, and the picture starts once it is on the card.
## **A frame is asked for while a picture is under way.** Sara rests in
## low-processor mode, which draws a frame only when something in the rendering
## server changed, and a picture's dabs go to the rendering device, which
## changes nothing there. So with no frame asked for, none is drawn while a
## picture fills, the card is handed its dabs only by the read at the end, the
## read waits for all of them, and an answer asked for in a later frame never
## comes, because the card answers only as a frame is drawn. With a frame
## asked for each share, the card runs a share's dabs as they come and answers
## the read two frames on. The price is the fill's time: a share comes once a
## drawn frame, at the display's rate, rather than once a turn of the loop.
## **Several pictures are under way, and one stroke.** A picture's ask, its
## wait for the card and its read would each end a share, and a picture whose
## tip is a file would spend frames waiting for it. So a picture waiting on the
## card or on its tip gives the share to the next one, up to `MOST_UNDER_WAY`
## under way, and a share is `SHARE_OF_FRAME` of a frame at the rate the window
## draws. One picture sends its stroke at a time, so no two strokes' events are
## ever mixed. Either change alone fills the grid more slowly than both.
class_name SaBrushPresetPictures
extends RefCounted

## A picture of *stored_name* is drawn and kept at *path*, empty when nothing
## could be drawn.
signal drawn(stored_name: String, path: String)

## How much of a frame the pictures may take, as a share of the frame's period
## at the rate the window draws, so the window keeps that rate while a fresh
## profile's pictures fill in. Half, because the rest of a frame takes about a
## third of the display's period, and a share runs over by the step it is in, a
## read, a composite or an event of a noise brush preset.
const SHARE_OF_FRAME: float = 0.5

## How many pictures may be under way at once, the one sending its stroke among
## them. Four is one sending its stroke, two waiting the two frames the card
## takes to answer, and one waiting for its tip. A boot that allowed eight had
## six under way at the most and ended 0.07 s sooner, and each picture holds an
## easel of its own.
const MOST_UNDER_WAY: int = 4

## Asks the engine for a frame, the chooser's grid's `queue_redraw`, handed over
## at every `queue`. A redraw marks the server changed, so the frame is drawn
## even when nothing on screen moves.
var _frame: Callable = Callable()

## The store the presets are read from, the tool that draws a preset of an
## engine not in `_painters`, and those painters by engine, as the chooser holds
## them. Handed over at every `queue`, because the chooser's own change whenever
## it binds a store.
var _store: SaPresetStore = null
var _painter: Script = null
var _painters: Dictionary = {}
## Whether the cells show the tip rather than the stroke.
var _tip: bool = false

## Names whose picture has to be drawn, oldest first, those under way not
## among them.
var _pending: Array[String] = []
## The pictures under way, oldest first. One at most is part way through its
## stroke, and the rest wait: for the card to hand back the stroke they sent,
## for their tip's file, or for their turn to send a stroke.
var _under_way: Array[UnderWay] = []


## A picture under way: its drawing, the name it is for, and the tip file it
## waits for, empty when it waits for none.
class UnderWay:
    extends RefCounted

    var drawing: SaPresetThumbs.Drawing = null
    var stored_name: String = ""
    var tip_path: String = ""

    func _init(begun: SaPresetThumbs.Drawing, begun_name: String, begun_tip: String) -> void:
        drawing = begun
        stored_name = begun_name
        tip_path = begun_tip


## The share of a frame the pictures take, in microseconds: `SHARE_OF_FRAME` of
## a frame's period at the rate the window draws, which is the display's
## refresh, or the engine's cap on frames when that is lower.
static func share_usec() -> int:
    var hertz := SaCursorPrediction.refresh_hz()
    if Engine.max_fps > 0:
        hertz = minf(hertz, float(Engine.max_fps))
    return int(SHARE_OF_FRAME * 1_000_000.0 / hertz)


## Queues *names* to be drawn from *store* with *painter*, or the script
## *painters* names for a preset's engine, as tips when *tip* is set, asking
## *frame* for a frame on each share while a picture is under way. Whatever was
## queued before is dropped, since the chooser queues its whole grid at once.
func queue(
    names: Array[String], store: SaPresetStore, painter: Script, painters: Dictionary, tip: bool, frame: Callable = Callable()
) -> void:
    drop()
    _pending = names.duplicate()
    _store = store
    _painter = painter
    _painters = painters
    _tip = tip
    _frame = frame


## Forgets every name waiting, and lets go of every picture under way.
func drop() -> void:
    _pending.clear()
    for under: UnderWay in _under_way:
        under.drawing.abandon()
    _under_way.clear()


## How many pictures are still to come, those under way among them.
func waiting() -> int:
    return _pending.size() + _under_way.size()


## One frame's share: the pictures under way advanced for *budget_usec*, or one
## picture to its end when that is negative or the clock counts frames, as a
## capture's does, where a split stroke drew its cell otherwise. Answers whether
## more is to come. A share that leaves a picture under way asks for the next
## frame, which hands the card this share's dabs and brings its answers back.
func draw(budget_usec: int) -> bool:
    if budget_usec < 0 or SaPenClock.is_pinned():
        _draw_whole()
    else:
        _draw_share(budget_usec)
    if not _under_way.is_empty() and _frame.is_valid():
        _frame.call()
    return waiting() > 0


## The oldest picture under way, or else the next name's, drawn to its end and
## kept. A picture drawn whole in one frame finishes its tip's load at its first
## dab, so it waits for nothing.
func _draw_whole() -> void:
    var under: UnderWay = null
    if not _under_way.is_empty():
        under = _under_way[0]
    elif _can_begin():
        under = _begin()
    if under != null:
        under.drawing.advance(-1)
        _keep(under)


## A share of *budget_usec*. The card's answers are read first, because a read
## is short and finishes a picture. Then one stroke at a time: the one part way
## through, else the oldest with a stroke to begin whose tip is on the card,
## else a picture begun while fewer than `MOST_UNDER_WAY` are under way. Every
## go and every begin but the share's first waits for the budget, so a share
## of nothing still takes a step, and a picture begun goes at once unless it
## waits for its tip.
func _draw_share(budget_usec: int) -> void:
    var started := Time.get_ticks_usec()
    var went := false
    for under: UnderWay in _under_way.filter(_on_the_card):
        if went and Time.get_ticks_usec() - started >= budget_usec:
            return
        # A picture kept as this share went may have dropped the rest.
        if _under_way.has(under):
            went = true
            _go(under, budget_usec - (Time.get_ticks_usec() - started))
    while not went or Time.get_ticks_usec() - started < budget_usec:
        var next := _next_stroke()
        if next == null:
            if not _can_begin():
                return
            went = true
            next = _begin()
            if next == null or SaTipCache.shared().is_loading(next.tip_path):
                continue
        went = true
        _go(next, budget_usec - (Time.get_ticks_usec() - started))


## The picture to send its stroke next: the one part way through its stroke,
## or else the oldest with a stroke to begin whose tip is on the card. Null when
## neither is under way.
func _next_stroke() -> UnderWay:
    for under: UnderWay in _under_way:
        if under.drawing.stage == SaPresetThumbs.Drawing.Stage.STROKE:
            return under
    for under: UnderWay in _under_way:
        if under.drawing.stage == SaPresetThumbs.Drawing.Stage.START and not SaTipCache.shared().is_loading(under.tip_path):
            return under
    return null


## Whether *under* waits for the card to hand back the stroke it sent.
func _on_the_card(under: UnderWay) -> bool:
    return under.drawing.stage == SaPresetThumbs.Drawing.Stage.CARD


## Advances *under* for *budget_usec*, a step at the least, and keeps it when it
## is finished.
func _go(under: UnderWay, budget_usec: int) -> void:
    if under.drawing.advance(maxi(budget_usec, 0)):
        _keep(under)


## Lets go of *under* and says its picture is drawn, kept where
## `SaPresetThumbs.keep` saved it.
func _keep(under: UnderWay) -> void:
    _under_way.erase(under)
    drawn.emit(under.stored_name, SaPresetThumbs.keep(_store.dir, under.stored_name, under.drawing))


## Whether another picture may begin: a name is waiting, the store and the
## painter are handed over, and fewer than `MOST_UNDER_WAY` are under way.
func _can_begin() -> bool:
    return not _pending.is_empty() and _store != null and _painter != null and _under_way.size() < MOST_UNDER_WAY


## Begins the next name's picture and answers it, or null when its preset will
## not load, which passes the name over. Its tip starts loading off the stroke
## the way a chosen preset's does, `SaTipCache.load_ahead`.
func _begin() -> UnderWay:
    var stored_name: String = _pending.pop_front()
    var settings := _store.load_preset(stored_name)
    if settings == null:
        return null
    # By the engine the settings' own class declares, since that is the class
    # the painter has to read.
    var painter: Script = _painters.get(SaPresetStore.preset_engine_of(settings), _painter)
    var drawing := SaPresetThumbs.Drawing.cached(painter, settings, _tip)
    var under := UnderWay.new(drawing, stored_name, SaTipCache.load_ahead(settings))
    _under_way.append(under)
    return under
