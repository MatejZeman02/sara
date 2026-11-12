## How a document comes in and goes out: open, import, the picture opened as a
## document of its own, save, save as, export, the files dropped on the window,
## and the one question every destructive path asks before a modified document
## is thrown away.
##
## **It is a node of its own, not the File menu's.** Places outside the menus
## need the flow and should not walk to the top bar to ask it for the menu
## called "File". Main builds it beside the shortcut router, and whoever needs
## it asks `in_tree`. The File menu keeps its rows and calls here.
##
## Quit and Close ask before a modified document is thrown away, and main's
## quit reaches the same question through `confirm_quit()`, so there is one
## prompt and one place that decides whether anything would be lost. New, Open,
## Open Recent and New from Clipboard ask nothing, because each opens a tab of
## its own and throws nothing away. Open alone replaces the front document, and
## only the untitled and untouched one Sara starts with, so starting Sara and
## opening a file still leaves one tab. A file already open brings its tab
## forward rather than opening twice.
##
## Every path that is about a document takes the one it is about, and the front
## one when the caller names none: with two documents open, a Save or a
## question has to say which painting it means. The quit asks about all of them
## at once, which is `SaQuitPrompt`.
##
## The dialogs it opens are its own children. Each one that draws Sara's chrome
## is an `SaDialogWindow`, which assigns the theme to itself, so a plain `Node`
## above it cuts nothing it needs.
class_name SaDocumentFiles
extends Node

## A file became the document, by whichever door. The welcome window goes away on it.
signal document_opened(path: String)

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## What main names the node, and what `in_tree` asks the main scene for.
const NODE_NAME := "DocumentFiles"
## The codec File > Save as JPEG XL asks for by name, the JPEG XL module's.
const JPEG_XL := &"jxl"

## The three answers to the unsaved-changes question, in button order.
const PROMPT_SAVE := 0
const PROMPT_DISCARD := 1
const PROMPT_CANCEL := 2

## The three answers to the picture-extension question, in button order.
const NAME_ADD_SAD := 0
const NAME_KEEP := 1
const NAME_CANCEL := 2

## The two answers to the question an appended name that exists asks.
const REPLACE := 0
const REPLACE_CANCEL := 1

## The names another program owns beside the formats Sara registers, whose own
## extensions the registry gives. A `.sad` under one of them is a file the
## program the name points at cannot open.
const FOREIGN_EXTENSIONS: PackedStringArray = ["bmp", "tga"]

## `func() -> SaCanvas`, the canvas whose document comes in and goes out, or an
## empty `Callable` for a flow with no canvas behind it, which is what a suite
## builds: every path then finds no document and does nothing, and the guard
## proceeds at once.
var _canvas_provider: Callable

## The open documents, main's own, or null for a flow built without one, which
## is a suite's and nothing else. It answers which document a path with no
## document named is about, which is the front one, and which surface holds a
## document the quit's Save All is saving.
var _documents: SaDocuments = null

## Lazily built, one per flow, so the format and its options from the last
## export are still there next time.
var _export_dialog: SaExportDialog = null
## File > Export Target, built on first use like Export.
var _targets_dialog: SaExportTargetsDialog = null

## The quit's question while it is up. Held because the dialog answers back to
## it and nothing else refers to it: a `RefCounted` the flow drops is freed
## under the open window.
var _quit_prompt: SaQuitPrompt = null

## The documents a `.sad` is being read into, no longer untouched though their
## file is not in yet, each true once its stack landed before its chunks.
var _loading: Dictionary[SaDocument, bool] = {}


func _init(canvas_provider: Callable = Callable(), documents: SaDocuments = null) -> void:
    name = NODE_NAME
    _canvas_provider = canvas_provider
    _documents = documents


func _ready() -> void:
    connect_drops()


## The flow under the main scene, or null when there is none: a suite's
## detached bar, or a tree whose scene is not Sara's.
static func in_tree(tree: SceneTree) -> SaDocumentFiles:
    if tree == null or tree.current_scene == null:
        return null
    return tree.current_scene.get_node_or_null(NodePath(NODE_NAME)) as SaDocumentFiles


## The input map action behind each chord, for the router: Ctrl+N, Ctrl+O,
## Ctrl+S and Ctrl+Shift+S do exactly what the File menu's row does, and both
## arrive at the same call here.
func run_action(action: StringName) -> void:
    match action:
        &"file_new":
            request_new_document()
        &"file_open":
            open_with_dialog()
        &"file_save":
            save_document(Callable())
        &"file_save_as":
            save_as(Callable())
        &"file_save_as_jpeg_xl":
            save_as(Callable(), JPEG_XL)


# --- The guard ----------------------------------------------------------------


