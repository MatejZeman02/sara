## The skeleton's Layer menu commands: the tables they are made from, the
## structure commands, the two locks, the mask's seven operations and Clip to
## the Layer Below, what each one does to the primary document's active layer,
## and the loop that registers them through the public door (hard rule 6).
##
## Its own file, cut from `skeleton_module.gd` by what the code owns, as
## `skeleton_blend_modes.gd`'s and `skeleton_selection_commands.gd`'s were:
## everything here acts on the layer stack or a layer's mask, the skeleton calls
## `register`, and the one table read from outside, `LAYER_MENU_COMMANDS`, the
## skeleton's face hands on.
extends RefCounted

## The Layer menu and the docker's own row act on the document already, and
## carried no chord, so they take Krita's map: duplicate, group, delete, move up
## and down, merge down, a new paint layer. Hiding a layer keeps none, because
## Krita ships none for it either and the eye icon already reaches it.
##
## A new paint layer answers Ctrl+Shift+N rather than Krita's Insert: it is what
## Photoshop ships and what a notebook with no Insert key can reach. The note mode gave
## the chord up and is on Ctrl+Alt+N, which no shipped map and no Krita action
## holds, so a painter's Copy Merged on Ctrl+Shift+C stays free.
##
## Merge Visible answers Ctrl+Shift+E, which Krita gives Flatten Image and a
## Krita hand presses to merge what it sees. The brush editor is on F5,
## Krita's own key for it.
##
## Duplicate Layer gave Ctrl+J up to Layer via Copy, Photoshop's own Ctrl+J,
## which duplicates the layer when nothing is selected, so the chord a
## painter pressed to duplicate still does that. It answers Ctrl+Alt+J, where
## Krita keeps Copy Selection to New Layer, so the Krita profile is the same
## three chords with the two swapped and Ctrl+J on the duplicate, as Krita has
## it.
##
## Each row is the id, the title, the menu words, the key, whether Ctrl, Shift
## and Alt are held with it, and the sentence. The sentence is what the row
## shows on hover. It is here rather than in the Layer menu because this is
## where the command is declared, so the menu, the Modules menu and anything
## else that offers the command read one wording of it.
const LAYER_COMMANDS: Array = [
    [
        &"layer_duplicate",
        "Duplicate the layer",
        "Duplicate Layer",
        KEY_J,
        true,
        false,
        true,
        "Duplicate the picked layers, each with its blend mode, opacity and locks.",
    ],
    [
        &"layer_group",
        "Group the selected layers",
        "Group",
        KEY_G,
        true,
        false,
        false,
        "Wrap the picked layers in a new group, or dissolve the group picked alone."
    ],
    [
        &"layer_merge_down",
        "Merge down",
        "Merge Down",
        KEY_E,
        true,
        false,
        false,
        "Merge the picked layers into the lowest of them, or one layer into the one below, using its blend mode.",
    ],
    [
        &"layer_merge_visible",
        "Merge the visible layers",
        "Merge Visible",
        KEY_E,
        true,
        true,
        false,
        "Merge every visible layer into one, as the canvas shows them, where the topmost of them stood. Hidden layers stay.",
    ],
    [
        &"layer_new_paint",
        "New paint layer",
        "New Layer",
        KEY_N,
        true,
        true,
        false,
        "Add an empty layer above the active one.",
    ],
]

