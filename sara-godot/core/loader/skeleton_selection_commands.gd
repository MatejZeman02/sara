## The skeleton's Select commands: the table they are made from, what each one
## does to the document's selection, and the loop that registers them through
## the public door (hard rule 6).
##
## Its own file, cut from `skeleton_module.gd` by what the code owns rather than
## by count, as `skeleton_blend_modes.gd`'s was:
## everything here is the selection's commands, the skeleton calls `register`,
## and the one thing it reads back is `has_selection`, which Crop to Selection
## dims its row by.
extends RefCounted

## Each row is the id, the title, the menu words, the chords as
## `[key, ctrl, shift]` with an optional fourth for Alt, and the sentence.
## Select All and Invert take the chords Photoshop and Krita share. The quick
## mask is Alt+Q, Q as it was, because the bare Q is the pan tool here and
## Shift+Q opens Quick Favourites, the Blender chord. Shift+M, the other
## letter it could have had, is one of the five the docker toggles left when
## they moved under the left hand, and stays nobody's.
##
## Deselect answers both programs' chords, because they differ: Ctrl+D is
## Photoshop's and the one a Photoshop hand reaches for, and Ctrl+Shift+A is
## Krita's (`deselect` in `scripts/agents/krita_chords.json`). A Krita hand
## presses it to drop a selection, so no other command may hold it, or the
## selection stays and the next stroke lays nothing. Nothing
## else here wants Ctrl+D: the bare D resets the colour pair.
##
## Reselect is Ctrl+Shift+D in Krita and Photoshop both, and brings back what
## the last Deselect dropped, which `SaSelection.deselect` keeps for it.
const ENTRIES: Array = [
    [
        &"select_all",
        "Select all",
        "All",
        [[KEY_A, true, false]],
        "Select the whole canvas, so an operation on the selection reaches every pixel.",
    ],
    [
        &"select_none",
        "Deselect",
        "Deselect",
        [[KEY_D, true, false], [KEY_A, true, true]],
        "Drop the selection. Painting reaches the whole layer again.",
    ],
    [
        &"select_reselect",
        "Reselect",
        "Reselect",
        [[KEY_D, true, true]],
        "Bring back the selection the last Deselect dropped, exactly as it was.",
    ],
    [
        &"select_invert",
        "Invert the selection",
        "Invert",
        [[KEY_I, true, true]],
        "Swap what is selected for what is not, over the canvas.",
    ],
    [
        &"select_quick_mask",
        "Quick mask",
        "Quick Mask",
        [[KEY_Q, false, false, true]],
        "Paint the selection itself instead of the picture. Every brush edits the mask until this is off.",
    ],
]


## Registers every row of `ENTRIES` on *ctx*. A weak reference in each
## handler, because the context holds the registries that hold the command.
static func register(ctx: SaContext) -> void:
    for entry: Array in ENTRIES:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var command := SaCommandDescriptor.create(entry_id, title, _run.bind(weakref(ctx), entry_id))
        command.label = entry[2]
        var chords: Array = []
        for held: Array in entry[3]:
            var chord := InputEventKey.new()
            chord.keycode = held[0]
            chord.ctrl_pressed = held[1]
            chord.shift_pressed = held[2]
            chord.alt_pressed = held.size() > 3 and held[3] == true
            chords.append(chord)
        command.default_events = chords
        command.category = &"select"
        command.sentence = entry[4]
        if entry_id == &"select_quick_mask":
            command.checked = _quick_mask_on.bind(weakref(ctx))
        if entry_id == &"select_none":
            command.enabled = has_selection.bind(weakref(ctx))
        if entry_id == &"select_reselect":
            command.enabled = _can_reselect.bind(weakref(ctx))
        command.show_in_context_menu = entry_id == &"select_quick_mask"
        ctx.register_command(command)


## Whether the primary document has a selection, which is what Crop to
## Selection and Deselect need to do anything and what dims their rows. The
## crop engine answers false on the same test.
static func has_selection(ctx_ref: WeakRef) -> bool:
    var selection := _selection_of(ctx_ref)
    return selection != null and selection.active


## Reselect's row is lit while a deselect has kept something to bring back.
static func _can_reselect(ctx_ref: WeakRef) -> bool:
    var selection := _selection_of(ctx_ref)
    return selection != null and selection.can_reselect()


## Quick Mask's tick: the selection is being painted rather than the picture.
static func _quick_mask_on(ctx_ref: WeakRef) -> bool:
    var selection := _selection_of(ctx_ref)
    return selection != null and selection.editing


## Runs one command on the primary document's selection. False when there is
## no document, and for a Reselect with nothing kept, so the chord falls
## through rather than being eaten by a command that did nothing.
##
## Every command but the quick mask is one undo step through
## `SaSelection.change`, which records nothing when the command changed
## nothing. The quick mask is a mode and not a change to what is selected.
static func _run(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null:
        return false
    var selection := document.selection
    match command_id:
        &"select_all":
            selection.change(SaSelection.ALL_TITLE, selection.select_all.bind(document.canvas_size))
        &"select_none":
            selection.change(SaSelection.DROP_TITLE, selection.deselect)
        &"select_reselect":
            return selection.change(SaSelection.RESELECT_TITLE, selection.reselect)
        &"select_invert":
            var filters := ctx.engine_for(&"selection_filters")
            var invert := func() -> void:
                # The role's script is a module's, known only at run time.
                @warning_ignore("unsafe_method_access")
                filters.invert(selection, document.canvas_size)
            selection.change(SaSelection.INVERT_TITLE, invert)
        &"select_quick_mask":
            selection.editing = not selection.editing
    return true


## The primary document's selection, or null when there is no document.
static func _selection_of(ctx_ref: WeakRef) -> SaSelection:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    return document.selection if document != null else null
