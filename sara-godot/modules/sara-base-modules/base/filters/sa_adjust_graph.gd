## The histogram across the top of the Levels filter: the levels of what the
## handles act on, redrawn as that changes under the dialog.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its pass is the door's `SaGraphPlot`, which the Graph docker draws too, and
## the easel it polls is the front surface's, which `SaInHand.Canvas` answers.
##
## **The layer, not the composite.** Levels rewrites one layer, and a graph of
## everything under that layer would be a graph of the wrong thing. So in the
## Filter menu's dialog the pass is `SaGraphPlot.run_over_layer`, one dispatch
## per allocated chunk of the active layer, which reads the paint and nothing
## else. The Preview tick changes nothing here on purpose. The preview is
## applied at composite time and never written to a chunk, so the layer's
## histogram is the input the handles act on, which is what Photoshop's Levels
## shows too: the graph holds still under a drag and the handles move across
## it.
##
## **A record's input, where the panel edits a record.** In the
## edit window of an attached record, or in the tool options panel of one, the
## handles act on the record's input rather than on the active layer, and
## Equalize bins that input. So the panel hands the graph its `attached_host`
## as a constructor argument, and while that answers a record hanging on a
## node the pass is `SaGraphPlot.run_over_sources` over the door's
## `SaNodeInput`: the layer's paint for a paint layer, the group's composite
## before its records, the picture before the root's records, and the
## backdrop at its scope for an adjustment layer. That input is composited for
## the pass, every position it covers, so it is not polled per composite the
## way a layer's chunks are. It takes a pass when the panel opens, when the
## channel moves, after a press, and once when the history has moved and no
## stroke is open, which is a stroke or an edit that has let go. A handle drag
## makes no history step and moves nothing the input reads, so it takes none.
##
## **A level, not a stored number**. `graph.gmacs` decodes the texel into what
## a screen would show before it bins it, so the bins are display levels, the
## same scale the handle bars under the graph are drawn in and the same
## whatever the document stores.
##
## **Bars, not spikes**. A painted layer holds a few levels,
## and the plot's 256 texels stretched across the dialog would draw each as a
## column a pixel or two wide. So every pass asks the plot for the reach that draws a
## lone bin at least three logical pixels wide at the width the graph is shown,
## and the kernel draws it as an outlined bar over a faint fill. A resize that
## changes the reach takes a pass.
##
## Nothing here computes a graph of its own. `SaGraphPlot` is the Graph
## docker's GPU half and both passes are its own public doors, so this file
## calls them and changes nothing in them. The pass is a
## compute dispatch whose output is a small texture, and no texel comes back to
## the CPU outside `capture_state`, which only a capture calls.
class_name SaAdjustGraph
extends TextureRect

## The graph the dialog shows. The id `SaGraphPlot.MODES` knows it by.
const MODE := "histogram"

## How tall the graph is drawn, in logical units. Enough to read a shape in and
## short enough that the dialog does not become a window about its own graph.
const HEIGHT := 120

## The luma row of the count buffer: red, green and blue come first, and the
## fourth row is the grey the note asked for. Lightness draws it too, counted
## as Oklab L rather than as luma, so Master and Lightness are two graphs.
const LUMA_ROW := 3

## Which row of the count buffer the dump folds into buckets, per channel.
## Master reports the luma row because it is the one row that summarises all
## three, and the claim the scenario makes is about the shape rather than about
## one channel. Every other channel reports the row it draws.
const DUMP_ROWS := {"master": LUMA_ROW, "lightness": LUMA_ROW, "red": 0, "green": 1, "blue": 2}

## The dump reports the luma row folded into this many buckets. All 256 bins
## would be a dump nobody reads, and the claim that painting
## on the layer moves the graph is a claim about the shape rather than about
## one bin: sixteen buckets carry the shape and fit on a line.
const BUCKETS := 16

## Which channel the panel's dropdown is on, which is what the graph draws.
## Written by the panel beside a `refresh`, the way `SaGraphPlot.scale` is
## written by the docker: it is the widget's subject rather than its
## internals, and a constructor argument cannot follow a dropdown.
var channel: String = "master"

var _plot: SaGraphPlot = null
## The panel's `attached_host`, answering `[document, record]` in a window or
## panel that edits a record and empty in the Filter menu's dialog. Asked on
## every poll, because the panel is handed a host only once it is in one.
var _host_of: Callable = Callable()
## How many passes the graph has taken, for a suite that counts them.
var _passes: int = 0
## What the last record pass graphed, `[document, record, node]`, and the
## history position it was taken at.
var _seen_host: Array = []
var _seen_step: int = -1
var _seen_composites: int = -1
var _seen_layer: SaLayer = null
var _seen_chunks: int = -1