## The Layer menu's rows with no chord, as `[id, title, menu words,
## sentence]`: the flatten that acts on the whole stack, the double
## resolution layer's two, its making and its resample, and Rasterize Impasto,
## which `SaRasterizeImpasto` runs, and Rasterize Layer, `SaRasterizeLayer`'s,
## which folds all of them in at once. The clear left this list
## when it took Backspace and Delete, and is registered beside the fills.
const LAYER_MENU_COMMANDS: Array = [
    [
        &"layer_new_double",
        "New layer at double resolution",
        "New Layer at Double Resolution",
        "Add an empty layer above the active one at twice the document's resolution, for fine work zoomed in.",
    ],
    [
        &"layer_bake",
        "Resample the layer to the document's resolution",
        "Resample to Document Resolution",
        "Resample the active double resolution layer to the document's resolution as it shows at 100%, in one step.",
    ],
    [
        &"layer_rasterize_impasto",
        "Rasterize the layer's impasto",
        "Rasterize Impasto",
        "Light the active layer's impasto into its pixels as the view shows it now, and flatten the impasto, in one step.",
    ],
    [
        &"layer_rasterize",
        "Rasterize the layer",
        "Rasterize Layer",
        "Turn the active layer into plain paint as it shows, its transform, mask, filters and impasto in its pixels.",
    ],
    [
        &"layer_flatten",
        "Flatten the image",
        "Flatten",
        "Merge all layers into one.",
    ],
]

## Photoshop's Layer via Copy and Layer via Cut, and Sara's Layer via Seamless
## Cut, as `[id, title, menu words, whether Shift is held with Ctrl+J, whether
## Alt is, sentence]`. Each puts what the selection covers of the active layer
## on a new layer right above it, in place, as one step, and leaves the
## clipboard as it was. Each stands in the canvas right click menu while a
## selection does, so a right click after a lasso offers them.
##
## **Layer via Seamless Cut stands beside Layer via Cut.** A cut
## through a soft selection leaves the new layer at the selection's share and
## the old at the rest, and one over the other covers less than the paint did,
## a pale rim. No cut keeps both pieces soft and stacks back, so the seamless
## one keeps the hole soft and makes the new layer as opaque as the stack
## needs, `seamless_copy_masked.gmacs`. A command of its own beside the cut,
## which keeps what it did.
const VIA_COMMANDS: Array = [
    [
        &"layer_via_copy",
        "Layer via copy",
        "Layer via Copy",
        false,
        false,
        "Copy what the selection covers of the layer to a new layer above it, in place. With nothing selected, duplicate it.",
    ],
    [
        &"layer_via_cut",
        "Layer via cut",
        "Layer via Cut",
        true,
        false,
        "Move what the selection covers of the layer to a new layer above it, in place, leaving a hole where it was.",
    ],
    [
        &"layer_via_seamless_cut",
        "Layer via seamless cut",
        "Layer via Seamless Cut",
        true,
        true,
        # gdlint:ignore=max-line-length
        "Move what the selection covers of the layer to a new layer above it, so the picture looks unchanged while both are shown. The new layer is opaque wherever the selection reaches.",
    ],
]

## What Layer via Copy says when the selection reaches no paint of the layer,
## where Photoshop says the selected area is empty.
const NOTHING_TO_LIFT := "The selection covers no paint on '%s', so there is nothing to put on a new layer."

## The two locks the Layers docker's row draws, as commands, so the Layer
## menu's check items get their chord and their handler from one declaration.
## Each row is the id, the title in sentence case as the Keyboard Shortcuts
## page lists it, the key, whether Ctrl, Shift and Alt are held with it, the
## sentence, and the menu words in title case.
##
## Neither Krita nor Photoshop ships a chord for a layer lock, so there is no
## habit to match and the letters are the ones the labels read from. Ctrl+L is
## Levels, so Lock Layer is Ctrl+Shift+L. Ctrl+A is Select All and
## Ctrl+Shift+A is Krita's Deselect, which a Krita hand presses to drop a
## selection and must not lock the alpha with, so Lock Alpha is Ctrl+Alt+A,
## which no shipped map and no Krita action holds.
const LAYER_LOCK_COMMANDS: Array = [
    [
        &"layer_lock",
        "Lock layer",
        KEY_L,
        true,
        true,
        false,
        "Stop painting on this layer.",
        "Lock Layer",
    ],
    [
        &"layer_alpha_lock",
        "Lock alpha",
        KEY_A,
        true,
        false,
        true,
        "Paint only where this layer already has paint. Its shape cannot grow.",
        "Lock Alpha",
    ],
]

