## Where a failure goes so that it reaches the screen, not only the log.
##
## A failure that reaches only the log is a line in a terminal the painter is
## not looking at and a window that draws nothing, whether a save failed, a
## kernel did not compile or the machine has no working Vulkan, so every failing
## call site reports here. `report()` writes the line to the log, then hands it
## to whatever is
## showing problems on screen, and keeps it when nothing is yet: the shader
## compiler runs as an autoload before any window exists, so the first problems
## of a session arrive before there is anywhere to put them. `SaMessage.install`
## attaches the sink once the main window is up and drains what was kept.
##
## **Two doors, because there are two kinds of problem**. `report` is a fault:
## something that was meant to work did not, and the line is worth reading twice
## and worth copying into a bug report, so it grows the window and waits to be
## dismissed. `refuse` is a refusal: the gesture the painter just made cannot
## happen and nothing is broken, no selection to patch, no canvas to record, a
## file that is not a picture, so the line goes to the corner and takes itself
## away again. The kind is said at the call site and travelled to the sink beside
## the line, because the alternative is a sink reading a severity out of a
## sentence, and a sentence is not a severity. It also decides whether the line
## on screen carries `source`: the fault does and the refusal does not.
##
## Static on purpose. Core code must not know a dialog exists, and a problem
## must be reportable from a `RefCounted` constructor with no tree to reach.
class_name SaProblems
extends RefCounted

## What kind of problem a report is, and so which surface it belongs on. The
## sink is handed one of these with every line.
enum Kind {
    FAULT,  ## Something that was meant to work did not. The growing window.
    REFUSAL,  ## The gesture cannot happen and nothing is broken. The corner.
}

## What a refusal's log line opens with, which `scripts/sara_findings.py` reads.
const REFUSED := "Refused, "

## Faults that arrived before a sink was attached, oldest first.
static var pending: PackedStringArray = PackedStringArray()

## Refusals that arrived before a sink was attached, oldest first. Kept apart
## from `pending` rather than beside it in a second array of kinds, because the
## two are drained onto two different surfaces and a test that empties one has no
## way to leave a parallel array of kinds in step with it.
static var pending_refusals: PackedStringArray = PackedStringArray()

## Whether `report` also echoes to the log. A test that provokes a problem on
## purpose turns this off, so the transcript shows the assertion and not the
## alarm it was checking for.
static var announce: bool = true

static var _sink: Callable = Callable()


## Records one fault. `source` names who is reporting, in the class's own name,
## and `text` says what went wrong in words a painter can act on.
static func report(source: String, text: String) -> void:
    _deliver(source, text, Kind.FAULT)


## Records one refusal: the gesture cannot happen, and the painter's next move is
## the whole of the answer. Same arguments as `report`, and the log line is a
## warning opening with `REFUSED`. On screen a refusal is shown without `source`,
## because the painter reading it is not the person who would file it.
static func refuse(source: String, text: String) -> void:
    _deliver(source, text, Kind.REFUSAL)


## Points reports at the screen. The sink takes one line and its kind, and
## receives every kept report at once, in order, before anything new. The faults
## first, because a fault that was waiting through the whole of boot is the one
## the painter most needs to see.
static func attach_sink(sink: Callable) -> void:
    _sink = sink
    var kept_faults := pending
    var kept_refusals := pending_refusals
    pending = PackedStringArray()
    pending_refusals = PackedStringArray()
    for line in kept_faults:
        _sink.call(line, Kind.FAULT)
    for line in kept_refusals:
        _sink.call(line, Kind.REFUSAL)


## Back to keeping reports, for a sink that is going away.
static func detach_sink() -> void:
    _sink = Callable()


## Whether a sink is attached, so a test can tell buffering from delivery.
static func has_sink() -> bool:
    return _sink.is_valid()


## The one place a report becomes a line, and the one place the two kinds are
## written differently.
##
## The log keeps the reporter for both, because a line in a terminal has no
## other way to say where it came from. The screen keeps it for a fault only. A
## fault is copied into a bug report and the reporter's name is half of what
## makes that report useful, but a refusal is a sentence about the gesture the
## painter just made, and a painter who has been told nothing is broken should
## not then be reading a GDScript class name in the corner. A refusal is logged
## as a warning, since an error line is what the door's findings call an engine
## error, and a right refusal is no error of the engine's.
static func _deliver(source: String, text: String, kind: Kind) -> void:
    var logged := "%s: %s" % [source, text]
    if announce and kind == Kind.REFUSAL:
        push_warning(REFUSED + logged)
    elif announce:
        push_error(logged)
    var shown := text if kind == Kind.REFUSAL else logged
    if _sink.is_valid():
        _sink.call(shown, kind)
    elif kind == Kind.REFUSAL:
        pending_refusals.append(shown)
    else:
        pending.append(shown)