## Runs *proceed* now when nothing would be lost, and otherwise asks first:
## Save runs a save and then proceeds, Discard proceeds, Cancel does nothing.
## A save running in the background is waited for first, so a quit never cuts
## one short.
## Enter is Save and Escape is Cancel, so it can be answered without a mouse.
##
## *about* is the document the question is about, and the front one when the
## caller names none, which is every caller with one document on screen.
func confirm_discard(what: String, proceed: Callable, about: SaDocument = null) -> void:
    var doc := about if about != null else _document()
    if doc == null or not doc.modified:
        SaSadFile.after_saves(proceed, what)
        return
    SaTrail.stage("asked whether to save the changes to %s before %s" % [display_name(doc), what])
    SaMessage.confirm(
        self,
        tr("Unsaved changes"),
        save_question(doc, what),
        PackedStringArray([tr("Save"), tr("Discard"), tr("Cancel")]),
        _on_prompt_answered.bind(proceed, what, doc),
        PROMPT_CANCEL,
        PROMPT_SAVE
    )


## The sentence the question about one document says, the quit's as well.
static func save_question(doc: SaDocument, what: String) -> String:
    return TranslationServer.translate("Save the changes to %s before %s?") % [display_name(doc), what]


## The question the quit asks, which is about every open document with unsaved
## work rather than about the one in front.
##
## Any modified document is asked about by `SaQuitPrompt`, one window naming
## them all. None at all waits for whatever is still being written and quits.
## A quit asked while that window is up brings it forward and asks nothing.
func confirm_quit(proceed: Callable) -> void:
    if _quit_prompt != null and _quit_prompt.standing():
        _quit_prompt.bring_forward()
        return
    var modified := _modified_documents()
    if modified.is_empty():
        SaSadFile.after_saves(proceed, tr("quitting"))
        return
    _quit_prompt = SaQuitPrompt.new(self, save_document, proceed)
    _quit_prompt.ask(modified)


## Every open document with unsaved work, in the order the owner holds them.
## The front document alone for a flow with no owner and for one whose owner
## holds no surface yet, which is a suite's main and the first frames of a
## boot: the canvas is there and the owner is still empty, and the painter is
## asked about the document in front alone.
func _modified_documents() -> Array[SaDocument]:
    var out: Array[SaDocument] = []
    if _documents == null or _documents.surfaces.is_empty():
        var only := _document()
        if only != null and only.modified:
            out.append(only)
        return out
    for surface in _documents.surfaces:
        var doc := surface.get_document()
        if doc != null and doc.modified:
            out.append(doc)
    return out


func _on_prompt_answered(index: int, proceed: Callable, what: String, doc: SaDocument) -> void:
    SaTrail.stage("answered %s" % ["Save", "Discard", "Cancel"][clampi(index, PROMPT_SAVE, PROMPT_CANCEL)])
    if index == PROMPT_SAVE:
        save_document(proceed, doc)
    elif index == PROMPT_DISCARD:
        SaSadFile.after_saves(proceed, what)


## The name the prompts and the title bar call the document. Static, because
## the window title asks it of a document without holding the flow, and the
## name a question gives a document and the name over the window are one
## sentence.
static func display_name(doc: SaDocument) -> String:
    if doc == null:
        return ""
    return SaDocumentLabel.text_for(SaDocumentLabel.file_name_of(doc), false, false)


# --- New, open ----------------------------------------------------------------


func request_new_document() -> void:
    # Deferred out of the popup's own signal handler, for the reason the Edit
    # menu gives: a window that takes focus from inside that re-entrancy
    # desynchronises the engine's popup focus bookkeeping.
    EventBus.new_document_requested.emit.call_deferred()


## File > New from Clipboard, `SaNewFromClipboard`'s, built in a tab of its
## own, and no tab opened when the clipboard holds no picture.
func new_from_clipboard() -> void:
    var doc := _document()
    var source := SaNewFromClipboard.read(doc, _held()) if doc != null else null
    if source != null:
        _open_from_clipboard(source)


## The clipboard every open document shares: the owner's this flow was built
## with, or else the one the current scene holds, which is a suite's runner.
func _held() -> SaClipboard:
    if _documents != null:
        return _documents.clipboard
    var tree := get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
    return SaDocuments.clipboard_in(tree.current_scene if tree != null else null)


func _open_from_clipboard(source: SaNewFromClipboard) -> void:
    if SaCardMemory.refuses(source.needs()):
        return
    var doc := _landing(true)
    var canvas := _canvas_for(doc)
    if doc == null:
        return
    if source.make(doc) == null:
        _drop_tab(doc)
        return
    # The canvas second, for the reason `_finish_opening_image` gives.
    if canvas != null:
        canvas.resize_canvas(doc.canvas_size)
    document_opened.emit("")


func open_with_dialog() -> void:
    var filters := [tr("*.sad ; Sara Document")]
    filters.append_array(SaImageImport.formats().layered_filters())
    filters.append(SaImageImport.dialog_filter())
    SaFilePicker.open(self, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(filters), _open_chosen)


## The chosen file, opened with no question in front of it, since it lands in
## a tab of its own or in the untouched document, and neither loses anything.
## Cancel in the picker touches nothing.
func _open_chosen(path: String) -> void:
    open_path(path)


