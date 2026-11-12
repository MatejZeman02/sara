## The commands the router owns: the table of them, the sentence each shows, and
## what each one does.
##
## The router is two things, a set of chord groups asked in turn, and this: a
## catalogue of what Sara can be asked to do from the keyboard or a menu row, in
## the registry's own vocabulary, with the handlers behind it. Only the first is
## about routing a key at all. This class finds what it acts on through the
## providers it is built with, so it holds no router and asks it nothing. The
## view helpers and the view mode policy are here rather than on the router or
## in `main.gd`, because this is what holds the registry.
##
## Everything here answers `bool`, because that is what a `SaCommandDescriptor`
## handler returns: false leaves the event for whoever asks next, which is what
## a chord that arrived with no view or no document has to do.
class_name SaShortcutCommands
extends RefCounted

## Interface scale, the three Shift chords. The step and the bounds live beside
## the commands that move it rather than on the router, because nothing that
## routes a key reads them.
const UI_SCALE_STEP: float = 0.25
const UI_SCALE_MIN: float = 0.5
const UI_SCALE_MAX: float = 3.0

## The `view_mode` number the tonemap shader branches on for a soft proof, which
## is how the notice below recognises a proof that is not the built-in one.
const SOFT_PROOF_VIEW_MODE: int = 3

## The words the View menu draws for the rows of `_rows` whose title is the
## shortcut page's sentence rather than a menu's short name.
const ROW_LABELS: Dictionary = {
    &"view_zoom_in": "Zoom In",
    &"view_zoom_out": "Zoom Out",
    &"view_zoom_100": "Reset Zoom",
    &"view_actual_pixels": "Actual Pixels",
    &"view_rotate_left": "Rotate Left",
    &"view_rotate_right": "Rotate Right",
    &"edit_copy_merged": "Copy Merged",
}

## () -> ToolMachine. The view is the tool machine's, so the chords and the
## wheel move the very same view object and the machine hears every change
## through its one subscription.
var _tool_machine_provider: Callable

## () -> SaCanvas. The document the clipboard, the reveal and the proof's
## notice work on.
var _canvas_provider: Callable

## () -> bool. The maximise, which asks the tree for the focused window and so
## is answered by the router, the one of the two that is a node.
var _maximise: Callable

## The notice a Paste with nothing to put down shows, from the chord and the
## Edit menu's row alike.
const NOTHING_TO_PASTE := "Nothing to paste. Copy in Sara, or put a picture on the desktop clipboard."

## The picture on the desktop clipboard, `SaDesktopPicture.read` in everything
## but a suite: a headless run has no desktop clipboard, and a run on the
## machine of whoever runs the gate would paste whatever they last copied.
## Answers an `SaDesktopPicture` or null.
## Test seam. A suite that replaces it puts `SaDesktopPicture.read` back.
static var desktop_picture: Callable = SaDesktopPicture.read

## What the view mode chords flip, or null, when those chords take nothing.
var _view_transforms: SaViewTransformRegistry

## The mode the last notice spoke for, so a mode put on through the View menu is
## told apart from one a chord here put on and has already said.
var _said_mode: StringName = SaViewTransformRegistry.NORMAL

## The menu's own commands, held here because the registry keeps only their
## handlers. A Callable does not keep its object alive, so an instance nobody
## holds is freed as soon as it has registered, and every handler it bound goes
## invalid. File, New and File, Open then did nothing at all.
var _menu_commands: SaMenuCommands = null


func _init(
    tool_machine_provider: Callable, canvas_provider: Callable, maximise: Callable, view_transforms: SaViewTransformRegistry
) -> void:
    _tool_machine_provider = tool_machine_provider
    _canvas_provider = canvas_provider
    _maximise = maximise
    _view_transforms = view_transforms
    if _view_transforms != null:
        EventBus.canvas_proof_mode_changed.connect(_on_canvas_proof_mode_changed)
        _said_mode = _view_transforms.mode
        _view_transforms.changed.connect(_on_view_transforms_changed)


