## When a filter dialog's preview on the canvas is drawn coarser and when it is
## drawn exact again: a run that follows the last one within
## [constant SETTLE_SECONDS] is a control being dragged, and its preview is a
## draft at about the screen's resolution. The first run after a pause is
## exact, and so is the redraw this asks for once the drag has stopped for that
## long, so the picture a finger lets go of is the one Apply writes.
##
## Its own class because it owns the one decision and the wake-up that ends
## it, a `Timer` in the dialog's tree, and the dialog only asks it.
## [SaPointPreview] holds the answer and the filter chain draws it, and a pass
## whose kernel takes no `block` is drawn exact whatever this says.
##
## Outside a running tree a timer never counts, so a suite's window and a
## dialog no one shows draw every run exact.
class_name SaCanvasDraft
extends Timer

## How long after a run the next counts as the same drag, and how long a drag
## rests before the exact redraw. Longer than the frames between two ticks of a
## slider dragged by hand, short enough that the exact picture follows the
## release before the eye looks for it.
const SETTLE_SECONDS: float = 0.25

## The most times a draft is halved, a fold for a square eight texels on a
## side, so a document zoomed far out is still drawn near its screen size.
const MOST_HALVINGS: int = 3

## The dialog's redraw of its canvas preview, called again once a drag has
## rested, when it asks [method halvings] and is answered 0.
var _settled: Callable
## Whether the last answer was a draft, so a rest after an exact run redraws
## nothing.
var _drafted: bool = false
## Up while [member _settled] runs, so its own ask starts no new wait.
var _settling: bool = false


func _init(settled: Callable) -> void:
    name = "CanvasDraft"
    one_shot = true
    wait_time = SETTLE_SECONDS
    _settled = settled
    timeout.connect(_on_timeout)


## How many times the run asked for now is halved on a canvas showing
## *pixels_per_texel* screen pixels a texel: 0 for the first run after a pause,
## and otherwise as many times as the square comes nearest one screen pixel.
## Starts the wait for the exact redraw.
func halvings(pixels_per_texel: float) -> int:
    if not is_inside_tree() or _settling:
        return 0
    var dragging := not is_stopped()
    start()
    _drafted = dragging and at_scale(pixels_per_texel) > 0
    return at_scale(pixels_per_texel) if dragging else 0


## How many times a square of texels is halved for its side to come nearest one
## screen pixel at *pixels_per_texel*, up to [constant MOST_HALVINGS].
##
## The nearest and not the largest square under a pixel, because the largest
## under one is half the screen's resolution at most zooms and four times the
## work: a canvas fitting a 4000 by 3000 photograph into a phone's window shows
## 0.27 pixels a texel, where the square under a pixel is two texels, 0.54 of a
## pixel, and the nearest is four, 1.08.
static func at_scale(pixels_per_texel: float) -> int:
    if pixels_per_texel <= 0.0 or pixels_per_texel >= 0.5:
        return 0
    return clampi(roundi(log(1.0 / pixels_per_texel) / log(2.0)), 0, MOST_HALVINGS)


func _on_timeout() -> void:
    if not _drafted:
        return
    _drafted = false
    _settling = true
    _settled.call()
    _settling = false
