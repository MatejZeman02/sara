## How much of a dirty set one frame composites, and the rest held in the
## backlog for the frames after it.
##
## A whole-layer fill under a stack of adjustment layers dirties every chunk,
## and the frame that composites them spends most of its time on the CPU
## issuing several dispatches a chunk and adjustment layer. The device's own
## calls are a small share of it. The rest is GDScript setting each dispatch
## up, so the frame is long by the number of chunks times the number of layers
## the walk draws over the canvas, and not by the pixels.
##
## So the easel's frame composites as many chunks as [constant FRAME_USEC]
## pays for and holds the rest in [SaCompositeBacklog], which composites them
## on the next frame as it does a region a pan reaches. A held region is held
## after the filter chain grew it, as a pan's is, so what each frame draws is
## what one composite of the whole set would have drawn there, and the picture
## after the last of them is the same texel for texel. Every reader of the
## output flushes the backlog first, so no reader sees a chunk still owed.
##
## The cost of a chunk is learnt from the composites already made, per chunk
## and per layer the walk draws over the canvas, since a stack with no such
## layer costs a fraction of one with twenty. Nothing is held until a
## composite has taught it, and a set the frame can pay for whole is never cut.
class_name SaCompositeBudget
extends RefCounted

## What one frame's composite may cost the CPU, in microseconds: under half of
## the 0.1 s a frame may take before the painter sees the window stop, so a
## frame that composites and draws the rest of the window still makes it. It
## was 80 ms against a mark of 0.2 s, and the frames after a group of a
## large painting is shown spent all of it and the pictures of the layers on top.
## It was 40 ms after that, and the card runs what a walk issued while the
## frame draws, as long again: a season's switch on the same file walked three
## chunks for 43 ms and drew for 50 to 67 ms after it, frames of 98 to 112 ms.
const FRAME_USEC := 30000.0

## The fewest chunks a composite has to have walked to teach the cost, so a
## stroke's one chunk, which costs its setup more than its walk, teaches
## nothing. A composite this budget cut teaches whatever it walked, since it
## walked what the cost learnt so far allowed: otherwise a cost learnt high,
## from a stack with fewer layers drawn over the canvas, cut every frame after
## it to fewer chunks than this and was never learnt again. Showing the
## large painting's group walked two chunks a frame of 24 ms for fourteen
## frames that way, against a frame paid for at 40.
const LEARNS_FROM := 4

## How far one new composite moves the learnt cost, between nought and one.
const FOLLOWS := 0.5

## The chunks the first frame walks on a stack of a new [method shape], which
## teaches the cost since the budget cut that frame. Showing a large painting's
## day group walked a probe of four chunks for 36 ms beside a fold paid for
## 22 ms, and the frame came to 121 ms.
const PROBE := 2

## Microseconds a chunk costs per [method weight], nought until a composite
## taught it.
var usec_per_unit := 0.0

## What the frame spent on the fold before its walk, in microseconds, which the
## easel writes before every composite and [method chunks_per_frame] takes off
## [constant FRAME_USEC]. A move in a large painting folded the caches of the
## stack for 30 ms and then walked 19 chunks for 30 more, and with the docker's
## rows and the drawing that frame came to 145 ms. So a frame whose fold spent
## the budget walks one chunk and leaves the rest to the next.
var spent_usec := 0

## Whether this frame's walk waits whole for the next, which the easel writes
## with [member spent_usec] when the fold paid a quarter of the frame before
## it: the payment that finishes a fold draws in the same frame, and the next
## frame has nothing else to pay.
var waits := false

## Whether [method hold_beyond] held back part of the composite the next
## [method learn] learns from.
var _cut := false

## The [method shape] of the stack the learnt cost was learnt on, -1 before
## the first lesson. A stack of another shape walks one probe of
## [constant PROBE] chunks before the budget trusts a cost again.
var _shape := -1


## What one chunk weighs in *document*: one, and one more for every visible
## adjustment layer the walk draws over the canvas rather than out of a cache,
## each of which runs its whole step over every chunk the walk reaches, and
## one more for every effect layer, each of which draws its input again over
## every chunk a change reaches before the walk. The first composite of the
## large winter painting after its open, 217 effect layers, cost 1.3 s for the
## canvas's 27 chunks, where a cost learnt on a stack with none paid for all
## of them in one frame.
static func weight(document: SaDocument) -> int:
    if document == null or document.fold == null:
        return 1
    var found := 1
    for entry: Dictionary in document.fold.bottom_stack + document.fold.top_stack:
        var layer := SaLayerStack.layer_of(entry)
        if layer != null and layer.is_adjustment() and layer.visible:
            found += 1
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.is_effect():
            found += 1
    return found


## How many chunks of *document* one frame pays for, never fewer than one, and
## -1 while no composite has taught the cost.
func chunks_per_frame(document: SaDocument) -> int:
    if usec_per_unit <= 0.0:
        return -1
    var paid := maxi(1, int((FRAME_USEC - spent_usec) / (usec_per_unit * weight(document))))
    return mini(paid, PROBE) if shape(document) != _shape else paid


## What tells one stack from another for the cost a chunk takes: the
## [method weight] and how many steps the fold left either side of the active
## layer. Showing a large painting's group moved the weight from 220 to 232,
## 217 of each the effect layers that weigh the same shown or hidden, while a
## chunk's walk went from 12 ms to 26 ms a unit. A cost learnt on the hidden
## stack let the first frame after the show walk 14 chunks for 93 ms, so a
## stack of a new shape walks a probe first and its cost is learnt from it.
static func shape(document: SaDocument) -> int:
    if document == null or document.fold == null:
        return 0
    return hash([weight(document), document.fold.bottom_stack.size(), document.fold.top_stack.size()])


## Leaves in *regions* the chunks this frame pays for, the top rows first and
## each row from the left, and moves the rest into *backlog*.
func hold_beyond(regions: Dictionary[Vector2i, Rect2i], backlog: SaCompositeBacklog, document: SaDocument) -> void:
    var allowed := chunks_per_frame(document)
    if waits:
        allowed = 0
    if allowed < 0 or regions.size() <= allowed:
        return
    _cut = true
    var order: Array[Vector2i] = []
    order.assign(regions.keys())
    order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
    backlog.hold(regions, order.slice(allowed), document)


## Learns from a composite of *chunks* chunks of *document* that took *usec*.
func learn(usec: int, chunks: int, document: SaDocument) -> void:
    var cut := _cut
    _cut = false
    if chunks <= 0 or (chunks < LEARNS_FROM and not cut):
        return
    var seen := float(usec) / float(chunks * weight(document))
    var shaped := shape(document)
    # A dearer chunk is believed at once and a cheaper one by halves, because
    # a frame paid for too much is what the painter sees and one paid for too
    # little only spreads the walk over a frame more.
    if usec_per_unit <= 0.0 or shaped != _shape or seen > usec_per_unit:
        usec_per_unit = seen
    else:
        usec_per_unit = lerpf(usec_per_unit, seen, FOLLOWS)
    _shape = shaped