## Opens *path* as a document: a tab of its own, or the front document when it
## is the untitled and untouched one Sara starts with, and the tab already
## holding the file brought forward instead when it is open. An image becomes a
## document sized to the picture, holding it and nothing else. File > Import is
## what puts a picture into the document that is already open.
##
## Public for the reason `import_path` below it is: the dialog, the recent list,
## a drop and the command line all arrive here.
func open_path(path: String) -> void:
    if _bring_open(path) or _document() == null:
        return
    var route := SaOpenRoute.new(path)
    if route.kind == SaOpenRoute.Kind.PICTURE:
        _open_image_as_document(path)
        return
    if SaImageImport.refuses_unread(path):
        return
    if route.kind == SaOpenRoute.Kind.SAD and SaCardMemory.refuses(SaCardMemory.for_sad(path)):
        return
    if route.kind == SaOpenRoute.Kind.LAYERED:
        _open_layered(path, route.layered)
        return
    var doc := _landing(true)
    if doc == null:
        return
    # Held as loading until the file is in, so a second path of the command
    # line does not take the same untouched document while this one reads.
    _loading[doc] = false
    var version := SaSadFile.version_at(path)
    # Its stack in with the chunks to come, the canvas takes its size.
    var landed := func() -> Rect2i:
        _loading[doc] = true
        return SaCanvasView.landed(_canvas_for(doc), doc.canvas_size)
    SaExport.open_sad(doc, path, _sad_opened.bind(path, version, doc), landed)


## The rest of `open_path` once the `.sad` at *path*, stamped *version*, is in
## *doc*, or *err* says why not. Called within `open_path` for a file that
## reads in one frame, and from a later frame for a deep one, which the window
## keeps drawing through, and a tab picked meanwhile.
func _sad_opened(err: Error, path: String, version: int, doc: SaDocument) -> void:
    var landed: bool = _loading.get(doc, false)
    _loading.erase(doc)
    var canvas := _canvas_for(doc)
    if err != OK:
        SaProblems.report("SaDocumentFiles", tr("Could not open '%s' (%s).") % [path, error_string(err)])
        SaSettings.remove_recent_file(path)
        _drop_tab(doc)
        return
    # A loaded document brings its own canvas size and its own storage depth,
    # and the easel's output texture was sized and formatted for the previous
    # one. Nothing rebound it, so opening a file of a different size already
    # displayed the wrong surface. With F16 documents it would also be a depth
    # the compositor cannot dispatch against.
    if canvas != null and not landed:
        canvas.resize_canvas(doc.canvas_size)
    # The history belonged to the document that was there before, and nothing on
    # a freshly opened file is an edit a painter made, so there is nothing to
    # take back. Without this the History docker would offer steps of somebody
    # else's painting and the first Ctrl+Z after an open would change no pixel
    # while claiming to have undone something. `_open_image_as_document` clears
    # both for the same reason, and this is the other door into the same state.
    if doc.undo_redo != null:
        doc.undo_redo.clear_history()
    if doc.history != null:
        doc.history.reset()
    doc.mark_saved(path)
    SaSettings.add_recent_file(path)
    # A file saved before a mode kept drawing above white opens as it draws
    # now, and the corner names the layers that changed.
    var changed := SaSadFile.changed_since(doc, version)
    if not changed.is_empty():
        SaMessage.notice(changed)
    document_opened.emit(path)


## An OpenRaster file as a document of its own, with its layers and groups.
## The picture's close first and the canvas after, in the order and for the
## reasons `_finish_opening_image` gives, and named and clean like an image.
## The depth is the painter's last choice unless a sixteen-bit layer asks for
## F32, and no window asks, as many layers have no single picture to ask about.
func _open_layered(path: String, format: SaImageFormat) -> void:
    var doc := _landing(true)
    var canvas := _canvas_for(doc)
    if doc == null:
        return
    # A layered file says its size and its layers only once read, so what it
    # needs is what reading it took, and one that took the card past its room
    # is let go again, unsaved since it is the file and not the painter's work.
    var before := SaCardMemory.held()
    if format.opener.call(path, doc, SaImportFitDialog.remembered_depth()) != OK:
        SaSettings.remove_recent_file(path)
        _drop_tab(doc)
        return
    if SaCardMemory.refuses(SaCardMemory.held() - before, before):
        doc.mark_saved("")
        _drop_tab(doc)
        return
    if canvas != null:
        canvas.resize_canvas(doc.canvas_size)
    SaDocumentSource.opened_from(doc, path)
    SaSettings.add_recent_file(path)
    document_opened.emit(path)
    PanoramaQuestion.ask_if_due(self, doc, path)