## A graph for the panel whose `attached_host` is *host_of*. Without one it
## always graphs the active layer.
func _init(host_of: Callable = Callable()) -> void:
    _host_of = host_of
    name = "ValueGraph"
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    stretch_mode = TextureRect.STRETCH_SCALE
    custom_minimum_size = Vector2(0.0, float(SaUI.px(HEIGHT)))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # A graph is not a control, and the handle bar under it is where the
    # clicks go.
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    tooltip_text = _tooltip_for([])


func _process(_delta: float) -> void:
    if not is_visible_in_tree():
        release()
        return
    follow()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED and _plot != null and SaGraphPlot.bar_reach_for(size.x) != _plot.bar_reach:
        refresh()


## One frame's look at whether the graph is stale, and a pass when it is.
## Public because a suite holds its window offscreen, where no frame runs.
##
## For a record's input it waits for the history to move with no stroke open,
## which is once when a stroke or an edit lets go and never on a composite of
## a held stroke. For the active layer it polls the easel's own counter rather
## than following a signal, for the reason the Graph docker polls: the easel
## and its document are both replaced under a dialog by File > New, and a few
## comparisons a frame are cheaper than following that with signals. A stroke
## on the layer marks chunks dirty, the composite runs, and the count moves,
## which is what makes the graph follow the paint. The active layer and its
## chunk count are compared as well, so a layer switched under the dialog or a
## chunk allocated by the first dab is a change even when the composite count
## is not. A preview drag composites too, and the pass runs again over a layer
## that did not change. That costs one dispatch per chunk of one layer, and a
## check that could tell the two apart would need a counter the layer does not
## keep.
func follow() -> void:
    var host := _host()
    if not host.is_empty():
        var document := host[0] as SaDocument
        if _stroke_open(document):
            return
        if host == _seen_host and _step_of(document) == _seen_step:
            return
        refresh()
        return
    var easel := _easel()
    if easel == null or easel.document == null:
        return
    var layer := easel.document.active_layer
    var chunks := layer.chunks.size() if layer != null else 0
    if easel.composite_count == _seen_composites and layer == _seen_layer and chunks == _seen_chunks:
        return
    _seen_composites = easel.composite_count
    _seen_layer = layer
    _seen_chunks = chunks
    refresh()


## Takes a pass now, whatever the poll thinks, the way the docker's own
## `refresh` does: a capture and a test want the picture without waiting for a
## frame that changed, and the panel asks for one when the channel moves.
func refresh() -> void:
    var host := _host()
    var easel := _easel() if host.is_empty() else null
    if host.is_empty() and (easel == null or easel.document == null):
        return
    if _plot == null:
        _plot = SaGraphPlot.new()
    # Photoshop's and Krita's count axis is linear and `SaGraphPlot` opens on
    # darktable's log, which flattens the shape and lifts the noise floor into
    # a curve of its own. The Graph docker keeps the log, because a scope is
    # what that docker is for. This is a dialog about one input's levels.
    _plot.scale = "linear"
    _plot.histogram_channel = channel
    _plot.bar_reach = SaGraphPlot.bar_reach_for(size.x)
    _passes += 1
    tooltip_text = _tooltip_for(host)
    var drawn := false
    if not host.is_empty():
        var document := host[0] as SaDocument
        _seen_host = host
        _seen_step = _step_of(document)
        _seen_layer = null
        var input := SaNodeInput.new(document, host[2] as SaLayer)
        drawn = _plot.run_over_sources(input.positions(), input.at, document.color_space, MODE)
    else:
        _seen_host = []
        drawn = _plot.run_over_layer(easel.document.active_layer, easel.document.color_space, MODE)
    if drawn:
        texture = _plot.shown
        # The same object after the first pass, so the setter marks nothing
        # and the rewritten picture needs its frame asked for.
        queue_redraw()
    else:
        # An input with nothing to bin, and the last graph must not stand in
        # for it.
        texture = null


## What the graph draws, in the words its tooltip and a capture use:
## "active layer" in the Filter menu's dialog, and for a record the node's
## input, "paint", "group", "root" or "backdrop".
func subject() -> String:
    return _subject_of(_host())


## The record the panel edits as `[document, record, node]`, the node null for
## the root, or empty when the panel edits none or the record hangs on no node.
func _host() -> Array:
    if not _host_of.is_valid():
        return []
    var host: Array = _host_of.call()
    if host.size() < 2:
        return []
    var found := SaNodeInput.node_of(host[0] as SaDocument, host[1] as SaAttachedFilter)
    if not bool(found[0]):
        return []
    return [host[0], host[1], found[1]]


static func _subject_of(host: Array) -> String:
    if host.is_empty():
        return "active layer"
    var node := host[2] as SaLayer
    if node == null:
        return "root"
    if node.is_adjustment():
        return "backdrop"
    return "group" if node.is_group else "paint"


func _tooltip_for(host: Array) -> String:
    match _subject_of(host):
        "paint":
            return tr("How many pixels of this layer sit at each level, the input the filter reads, before the handles.")
        "group":
            return tr("How many pixels of the group's composite sit at each level, before its filters and the handles.")
        "root":
            return tr("How many pixels of the whole picture sit at each level, before the document's filters and the handles.")
        "backdrop":
            return tr("How many pixels of the picture under this adjustment layer sit at each level, before the handles.")
    return tr("How many pixels of the active layer sit at each level, before the handles.")