## Puts the router's own chords in *registry*. Safe to call again: a command
## already there is left alone, so a second router does not push_error over the
## first one's registrations.
func register_into(registry: SaCommandRegistry) -> void:
    if registry == null:
        return
    for entry: Array in _rows():
        if registry.has(entry[0]):
            continue
        var command := SaCommandDescriptor.create(entry[0], entry[1], entry[2])
        command.default_events = entry[3]
        command.category = entry[4]
        if entry.size() > 5:
            command.sentence = entry[5]
        command.label = ROW_LABELS.get(entry[0], "")
        registry.register(command, &"sara-skeleton")
    if _menu_commands == null:
        _menu_commands = SaMenuCommands.new(
            _fit_view, _center_view, _reset_rotation, _history, _document, _holds_session.bind(_tool_machine_provider)
        )
    _menu_commands.register_into(registry)


## The table itself, one row per command.
##
## Zoom is on Ctrl with plus, minus and zero, which is Krita's and Photoshop's
## and the interface scale on the same three with Shift, so the two never fight
## over a chord. Actual pixels is Ctrl with one, Photoshop's, which neither the
## shipped set nor Krita's gives anything else. All six, and the three
## clipboard chords, are in the registry rather than answered by keycode in the
## router's own branches, so the shortcuts dialog lists them and a painter can
## rebind any of them.
##
## The events name the key by its label rather than by its position, because
## a chord a painter is told about is the one printed on the key. Each row is
## the command id, its title, its handler and the keys it answers to.
##
## **A sixth element is the sentence a menu row shows on hover**, and a row with
## no menu entry to explain leaves it off, the way
## `SaAppCommands.DOCKER_COMMANDS` leaves off its second key. The interface
## scale and the two proofs are reached from Preferences and the keyboard and
## from no menu, so there is nothing here for them to say.
func _rows() -> Array:
    return [
        [
            &"view_zoom_in",
            "Zoom in",
            _zoom_view.bind(true),
            [_chord(KEY_EQUAL, true), _chord(KEY_PLUS, true), _chord(KEY_KP_ADD, true)],
            &"view",
            tr("Closer, about the middle of the view. The document is not resized."),
        ],
        [
            &"view_zoom_out",
            "Zoom out",
            _zoom_view.bind(false),
            [_chord(KEY_MINUS, true), _chord(KEY_KP_SUBTRACT, true)],
            &"view",
            tr("Further away, about the middle of the view. The document is not resized."),
        ],
        # Under the id it had as Zoom to 100 percent, so a chord a painter saved
        # for it, the Krita table's row and every scenario still name it.
        [
            &"view_zoom_100",
            "Reset zoom",
            _reset_zoom,
            [_chord(KEY_0, true), _chord(KEY_KP_0, true)],
            &"view",
            tr("Toggle between your view and the picture centred, fitted or at 100% as set in Preferences > Canvas and colour."),
        ],
        [
            &"view_actual_pixels",
            "Actual pixels",
            _actual_pixels,
            [_chord(KEY_1, true), _chord(KEY_KP_1, true)],
            &"view",
            tr("Centre the picture at 100%, one image pixel to one screen pixel."),
        ],
        [
            &"view_rotate_left",
            "Rotate the view left",
            _rotate_view.bind(-1.0),
            [_chord(KEY_BRACKETLEFT, true)],
            &"view",
            tr("Turn the view anticlockwise, the way a painter turns the paper."),
        ],
        [
            &"view_rotate_right",
            "Rotate the view right",
            _rotate_view.bind(1.0),
            [_chord(KEY_BRACKETRIGHT, true)],
            &"view",
            tr("Turn the view clockwise, the way a painter turns the paper."),
        ],
        [
            &"ui_scale_up",
            "Larger interface",
            _nudge_ui_scale.bind(UI_SCALE_STEP),
            [_chord(KEY_EQUAL, true, true), _chord(KEY_PLUS, true, true), _chord(KEY_KP_ADD, true, true)],
            &"interface",
        ],
        [
            &"ui_scale_down",
            "Smaller interface",
            _nudge_ui_scale.bind(-UI_SCALE_STEP),
            [_chord(KEY_MINUS, true, true), _chord(KEY_KP_SUBTRACT, true, true)],
            &"interface",
        ],
        [
            &"ui_scale_reset",
            "Reset the interface size",
            _reset_ui_scale,
            [_chord(KEY_0, true, true), _chord(KEY_KP_0, true, true)],
            &"interface",
        ],
        [&"view_soft_proof", "Soft proof", _canvas_proof, [_chord(KEY_Y, true)], &"view"],
        [
            &"view_shape_check",
            "Shape check",
            _shape_check,
            [_chord(KEY_Q, true, true)],
            &"view",
            tr("Show the canvas as flat blocks at a few steps of lightness, so the silhouette reads on its own."),
        ],
        [&"view_minimap_proof", "Minimap proof", _minimap_proof, [_chord(KEY_Y, true, true)], &"view"],
        [
            &"docker_maximise",
            "Maximize the focused docker",
            _maximise,
            [_chord(KEY_SPACE, true)],
            &"docker",
            tr("Fill the window with the docker or dialog that has the keyboard, and put it back on the same shortcut."),
        ],
        [
            &"edit_cut",
            "Cut",
            _clipboard.bind(&"cut"),
            [_chord(KEY_X, true)],
            &"edit",
            tr("Copy the selected part of the active layer, then clear it, as one history step."),
        ],
        [
            &"edit_copy",
            "Copy",
            _clipboard.bind(&"copy"),
            [_chord(KEY_C, true)],
            &"edit",
            tr(
                (
                    "Copy the selected part of the active layer, or the whole layer if nothing is selected. "
                    + "The pixels stay inside Sara and paste into Sara only."
                )
            ),
        ],
        [
            &"edit_copy_merged",
            "Copy merged",
            _clipboard.bind(&"copy_merged"),
            [_chord(KEY_C, true, true)],
            &"edit",
            tr(
                (
                    "Copy the selected part of every visible layer, merged as the canvas shows it, or the whole picture if "
                    + "nothing is selected. The pixels stay inside Sara and paste into Sara only."
                )
            ),
        ],
        [
            &"edit_paste",
            "Paste",
            _clipboard.bind(&"paste"),
            [_chord(KEY_V, true)],
            &"edit",
            tr(
                (
                    "Paste as a new layer in the same place. With nothing copied in Sara, paste a picture from the "
                    + "desktop clipboard at once, centred, at its own size when it fits."
                )
            ),
        ],
        [
            &"edit_paste_special",
            "Paste special",
            _clipboard.bind(&"paste_special"),
            [_chord(KEY_V, true, true)],
            &"edit",
            tr("Paste the picture on the desktop clipboard as a new layer, asking first how it should fit the canvas."),
        ],
    ]


