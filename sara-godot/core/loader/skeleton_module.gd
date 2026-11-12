## The skeleton's own built-ins, registered through the public module API.
##
## This exists to make the guiding rule executable: every built-in feature
## registers the same way a third party would, so an API gap shows up as a broken
## built-in at startup rather than as someone else's bug report. The blend modes
## are registered here rather than kept as a list inside SaCompositor, whose
## kernel *indices* would have to match the order of #kernel directives in
## composite.gmacs in silence.
##
## Tools are deliberately NOT here: they live in sara-base-modules, because a
## skeleton that ships zero tools is the strongest proof the tool API is real.
extends SaModule

## The blend modes are `skeleton_blend_modes.gd`, the table and its loop.
const SkeletonBlendModes = preload("res://core/loader/skeleton_blend_modes.gd")
## The Select commands are `skeleton_selection_commands.gd`, the same shape.
const SkeletonSelectionCommands = preload("res://core/loader/skeleton_selection_commands.gd")
## Krita's blending mode commands, on the brush's mode.
const SkeletonBlendModeCommands = preload("res://core/loader/skeleton_blend_mode_commands.gd")
## The Layer menu's commands, the locks and the mask's, are
## `skeleton_layer_commands.gd`.
const SkeletonLayerCommands = preload("res://core/loader/skeleton_layer_commands.gd")
## The view's switches and modes are `skeleton_view_transforms.gd`.
const SkeletonViewTransforms = preload("res://core/loader/skeleton_view_transforms.gd")
## The picture formats, every reader and writer still in core, are a package.
const SkeletonImageFormats = preload("res://core/loader/image_formats/skeleton_image_formats.gd")
## The Layer menu's rows with no chord, which the chords suite reads off the
## skeleton, the package's face, rather than off the file that declares them.
const LAYER_MENU_COMMANDS: Array = SkeletonLayerCommands.LAYER_MENU_COMMANDS
## The skeleton is Sara's whole project, so its folder is `res://` and its
## manifest `res://manifest.cfg`.
const FOLDER := "res://"


## The manifest says the version `project.godot` gives Sara, and a suite holds
## the two together. The default `register()` never walks the folder, because
## the skeleton writes its own.
func _init() -> void:
    super(FOLDER)


func get_id() -> StringName:
    return &"sara-skeleton"


func get_name() -> String:
    return "Sara Skeleton"


## Sara's own version, where the manifest is not read.
func get_version() -> String:
    return SaBuildInfo.version()


func register(ctx: SaContext) -> void:
    SkeletonBlendModes.register(ctx)

    # The plain RGBA layer, registered the same way a module would register an
    # impasto or a Kubelka-Munk one. This is the executable half of the guiding
    # rule for layer types: removing this line has to break the layers docker,
    # because a door only the built-ins can walk through is not a door.
    ctx.register_layer_type(SaLayerTypeDescriptor.plain())
    # The background that stores nothing, through the same door, so a
    # module's generated type has a built-in to measure against.
    ctx.register_layer_type(SaLayerTypeDescriptor.background())
    # The paper ground beside it, the second generator, which is what says the
    # door takes more than the one type it was written around.
    ctx.register_layer_type(SaLayerTypeDescriptor.paper())
    ctx.register_layer_type(SaLayerTypeDescriptor.canvas())
    # The adjustment layer, whose attached filters run over the backdrop below it.
    ctx.register_layer_type(SaBackdropLayer.descriptor())
    # The effect layer, whose attached filters run over a node it names.
    ctx.register_layer_type(SaEffectLayer.descriptor())
    # The layer a frame another program sends lands in, which a module that
    # receives one reaches by its role, since a module never names the skeleton.
    ctx.register_layer_type(SaFrameLayer.descriptor())
    # Flat, equirectangular and polar, through the door a module's kind takes.
    for kind: SaProjection.Kind in SaProjection.builtins():
        ctx.register_projection(kind)

    # The engines the skeleton constructs, under the roles the construction
    # sites ask for. Each `new()` in the Canvas Size and Image Size dialogs,
    # the crop-to-selection command, the Select menu's invert and the crop
    # and transform tools is a lookup of one of these, so a module that
    # registers a subclass under the same role is what those sites build
    # from then on. The flood and the gradient are the base module's
    # engines, and it registers them under `flood` and `gradient` the same
    # way. `transform` followed them there: the transform tool was its only
    # asker, so the line is the base module's now and the skeleton keeps no
    # engine for one feature.
    ctx.register_role(&"crop", SaCrop)
    # The crop tool crops the active layer through its live transform, which
    # a module reaches by this role and not by name.
    ctx.register_role(&"live_transform", SaLiveTransform)
    ctx.register_role(&"resample", SaResample)
    ctx.register_role(SaFrameLayer.ROLE, SaFrameLayer)
    ctx.register_role(&"selection_filters", SaSelectionFilters)

    SkeletonLayerCommands.register(ctx)
    _register_symmetry_commands(ctx)
    SkeletonSelectionCommands.register(ctx)
    SkeletonBlendModeCommands.register(ctx)
    SaSimulation.register_commands(ctx)
    SkeletonViewTransforms.register(ctx)
    SkeletonImageFormats.register(ctx)
    _register_image_commands(ctx)
    _register_fill_commands(ctx)
    SaFilterAgain.register_command(ctx)