## The mask's seven operations, as commands of the layer category, so the Layer
## menu, the docker's dropdown and the keyboard run one `SaMaskOps.run`, whose
## constants the ids repeat as literals because a `const` naming a global class
## breaks the class cache. Only the add carries a chord. Krita's is Ctrl+Shift+G
## and that chord is Clip to Layer Below here, so the add takes Ctrl+Shift+M,
## which no command and no tool answers.
const MASK_COMMANDS: Array = [
    [
        &"layer_mask_add",
        "Add a mask",
        "Add Mask",
        KEY_M,
        "A mask on the active layer or group that hides nothing yet. Paint it black to hide.",
    ],
    [
        &"layer_mask_add_from_selection",
        "Add a mask from the selection",
        "Add Mask from Selection",
        KEY_NONE,
        "A mask that shows what is selected and hides the rest. With nothing selected it hides nothing.",
    ],
    [
        &"layer_mask_delete",
        "Delete the mask",
        "Delete Mask",
        KEY_NONE,
        "Take the mask away without applying it, so the layer shows whole.",
    ],
    [
        &"layer_mask_apply",
        "Apply the mask",
        "Apply Mask",
        KEY_NONE,
        "Hide for good what the mask hides: its coverage is multiplied into the layer's alpha and the mask goes.",
    ],
    [&"layer_mask_invert", "Invert the mask", "Invert Mask", KEY_NONE, "What the mask hid shows, and what it showed is hidden."],
    [
        &"layer_mask_disable",
        "Disable or enable the mask",
        "Disable Mask",
        KEY_NONE,
        "Switch the mask off, so the layer shows whole, or back on. The mask is kept either way.",
    ],
    [
        &"layer_mask_to_selection",
        "Mask to selection",
        "Mask to Selection",
        KEY_NONE,
        "Select what the mask shows, in place of the selection.",
    ],
]


