## The document's undo history, bounded by bytes rather than by steps.
##
## `UndoRedo.max_steps` counts actions, and an action is worth whatever it touched.
## Thirty-two steps of a dab is a few megabytes and thirty-two steps of a
## full-canvas stroke is about 2.5 GiB, so a cap on steps says nothing about
## memory. This spends a budget instead, and lets the step count be whatever fits.
##
## Godot's UndoRedo has no eviction hook, so the budget is enforced the only way it
## exposes: by setting `max_steps` to the number of steps that fit, *before* the
## action that would push it over. Applied afterwards it would always be one step
## late, and one step is exactly the case that matters, a single stroke covering
## the whole canvas.
class_name SaHistory
extends RefCounted

## The floor under the paint budget, whatever the document is.
##
## 256 MiB is several hundred ordinary dabs, and on a 1920x1080 F32 document it
## is six whole-canvas steps and no more. A constant says nothing about the
## document it is spent on, so the same number that is generous for a
## sketchpad is two steps on a 4K canvas. It is the floor rather than the
## answer, and `effective_budget` is the answer.
const DEFAULT_BUDGET_BYTES: int = 256 * 1024 * 1024

## A second pool, for the layers a structural step keeps alive: a deleted,
## merged or flattened layer sits in its history entry with every chunk it had.
## Its own allowance, so that a delete never evicts painting history. Modest on purpose: two full-grid 1920x1080 F32 layers.
## Both pools share the one UndoRedo list, so when this one overflows the
## oldest steps go whatever kind they are, but a paint step alone can never
## push a delete out and a delete can never push a stroke out.
const DEFAULT_LAYER_BUDGET_BYTES: int = 96 * 1024 * 1024

var budget_bytes: int = DEFAULT_BUDGET_BYTES
var layer_budget_bytes: int = DEFAULT_LAYER_BUDGET_BYTES

## What the most expensive step this document has produced cost, which is what a
## whole-canvas step costs once one has happened.
##
## Written here and read from outside. Measured rather than computed from the
## canvas rectangle on purpose: a step is worth what it snapshots, and a
## document with three layers a fill touches at once costs three grids where the
## rectangle says one. It never falls back, because the budget is a cap rather
## than an allocation and a cap that shrinks under a painter mid-session evicts
## on the next step for no reason the painter can see. `reset` clears it, which
## is what a new document does.
var largest_step_bytes: int = 0

## How many steps eviction has taken since the document opened. Without it the
## painter sees six rows in the Undo History docker and no sign that a seventh
## ever existed. The Info docker shows it as a row and
## the Undo History docker says it in its own footer, which is where a painter
## looking for a missing row is already looking.
var dropped_steps: int = 0

## Whether a drop also leaves its line in the console. On in the application,
## where the log is what a tester sends with a bug report, and off in a suite
## that drops steps on purpose to prove the arithmetic.
var announce_drops: bool = true

## Pins the budget at `budget_bytes` exactly, for a test that wants an exact
## number of steps to fit. `announce_drops` is the same escape hatch for the
## same reason: the behaviour under test is the arithmetic, not the policy on
## top of it.
var pin_budget: bool = false

## True while `quietly` runs, so a drop inside it is not said.
var _quiet: bool = false

var _undo_redo: UndoRedo
## Bytes per action, oldest first, kept in step with the UndoRedo's own list.
var _step_bytes: Array[int] = []
## The same, for the layers each action keeps alive. Zero for a paint step.
var _step_layer_bytes: Array[int] = []
## The snapshot states each action holds, in the same order, each a list of
## grid position -> SaChunk, SaChunkDelta or null dictionaries. The same
## Dictionary the action is bound to, so a swap that trades its entries is
## read as it stands. What `SaResidency` moves to RAM first, the oldest first.
var _step_states: Array[Array] = []
## What each action keeps beyond its snapshot states, in the same order: the
## layers a structural step took out of the document and the state a whole
## grid's swap is bound to. `SaResidency` moves their chunks to RAM with the
## snapshots, a layer's only while it is out of the tree.
var _step_kept: Array[Array] = []
## A serial per action, in the same order, which is what `position` answers.
var step_serials: Array[int] = []
## The serial of where the history stands before its oldest kept action: the
## document as it was made, or the last step eviction took.
var base_serial: int = 0