## A key by its label, for the InputMap.
static func _chord(keycode: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    return event


## Ctrl+Y: the canvas shows what the Canvas proof preference names, or the
## picture again when it is already showing it. Which mode that is comes from
## Preferences rather than from here, because the proof is one the painter
## chooses and not only a greyscale one.
func _canvas_proof() -> bool:
    return _toggle_view_mode(StringName(SaSettings.canvas_proof_mode))


## Ctrl+Shift+Q: the shape check on, or the picture again when it is already on.
##
## Q for squint, which is the thing this mode replaces, and the one letter the
## word offers that nothing else takes. It names its mode outright rather than
## reading one out of Preferences the way Ctrl+Y does, because there is only
## ever the one shape check.
func _shape_check() -> bool:
    return _toggle_view_mode(&"shape_check")


## A view mode chord: the mode if it is not showing, the picture if it is.
##
## It says which of the two it just did. Ctrl+Y is the chord that reaches here,
## and a soft proof of a picture already inside the proof gamut clips nothing a
## screen can show, so without a line the chord and a chord that never arrived
## look the same, and the proof would seem to do nothing.
func _toggle_view_mode(mode: StringName) -> bool:
    if _view_transforms == null:
        return false
    var was_showing := _view_transforms.mode == mode
    _said_mode = SaViewTransformRegistry.NORMAL if was_showing else mode
    _view_transforms.set_mode(_said_mode)
    SaMessage.notice(_view_mode_line(mode, not was_showing))
    return true


## A mode put on from anywhere but the chords above, the View menu's row above
## all. Only a soft proof speaks, and it says the line the chord would have,
## because a proof that changes nothing has to say why whichever door it came
## through, and the menu is one of those doors. Every other
## mode changes the picture at once and keeps the silence it had.
func _on_view_transforms_changed() -> void:
    var mode := _view_transforms.mode
    if mode == _said_mode:
        return
    _said_mode = mode
    var descriptor := _view_transforms.get_descriptor(mode)
    if descriptor != null and descriptor.view_mode == SOFT_PROOF_VIEW_MODE:
        SaMessage.notice(_view_mode_line(mode, true))


## The line the notice above says.
##
## The mode's own registered name, so a module's mode names itself here without
## a line being added, and for the soft proof the gamut it clips to as well
## and whether it can clip anything, in the words `SaGamut.proof_line` writes,
## because which gamut is the whole question the chord answers. Recognised by
## the descriptor's `view_mode`, which is the same number
## `shaders/canvas/tonemap.gdshader` branches on, rather than by the built-in's
## id: a module registering its own proof against that branch gets the gamut
## named too.
func _view_mode_line(mode: StringName, turned_on: bool) -> String:
    var descriptor := _view_transforms.get_descriptor(mode)
    var mode_name := descriptor.display_name if descriptor != null else String(mode)
    if not turned_on:
        return tr("%s off") % mode_name
    if descriptor != null and descriptor.view_mode == SOFT_PROOF_VIEW_MODE:
        var document := _document()
        var space := document.color_space if document != null else SaColorSpace.unspecified()
        var proof := SaSettings.proof_profile_space().gamut()
        return proof.proof_line(mode_name, space.gamut(), SaSettings.DISPLAY_PROFILES)
    return mode_name


## Preferences changed what Ctrl+Y proofs to. A proof already on the screen
## follows at once, and a canvas showing some other mode is left alone, because
## the painter chose that one from the View menu rather than from this setting.
func _on_canvas_proof_mode_changed(previous: StringName, current: StringName) -> void:
    if _view_transforms.mode == previous:
        _view_transforms.set_mode(current)


## Ctrl+Shift+Y: the same for the minimap, which keeps its own answer so it can
## be grey while the canvas stays in colour, and a minimap nobody has opened yet
## has nothing to proof.
##
## Looked up by name rather than held, because the docker can be reparented into
## a secondary workspace, and asked by its method rather than by its class,
## because the docker is a `Window` a suite cannot add to its tree and stands a
## plain node in for.
func _minimap_proof() -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    var minimap := tree.root.find_child(SaDockerIds.MINIMAP, true, false) if tree != null else null
    if minimap != null and minimap.has_method(&"toggle_proof"):
        minimap.call(&"toggle_proof")
    return true


## View > Fit to View and its F. *whole* is View > Fit to Window.
func _fit_view(whole: bool = false) -> bool:
    var view := _view()
    if view == null:
        return false
    view.fit_into(_document_size(), view.get_visible_rect() if whole else view.get_free_rect())
    _reveal_after_zoom()
    return true


## View > Centre View and its V: the document back in the middle, at the zoom
## it has.
func _center_view() -> bool:
    var view := _view()
    if view == null:
        return false
    view.center(_document_size())
    _reveal_after_zoom()
    return true


## View > Reset Rotation and its R.
func _reset_rotation() -> bool:
    var view := _view()
    if view == null:
        return false
    view.rotate_at(0.0, _middle(view))
    _reveal_after_zoom()
    return true


## The chords zoom about the middle of the free rectangle, because a key has no
## pointer, `_middle` says why that middle. False without a view, so the event
## is somebody else's, and true once a reference board under the pointer took it.
func _zoom_view(inward: bool) -> bool:
    var view := _view()
    if view == null or ReferenceZoomGestures.step_hovered(inward):
        return false
    SaView.Steps.notch(view, 1.0, inward, _middle(view))
    _reveal_after_zoom()
    return true


## The middle of *view*'s free rectangle, the point a chord zooms and turns
## about, and the middle Ctrl+0, Ctrl+1 and Fit to View centre the picture on.
##
## Rather than the window's middle, which is not the free rectangle's whenever
## the top bar is taller than the status line or the docker columns differ in
## width, so a picture Ctrl+0 had centred would leave the centre with every
## step and sit low between the bars.
static func _middle(view: SaView) -> Vector2:
    return view.get_free_rect().get_center()


## Ctrl+0, Reset Zoom: what the Display page's Ctrl+0 shows row names, centred
## as Krita's "100%" is, and a second press before the view moves goes back to
## the view the first left, which `SaView.reset` keeps when asked to toggle.
func _reset_zoom() -> bool:
    var view := _view()
    if view == null:
        return false
    view.reset(_document_size(), true)
    _reveal_after_zoom()
    return true


## Ctrl+1, Actual Pixels: one texel on one device pixel, centred, whatever the
## Ctrl+0 row says.
func _actual_pixels() -> bool:
    var view := _view()
    if view == null:
        return false
    view.zoom_to_actual_pixels(_middle(view))
    view.center(_document_size())
    _reveal_after_zoom()
    return true


## Ctrl with the brackets turns the view a step either way, Krita's chords.
## The bare brackets stay the brush size.
func _rotate_view(direction: float) -> bool:
    var view := _view()
    if view == null:
        return false
    view.rotate_at(view.get_rotation() + SaView.ROTATION_STEP * direction, _middle(view))
    _reveal_after_zoom()
    return true


func _nudge_ui_scale(delta: float) -> bool:
    _set_ui_scale(SaUI.user_scale + delta)
    return true


func _reset_ui_scale() -> bool:
    SaSettings.ui_scale = 1.0
    return true


## Ctrl+X, Ctrl+C, Ctrl+Shift+C and Ctrl+V, through the clipboard every open
## document shares, the same calls the Edit menu makes.
##
## A Cut or a Copy leaves its mark on the desktop clipboard, and a Paste that
## finds the mark gone puts the desktop's picture down before Sara's copy, the
## layers, a mask's copy and several layers alike, because the painter copied
## it later. With no picture there, words copied in a browser say, Sara's copy
## is still the one pasted.
func _clipboard(operation: StringName) -> bool:
    var document := _document()
    var held := shared_clipboard()
    if operation == &"paste" and ReferenceDocker.take_paste(Engine.get_main_loop() as SceneTree):
        return true
    if document == null or (held == null and not operation.begins_with("paste")):
        return false
    var desktop_read := false
    if operation == &"paste" and held != null and held.holds() and held.desktop_changed():
        var picture := _desktop_picture()
        if picture != null:
            var tree := Engine.get_main_loop() as SceneTree
            _place_desktop(document, tree.current_scene if tree != null else null, picture, _composite, false)
            return true
        desktop_read = true
    var done := _clipboard_act(document, held, operation, desktop_read)
    if done and operation in [&"cut", &"copy", &"copy_merged"] and held != null:
        held.mark_desktop()
    return done


## The clipboard *operation* on *document* through *held*, by the mask in hand
## or the picked rows. *desktop_read* says a paste already found no picture on
## the desktop, so it is not asked twice.
func _clipboard_act(document: SaDocument, held: SaClipboard, operation: StringName, desktop_read: bool) -> bool:
    # With a mask the paint target the mask is what is cut, copied and pasted
    # into, and `SaMaskClipboard` does it.
    var masked := _mask_in_hand(document, held, operation)
    if masked != null:
        return _clipboard_mask(document, held, masked, operation)
    # Several picked rows go to the held layers, and one goes alone.
    var picked := document.picked.acted_on(document)
    match operation:
        &"cut" when picked.size() > 1:
            held.clear()
            held.layers.cut(document, picked)
        &"cut":
            held.cut(document, document.active_layer)
        &"copy" when picked.size() > 1:
            held.clear()
            held.layers.copy(document, picked)
        &"copy":
            held.copy(document, document.active_layer)
        &"copy_merged":
            return _copy_merged(document, held)
        &"paste" when held != null and not held.layers.is_empty():
            var pasted := held.layers.paste(document)
            _composite(pasted[-1] if not pasted.is_empty() else null)
        &"paste", &"paste_special":
            var tree := Engine.get_main_loop() as SceneTree
            var host := tree.current_scene if tree != null else null
            paste(document, host, _composite, operation == &"paste_special", desktop_read)
    return true


## The owner of the mask a clipboard *operation* acts on, a layer, a group or
## an attached filter's record, or null when it acts on layers as before: no
## mask is the paint target, the operation is Copy Merged or Paste Special,
## which read the canvas and the desktop, or a paste finds no held picture to
## write or holds several layers, which paste as layers.
static func _mask_in_hand(document: SaDocument, held: SaClipboard, operation: StringName) -> Object:
    if operation == &"copy_merged" or operation == &"paste_special":
        return null
    if operation == &"paste" and (held == null or held.is_empty() or not held.layers.is_empty()):
        return null
    return SaMaskOps.owner_of(document, document.mask_target)


## Cut, Copy or Paste on *masked*'s mask. A cut or a paste on the mask of a
## locked layer is refused in the corner, as a stroke there is, because both
## write the mask.
func _clipboard_mask(document: SaDocument, held: SaClipboard, masked: Object, operation: StringName) -> bool:
    var mask_clipboard := SaMaskClipboard.new(document)
    if operation == &"copy":
        mask_clipboard.copy(held, masked)
        return true
    var mask := SaMaskOps.mask_of(masked)
    var holder := mask.holder_in(document) if mask != null else null
    if holder != null and holder.is_locked:
        SaContext.refuse_paint(holder, tr("cut") if operation == &"cut" else tr("paste"))
        return false
    if operation == &"cut":
        mask_clipboard.cut(held, masked)
    elif mask_clipboard.paste(held, masked):
        _composite(document.active_layer)
    return true


## The clipboard every open document shares, the one the current scene's owner
## holds: main's in the app and the runner's in a suite. Null with no owner.
static func shared_clipboard() -> SaClipboard:
    var tree := Engine.get_main_loop() as SceneTree
    return SaDocuments.clipboard_in(tree.current_scene if tree != null else null)


## Paste puts down Sara's own pixels when Copy left some, and otherwise a desktop
## picture as a new layer at once, as `SaImportFitDialog.Asks.NEVER` says. *special*
## is Paste Special, which always asks and skips Sara's pixels, which have no fit.
##
## Sara's clipboard first while the desktop still holds its copy's mark,
## because Copy is then the more recent intent, and because a copy of Sara's own
## pixels carries the colour space they were painted in, which a screenshot on
## the desktop clipboard cannot. A desktop given a picture since the copy,
## `SaClipboard.desktop_changed`, is pasted from instead, and one given only
## words leaves Sara's copy the one pasted. *desktop_read* says the caller has
## asked the desktop already and found no picture. It is the command's rather than the Edit menu row's, so the row and
## Ctrl+V both run it and the chord reaches the desktop picture too.
##
## With nothing in either it says so, rather than returning in silence, which
## leaves a painter unable to tell a refused paste from one that never arrived. A
## picture the engine does not see is read through a clipboard program on
## Linux, which `SaDesktopPicture` explains.
static func paste(
    document: SaDocument, host: Node, placed: Callable = Callable(), special: bool = false, desktop_read: bool = false
) -> void:
    var held := shared_clipboard()
    var sara_first := not special and held != null and not held.is_empty()
    var asks_desktop := not desktop_read and (not sara_first or held.desktop_changed())
    var picture := _desktop_picture() if asks_desktop else null
    if sara_first and picture == null:
        # Asks how a copy larger than the canvas lands, as a picture is asked.
        SaImportFitDialog.place_held(host, document, held, placed)
        return
    if picture == null:
        SaMessage.notice(TranslationServer.translate(NOTHING_TO_PASTE))
        return
    _place_desktop(document, host, picture, placed, special)


## The picture on the desktop clipboard, or null when it holds none.
static func _desktop_picture() -> SaDesktopPicture:
    var picture := desktop_picture.call() as SaDesktopPicture if desktop_picture.is_valid() else null
    if picture == null or picture.image == null or picture.image.is_empty():
        return null
    return picture


## *picture* down on *document* as a new layer, asking how it fits when
## *special*, as Paste Special does.
static func _place_desktop(document: SaDocument, host: Node, picture: SaDesktopPicture, placed: Callable, special: bool) -> void:
    if picture.left_out > 0:
        SaMessage.notice(SaDesktopPicture.left_out_line(picture.left_out))
    var asks := SaImportFitDialog.Asks.ALWAYS if special else SaImportFitDialog.Asks.NEVER
    SaImportFitDialog.place(host, document, picture.image, picture.layer_name, picture.space, placed, false, asks)


## Copy Merged reads the easel's output, so the output is brought up to date
## over what the copy takes first: what changed since the last frame, then
## what the window held back. Without the first, a copy pressed in the frame a
## fill landed in would take the picture from before it. A layer shown or
## hidden a moment before is paid for first, `SaEasel.catch_up`.
func _copy_merged(document: SaDocument, held: SaClipboard) -> bool:
    var canvas := _canvas_provider.call() as SaCanvas if _canvas_provider.is_valid() else null
    var easel := canvas.easel if canvas != null else null
    if easel == null or easel.output == null:
        return false
    easel.catch_up()
    easel.flush(document.selection.bounds if document.selection.active else Rect2i())
    held.copy_merged(document, easel.output)
    return true


## A pasted picture is on the canvas once it is composited again.
func _composite(layer: SaLayer) -> void:
    var canvas := _canvas_provider.call() as SaCanvas if _canvas_provider.is_valid() and layer != null else null
    if canvas != null:
        canvas.request_composite()


## Edit > Undo and Redo on the document the chords undo in.
func _history(undo: bool) -> bool:
    var document := _document()
    if document == null:
        return false
    # An open liquify or transform session first, for the reason the router's
    # chord gives.
    var machine := _tool_machine()
    if machine != null:
        machine.close_session()
    return document.undo() if undo else document.redo()


static func _set_ui_scale(value: float) -> void:
    SaSettings.ui_scale = clampf(value, UI_SCALE_MIN, UI_SCALE_MAX)


## Whether the machine *provider* answers holds a session the history has not
## taken yet. Static and bound to the provider, because a lambda here captures
## this table, which holds the menu's commands that hold the lambda, a cycle
## that leaked every table a suite built.
static func _holds_session(provider: Callable) -> bool:
    var machine := provider.call() as ToolMachine if provider.is_valid() else null
    return machine != null and machine.holds_session()


func _tool_machine() -> ToolMachine:
    return _tool_machine_provider.call() as ToolMachine if _tool_machine_provider.is_valid() else null


func _document() -> SaDocument:
    var canvas := _canvas_provider.call() as SaCanvas if _canvas_provider.is_valid() else null
    return canvas.document if canvas != null else null


func _view() -> SaView:
    var tool_machine := _tool_machine()
    if tool_machine == null or tool_machine.surface == null:
        return null
    return tool_machine.surface.view


func _document_size() -> Vector2i:
    var tool_machine := _tool_machine()
    return tool_machine.surface.get_canvas_size() if tool_machine != null and tool_machine.surface != null else Vector2i.ZERO


## Zooming out reveals chunks outside the composited region, as the zoom tool
## and the wheel already know.
func _reveal_after_zoom() -> void:
    var document := _document()
    if document != null:
        document.reveal_all_allocated_chunks()