## The three symmetry switches, registered the way a module's command is, so
## the feature has the same door as everything else. No default chord: Krita
## ships none either.
##
## The two axes are Mirror Horizontally and Mirror Vertically, the words the
## bar's pair says as Mirror H and Mirror V, so the control has one name
## wherever a painter meets it. The view's flip on H says Flip and never
## Mirror: one word for both jobs had a painter who meant to check a face
## flipped paint two noses. The sentence says which of the two this is.
func _register_symmetry_commands(ctx: SaContext) -> void:
    var entries := [
        [&"symmetry_horizontal", "Mirror horizontally", &"mirror_horizontal", "Mirror Horizontally", "mirrored left to right"],
        [&"symmetry_vertical", "Mirror vertically", &"mirror_vertical", "Mirror Vertically", "mirrored top to bottom"],
        [&"symmetry_radial", "Radial symmetry", &"radial", "Radial Symmetry", "repeated around the centre"],
    ]
    for entry: Array in entries:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var command := SaCommandDescriptor.create(entry_id, title, _toggle_symmetry.bind(weakref(ctx), entry[2]))
        command.label = entry[3]
        command.sentence = "Paint every stroke again, %s. The view is not flipped." % entry[4]
        command.category = &"symmetry"
        command.show_in_context_menu = true
        ctx.register_command(command)