## A picture as a document of its own: the canvas is the picture's size, its
## colour space is the one the file declares, and the picture is the only layer
## on it.
##
## Through `reset_to_default` and `place`, the two doors File > New and File >
## Import already use, rather than a third way of building a document. The
## document goes first and the canvas second, which is the order
## `main_dialogs.gd` uses for File > New and for the same reason: the composite
## the resize schedules should already see the new layers.
##
## The two layers a fresh document comes with are then taken off, because the
## request is for the picture and neither of them is: a grey background under a
## photograph is invisible, and the empty paint layer over it is one nobody
## made. `SaLayerOps.remove` is undoable and so is `place`, and none of it is an edit
## a painter made, so the history is cleared after rather than opening a
## document whose first Ctrl+Z brings back a layer that was never seen.
##
## It has no `.sad` yet, so Save asks where and never writes over the picture,
## and it holds the picture exactly, so closing asks nothing (`SaDocumentSource`).
##
## A question sits between the file and the document: the picture is read here,
## the depth it is stored at is asked for, and the document is built in the
## answer. A file that names its own float width is not asked, so an EXR opens
## at the width it names.
func _open_image_as_document(path: String) -> void:
    var image: Image = await SaPictureRead.read(self, path)
    if image == null:
        return
    var texels := image.get_width() * image.get_height()
    if SaCardMemory.refuses(SaCardMemory.for_canvas(image.get_size(), texels)):
        return
    SaOpenDepth.ask(self, path, image, func(space: SaColorSpace) -> void: _finish_opening_image(path, image, space))


## What the depth question answers into, and what a file that answered it itself
## reaches straight away. Split out because a window's answer arrives on a later
## frame and the recent-files entry belongs to the picture that actually landed.
## The tab is opened here, after the question, so Cancel there opens none.
func _finish_opening_image(path: String, image: Image, space: SaColorSpace) -> void:
    var doc := _landing(true)
    var canvas := _canvas_for(doc)
    if open_picture_into(doc, path, image, space) == null:
        _drop_tab(doc)
        return
    # The canvas second, so the full composite the resize schedules already sees
    # the picture rather than the layers it replaced. Same order and same reason
    # as `main_dialogs.gd`'s File > New.
    if canvas != null:
        canvas.resize_canvas(doc.canvas_size)
    SaSettings.add_recent_file(path)
    document_opened.emit(path)
    PanoramaQuestion.ask_if_due(self, doc, path)


## The document half of the above, on *doc* rather than on the open one.
##
## Public and taking a document because `_document()` asks main for its canvas,
## which no suite builds, so this is the half a test can be written against.
##
## *space* is the gamut and the depth the document is to be built at, and null
## asks the file, which is what a caller that asks no depth question wants.
static func open_image_into(doc: SaDocument, path: String, space: SaColorSpace = null) -> SaLayer:
    var image := SaImageImport.read(path)
    if image == null:
        return null
    return open_picture_into(doc, path, image, space)


## The same, for a caller that has read the picture already, so the window that
## asked which depth to store it at does not make the file be read twice.
static func open_picture_into(doc: SaDocument, path: String, image: Image, space: SaColorSpace = null) -> SaLayer:
    if doc == null or image == null:
        return null
    var chosen := space
    if chosen == null:
        # No answer from a caller, so the file's own float width if it has one
        # and the painter's last choice if it has not. F32 is what falls out of
        # the setting rather than what is written here, because a constant in
        # this line would make every import 32-bit whatever the painter chose.
        var named := SaImageImport.depth_for(image)
        var depth: int = named if named >= 0 else SaImportFitDialog.remembered_depth()
        chosen = SaImageImport.space_for(path).with_depth(depth as SaColorSpace.Depth)
    doc.reset_to_default(image.get_size(), chosen, doc.dpi)
    # Quietly, on the history `reset_to_default` has just made, or a picture
    # over its layer pool makes the second removal drop the add ahead of it and
    # say the undo history is full, to a painter who has only opened a file.
    var build := func() -> SaLayer: return _picture_alone(doc, image, path, chosen)
    var layer := (doc.history.quietly(build) if doc.history != null else build.call()) as SaLayer
    if layer == null:
        return null
    # None of the three steps above is an edit a painter made, so none of them
    # is one to take back. Without this the first Ctrl+Z on a freshly opened
    # picture brings back a grey layer that was never on screen.
    if doc.undo_redo != null:
        doc.undo_redo.clear_history()
    if doc.history != null:
        doc.history.reset()
    SaDocumentSource.opened_from(doc, path)
    return layer


## The picture put down as the only layer of a fresh *doc*, the half of
## `open_image_into` that commits steps and so runs quietly.
static func _picture_alone(doc: SaDocument, image: Image, path: String, space: SaColorSpace) -> SaLayer:
    var layer := SaImageImport.place(doc, image, path.get_file().get_basename(), space, SaImageImport.Fit.ORIGIN)
    if layer == null:
        return null
    for spare: SaLayer in SaLayerOps.new(doc).layers():
        if spare != layer:
            SaLayerOps.new(doc).remove(spare)
    # The layers docker rebuilds on `child_exiting_tree`, which fires before the
    # child is gone, so the row of the last layer removed outlived its layer and
    # the docker showed a nameless row. Naming the active layer again is what
    # the docker listens to for a rebuild, and it is true anyway.
    doc.set_active_layer(layer)
    return layer


## The picture goes into the open document as a layer. A file dialog of its
## own, filtered to the image formats and OpenRaster, because a painter
## reaching for Import is not choosing between a `.sad` and a PNG.
func import_with_dialog() -> void:
    var filters := [SaImageImport.dialog_filter()]
    filters.append_array(SaImageImport.formats().layered_filters())
    SaFilePicker.open(self, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(filters), import_path)