## Where *document*'s history stands, which moves once for each step taken,
## undone or redone.
static func _step_of(document: SaDocument) -> int:
    return document.history.position() if document.history != null else -1


## Whether a stroke is held on *document*: a dab in the stroke buffer, or an
## erase painting straight into the layer, whose snapshot is taken as it goes.
## The transaction's class is the document package's own, so its field is read
## by name.
static func _stroke_open(document: SaDocument) -> bool:
    if document.stroke_layer != null and not document.stroke_layer.chunks.is_empty():
        return true
    var transaction: RefCounted = document.stroke_transaction
    if transaction == null:
        return false
    var before: Variant = transaction.get(&"before_chunks")
    return before is Dictionary and not (before as Dictionary).is_empty()


## Drops the pass and everything it owns. Called when the graph is hidden, so
## a closed dialog leaves nothing running and nothing allocated: the plot holds
## a buffer of a quarter of a million counts and a picture, and a dialog opened
## once a session should not keep either.
##
## The `Texture2DRD` goes first, because it holds the RID the `SaTexture` under
## it is about to free, which is the order `SaGraphPlot.set_plot_size` gives.
func release() -> void:
    if _plot == null:
        return
    texture = null
    _plot = null
    _seen_composites = -1
    _seen_layer = null
    _seen_chunks = -1
    _seen_host = []
    _seen_step = -1


## The document the easel the dialog is over holds, whose active layer the
## graph draws in the Filter menu's dialog. Null when there is none.
func easel_document() -> SaDocument:
    var easel := _easel()
    return easel.document if easel != null else null


## The tool machine of the canvas the dialog is over, untyped as a surface
## holds it, which the Levels eyedroppers put the Eyedropper in the hand of.
## Null when there is none.
func easel_machine() -> Variant:
    var surface := _front_surface()
    return surface.tool_machine if surface != null else null


func _easel() -> SaEasel:
    var surface := _front_surface()
    return surface.easel if surface != null else null


## The surface the dialog is over. Several canvases are alive at once, the
## Info docker's scratchpad among them, so the question is which, and the
## answer is the front surface: the document the painter opened the dialog
## over.
func _front_surface() -> SaSurface:
    return SaInHand.Canvas.front() if is_inside_tree() else null


## What the graph is showing, for the capture harness: the mode, whether a pass
## has run, and the luma row folded into `BUCKETS`. A picture of a histogram is
## a poor way to grade "the graph moved", and the buckets make it arithmetic.
##
## The read is a buffer readback and a stall, which is why it lives here rather
## than in `_process`: `harness/report/sa_state_report.gd` is the only caller and it runs in
## a capture. No texel comes back either way, so hard rule 1 is untouched.
func capture_state() -> Dictionary:
    if _plot == null:
        return {"present": false, "showing": is_visible_in_tree(), "channel": channel, "graphs": subject()}
    var counts := _plot.read_counts()
    var row: int = int(DUMP_ROWS.get(channel, LUMA_ROW))
    var buckets: Array = []
    var total := 0
    var weighted := 0.0
    # 256 over 16, both constants and both powers of two, so the division is
    # exact and the warning is about the operator rather than about this sum.
    @warning_ignore("integer_division")
    var per := SaGraphPlot.BINS / BUCKETS
    for bucket in BUCKETS:
        var sum := 0
        for step in per:
            var at := row * SaGraphPlot.BINS + bucket * per + step
            if at < counts.size():
                sum += counts[at]
        buckets.append(sum)
        total += sum
        weighted += float(sum) * (float(bucket) + 0.5) / float(BUCKETS)
    return {
        "present": true,
        "showing": is_visible_in_tree(),
        "mode": MODE,
        "layer": String(_seen_layer.name) if _seen_layer != null else "",
        # What the pass reads: the active layer, or the input of the record
        # the panel edits.
        "graphs": subject(),
        "passes": _passes,
        # The two claims no picture can carry: the count axis is
        # Photoshop's rather than darktable's, and the dropdown reaches the
        # graph. `row` is which row of the buffer `bins` was folded from.
        "scale": _plot.scale,
        "channel": channel,
        "row": row,
        # How wide a lone level is drawn: the bins either side its bar
        # spreads over, and the bar in logical pixels at the width shown.
        "bar_reach": _plot.bar_reach,
        "bar_width": snappedf(SaGraphPlot.bar_width(_plot.bar_reach, size.x), 0.01),
        "shown_width": size.x,
        "bins": buckets,
        "samples": total,
        # Where the middle of the distribution sits, 0 to 1. A white stroke on
        # a dark layer slides it up, which is the claim the scenario makes.
        "mean": weighted / float(total) if total > 0 else 0.0,
    }