static func register(ctx: SaContext) -> void:
    # Clip to the layer below, on the active layer, with Krita's chord. The
    # registry makes it from these events rather than an action in
    # project.godot, which is the same way a module ships a shortcut. A weak
    # reference, because the context holds the registries that hold this
    # command, and a handler holding the context would close that into a cycle
    # nothing ever frees.
    var clip := SaCommandDescriptor.create(
        &"layer_clip_to_below", "Clip to the layer below", _toggle_clip_to_below.bind(weakref(ctx))
    )
    clip.label = "Clip to Layer Below"
    var chord := InputEventKey.new()
    chord.keycode = KEY_G
    chord.ctrl_pressed = true
    chord.shift_pressed = true
    clip.default_events = [chord]
    clip.category = &"layer"
    clip.sentence = "Show this layer only where the layer below it has paint, and hide it when that one is hidden."
    ctx.register_command(clip)

    for entry: Array in LAYER_LOCK_COMMANDS:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var lock := _structure_command(ctx, entry_id, title)
        var lock_key := InputEventKey.new()
        lock_key.keycode = entry[2]
        lock_key.ctrl_pressed = entry[3]
        lock_key.shift_pressed = entry[4]
        lock_key.alt_pressed = entry[5]
        lock.default_events = [lock_key]
        lock.label = entry[7]
        lock.category = &"layer"
        lock.sentence = entry[6]
        lock.checked = _layer_flag.bind(weakref(ctx), entry[0])
        ctx.register_command(lock)

    for entry: Array in LAYER_COMMANDS:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var command := _structure_command(ctx, entry_id, title)
        command.label = entry[2]
        var key := InputEventKey.new()
        key.keycode = entry[3]
        key.ctrl_pressed = entry[4]
        key.shift_pressed = entry[5]
        key.alt_pressed = entry[6]
        command.default_events = [key]
        command.category = &"layer"
        command.sentence = entry[7]
        ctx.register_command(command)

    for entry: Array in VIA_COMMANDS:
        var via_id: StringName = entry[0]
        var title: String = entry[1]
        var via := SaCommandDescriptor.create(via_id, title, _via_command.bind(weakref(ctx), via_id))
        via.label = entry[2]
        var via_key := InputEventKey.new()
        via_key.keycode = KEY_J
        via_key.ctrl_pressed = true
        via_key.shift_pressed = entry[3]
        via_key.alt_pressed = entry[4]
        via.default_events = [via_key]
        via.category = &"layer"
        via.sentence = entry[5]
        via.enabled = _via_runs.bind(weakref(ctx), via_id)
        via.show_in_context_menu = true
        via.context_when = _selection_stands.bind(weakref(ctx))
        ctx.register_command(via)

    for entry: Array in MASK_COMMANDS:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var mask_command := SaCommandDescriptor.create(entry_id, title, _mask_command.bind(weakref(ctx), entry_id))
        mask_command.label = entry[2]
        mask_command.enabled = _mask_runs.bind(weakref(ctx), entry[0])
        if entry_id == &"layer_mask_disable":
            mask_command.checked = _mask_disabled.bind(weakref(ctx))
        if entry[3] != KEY_NONE:
            var mask_key := InputEventKey.new()
            mask_key.keycode = entry[3]
            mask_key.ctrl_pressed = true
            mask_key.shift_pressed = true
            mask_command.default_events = [mask_key]
        mask_command.category = &"layer"
        mask_command.sentence = entry[4]
        ctx.register_command(mask_command)

    var delete_command := _structure_command(ctx, &"layer_delete", "Delete the layer")
    delete_command.label = "Delete Layer"
    var delete_key := InputEventKey.new()
    delete_key.keycode = KEY_DELETE
    delete_key.shift_pressed = true
    delete_command.default_events = [delete_key]
    delete_command.category = &"layer"
    delete_command.sentence = "Delete the picked layers as one step. The only layer is emptied rather than deleted."
    ctx.register_command(delete_command)

    var up := _structure_command(ctx, &"layer_move_up", "Move the layer up")
    up.label = "Move Up"
    var up_key := InputEventKey.new()
    up_key.keycode = KEY_PAGEUP
    up_key.ctrl_pressed = true
    up.default_events = [up_key]
    up.category = &"layer"
    up.sentence = "Move the layer up one place."
    ctx.register_command(up)

    var down := _structure_command(ctx, &"layer_move_down", "Move the layer down")
    down.label = "Move Down"
    var down_key := InputEventKey.new()
    down_key.keycode = KEY_PAGEDOWN
    down_key.ctrl_pressed = true
    down.default_events = [down_key]
    down.category = &"layer"
    down.sentence = "Move the layer down one place."
    ctx.register_command(down)

    # PageUp and PageDown make the next row active: the stack bottom first is
    # the docker's list read upwards.
    for step: Array in [
        [&"layer_select_above", "Select the layer above", KEY_PAGEUP, "The next row up the list becomes the active layer."],
        [&"layer_select_below", "Select the layer below", KEY_PAGEDOWN, "The next row down the list becomes the active layer."],
    ]:
        var select_id: StringName = step[0]
        var title: String = step[1]
        var select := _structure_command(ctx, select_id, title)
        var select_key := InputEventKey.new()
        select_key.keycode = step[2]
        select.default_events = [select_key]
        select.category = &"layer"
        select.sentence = step[3]
        ctx.register_command(select)

    # Rows of the Layer menu that had no command and no chord. Each has an action
    # with no key, so the Keyboard Shortcuts page lists it and a painter can bind it.
    for entry: Array in LAYER_MENU_COMMANDS:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var command := _structure_command(ctx, entry_id, title)
        command.label = entry[2]
        command.category = &"layer"
        command.sentence = entry[3]
        ctx.register_command(command)