## The picture from *path* into the open document, asking how to fit it when its
## size differs from the canvas. Public because a drop, the Import entry and the
## capture harness all arrive here. An OpenRaster file brings its layers and
## groups in above the active layer as one step, at their own offsets, with no
## fit to ask about since a stack of layers has no single size to fit.
func import_path(path: String) -> void:
    var doc := _document()
    if doc == null:
        return
    var layered := SaImageImport.formats().layered_named(path)
    if layered != null:
        var block: Array[SaLayer] = layered.importer.call(path, doc)
        _placed(block[-1] if not block.is_empty() else null)
        return
    var image := SaImageImport.read(path)
    if image == null:
        return
    var texels := image.get_width() * image.get_height()
    if SaCardMemory.refuses(SaCardMemory.for_canvas(image.get_size(), texels)):
        return
    var named := SaImageImport.named_space_for(path)
    var source := named if named != null else SaImageImport.convention_for(path)
    var profile := SaImageImport.profile_for(path)
    var under := SaImportFitDialog.Asks.UNDER_ASK
    SaImportFitDialog.place(self, doc, image, path.get_file().get_basename(), source, _placed, named != null, under, profile)


func _placed(layer: SaLayer) -> void:
    if layer == null:
        return
    var canvas := _canvas()
    if canvas != null:
        canvas.request_composite()


# --- Drops --------------------------------------------------------------------


## A file dropped on the window: a.sad or an .ora opens, with the same prompt File > Open
## gives, and an image becomes a layer. Connected once the flow is in a window,
## which a suite's detached one never is.
func connect_drops() -> void:
    if not is_inside_tree():
        return
    var window := get_window()
    if window != null and not window.files_dropped.is_connected(_on_files_dropped):
        window.files_dropped.connect(_on_files_dropped)


## Deferred by a frame, which is the whole of the fix.
##
## The routing needs to know where the drop landed and `files_dropped` carries
## the file names and nothing else, so the only thing left to ask is the
## pointer. On Wayland the pointer is the one reading that is wrong at exactly
## this moment: the compositor takes pointer focus away for the length of a
## drag and hands the position back only in the `wl_pointer.enter` that follows
## the drop, and Godot 4.7 throws away the coordinates `wl_data_device.enter`
## and `.motion` carry rather than tracking the drag. Read inside the signal,
## `DisplayServer.mouse_get_position()` is therefore wherever the hand left the
## pointer before it went to the Files app, which is usually over the canvas,
## and a drop the painter aims at the Reference docker would become a layer.
## Deferring puts the reading after the same frame's event flush, which is
## where that restored position lands. On X11 `XQueryPointer` is live already
## and a frame changes nothing.
func _on_files_dropped(files: PackedStringArray) -> void:
    _route_drop.call_deferred(files)


func _route_drop(files: PackedStringArray) -> void:
    if not is_inside_tree():
        return
    if SaWindowForward.take_drop(get_window(), files, drop_point(get_tree())):
        return
    for path in files:
        if SaImageImport.is_image_path(path):
            import_path(path)
        elif path.get_extension().to_lower() == "sad" or SaImageImport.formats().layered_named(path) != null:
            open_path(path)


## Where a drop landed, in the root viewport's own units.
##
## Through the cursor policy rather than `get_mouse_position()`, because that
## class is the one place that answers "where is the pointer" and a second
## reading is a second answer to disagree with the ring and the over-UI test.
static func drop_point(tree: SceneTree) -> Vector2:
    return SaCursorPolicy.pointer_in_window(tree.root)


## Drops files on a window: `{"drop": "res://picture.png"}`, `{"drop": {"files":
## [...]}}` or, for a docker the painter has let out into an OS window of its own,
## `{"drop": {"files": [...], "window": "ReferenceDocker"}}`.
##
## The step raises `files_dropped` on a window, which is the one thing a
## compositor does that a scenario cannot: it picks the surface the file was
## let go over and hands the names to it. `window` is that choice, and the root
## is the default because with subwindows embedded there is only one surface.
##
## Nothing here says where inside the window the drop landed, on purpose. A
## scenario puts the pointer where it means the drop to be with a `move` step
## first, so this step proves the routing rather than standing in for it.
static func capture_drop(tree: SceneTree, spec: Variant) -> String:
    var files := PackedStringArray()
    var window_name := ""
    if spec is String:
        files.append(String(spec))
    elif spec is Array:
        for entry: Variant in spec:
            files.append(String(entry))
    elif spec is Dictionary:
        window_name = String(spec.get("window", ""))
        var asked: Variant = spec.get("files", [])
        if asked is String:
            files.append(String(asked))
        else:
            for entry: Variant in asked:
                files.append(String(entry))
    if files.is_empty():
        return "SaCapture: drop wants a file, or a list of them"
    var window := tree.root as Window
    if not window_name.is_empty():
        window = tree.root.find_child(window_name, true, false) as Window
        if window == null:
            return "SaCapture: no window called '%s' to drop on" % window_name
    window.files_dropped.emit(files)
    return (
        "SaCapture: dropped %d file(s) on %s at %s"
        % [files.size(), window_name if not window_name.is_empty() else "the root window", drop_point(tree)]
    )