## The Image menu's crop. Registered rather than wired into the menu, because
## the menu is a place to reach it from and the chord is another, and a
## command that lives in a menu handler has only one door.
##
## Ctrl+Shift+X, because neither Krita nor Photoshop ships a default for this
## and everything nearer was taken: C is the crop tool, X swaps the colour
## pair, and Ctrl+Shift+C is Copy Merged in Krita and Photoshop both, left free
## for a Copy Merged of Sara's own. The note mode is on Ctrl+Alt+N.
func _register_image_commands(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(
        &"image_crop_to_selection", "Crop to selection", _crop_to_selection.bind(weakref(ctx))
    )
    command.label = "Crop to Selection"
    var chord := InputEventKey.new()
    chord.keycode = KEY_X
    chord.ctrl_pressed = true
    chord.shift_pressed = true
    command.default_events = [chord]
    command.category = &"image"
    command.sentence = "Cut the canvas down to the selection's bounding box, in one undoable step."
    command.enabled = SkeletonSelectionCommands.has_selection.bind(weakref(ctx))
    ctx.register_command(command)


## The two fills, each row its id, its title, its chord, its menu label and
## the sentence its row shows, whole so a catalogue translates it whole.
const FILL_COMMANDS := [
    [
        &"fill_foreground",
        "Fill with foreground colour",
        KEY_BACKSPACE,
        "Fill with Foreground Colour",
        "Fill with foreground colour, over the selected area or the whole layer when nothing is selected, in one history step.",
    ],
    [
        &"fill_background",
        "Fill with background colour",
        KEY_DELETE,
        "Fill with Background Colour",
        "Fill with background colour, over the selected area or the whole layer when nothing is selected, in one history step.",
    ],
]


## The two fills of the colour pair. Alt+Backspace lays the foreground colour
## down and Alt+Delete the background, which is Photoshop's map.
##
## These are the build's own chords, and the shipped Krita profile replaces
## them with Krita's, Shift+Backspace and Delete, the way it replaces every
## command its table names. So a painter on that profile presses Alt and
## Backspace and nothing answers, which is no fault, and the Keyboard Shortcuts
## page is where the other chord shows.
##
## The clear is the third, a fill with nothing, and takes both bare keys:
## Backspace is Krita's Clear and Delete is Photoshop's, so
## either hand clears the selected area in one step.
## A focused name field keeps a bare key, which is `text_field_keeps` in
## `ShortcutRouter`, so a rename box still deletes its own letters. Krita's
## profile gives Delete back to the background fill, as Krita ships it, and
## leaves the clear on Backspace alone.
##
## Registered rather than wired into the Edit menu, for the reason the crop
## above is: a chord is one door to a command and a menu is another, and a
## command that lives in a menu handler has only the one.
func _register_fill_commands(ctx: SaContext) -> void:
    for entry: Array in FILL_COMMANDS:
        var entry_id: StringName = entry[0]
        var title: String = entry[1]
        var command := SaCommandDescriptor.create(entry_id, title, _fill_command.bind(weakref(ctx), entry_id))
        var key := InputEventKey.new()
        key.keycode = entry[2]
        key.alt_pressed = true
        command.default_events = [key]
        command.label = entry[3]
        command.sentence = entry[4]
        command.category = &"edit"
        ctx.register_command(command)

    var clear := SaCommandDescriptor.create(&"layer_clear", "Clear the layer", _fill_command.bind(weakref(ctx), &"layer_clear"))
    clear.label = "Clear Layer"
    for keycode: Key in [KEY_BACKSPACE, KEY_DELETE]:
        var bare := InputEventKey.new()
        bare.keycode = keycode
        clear.default_events.append(bare)
    clear.category = &"layer"
    clear.sentence = "Empty the selected area to transparent, or the whole layer when nothing is selected, in one history step."
    ctx.register_command(clear)


## Fills the active layer from the colour pair, or clears every picked layer for
## `layer_clear`, inside the selection when there is one, as one history step.
## `SaDocument.fill_layer` owns both of those and refuses a locked layer
## already, so this adds only what a chord needs. This only chooses the target:
## while a mask is the paint target the three keys act on that mask, and on an
## adjustment or an effect layer, which holds no pixels of its own, they act on
## the layer's mask, which decides where its work shows, as Krita's Delete on a
## filter layer clears its selection. Both go through `_fill_mask`, and the
## writing is `SaMaskOps`'s.
##
## False in every case that changes nothing, so the key falls through rather
## than being eaten by a command that did nothing: a group holds its members
## and not pixels, a locked layer is what the lock is for, and a clear of a
## layer with no paint where it would clear has nothing to take away.
##
## A layer that refuses says so in the corner, on the bus a refused stroke uses,
## because a documented chord that answers with silence reads as a broken chord.
## No document says nothing, since there is nothing on screen to explain.
##
## With nothing selected the fill takes the whole layer, as Krita's does, and
## says so on `EventBus.corner_notice`, a route of its own because the fill was
## not refused. The line fades by itself, so it shows on every such fill and a
## fill inside a selection stays as quiet as it was. No line ever says a fill
## or a clear happened when it did not.
func _fill_command(ctx_ref: WeakRef, command_id: StringName) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null or document.active_layer == null:
        return false
    var layer := document.active_layer
    var clearing := command_id == &"layer_clear"
    if _session_in_hand(ctx, easel):
        var held := (
            "The tool still holds a change that is not applied, so the %s did nothing."
            + " Press Enter to apply it or Escape to cancel it first."
        )
        EventBus.paint_refused.emit(tr(held) % (tr("clear") if clearing else tr("fill")))
        return false
    var masked := SaMaskOps.owner_of(document, document.mask_target)
    if masked != null:
        return _fill_mask(document, masked, command_id)
    if layer.is_group:
        EventBus.paint_refused.emit(tr("A group holds layers rather than pixels, so nothing changed. Pick a layer inside it."))
        return false
    if layer.is_locked:
        SaContext.refuse_paint(layer, tr("clear") if clearing else tr("fill"))
        return false
    if layer.is_adjustment() or layer.is_effect():
        return _fill_mask(document, layer, command_id)
    # A generated layer's fill is its colour, so only the rest are asked, and
    # they say the brush's line for a scene layer or a live transform.
    if not layer.is_generated() and SaContext.refuse_paint(layer, tr("clear") if clearing else tr("fill")):
        return false
    var acted_on := document.picked.acted_on(document)
    if clearing and not _holds_paint_to_clear(document, acted_on):
        EventBus.paint_refused.emit(tr("There is no paint to clear here, so nothing changed."))
        return false
    if clearing:
        SaLayerSetStep.new(document).clear(acted_on)
    else:
        document.fill_layer(SaColors.background if command_id == &"fill_background" else SaColors.foreground)
    if document.selection == null or not document.selection.active:
        EventBus.corner_notice.emit(
            (
                tr("Nothing was selected, so the whole layer was cleared.")
                if clearing
                else tr("Nothing was selected, so the fill covered the whole layer.")
            )
        )
    return true


## Whether the tool on *easel*'s surface holds a change it has not written
## yet, a transform's box dragged and not applied above all. The lift is drawn
## where the box is and the layer's own pixels under it are what a fill would
## write, so the colour would land hidden and show where the layer sat once
## the box is applied or cancelled. The machine is the tools package's, which
## core reads by name only, as `SkeletonBlendModeCommands.target_settings` does.
static func _session_in_hand(ctx: SaContext, easel: Object) -> bool:
    for surface: SaSurface in ctx.list_surfaces():
        if surface.easel != easel or surface.tool_machine == null:
            continue
        # Every tool and not the active one only: Alt+Backspace holds Alt,
        # which hands the canvas to the eyedropper while the chord is down,
        # and the transform keeps its box in the air behind it.
        var machine: Object = surface.tool_machine
        var tools: Variant = machine.get(&"registered_tools")
        var registered: Dictionary = tools if tools is Dictionary else {}
        for tool: Variant in registered.values():
            if tool is ToolState:
                var state: ToolState = tool
                if state.holds_session():
                    return true
    return false


## Whether a clear of *picked* would take anything away: a layer that is not
## locked and holds a chunk, inside the selection when there is one, or a
## generated layer, whose clear is its colour. A layer that turns paint away
## keeps its chunks through a clear, so they are not counted. A clear under a
## selection lands only on paint the layer holds, as `SaDocument.fill_layer`
## says, so a layer with no chunk the selection holds would clear nothing.
static func _holds_paint_to_clear(document: SaDocument, picked: Array[SaLayer]) -> bool:
    var selection := document.selection
    var whole := selection == null or not selection.active
    for layer: SaLayer in picked:
        if not is_instance_valid(layer) or layer.is_locked or layer.is_group:
            continue
        if layer.is_generated():
            return true
        if layer.refuses_paint():
            continue
        for grid_pos: Vector2i in layer.chunks:
            if whole or selection.chunks.has(grid_pos):
                return true
    return false


## The fill keys on the mask of *owner*: the mask that is the paint target, or
## the mask of an adjustment or an effect layer, which `SaMaskOps.fill` gives
## one first. The owner's pixels are left as they were. The layer that holds
## the mask refuses when it is locked, as it does for the layer's own fill, and
## a group's mask fills like any other, since the mask holds coverage where the
## group holds no pixels.
##
## A fill that changed nothing answers false with a reason in the corner and
## never a line saying it changed something. A clear of an adjustment's or an
## effect's own mask says in the corner what the painter sees, that its work
## is hidden, since the key did not clear the pixels it did not have.
func _fill_mask(document: SaDocument, owner: Object, command_id: StringName) -> bool:
    var clearing := command_id == &"layer_clear"
    var holder := owner as SaLayer
    if holder == null and document.mask_target != null:
        holder = document.mask_target.holder_in(document)
    if holder != null and holder.is_locked:
        SaContext.refuse_paint(holder, tr("clear") if clearing else tr("fill"))
        return false
    var ops := SaMaskOps.new(document)
    var changed := (
        ops.clear(owner)
        if clearing
        else ops.fill_with(owner, SaColors.background if command_id == &"fill_background" else SaColors.foreground)
    )
    if not changed:
        EventBus.paint_refused.emit(tr("The mask would read the same afterwards, so nothing changed."))
        return false
    var whole := document.selection == null or not document.selection.active
    var shown := owner as SaLayer
    if clearing and shown != null and (shown.is_adjustment() or shown.is_effect()):
        var notice := tr("The effect is hidden in the selected area.")
        if shown.is_adjustment() and whole:
            notice = tr("Nothing was selected, so the adjustment is hidden across the whole layer.")
        elif shown.is_adjustment():
            notice = tr("The adjustment is hidden in the selected area.")
        elif whole:
            notice = tr("Nothing was selected, so the effect is hidden across the whole layer.")
        EventBus.corner_notice.emit(notice)
    elif whole:
        EventBus.corner_notice.emit(
            (
                tr("Nothing was selected, so the whole mask was cleared.")
                if clearing
                else tr("Nothing was selected, so the fill covered the whole mask.")
            )
        )
    return true


## Crops the primary document to its selection. False when there is none, so
## the chord falls through rather than resizing to nothing.
func _crop_to_selection(ctx_ref: WeakRef) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null:
        return false
    # The crop engine is whatever script a module registered for the role, so
    # its constructor and its method are known only at run time.
    @warning_ignore("unsafe_method_access")
    return ctx.engine_for(&"crop").new(document).crop_to_selection()


## Flips one symmetry switch on the primary document. True when there was one.
func _toggle_symmetry(ctx_ref: WeakRef, field: StringName) -> bool:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null:
        return false
    var symmetry := document.symmetry
    if field == &"radial":
        symmetry.radial = 0 if symmetry.radial >= 2 else symmetry.radial_count
    else:
        symmetry.set(field, not symmetry.get(field))
    return true