## While `as_one` runs its work, the steps the work commits, each
## [name, do, undo, paint bytes, layer bytes, the objects the two belong to],
## gathered rather than registered. UndoRedo keeps a reference to the
## RefCounted object a method it is given belongs to, and a Callable alone
## keeps none, so an `SaLayerOps` built for one row of the set and dropped
## before the gather ends is held here and then by the step.
var _gathered: Array = []
var _gathering: bool = false

## The last serial handed out, by any history. Shared, so a document rebuilt
## with a new history can never meet a serial its old one handed out.
static var _last_serial: int = 0


func _init(undo_redo: UndoRedo) -> void:
    _undo_redo = undo_redo
    base_serial = _next_serial()


## Registers one reversible action and charges what it holds against the budget.
##
## *action* goes on both sides, which is how one snapshot serves undo and redo
## alike (see SaDocument.swap_pixels), and it arrives already bound. *state*
## is passed separately only to be weighed. Binding it here instead would look
## tidier and be wrong: `Callable.bind()` appends, so binding a second argument in a
## second call puts it before the first one rather than after, and the arguments
## arrive reversed.
##
## *layer_bytes* is what the step keeps alive beyond its chunk snapshots, the
## chunks of a layer it took out of the document, and is charged to the layer
## pool rather than the paint one. *kept* is what holds those chunks, the
## layers taken out or the state the action swaps, so the history can hand them
## to `SaResidency` as it hands the snapshots.
func commit(action_name: String, action: Callable, state: Dictionary, layer_bytes: int = 0, kept: Array = []) -> void:
    if _undo_redo == null:
        return
    if _gathering:
        _gathered.append([action_name, action, action, bytes_of(state), layer_bytes, action.get_object(), [state], kept])
        return
    var incoming := bytes_of(state)
    _begin(incoming, layer_bytes)
    _undo_redo.create_action(action_name)
    _undo_redo.add_do_method(action)
    _undo_redo.add_undo_method(action)
    # 'false' means do not run the do side now: the caller already left the
    # document in its "after" shape, so the first thing this action can do is be
    # undone.
    _undo_redo.commit_action(false)
    _finish(incoming, layer_bytes, [state], kept)


## Registers one reversible action with a do side and an undo side of its own.
##
## For a change that is a value rather than a snapshot, a layer's opacity or
## its place in the stack, where both directions are known up front and no
## swap is needed. *merge* is UndoRedo's own: MERGE_ENDS folds a run of same
## named actions into one whose undo is the first value and whose do is the
## last, which is what turns a slider drag into one step rather than one per
## pixel it travelled. A folded action adds nothing to the list and so nothing
## to the accounting. *states* are the snapshot states the two sides are bound
## to, which `as_one` passes for the steps it gathered, and *kept* what they
## keep beyond them, as `commit` takes it.
func commit_pair(
    action_name: String,
    do_action: Callable,
    undo_action: Callable,
    paint_bytes: int = 0,
    layer_bytes: int = 0,
    merge: UndoRedo.MergeMode = UndoRedo.MERGE_DISABLE,
    states: Array = [],
    kept: Array = []
) -> void:
    if _undo_redo == null:
        return
    if _gathering:
        _gathered.append(
            [
                action_name,
                do_action,
                undo_action,
                paint_bytes,
                layer_bytes,
                [do_action.get_object(), undo_action.get_object()],
                states,
                kept
            ]
        )
        return
    _begin(paint_bytes, layer_bytes)
    # The version, not the count, tells a folded action from a new one. A new
    # action raises it by one and a folded one leaves it where it was, whatever
    # the commit discarded. The count stays the same both when the action
    # folds and when it replaces one redo step or pushes the oldest step out,
    # and reading those two as folded loses a step from the lists here.
    var version_before := _undo_redo.get_version()
    _undo_redo.create_action(action_name, merge)
    _undo_redo.add_do_method(do_action)
    _undo_redo.add_undo_method(undo_action)
    _undo_redo.commit_action(false)
    if _undo_redo.get_version() == version_before and merge != UndoRedo.MERGE_DISABLE:
        # The folded action now holds a state no save has seen, so it is a
        # new place to stand even though the list did not grow.
        var current := _undo_redo.get_current_action()
        if current >= 0 and current < step_serials.size():
            step_serials[current] = _next_serial()
        return
    _finish(paint_bytes, layer_bytes, states, kept)