# --- Save ---------------------------------------------------------------------


## Save: silently to the document's own file, or Save As for one that has none.
## *then* runs after a successful save, which is how the prompt saves and quits.
##
## *about* is the document saved, and the front one when the caller names none.
## The quit's Save All names each document in turn, so a painting that is not
## on screen is written to its own file.
func save_document(then: Callable, about: SaDocument = null) -> void:
    var doc := about if about != null else _document()
    if doc == null:
        return
    if doc.file_path.is_empty():
        save_as(then, &"", doc)
        return
    _save_to(doc.file_path, then, &"", doc)


## Save As, and with *codec* a save in that codec, asked for by its name, which
## File > Save as JPEG XL is. With no module registering the codec it says why
## and writes nothing. *about* is the document written, as in `save_document`.
func save_as(then: Callable, codec := &"", about: SaDocument = null) -> void:
    if not codec.is_empty() and SaCodecRegistry.shared().named(codec) == null:
        SaTrail.stage("Save as JPEG XL found no codec called %s" % codec)
        SaProblems.refuse(
            "SaDocumentFiles", tr("Save as JPEG XL needs the JPEG XL module, which this Sara did not load. Nothing was saved.")
        )
        return
    # Read before the picker opens rather than after it is answered: the file
    # is written to the document the painter asked about, and with several open
    # another one can come to the front while the window stands.
    var doc := about if about != null else _document()
    SaFilePicker.open(
        self,
        SaFilePicker.Mode.SAVE_FILE,
        PackedStringArray([tr("*.sad ; Sara Document")]),
        choose_save_name.bind(_save_to.bind(then, codec, doc))
    )


## The name a Save As writes for what the painter typed: a name ending `.sad`
## in any case is kept, and every other name has `.sad` put after it, so
## `sketch.jpg` becomes `sketch.jpg.sad` rather than losing what was typed.
static func sad_path_for(path: String) -> String:
    return path if path.get_extension().to_lower() == "sad" else path + ".sad"


## Whether *path* ends in the extension of a picture or of another program's
## container, the names a painter types meaning a file that program opens.
static func is_picture_name(path: String) -> bool:
    var extension := path.get_extension().to_lower()
    return SaImageImport.formats().open_extensions().has(extension) or FOREIGN_EXTENSIONS.has(extension)


## Turns the name the picker answered with into the one the save writes, asking
## what has to be asked on the way, and calls *proceed* with it, or not at all
## when the painter cancels.
##
## The platform picker appends nothing, so without this `noext` and
## `sketch.jpg` would both be written as Sara documents named exactly that, and
## the `.jpg` a file no other program could open, with nothing saying so. A picture's extension
## asks, because the painter may have meant Export. Any other name gets `.sad`
## without a question.
func choose_save_name(path: String, proceed: Callable) -> void:
    if path.get_extension().to_lower() == "sad" or path.begins_with(SaFilePicker.CONTENT_SCHEME):
        proceed.call(path)
    elif is_picture_name(path):
        var extension := path.get_extension().to_upper()
        SaTrail.stage("asked whether %s should be saved as %s" % [path.get_file(), sad_path_for(path).get_file()])
        SaMessage.confirm(
            self,
            tr("Save As"),
            (
                tr("%s will be a Sara document, not a %s. Save it as %s?")
                % [path.get_file(), extension, sad_path_for(path).get_file()]
            ),
            PackedStringArray([tr("Add .sad"), tr("Keep the name"), tr("Cancel")]),
            _on_extension_answered.bind(path, proceed),
            NAME_CANCEL,
            NAME_ADD_SAD
        )
    else:
        _confirm_appended(sad_path_for(path), proceed)


func _on_extension_answered(index: int, path: String, proceed: Callable) -> void:
    SaTrail.stage("answered %s" % ["Add .sad", "Keep the name", "Cancel"][clampi(index, NAME_ADD_SAD, NAME_CANCEL)])
    if index == NAME_ADD_SAD:
        _confirm_appended(sad_path_for(path), proceed)
    elif index == NAME_KEEP:
        proceed.call(path)


## The platform picker asked about the name as typed and never about the one
## with `.sad` put after it, so a file under that name is asked about here.
## Cancel is the default, because Enter on a question nobody read should not
## throw a painting away.
func _confirm_appended(path: String, proceed: Callable) -> void:
    if not FileAccess.file_exists(path):
        proceed.call(path)
        return
    SaTrail.stage("asked whether to replace %s" % path.get_file())
    SaMessage.confirm(
        self,
        tr("Replace file"),
        tr("%s already exists. Replace it?") % path.get_file(),
        PackedStringArray([tr("Replace"), tr("Cancel")]),
        _on_replace_answered.bind(path, proceed),
        REPLACE_CANCEL,
        REPLACE_CANCEL
    )


func _on_replace_answered(index: int, path: String, proceed: Callable) -> void:
    SaTrail.stage("answered %s" % ("Replace" if index == REPLACE else "Cancel"))
    if index == REPLACE:
        proceed.call(path)