## What each structure command does and when its row is lit, by id, which the
## loops in `register` bind into the command. A new layer command is its row in
## a table above and its line here, with the act beside it, and nothing else
## names its id.
##
## Each line is the act and, for a command whose row dims, the test. An act on
## the stack takes the document alone and runs with no active layer, and an act
## on the set takes the document, the picked set and the context.
static func _acts() -> Dictionary:
    return {
        &"layer_new_paint": [_on_stack, _new_paint],
        &"layer_new_double": [_on_stack, _new_double],
        &"layer_flatten": [_on_stack, _flatten],
        &"layer_merge_visible": [_on_stack, _merge_visible],
        &"layer_duplicate": [_on_set, _duplicate],
        &"layer_merge_down": [_on_set, _merge_down, _can_merge_down],
        &"layer_move_up": [_on_set, _move.bind(1), _can_move.bind(1)],
        &"layer_move_down": [_on_set, _move.bind(-1), _can_move.bind(-1)],
        &"layer_select_above": [_on_set, _select_step.bind(1)],
        &"layer_select_below": [_on_set, _select_step.bind(-1)],
        &"layer_group": [_on_set, _group],
        &"layer_delete": [_on_set, _delete, _can_delete],
        &"layer_lock": [_on_set, _lock],
        &"layer_alpha_lock": [_on_set, _alpha_lock],
        &"layer_bake": [_on_set, _bake, _can_bake],
        &"layer_rasterize_impasto": [_on_set, _rasterize_impasto, _can_rasterize_impasto],
        &"layer_rasterize": [_on_set, _rasterize, _can_rasterize],
    }


## Makes the descriptor of a structure command from its line in `_acts`, the
## handler and, where the line has one, the test that dims its row.
static func _structure_command(ctx: SaContext, command_id: StringName, title: String) -> SaCommandDescriptor:
    var line: Array = _acts()[command_id]
    var by_ref: Callable = line[0]
    var command := SaCommandDescriptor.create(command_id, title, by_ref.bind(weakref(ctx), line[1]))
    if line.size() > 2:
        command.enabled = _runs.bind(weakref(ctx), line[2])
    return command


## Runs an act on the primary document's stack, answering whether there was a
## document to act on.
static func _on_stack(ctx_ref: WeakRef, act: Callable) -> bool:
    var document := _primary_document(ctx_ref)
    if document == null:
        return false
    act.call(document)
    return true


## Runs an act on the primary document's picked set, answering whether there
## was a layer to act on.
##
## **Duplicate, Group, Merge Down, Delete and the two locks act on the picked
## set**, `document.picked`, which the Layers docker hands on whenever its pick
## moves, and do to it what the docker's own buttons do. Read off the active
## layer alone, Ctrl+E would merge it into the layer under the set, one the
## painter never picked. With no docker the set is the active layer.
static func _on_set(ctx_ref: WeakRef, act: Callable) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var document := _primary_document(ctx_ref)
    if document == null or document.active_layer == null:
        return false
    act.call(document, document.picked.acted_on(document), ctx)
    return true


## Whether a structure command would act on the active layer, which dims its
## row. Each test asks the `can_` function beside the operation its act runs,
## so the row and the press cannot come to disagree.
static func _runs(ctx_ref: WeakRef, test: Callable) -> bool:
    var document := _primary_document(ctx_ref)
    if document == null or document.active_layer == null:
        return false
    return test.call(document, document.picked.acted_on(document))


static func _new_paint(document: SaDocument) -> void:
    SaLayerOps.new(document).add()


static func _new_double(document: SaDocument) -> void:
    SaLayerOps.new(document).add(&"", null, 2.0)


static func _flatten(document: SaDocument) -> void:
    SaLayerOps.new(document).flatten()


static func _merge_visible(document: SaDocument) -> void:
    SaMergeVisible.new(document).merge()


static func _duplicate(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext) -> void:
    SaLayerDuplicate.new(document).write(SaLayerStack.roots(document, picked))


static func _merge_down(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext) -> void:
    SaLayerOps.new(document).merge_down(document.active_layer, picked)


static func _can_merge_down(document: SaDocument, picked: Array[SaLayer]) -> bool:
    return SaLayerOps.new(document).can_merge_down(document.active_layer, picked)


## Moves the picked set one place up the stack, or down, with the step bound.
static func _move(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext, step: int) -> void:
    SaLayerSetStep.new(document).move(picked, step)


static func _can_move(document: SaDocument, picked: Array[SaLayer], step: int) -> bool:
    return SaLayerSetStep.new(document).can_move(picked, step)


