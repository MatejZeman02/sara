## A Stats number the reduction service counts: the words its rows show, and
## the wait for a tally before it is read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One readout and one request and fold for every number.** Coverage and
## edges, the dominant hues, saturation by value and the value groups each
## once carried the same label class and the same wait in their `follow`. A
## number extends this class, makes the words of each row with [method readout]
## and reads its total in [method _fold], and the wait is this class's alone.
##
## **The wait.** An answer still on its way would show a total half folded, or
## the total of the run before, so [method follow] leaves the rows as they are
## while the reduction is waiting, asks every readout for the frames the answer
## comes back on, and the docker asks again when it is folded.
class_name SaStatsNumber
extends SaStatsPart


## The words a row shows, which carry the number's rule on hover and keep
## frames coming while a tally is on its way. Sara runs in `low_processor_mode`,
## so a frame is drawn only when something on screen changed, and the device
## hands a tally back only once the frame its ask went into comes round. A
## painter who stops and holds the pen still would go on seeing the numbers of
## the stroke before until the pointer moved. A redraw a frame while the answer
## is out asks for the two or three it takes, and none once it is in.
class Readout:
    extends Label

    var _numbers: SaReductionService.OverDocument

    func _init(numbers: SaReductionService.OverDocument, hover: String) -> void:
        _numbers = numbers
        mouse_filter = Control.MOUSE_FILTER_PASS
        tooltip_text = hover

    func _ready() -> void:
        # The engine turns processing on at ready for a script with `_process`.
        set_process(_numbers.waiting > 0)

    ## Asks for a frame each frame until the answer is folded in.
    func wait_for_answer() -> void:
        set_process(true)

    func _process(_delta: float) -> void:
        if _numbers.waiting > 0:
            queue_redraw()
        else:
            set_process(false)


## Every readout this number made, which the wait asks for frames. The docker
## frees them with its page, so each is checked before it is asked.
var _readouts: Array = []


## A new readout for one of the number's rows, saying *hover* on hover. The
## number translates it, where the template's writer reads its literal.
func readout(hover: String) -> Readout:
    var made := Readout.new(reduction as SaReductionService.OverDocument, hover)
    _readouts.append(made)
    return made


func refresh(surface: SaSurface) -> void:
    if surface != null:
        follow(surface.get_document())


## Reads *document*'s numbers out of the reduction's total into the rows, or,
## while an answer is still on its way, has the rows wait for it.
func follow(document: SaDocument) -> void:
    if document == null:
        return
    var numbers := reduction as SaReductionService.OverDocument
    if numbers.waiting > 0:
        # Untyped, because a typed loop variable refuses a freed readout.
        for shown: Variant in _readouts:
            if is_instance_valid(shown):
                (shown as Readout).wait_for_answer()
        return
    _fold(document)


## Reads the folded total for *document* and writes it into the rows. Each
## number says what its total holds.
func _fold(_document: SaDocument) -> void:
    pass