## Writes the document to *path* in the background, in the codec *codec* when
## the painter asked for one by name, and in Zstd otherwise. *about* is the
## document written, and the front one when the caller names none.
func _save_to(path: String, then: Callable, codec := &"", about: SaDocument = null) -> void:
    var doc := about if about != null else _document()
    if doc == null:
        return
    # A session a tool holds over the picture is written first, as an undo
    # writes it, so the file holds what the painter sees: a gradient's end
    # dragged with the button still down had taken the ramp off the layer.
    # The session is the one over this document, which is its own surface's.
    var canvas := _canvas_for(doc)
    var machine := canvas.tool_machine() if canvas != null else null
    if machine != null:
        machine.close_session()
    # In the background, so the painter paints on while the file is written.
    # The save marks the document saved itself, when nothing changed after
    # its snapshot, and *then* waits for the file. The preview is taken on the
    # card now and read over the save's frames, because reading it back here
    # holds the frame for a long while at 4K.
    var began := Time.get_ticks_usec()
    # Off the easel holding this document, which is its parent, rather than off
    # the one on screen: each document a Save All writes carries its own
    # picture into its own file.
    var preview := SaExport.take_preview(doc.get_parent() as SaEasel)
    var took := roundi((Time.get_ticks_usec() - began) / 1000.0)
    SaTrail.mark("the preview of %s taken on the card in %d ms" % [path.get_file(), took])
    # The export targets are kept relative to the file written, so a Save As
    # into another folder still names the files it named.
    SaExportTargets.rebase(doc, path)
    SaSadFile.save_in_background(doc, path, -1, preview, true, _on_saved.bind(path, then, doc), true, codec)


func _on_saved(err: Error, path: String, then: Callable, doc: SaDocument = null) -> void:
    # A save that failed has said so in the problems line already.
    if err != OK:
        return
    SaSettings.add_recent_file(path)
    # Each file File > Export Target named, once the .sad is whole, read back
    # now and written on a worker, and *then* waits until they are whole. A
    # target that fails leaves the save done and is named on the status line.
    SaExportTargets.write_after_save(doc, path, then)


# --- Export -------------------------------------------------------------------


## Built on first use and reused after, so the format and its options are still
## what they were last time.
func open_export_dialog() -> void:
    var canvas := _canvas()
    if canvas == null or not is_inside_tree():
        return
    if _export_dialog == null:
        _export_dialog = ExportDialogScript.new()
        add_child(_export_dialog)
    _export_dialog.open_for(canvas)


## File > Export Target, over the document in front.
func open_export_targets() -> void:
    var doc := _document()
    if doc == null or not is_inside_tree():
        return
    if _targets_dialog == null:
        _targets_dialog = SaExportTargetsDialog.new()
        add_child(_targets_dialog)
    _targets_dialog.open_for(doc)


# --- Tabs ---------------------------------------------------------------------


## Whether *doc* is the untitled and untouched document Sara starts with, the
## one an Open replaces rather than opening a tab beside.
func is_untouched(doc: SaDocument) -> bool:
    return doc != null and SaDocumentSource.name_of(doc).is_empty() and not doc.modified and not _loading.has(doc)


## The document a new painting or a file lands in, brought to the front: the
## front one when *replace_untouched* and it is untouched, and otherwise a
## fresh tab. The front one too for a flow with no tabs, which is a suite's and
## holds one document. Null when no tab could be built.
func _landing(replace_untouched: bool) -> SaDocument:
    var front := _document()
    var tabs := SaDocumentTabs.in_tree(get_tree()) if is_inside_tree() else null
    if tabs == null or (replace_untouched and is_untouched(front)):
        var canvas := _canvas_for(front)
        # The document open now closes here, so its card gets its picture first.
        if canvas != null:
            SaWelcomeWindow.keep_closing_picture(canvas.easel)
        return front
    var surface := tabs.add_document()
    return SaSurface.document_of(surface)


## The canvas File > New builds its painting of *size* on, a fresh tab's, or
## *fallback* where no flow runs, and null when the card has no room for it.
## Static so the New dialog's answer asks it in one line.
static func canvas_for_new(tree: SceneTree, fallback: SaCanvas, size := Vector2i.ZERO) -> SaCanvas:
    var files := in_tree(tree)
    if files == null:
        return fallback
    if SaCardMemory.refuses(SaCardMemory.for_canvas(size)):
        return null
    return files._canvas_for(files._landing(true))


## Brings forward the tab already holding the file at *path*. Answers whether
## one did.
func _bring_open(path: String) -> bool:
    if _documents == null:
        return false
    var wanted := ProjectSettings.globalize_path(path).simplify_path()
    for surface in _documents.surfaces:
        var doc := surface.get_document()
        var held := doc.file_path if doc != null and not doc.file_path.is_empty() else SaDocumentSource.path_of(doc)
        if not held.is_empty() and ProjectSettings.globalize_path(held).simplify_path() == wanted:
            _documents.bring_to_front(surface)
            return true
    return false