## Makes the row one place up the stack, or down, the active layer, and
## nothing past either end.
static func _select_step(document: SaDocument, _picked: Array[SaLayer], _ctx: SaContext, step: int) -> void:
    var stack := SaLayerOps.new(document).layers()
    var at := stack.find(document.active_layer) + step
    if at >= 0 and at < stack.size():
        document.set_active_layer(stack[at])


## Dissolves the group picked alone, or wraps the picked set in a new group
## and makes it active.
static func _group(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext) -> void:
    var groups := SaLayerOps.new(document)
    if picked.size() == 1 and document.active_layer.is_group:
        groups.ungroup(document.active_layer)
        return
    var group := groups.group_layers(picked)
    if group != null:
        document.set_active_layer(group)


static func _delete(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext) -> void:
    SaLayerOps.new(document).remove_many(picked)


static func _can_delete(document: SaDocument, picked: Array[SaLayer]) -> bool:
    return picked.size() > 1 or SaLayerOps.new(document).can_remove(document.active_layer)


## The locks are one step over the set, which the docker row hears through the
## document. The active layer's flag says which way the set goes, as the menu's
## tick shows it.
static func _lock(document: SaDocument, picked: Array[SaLayer], _ctx: SaContext) -> void:
    SaLayerFlagStep.new(document).write(picked, &"paint", not document.active_layer.is_locked)


static func _alpha_lock(document: SaDocument, picked: Array[SaLayer], ctx: SaContext) -> void:
    var layer := document.active_layer
    SaLayerFlagStep.new(document).write(picked, &"alpha", not layer.alpha_locked)
    if layer.alpha_locked:
        EventBus.corner_notice.emit(_alpha_lock_line(ctx, layer))


static func _bake(document: SaDocument, _picked: Array[SaLayer], _ctx: SaContext) -> void:
    SaLayerOps.new(document).bake(document.active_layer)


static func _can_bake(document: SaDocument, _picked: Array[SaLayer]) -> bool:
    return SaLayerOps.new(document).can_bake(document.active_layer)


static func _rasterize_impasto(document: SaDocument, _picked: Array[SaLayer], ctx: SaContext) -> void:
    SaRasterizeImpasto.new(ctx.get_easel()).rasterize(document.active_layer)


static func _can_rasterize_impasto(document: SaDocument, _picked: Array[SaLayer]) -> bool:
    return SaRasterizeImpasto.can_rasterize(document, document.active_layer)


static func _rasterize(document: SaDocument, _picked: Array[SaLayer], ctx: SaContext) -> void:
    SaRasterizeLayer.new(ctx.get_easel()).rasterize(document.active_layer)


static func _can_rasterize(document: SaDocument, _picked: Array[SaLayer]) -> bool:
    return SaRasterizeLayer.can_rasterize(document, document.active_layer)


## The corner line Lock Alpha turning on says: the layer by name, what the lock
## does to the next stroke, and the way to turn it off. A lock taken by a chord
## pressed for something else reads as a brush that stopped working, and
## turning it off is what the painter went looking for, so that says nothing.
## The chord is read from the map as it stands, so a rebind names the new one,
## and a profile that clears it, as Krita's does, points at the menu.
static func _alpha_lock_line(ctx: SaContext, layer: SaLayer) -> String:
    var line := (
        TranslationServer.translate("Lock Alpha is on for '%s', so paint lands only where the layer already has paint.")
        % layer.name
    )
    var chord := ctx.commands.chord_text(&"layer_alpha_lock", 1)
    if chord.is_empty():
        return line + " " + TranslationServer.translate("Lock Alpha on the Layer menu turns it off.")
    return line + " " + TranslationServer.translate("%s turns it off.") % chord