## Everything that has to happen before create_action.
##
## Read before it, because that call does two things to the list and only the
## first is recoverable afterwards: it drops everything past the pointer, which
## is the redo stack, and then drops from the front if max_steps bites.
## Afterwards the count alone cannot tell those two apart.
func _begin(paint_bytes: int, layer_bytes: int) -> void:
    # Before the budget is read, because the step arriving is part of what the
    # budget has to hold: a first whole-canvas fill on a fresh document would
    # otherwise be weighed against a budget that has never seen one.
    largest_step_bytes = maxi(largest_step_bytes, paint_bytes)
    var kept: int = maxi(_undo_redo.get_current_action() + 1, 0)
    if _step_bytes.size() > kept:
        _step_bytes.resize(kept)
        _step_layer_bytes.resize(kept)
        _step_states.resize(kept)
        _step_kept.resize(kept)
        step_serials.resize(kept)
    _undo_redo.max_steps = _steps_that_fit_beside(paint_bytes, layer_bytes) + 1


func _finish(paint_bytes: int, layer_bytes: int, states: Array = [], kept: Array = []) -> void:
    var fits := _undo_redo.max_steps - 1
    if _step_bytes.size() > fits:
        var lost := _step_bytes.size() - fits
        _step_bytes = _step_bytes.slice(_step_bytes.size() - fits)
        _step_layer_bytes = _step_layer_bytes.slice(_step_layer_bytes.size() - fits)
        _step_states = _step_states.slice(_step_states.size() - fits)
        _step_kept = _step_kept.slice(_step_kept.size() - fits)
        base_serial = step_serials[lost - 1]
        step_serials = step_serials.slice(step_serials.size() - fits)
        dropped_steps += lost
        _say_steps_were_dropped(lost)
    _step_bytes.append(paint_bytes)
    _step_layer_bytes.append(layer_bytes)
    _step_states.append(states)
    _step_kept.append(kept)
    step_serials.append(_next_serial())


## Where the history stands, as the serial of the step the document is on.
##
## Two answers are equal exactly when the document is in the same state by
## way of its history, which is what the modified mark compares against the
## place it was saved at. The action index cannot say that:
## an undo and a new step land on the same index with different pixels, and
## eviction shifts every index down. Nor can `UndoRedo.get_version()`, which
## counts back down on an undo and up again on the next step, so a step taken
## after an undo wears the version of the one it replaced.
func position() -> int:
    if _undo_redo == null:
        return base_serial
    var current := _undo_redo.get_current_action()
    if current < 0 or step_serials.is_empty():
        return base_serial
    return step_serials[mini(current, step_serials.size() - 1)]


static func _next_serial() -> int:
    _last_serial += 1
    return _last_serial


## Runs *work* and answers what it returned, with the drop's line held back for
## any step it drops.
##
## For a document being built rather than edited. Opening a picture adds its
## layer and takes the two default layers off through the same undoable doors a
## painter uses, and the caller clears the history straight after, because none
## of those is a step to take back. Under a picture over the layer pool, about
## six megapixels, the second removal drops the add before it, and the painter
## who has done nothing but open a file would be told the undo history was full.
## The drops still happen and are still counted until that reset. Only the line
## is held, because nothing the painter made was lost.
func quietly(work: Callable) -> Variant:
    _quiet = true
    var answer: Variant = work.call()
    _quiet = false
    return answer