## Closes the tab *doc* was opened into when what was to fill it failed, so a
## file that would not read leaves no empty tab behind. Only an untouched
## document closes, which loses nothing, and the last one stays.
func _drop_tab(doc: SaDocument) -> void:
    var tabs := SaDocumentTabs.in_tree(get_tree()) if is_inside_tree() else null
    if tabs != null and _documents != null and is_untouched(doc) and _documents.surfaces.size() > 1:
        tabs.close(_documents.surface_of(doc))


# --- Plumbing -----------------------------------------------------------------


func _canvas() -> SaCanvas:
    return _canvas_provider.call() as SaCanvas if _canvas_provider.is_valid() else null


## The canvas showing *doc*: the provider's for the document in front, and the
## view of the surface the owner holds it on for any other. Null for a document
## shown through no Control, which is what a suite's surface is.
func _canvas_for(doc: SaDocument) -> SaCanvas:
    var canvas := _canvas()
    if doc == null or (canvas != null and canvas.document == doc):
        return canvas
    return SaCanvasView.canvas_of(_documents.surface_of(doc)) if _documents != null else null


## The document a path is about when its caller named none: the one the painter
## is working on, which is the front surface's. The canvas provider answers for
## a flow built with no owner, which is a suite's.
func _document() -> SaDocument:
    var front := _documents.front if _documents != null else null
    if front != null:
        return front.get_document()
    var canvas := _canvas()
    return canvas.document if canvas != null else null


## The question a picture of a panorama's shape asks once it has opened: is it
## an equirectangular panorama, Assign or Keep Flat, Keep Flat the default and
## what Escape answers. Assign is `SaProjection.assign`, one history step, so
## the picture's pixels stay where they are and Ctrl+Z takes the kind back.
##
## Asked after the picture has landed rather than before, so the painter sees
## what they are asked about and the assign has the document to act on. A
## `.sad` is never asked, since its header says what it is, and the preference
## `SaSettings.ask_panorama` turns the question off.
##
## An inner class because it owns one sentence and two rules and nothing else of
## the flow, and the flow calls it from the two places a picture lands.
class PanoramaQuestion:
    extends RefCounted

    ## What the question's window is called, so a suite and a scenario's
    ## `click` find it among the flow's children.
    const NODE_NAME := "PanoramaQuestion"

    ## The two answers in button order. Keep Flat is both the default and the
    ## cancel, so Enter and Escape alike leave the document as it opened.
    const ASSIGN := 0
    const KEEP_FLAT := 1

    ## Whether a document of *size*, opened from *path* as *projection*, is
    ## asked about: a picture exactly twice as wide as it is tall that is not a
    ## `.sad`, still flat, with the preference on.
    static func due(path: String, size: Vector2i, projection: SaProjection) -> bool:
        if not SaSettings.ask_panorama or path.get_extension().to_lower() == "sad":
            return false
        if projection != null and projection.kind.id != SaProjection.FLAT:
            return false
        return size.y > 0 and size.x == size.y * 2

    ## Puts the question up on *host* when *doc*, just opened from *path*, is
    ## due one, and returns it, or null when nothing is asked.
    static func ask_if_due(host: Node, doc: SaDocument, path: String) -> SaMessage:
        if host == null or doc == null or not due(path, doc.canvas_size, doc.projection):
            return null
        var picture := path.get_file()
        SaTrail.stage("asked whether %s is a panorama" % picture)
        var dialog := SaMessage.confirm(
            host,
            host.tr("A panorama?"),
            (
                host.tr(
                    (
                        "%s is twice as wide as it is tall, the shape of an equirectangular panorama. "
                        + "Assign that projection to it? Assign moves no pixel and is one undo step, "
                        + "and Image > Projection... changes it later."
                    )
                )
                % picture
            ),
            PackedStringArray([host.tr("Assign"), host.tr("Keep Flat")]),
            func(index: int) -> void: _answered(host, doc, index),
            KEEP_FLAT,
            KEEP_FLAT
        )
        dialog.name = NODE_NAME
        return dialog

    static func _answered(host: Node, doc: SaDocument, index: int) -> void:
        SaTrail.stage("answered %s" % ("Assign" if index == ASSIGN else "Keep Flat"))
        if index != ASSIGN:
            return
        var kind := _equirectangular(host)
        if kind != null:
            SaProjection.assign(doc, SaProjection.new(kind))

    ## The equirectangular kind the running app registered, looked up as the
    ## `.sad` reader looks its kinds up, or the skeleton's own where no main
    ## scene holds a registry, which is a suite's.
    static func _equirectangular(host: Node) -> SaProjection.Kind:
        var tree := host.get_tree() if host != null and host.is_inside_tree() else null
        var main_node: Node = tree.current_scene if tree != null else null
        var held: Variant = main_node.get("registries") if main_node != null else null
        var kinds: SaProjection.Kinds = (held as SaRegistries).projections if held is SaRegistries else null
        var found: SaProjection.Kind = kinds.find(SaProjection.EQUIRECTANGULAR) if kinds != null else null
        if found != null:
            return found
        for kind: SaProjection.Kind in SaProjection.builtins():
            if kind.id == SaProjection.EQUIRECTANGULAR:
                return kind
        return null