## A mask operation on every layer of the primary document's picked set, as one
## step, answering whether there was one it could run on.
static func _mask_command(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null:
        return false
    return SaLayerSetStep.new(document).run_mask(command_id, document.picked.acted_on(document), document.active_layer)


## Layer via Copy, Layer via Cut or Layer via Seamless Cut on the primary
## document's active layer, answering whether a layer was made. The seamless
## cut is a cut in all but the new layer's alpha, `SaClipboard.to_new_layer`.
##
## **Through a clipboard of its own**, `SaClipboard.to_new_layer`, so what
## Copy left in the document's clipboard is still there to paste. The copy,
## the cut's clearing and the paste's new layer are three doors that
## each record, and `as_one` gathers them into one step, so one Ctrl+Z takes
## the new layer away and puts the cut pixels back.
##
## **With nothing selected Layer via Copy duplicates** the picked layers, as
## Duplicate Layer does and as Photoshop's Ctrl+J does, and Layer via Cut does
## nothing, its row dimmed.
static func _via_command(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var document := _primary_document(ctx_ref)
    if document == null or document.active_layer == null:
        return false
    var seamless := command_id == &"layer_via_seamless_cut"
    var cut := command_id == &"layer_via_cut" or seamless
    # Select All's selection is everything on the layer, so Layer via Copy
    # duplicates as with none, past the canvas edge too.
    if not document.selection.active or (not cut and document.selection.selects_everything()):
        if cut:
            return false
        return SaLayerDuplicate.new(document).write(SaLayerStack.roots(document, document.picked.acted_on(document))) != null
    var layer := document.active_layer
    var made: Array[SaLayer] = []
    var work := func() -> void:
        var put := SaClipboard.to_new_layer(document, layer, cut, seamless)
        if put != null:
            made.append(put)
    var title := "Layer via Seamless Cut" if seamless else ("Layer via Cut" if cut else "Layer via Copy")
    if document.history != null:
        document.history.as_one(title, work)
    else:
        work.call()
    if made.is_empty() and not (cut and layer.is_locked):
        # A locked layer's cut says why itself, so this says the other reason.
        SaProblems.refuse(title, TranslationServer.translate(NOTHING_TO_LIFT) % layer.name)
    return not made.is_empty()


## Whether a Layer via command can run, which dims its row: Copy on any layer,
## and the two cuts only while something is selected.
static func _via_runs(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var document := _primary_document(ctx_ref)
    if document == null or document.active_layer == null:
        return false
    return command_id == &"layer_via_copy" or document.selection.active


## Whether the primary document holds a selection, which puts the three Layer
## via rows in the canvas right click menu.
static func _selection_stands(ctx_ref: WeakRef) -> bool:
    var document := _primary_document(ctx_ref)
    return document != null and document.selection != null and document.selection.active


## The primary document, or null with no context or no easel.
static func _primary_document(ctx_ref: WeakRef) -> SaDocument:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    return easel.document if easel != null else null


## The primary document's active layer, or null, for the ticks and dims below.
static func _active_layer(ctx_ref: WeakRef) -> SaLayer:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    return document.active_layer if document != null else null


## A lock's tick: the active layer's own flag, unticked with no layer.
static func _layer_flag(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var layer := _active_layer(ctx_ref)
    if layer == null:
        return false
    return layer.is_locked if command_id == &"layer_lock" else layer.alpha_locked


## Whether a mask operation can run on a layer of the picked set, which dims its row.
static func _mask_runs(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null:
        return false
    return SaLayerSetStep.can_mask(command_id, document.picked.acted_on(document))


## Disable Mask's tick: a mask is there and it is off.
static func _mask_disabled(ctx_ref: WeakRef) -> bool:
    var layer := _active_layer(ctx_ref)
    return SaMaskOps.can(&"layer_mask_disable", layer) and not layer.mask.enabled


## Flips the clip flag over the picked set as one step, the active layer's flag
## saying which way, as the More menu's row does, so the chord is a step of the
## history like the row. True when there was a layer to flip.
static func _toggle_clip_to_below(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    if ctx == null:
        return false
    var easel := ctx.get_easel()
    var document: SaDocument = easel.document if easel != null else null
    if document == null or document.active_layer == null:
        return false
    SaLayerFlagStep.new(document).write(document.picked.acted_on(document), &"clip", not document.active_layer.clip_to_below)
    return true