## Runs *work* and registers every step it commits as one, named *action_name*,
## or named as its only step when it commits one. Answers how many steps the
## work committed.
##
## For an action on the Layers docker's picked set, which runs the action a
## row at a time through the doors a single row takes and is still one press,
## so one Ctrl+Z puts every row back. The gathered steps redo
## in the order they ran and undo the other way round, so each finds the
## document as it left it. A step is never folded into the one before it while
## gathering, and a gather inside a gather joins the outer one.
func as_one(action_name: String, work: Callable) -> int:
    if _undo_redo == null or _gathering:
        work.call()
        return 0
    _gathering = true
    _gathered = []
    work.call()
    _gathering = false
    var steps := _gathered
    _gathered = []
    if steps.is_empty():
        return 0
    if steps.size() == 1:
        var only: Array = steps[0]
        var name: String = only[0]
        var do_it: Callable = only[1]
        var undo_it: Callable = only[2]
        var paint_bytes: int = only[3]
        var layer_bytes: int = only[4]
        var held: Array = only[6]
        var only_kept: Array = only[7]
        commit_pair(name, do_it, undo_it, paint_bytes, layer_bytes, UndoRedo.MERGE_DISABLE, held, only_kept)
        return 1
    var dos: Array[Callable] = []
    var undos: Array[Callable] = []
    var paint := 0
    var layers := 0
    var owners: Array = []
    var states: Array = []
    var kept: Array = []
    for step: Array in steps:
        owners.append(step[5])
        var held: Array = step[6]
        states.append_array(held)
        var step_kept: Array = step[7]
        kept.append_array(step_kept)
        dos.append(step[1])
        undos.push_front(step[2])
        paint += step[3]
        layers += step[4]
    var do_all := SaHistory._played(dos, owners)
    var undo_all := SaHistory._played(undos, owners)
    commit_pair(action_name, do_all, undo_all, paint, layers, UndoRedo.MERGE_DISABLE, states, kept)
    return steps.size()


## One Callable that calls each of *actions* in turn. Static, so it holds the
## actions and never this history, which the UndoRedo would then keep alive.
##
## *owners* are the objects the actions belong to, held for as long as the step
## is, which is what UndoRedo does for a method given it directly. A closure
## holds only what it reads, so it reads them: with none there is nothing to play.
static func _played(actions: Array[Callable], owners: Array) -> Callable:
    return func() -> void:
        if owners.is_empty():
            return
        for action in actions:
            action.call()


## The console line a drop leaves, and no line on screen at all.
##
## A drop that says nothing leaves a painter with six rows where eight ramps
## were and the way back to a flat canvas gone, with no message, no count and
## no setting to reach for. A pop-up per drop says too much, three of them from
## three ramps in a row, so the screen gets no line. The painter finds out why
## their history is short from the running count in the Undo History docker's
## own footer, one line that stands rather than a line per drop, and it names Preferences > General because the setting is the
## painter's next move. The log keeps its line per drop, because a tester's log
## is where a bug report comes from and a tester wants every one of them.
func _say_steps_were_dropped(lost: int) -> void:
    if pin_budget or _quiet or not announce_drops:
        return
    var what := (
        tr("the oldest step was dropped")
        if lost == 1
        else tr_n("the %d oldest step was dropped", "the %d oldest steps were dropped", lost) % lost
    )
    push_warning("SaHistory: " + tr("Undo history is full, so %s. Preferences > Interface sets how deep it goes.") % what)


## How many of the steps already held can stay alongside one of *incoming* bytes.
##
## Counted from the newest backwards, because that is the end worth keeping, and
## it can be zero: a single step larger than the whole budget still gets to exist,
## since being unable to undo the last thing you did is worse than being over.
## Both pools are walked together, and the first to overflow is where the list
## is cut, because one UndoRedo list can only be shortened from the front.
##
## A step that puts nothing into a pool is never what overflows it. That reads
## as a tautology until the incoming step is over its pool on its own, when the
## room left is below zero and a total of nothing is already "over". Three
## filled layers of a 1920x1080 document deleted as one set are about 120 MiB
## against the 96 MiB layer pool, and without the rule the six adds and fills
## before the delete, which keep no layer at all, would be dropped by a pool
## they never drew on. The delete still stands alone over its pool, and the next step that
## keeps a layer pushes it out, as an oversized stroke is pushed out by the
## next stroke.
func _steps_that_fit_beside(incoming: int, incoming_layers: int = 0) -> int:
    var room := effective_budget() - incoming
    var layer_room := layer_budget_bytes - incoming_layers
    var total := 0
    var layer_total := 0
    var fits := 0
    for i in range(_step_bytes.size() - 1, -1, -1):
        total += _step_bytes[i]
        layer_total += _step_layer_bytes[i]
        var paint_over := _step_bytes[i] > 0 and total > room
        var layers_over := _step_layer_bytes[i] > 0 and layer_total > layer_room
        if paint_over or layers_over:
            break
        fits += 1
    return fits


## The paint budget as it stands, which follows the document rather than a constant.
##
## `budget_bytes` is the floor and the depth from Preferences is the ask, so a
## document whose whole-canvas step costs 40 MiB gets 480 MiB at the default
## twelve and a document whose steps are dabs never leaves the floor. This is
## the cheapest of three answers, a budget that follows the document's own size
## rather than a constant, read off the steps themselves.
##
## The two it is not: eviction cannot take the largest step rather than the
## oldest, because one UndoRedo list shortens from one end only. Spilling a
## snapshot to system memory, which `SaResidency` does past the card's budget,
## keeps the depth this allows without holding all of it in VRAM.
func effective_budget() -> int:
    if pin_budget:
        return budget_bytes
    return maxi(budget_bytes, whole_canvas_depth() * largest_step_bytes)


## How many of the document's most expensive step the painter asked for.
##
## Read live rather than copied in when the history is made, so raising it in
## Preferences reaches a document that is already open. `SaColorRamp` reads its
## own two settings the same way, and the autoload is up before any document is.
func whole_canvas_depth() -> int:
    return maxi(SaSettings.history_depth, 0)


## VRAM the history is holding right now in chunk snapshots.
func total_bytes() -> int:
    var total := 0
    for step in _step_bytes:
        total += step
    return total


## VRAM the history is holding in layers taken out of the document.
func total_layer_bytes() -> int:
    var total := 0
    for step in _step_layer_bytes:
        total += step
    return total


## The snapshot states of every step kept, the oldest step's first, each a
## grid position -> SaChunk, SaChunkDelta or null dictionary. What
## `SaResidency` moves to RAM before any layer's chunks.
func snapshot_states() -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    for states: Array in _step_states:
        for state: Dictionary in states:
            found.append(state)
    return found


## What every step kept holds, one list per step, the oldest step's first: its
## snapshot states and then what it keeps beyond them, the layers it took out
## and the states its swaps are bound to. What `SaResidency` moves to RAM
## before any layer of the tree, and what `SaMemoryBudget.history_bytes` reads.
func holdings() -> Array[Array]:
    var found: Array[Array] = []
    for i in _step_states.size():
        var held: Array = []
        held.append_array(_step_states[i])
        if i < _step_kept.size():
            held.append_array(_step_kept[i])
        found.append(held)
    return found


## How many reversible steps are being kept, a result rather than a setting.
func step_count() -> int:
    return _step_bytes.size()


## Forgets the accounting. The caller is expected to clear the UndoRedo itself,
## because this does not own it.
func reset() -> void:
    _step_bytes.clear()
    _step_layer_bytes.clear()
    _step_states.clear()
    _step_kept.clear()
    step_serials.clear()
    # A place no save has stood on, so the document is clean after a reset only
    # when whoever reset it says so.
    base_serial = _next_serial()
    largest_step_bytes = 0
    dropped_steps = 0


## What one action's snapshot costs, as grid position -> SaChunk, SaChunkDelta or
## null. A stroke leaves deltas and a fill leaves whole chunks, so both are weighed.
static func bytes_of(state: Dictionary) -> int:
    var total := 0
    for grid_pos: Vector2i in state:
        var entry: Variant = state[grid_pos]
        if entry is SaChunkDelta:
            var delta: SaChunkDelta = entry
            total += delta.byte_size()
        elif entry is SaChunk:
            var chunk: SaChunk = entry
            total += chunk.byte_size()
    return total
