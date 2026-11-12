## The commands the menus alone offer: every static row of a menu that no other
## registration answers, registered the way the others are, so a menu is a list of command ids and nothing else.
##
## Beside the menus rather than in `ui/shortcuts`, because the router names none
## of them: a key reaches one through the registry, the way it reaches a
## module's command. The four that move the view or the document's history are
## the shortcut table's own handlers, handed in as callables, so the row and the
## chord of Fit, Centre, Reset Rotation, Undo and Redo run one implementation.
class_name SaMenuCommands
extends RefCounted

const LocalServerDialog := preload("res://ui/dialogs/sa_local_server_dialog.gd")

## New to Redo, the seven `project.godot` declares and the router answers before
## the registry would, so an action here would answer one press twice.
const ROUTER_ACTIONS: Array[StringName] = [
    &"file_new", &"file_open", &"file_save", &"file_save_as", &"ui_quit", &"edit_undo", &"edit_redo"
]

## Sara Default's keys for the rows that ship one: three view rows in one column
## under the left index finger, and F1 for the manual, the key nearly every
## desktop program answers with its help. The Info docker is on F9.
const KEYS: Dictionary[StringName, String] = {
    &"view_fit": "F", &"view_rotate_reset": "R", &"view_center": "V", &"help_manual": "F1"
}

## The Preferences page each of Help's settings rows opens, spelled exactly as
## the window's own `FIXED_PAGES` spells it, because `show_page` matches a title
## and not a translation. A test reads every one back against that table.
##
## Two, where the Settings menu had three. Its Keyboard Shortcuts row opened the
## page Help's own row already opened, and Help keeps that one. The rows say
## Display Settings... and Tablet Settings..., which is what a painter comes
## for, and land on the pages that hold those settings, whose titles say more.
const SETTINGS_PAGES: Dictionary = {
    &"help_display": "Canvas and colour",
    &"help_tablet": "Pen and tablet",
}

## How often, a quarter of a second apart, a desktop's opener is looked at
## before Sara stops waiting for its answer: ten seconds. An opener still
## running then has started a browser, which keeps it, and that says nothing.
const OPENER_LOOKS := 40

## The call a row that leaves Sara makes, `(url: String) -> Error`, which is
## [method desktop_open] in everything but a suite, which makes it fail. A
## suite that replaces it puts [method desktop_open] back.
static var opener: Callable = desktop_open

## `() -> bool` each, the shortcut table's view handlers. Fit's takes a `whole`
## as well, true for Fit to Window.
var _fit_view: Callable
var _center_view: Callable
var _reset_rotation: Callable
## `(undo: bool) -> bool`, the shortcut table's history on the chords' document.
var _history: Callable
## `() -> SaDocument`, the document the chords act on, which is what a row asks
## when it decides whether a press would do anything. Empty on a bar with no app
## around it, where every such row is dimmed.
var _document: Callable
## `() -> bool`, whether the tool machine holds a session a press on Undo would
## write as a step first, [method ToolMachine.holds_session]. Empty where no
## machine stands behind the bar, and then only the history lights the row.
var _holds_session: Callable


func _init(
    fit_view: Callable,
    center_view: Callable,
    reset_rotation: Callable,
    history: Callable,
    document: Callable = Callable(),
    holds_session: Callable = Callable()
) -> void:
    _fit_view = fit_view
    _center_view = center_view
    _reset_rotation = reset_rotation
    _history = history
    _document = document
    _holds_session = holds_session


## Registers every row that is not in *registry* yet, under the skeleton's
## name, the way the shortcut table registers its own.
func register_into(registry: SaCommandRegistry) -> void:
    if registry == null:
        return
    for command: SaCommandDescriptor in commands():
        if not registry.has(command.id):
            registry.register(command, &"sara-skeleton")


## The menu rows that ran code of their own and were no command, as commands, so
## every static row of every menu is one. Each is `[id, title, menu words,
## handler, category, sentence]`, and the optional seventh is the tick.
##
## The title is what the page would call the command, and the menu words are
## what its row reads, which is shorter because it stands under its menu's name.
func _menu_rows() -> Array:
    return [
        [
            &"file_new",
            "New document",
            "New...",
            _file_action.bind(&"file_new"),
            &"file",
            tr("A fresh document, at the size, depth and colour space you pick in the dialog."),
        ],
        [
            &"file_new_from_clipboard",
            "New document from the clipboard",
            "New from Clipboard",
            _file_action.bind(&"file_new_from_clipboard"),
            &"file",
            tr("A fresh document the size of the picture on the clipboard, which it holds as its one layer."),
        ],
        [
            &"file_open",
            "Open",
            "Open File...",
            _file_action.bind(&"file_open"),
            &"file",
            tr("Open a Sara document (.sad) or a picture."),
        ],
        [
            &"file_import",
            "Import a picture",
            "Import Picture...",
            _file_action.bind(&"file_import"),
            &"file",
            tr("Add a picture to the open document as a new layer. Nothing is replaced."),
        ],
        [
            &"file_save",
            "Save",
            "Save",
            _file_action.bind(&"file_save"),
            &"file",
            tr("Write the document back to its own .sad file. One that has no file yet asks where."),
        ],
        [
            &"file_save_as",
            "Save as",
            "Save As...",
            _file_action.bind(&"file_save_as"),
            &"file",
            tr("Write the document to a .sad file you choose, and paint into that one from now on."),
        ],
        [
            &"file_save_as_jpeg_xl",
            "Save as JPEG XL",
            "Save as JPEG XL...",
            _file_action.bind(&"file_save_as_jpeg_xl"),
            &"file",
            tr("Write a smaller .sad file you choose, coded in JPEG XL, slower than Save. An older Sara cannot open it."),
        ],
        [
            &"file_export",
            "Export",
            "Export...",
            _file_action.bind(&"file_export"),
            &"file",
            SaExportDialog.menu_sentence(),
        ],
        [
            &"file_export_targets",
            "Export target",
            "Export Target...",
            _file_action.bind(&"file_export_targets"),
            &"file",
            tr("Name PNG files every Save writes as well, such as a game's art in the game's folder."),
        ],
        [
            &"ui_quit",
            "Quit",
            "Quit",
            _emit_later.bind(EventBus.quit_requested),
            &"interface",
            tr("Close Sara. A document with unsaved changes asks before anything is lost."),
        ],
        [
            &"edit_undo",
            "Undo",
            "Undo",
            _history.bind(true),
            &"edit",
            tr("Step back through this document's history. The Undo History docker shows how far it goes."),
        ],
        [
            &"edit_redo",
            "Redo",
            "Redo",
            _history.bind(false),
            &"edit",
            tr("Step forward again, until the next change replaces what was undone."),
        ],
        [
            &"image_color_space",
            "Colour space",
            "Colour Space...",
            _emit_later.bind(EventBus.color_space_requested),
            &"image",
            tr("Assign a colour space to this document, or convert it to another."),
        ],
        [
            &"image_projection",
            "Projection",
            "Projection...",
            _emit_later.bind(EventBus.projection_requested),
            &"image",
            tr("Say whether this document is flat or a panorama, without moving a pixel."),
        ],
        [
            &"image_flip_horizontal",
            "Flip the image horizontally",
            "Flip Horizontally",
            _flip_image.bind(true),
            &"image",
            tr("Flip the whole picture left to right, every layer and mask with it, in one step. The selection is dropped."),
        ],
        [
            &"image_flip_vertical",
            "Flip the image vertically",
            "Flip Vertically",
            _flip_image.bind(false),
            &"image",
            tr("Flip the whole picture top to bottom, every layer and mask with it, in one step. The selection is dropped."),
        ],
        [
            &"image_rotate_clockwise",
            "Rotate the image 90° clockwise",
            "Rotate 90° Clockwise",
            _rotate_image.bind(1),
            &"image",
            tr("Rotate the image 90° clockwise."),
        ],
        [
            &"image_rotate_anticlockwise",
            "Rotate the image 90° anticlockwise",
            "Rotate 90° Anticlockwise",
            _rotate_image.bind(-1),
            &"image",
            tr("Rotate the image 90° anticlockwise."),
        ],
        [
            &"image_rotate_180",
            "Rotate the image 180°",
            "Rotate 180°",
            _rotate_image.bind(2),
            &"image",
            tr("Turn the whole picture upside down, in one step. The selection is dropped."),
        ],
        [
            &"layer_flip_horizontal",
            "Flip the layer horizontally",
            "Flip Layer Horizontally",
            _flip_layer.bind(true),
            &"layer",
            tr("Flip the active layer left to right about the middle of the canvas, or every layer in a group."),
        ],
        [
            &"layer_flip_vertical",
            "Flip the layer vertically",
            "Flip Layer Vertically",
            _flip_layer.bind(false),
            &"layer",
            tr("Flip the active layer top to bottom about the middle of the canvas, or every layer in a group."),
        ],
        [
            &"layer_make_smart",
            "Make the layer a smart layer",
            "Make Smart Layer",
            _smart.bind(SaLiveTransform.make_smart),
            &"layer",
            tr("Keep the active layer's paint as it was painted and draw it through a transform you can change or reset."),
        ],
        [
            &"layer_reset_transform",
            "Reset the smart layer's transform",
            "Reset Transform",
            _smart.bind(SaLiveTransform.reset_map),
            &"layer",
            tr("Draw the active smart layer where its paint was painted again, in one step. It stays smart."),
        ],
        [
            &"layer_bake_transform",
            "Convert the smart layer to an ordinary layer",
            "Convert to Ordinary Layer",
            _smart.bind(SaLiveTransform.bake),
            &"layer",
            tr("Write the active smart layer's transform into its pixels and make it an ordinary layer, in one step."),
        ],
        [
            &"layer_link_smart",
            "Copy the smart layer sharing its source",
            "Share Source with a Copy",
            _smart.bind(SaSharedSource.share),
            &"layer",
            tr("Copy the active smart layer with a transform of its own, sharing one source, so an edit to it shows in both."),
        ],
        [
            &"layer_unlink_source",
            "Make the smart layer's source independent",
            "Make Source Independent",
            _smart.bind(SaSharedSource.make_independent),
            &"layer",
            tr("Give the active smart layer a copy of its shared source of its own, in one step. It stays smart."),
        ],
        [
            &"layer_link_file",
            "Link the smart layer to a picture file",
            "Link to File...",
            _link_file,
            &"layer",
            tr("Draw the active smart layer from a picture on disk, which you change elsewhere and reload here."),
        ],
        [
            &"layer_reload_link",
            "Reload the smart layer's linked file",
            "Reload Linked File",
            _smart.bind(SaLinkedFile.reload_file),
            &"layer",
            tr("Read the active smart layer's linked file again, in one step. Its transform and settings stay."),
        ],
        [
            &"layer_link_absolute",
            "Make the linked file's path absolute",
            "Make Path Absolute",
            _smart.bind(SaLinkedFile.make_absolute),
            &"layer",
            tr("Save the path of the active smart layer's linked file from the root of the disk."),
        ],
        [
            &"layer_link_relative",
            "Make the linked file's path relative",
            "Make Path Relative",
            _smart.bind(SaLinkedFile.make_relative),
            &"layer",
            tr("Save the path of the active smart layer's linked file from the document's folder, so the two move together."),
        ],
        [
            &"layer_embed_link",
            "Embed the smart layer's linked file",
            "Embed Linked File",
            _smart.bind(SaLinkedFile.embed),
            &"layer",
            tr("Keep the picture of the active smart layer's linked file in the document and drop the link, in one step."),
        ],
        [
            &"layer_clear_override",
            "Clear the strokes over the smart layer's linked file",
            "Clear Override",
            _smart.bind(SaLinkedFile.clear_override),
            &"layer",
            tr("Drop the strokes painted into the active smart layer's linked file, in one step, so it shows the file alone."),
        ],
        [
            &"select_color_range",
            "Select a colour range",
            "Colour Range...",
            _select_dialog.bind(&"color_range"),
            &"select",
            tr("Select every pixel near a colour you pick, anywhere on the canvas, fading out with the fuzziness."),
        ],
        [
            &"select_feather",
            "Feather the selection",
            "Feather...",
            _select_dialog.bind(&"feather"),
            &"select",
            tr("Soften the selection's edge over a radius you give, so paint fades out across it."),
        ],
        [
            &"select_border",
            "Border the selection",
            "Border...",
            _select_dialog.bind(&"border"),
            &"select",
            tr("Replace the selection with a band of the width you give, along the edge it had."),
        ],
        [
            &"select_grow",
            "Grow the selection",
            "Grow...",
            _select_dialog.bind(&"grow"),
            &"select",
            tr("Move the selection's edge out by the pixels you give, to take in the soft fringe a wand click stopped short of."),
        ],
        [
            &"select_shrink",
            "Shrink the selection",
            "Shrink...",
            _select_dialog.bind(&"shrink"),
            &"select",
            tr("Shrink the selection by a number of pixels. Parts thinner than twice that disappear."),
        ],
        [
            &"view_second_row",
            "Show the second row",
            "Show Second Row",
            _flip_second_row,
            &"view",
            tr("Show a second row for controls that do not fit on the first."),
            _second_row_on,
        ],
        [
            &"view_fit",
            "Fit the document between the dockers",
            "Fit to View",
            _fit_view,
            &"view",
            tr("Zoom so the whole document is on screen, in the room between the dockers."),
        ],
        [
            &"view_fit_window",
            "Fit the document to the window",
            "Fit to Window",
            _fit_window,
            &"view",
            tr("Zoom so the whole document fills the window, under the dockers as well."),
        ],
        [
            &"view_center",
            "Centre the view",
            "Centre View",
            _center_view,
            &"view",
            tr("Put the document back in the middle, at the zoom it is already at."),
        ],
        [&"view_rotate_reset", "Reset the rotation", "Reset Rotation", _reset_rotation, &"view", "Put the view back upright."],
        [
            &"view_grid",
            "Show the grid",
            "Toggle Grid",
            _flip_grid,
            &"view",
            tr("A hairline grid over the document. It is not painted on."),
            _grid_on,
        ],
        [
            &"window_new_secondary",
            "New window for a second monitor",
            "New Window for Second Monitor",
            _emit_now.bind(EventBus.secondary_workspace_requested),
            &"window",
            tr("Another window, to drag dockers into and put on a second monitor."),
        ],
        [
            &"window_gather_dockers",
            "Move every docker to the main window",
            "Move All Dockers to Main Window",
            _gather_dockers,
            &"window",
            tr("Bring every docker back into this window, including any left on a monitor you unplugged."),
        ],
        [
            &"help_welcome",
            "Welcome",
            "Welcome",
            _emit_later.bind(EventBus.welcome_requested),
            &"help",
            tr("The window Sara opens at start, with the recent files, the news and the quick settings."),
        ],
        [
            &"help_shortcuts",
            "Keyboard shortcuts",
            "Keyboard Shortcuts",
            _emit_later.bind(EventBus.shortcuts_requested),
            &"help",
            tr("List every keyboard shortcut. Change them in Preferences > Keyboard shortcuts."),
        ],
        [
            &"help_display",
            "Display settings",
            "Display Settings...",
            _settings_page.bind(SETTINGS_PAGES[&"help_display"], SaDisplayPage.PROFILE_ROW),
            &"help",
            tr(
                (
                    "Open Preferences > Canvas and colour at the monitor's colour profile. The exposure stops are "
                    + "on the same page."
                )
            ),
        ],
        [
            &"help_tablet",
            "Tablet settings",
            "Tablet Settings...",
            _settings_page.bind(SETTINGS_PAGES[&"help_tablet"]),
            &"help",
            tr("Open Preferences > Pen and tablet, where the pen is calibrated against the screen."),
        ],
        [
            &"help_manual",
            "Manual",
            "Manual",
            _emit_later.bind(EventBus.manual_requested),
            &"help",
            tr("The painter's manual, in a window of its own. It comes with Sara, so it needs no network and no browser."),
        ],
        [
            &"help_color_spaces",
            "Colour spaces",
            "Colour Spaces...",
            _emit_later.bind(EventBus.color_spaces_requested),
            &"help",
            tr("Every colour space Sara knows, its gamut drawn on the chromaticity diagram, opened on the painting's own."),
        ],
        [
            &"help_documentation",
            "Documentation",
            "Documentation",
            open_url.bind(SaModulesMenu.DOCUMENTATION_URL),
            &"help",
            tr("Opens the developers' pages in Sara's repository in your browser. The painter's manual is Help, Manual."),
        ],
        [
            &"help_report",
            "Report a problem",
            "Report a Problem",
            open_report,
            &"help",
            tr("Opens the issue tracker of Sara's repository in your browser."),
        ],
        [
            &"help_connect_agent",
            "Local server",
            "Local Server",
            _emit_now.bind(EventBus.local_server_requested),
            &"help",
            tr(
                (
                    "A server on this computer only, which a notebook or a coding agent paints through. Ticking it "
                    + "opens it and says how to connect, and unticking it closes it."
                )
            ),
            _local_server_on,
        ],
        [
            &"help_about",
            "About Sara",
            "About Sara",
            _emit_later.bind(EventBus.about_requested),
            &"help",
            tr("The version, the licence and where Sara comes from."),
        ],
        [
            &"filter_browse",
            "Browse filters",
            "Browse Filters...",
            _browse_filters,
            &"filter",
            tr(
                (
                    "Every filter a module registered, in one docker, with a search and a preview. "
                    + "The rows below stay where they are."
                )
            ),
        ],
        [
            &"filter_copy_prompt",
            "Copy the kernel prompt",
            "Copy the kernel prompt",
            _copy_kernel_prompt,
            &"filter",
            tr(
                (
                    "Puts the contract a kernel has to keep on the clipboard, so a language model "
                    + "you paste it into writes a pixel function you can drop in a module."
                )
            ),
        ],
        [
            &"modules_reload",
            "Reload modules",
            "Reload Modules",
            _reload_modules,
            &"modules",
            tr(
                (
                    "Read every module in your folders again, with its scripts and kernels, without a restart. A module that "
                    + "shipped with Sara stays as it is."
                )
            ),
        ],
        [
            &"modules_new",
            "New module",
            "New Module...",
            _emit_later.bind(EventBus.new_module_requested),
            &"modules",
            (
                tr("Create a module in %s and open the folder. Read in by Reload Modules or at the next start.")
                % ModuleLoader.user_modules_path()
            ),
        ],
        [
            &"modules_open_folder",
            "Open the user modules folder",
            "Open User Modules Folder...",
            open_url.bind(ModuleLoader.user_modules_path()),
            &"modules",
            (
                tr("%s. A folder with a module.gd in it is loaded by Reload Modules or at the next start.")
                % ModuleLoader.user_modules_path()
            ),
        ],
    ]


## The rows above as commands, each an action of its own name, which is its row
## on the Keyboard Shortcuts page, but for [constant ROUTER_ACTIONS].
func commands() -> Array[SaCommandDescriptor]:
    var out: Array[SaCommandDescriptor] = []
    for entry: Array in _menu_rows():
        var command := SaCommandDescriptor.create(entry[0], entry[1], entry[3])
        if ROUTER_ACTIONS.has(command.id):
            command.action = &""
        if KEYS.has(command.id):
            command.default_events = [SaShortcutStore.parse_chord(KEYS[command.id])]
        command.label = entry[2]
        command.category = entry[4]
        command.sentence = entry[5]
        if entry.size() > 6:
            command.checked = entry[6]
        command.enabled = _enabled_checks().get(entry[0], Callable())
        out.append(command)
    return out


## The rows that can do nothing in some state, each with the question that
## dims it. Each asks what its handler reads, so a row that takes a press is a
## row whose press does something: Undo and Redo the document's history,
## Feather, Border, Grow and Shrink the selection they would reshape, and Reset
## Transform and Convert to Ordinary Layer the active smart layer.
func _enabled_checks() -> Dictionary:
    return {
        &"edit_undo": _can_step.bind(true),
        &"edit_redo": _can_step.bind(false),
        &"select_feather": _has_selection,
        &"select_border": _has_selection,
        &"select_grow": _has_selection,
        &"select_shrink": _has_selection,
        &"layer_reset_transform": _has_transform,
        &"layer_bake_transform": _has_transform,
        &"layer_link_smart": _has_transform,
        &"layer_unlink_source": _shares_source,
        &"layer_reload_link": _is_linked,
        &"layer_link_absolute": _is_linked,
        &"layer_link_relative": _is_linked,
        &"layer_embed_link": _is_linked,
        &"layer_clear_override": _is_linked,
    }


## Whether the chords' document has a step to take back, or forward again.
##
## **Undo is lit over an open session as well**, a liquify push or a transform
## move the history does not hold yet, because the press writes it as a step
## first and takes that step back. Redo is not: the session written clears the
## redo list, so a lit Redo there would do nothing.
func _can_step(undo: bool) -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    if document == null or document.undo_redo == null:
        return false
    if not undo:
        return document.undo_redo.has_redo()
    return document.undo_redo.has_undo() or (_holds_session.is_valid() and bool(_holds_session.call()))


## View > Fit to Window, the shortcut table's fit told to take the whole visible
## rectangle and leave the dockers no room. One handler for both rows, so the
## two fits never differ in anything but their room.
func _fit_window() -> bool:
    return bool(_fit_view.call(true)) if _fit_view.is_valid() else false


## Image > Flip Horizontally and Flip Vertically, on the chords' document.
func _flip_image(horizontal: bool) -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaOrient.new(document).flip_image(horizontal)


## Image > Rotate, *quarters* clockwise quarter turns, a negative number the
## other way.
func _rotate_image(quarters: int) -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaOrient.new(document).rotate_image(quarters)


## Layer > Flip Horizontally and Flip Vertically, on the active layer. A layer
## that cannot be flipped says why in the corner, from `SaOrient`.
func _flip_layer(horizontal: bool) -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaOrient.new(document).flip_layer(document.active_layer, horizontal)


## Layer > Make Smart Layer, Reset Transform and Convert to Ordinary Layer,
## *run* on the active layer. A layer it cannot act on says why in the corner,
## from `SaLiveTransform`.
func _smart(run: Callable) -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and bool(run.call(document, document.active_layer))


## Whether the chords' document's active layer is a smart layer, one that
## carries a live transform. An ordinary layer's transform was written in when
## the tool's box was confirmed, so Reset and Convert are dimmed for it.
func _has_transform() -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaLiveTransform.can_bake(document.active_layer)


## Whether the chords' document's active layer shares its source with another.
func _shares_source() -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaSharedSource.can_unlink(document.active_layer)


## Whether the chords' document's active layer is linked to a file.
func _is_linked() -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and SaLinkedFile.is_linked(document.active_layer)


## Layer > Link to File...: the file picker, filtered to the flat pictures, and
## the picture chosen linked to the active layer. A layer that cannot take a
## link says why in the corner, from `SaLinkedFile`.
func _link_file() -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    var tree := Engine.get_main_loop() as SceneTree
    if document == null or tree == null:
        return false
    var filters := PackedStringArray([SaImageImport.dialog_filter()])
    var chosen := func(path: String) -> void: SaLinkedFile.link_file(document, document.active_layer, path)
    SaFilePicker.open(tree.root, SaFilePicker.Mode.OPEN_FILE, filters, chosen)
    return true


## Whether the chords' document has a selection to reshape.
func _has_selection() -> bool:
    var document := _document.call() as SaDocument if _document.is_valid() else null
    return document != null and document.selection != null and document.selection.active


## A File row: the document flow main builds, or nothing on a bar with no app
## around it. New, Open, Save and Save As are the flow's own chord actions.
func _file_action(action: StringName) -> bool:
    var files := SaDocumentFiles.in_tree(Engine.get_main_loop() as SceneTree)
    if files == null:
        return false
    match action:
        &"file_import":
            # No discard prompt: an import adds a layer and throws nothing away.
            files.import_with_dialog()
        &"file_new_from_clipboard":
            files.new_from_clipboard()
        &"file_export":
            files.open_export_dialog()
        &"file_export_targets":
            files.open_export_targets()
        _:
            files.run_action(action)
    return true


## A request on the bus, sent once the menu that asked for it has closed.
## Popping a window that takes focus from inside a popup's own handler runs
## while the popup is still mid-hide, which desynchronises the engine's popup
## and focus bookkeeping.
static func _emit_later(request: Signal) -> bool:
    request.emit.call_deferred()
    return true


## A request on the bus sent at once: one that opens no window, or Local
## Server's, a tick row that leaves its menu open rather than mid-hide and whose
## tick is read again the moment the press returns.
static func _emit_now(request: Signal) -> bool:
    request.emit()
    return true


## Select > Colour Range, Feather, Border, Grow and Shrink. Each dialog, and
## the radius and fuzziness it remembers between opens, is the Select menu's,
## so the command asks that menu for it.
static func _select_dialog(which: StringName) -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    var menu: SaSelectMenu = null
    for node: Node in tree.root.find_children("*", "PanelContainer", true, false) if tree != null else []:
        if node is TopMenuBar:
            menu = (node as TopMenuBar).menu("Select") as SaSelectMenu
    if menu == null:
        return false
    if which == &"color_range":
        menu.open_color_range_dialog()
    else:
        menu.open_radius_dialog(which)
    return true


static func _flip_second_row() -> bool:
    SaSettings.second_row = not SaSettings.second_row
    return true


static func _second_row_on() -> bool:
    return SaSettings.second_row


static func _flip_grid() -> bool:
    SaSettings.show_grid = not SaSettings.show_grid
    return true


static func _grid_on() -> bool:
    return SaSettings.show_grid


## Whether a door listens in this Sara, the boot's included, which ticks
## Modules › Local Server. Asked of the group the harness puts the door in,
## since the menus never name the harness.
static func _local_server_on() -> bool:
    return LocalServerDialog.listening(Engine.get_main_loop() as SceneTree)


## Window > Move All Dockers to Main Window.
static func _gather_dockers() -> bool:
    EventBus.docker_reparent_requested.emit("*all*", null)
    return true


## One of Help's settings rows: Preferences, opened on the page of that title,
## and scrolled to the row of *row_key* with the row marked when one is named.
static func _settings_page(page_title: String, row_key: StringName = &"") -> bool:
    if row_key.is_empty():
        EventBus.settings_page_requested.emit.call_deferred(page_title)
    else:
        EventBus.settings_row_requested.emit.call_deferred(page_title, row_key)
    return true


## A Help or Modules row that leaves Sara for the browser or the file manager.
## When the desktop answers that nothing opened, the corner says what was meant
## to open and where it is, because a seat with no browser otherwise closed the
## menu on silence. A browser that opened says nothing.
static func open_url(url: String) -> bool:
    if int(opener.call(url)) != OK:
        EventBus.paint_refused.emit(not_opened(url))
    return true


## Help > Report a Problem, the issue form with this build and machine filled in.
static func open_report() -> bool:
    return open_url(SaHelpMenu.report_url())


## Hands *url* to the desktop, the browser for an address and the file manager
## for a folder. On Linux and the BSDs the engine's `OS.shell_open` answers OK
## before `xdg-open` has run, even when there is no `xdg-open` at all, so Sara
## starts `xdg-open` itself and watches it, and an opener that ends with an
## error is said in the corner then. Anywhere else the engine's answer is the
## desktop's, and is returned.
static func desktop_open(url: String) -> Error:
    if OS.get_name() not in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
        return OS.shell_open(url)
    var pid := OS.create_process("xdg-open", [url])
    if pid < 0:
        return FAILED
    _watch_opener(pid, url, OPENER_LOOKS)
    return OK


## Looks at the opener *pid* started for *url* and again a quarter of a second
## later, *looks* more times. One that ended with an error says so in the corner.
static func _watch_opener(pid: int, url: String, looks: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    if not OS.is_process_running(pid):
        if OS.get_process_exit_code(pid) > 0:
            EventBus.paint_refused.emit(not_opened(url))
        return
    if looks > 0:
        tree.create_timer(0.25).timeout.connect(_watch_opener.bind(pid, url, looks - 1))


## The line the corner shows when *url* did not open: the address written out
## to be copied, Take a Note named for the issue tracker since it needs no
## browser, and the folder's path for a folder the file manager did not show.
## The manual's web links say the same.
static func not_opened(url: String) -> String:
    if not url.contains("://"):
        return TranslationServer.translate("The folder could not be shown in a file manager. It is %s.") % url
    if url.begins_with(SaHelpMenu.REPORT_URL):
        return (
            (
                TranslationServer.translate("No browser answered, so the issue tracker did not open. Its address is %s.")
                % SaHelpMenu.REPORT_URL
            )
            + " "
            + TranslationServer.translate("Help > Take a Note needs no browser and keeps your words in a file.")
        )
    return TranslationServer.translate("No browser answered, so the page did not open. Its address is %s.") % url


## Filter > Browse Filters, which summons the Filters docker. A tree with none,
## a detached bar's, finds nothing.
static func _browse_filters() -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    if FiltersDocker.find_in(tree) == null:
        return false
    # Deferred for the reason `_emit_later` gives: the docker takes focus.
    FiltersDocker.summon.call_deferred(tree)
    return true


## Modules > Copy the kernel prompt: the contract a kernel keeps, on the clipboard.
static func _copy_kernel_prompt() -> bool:
    var text := SaModulesMenu.prompt_text()
    if text.is_empty():
        return false
    DisplayServer.clipboard_set(text)
    return true


## Modules > Reload Modules. Deferred, so the popup has closed and no row of the
## menu is on the stack while the reload rebuilds the registries it was built
## from. The menu is built again on its next open.
static func _reload_modules() -> bool:
    ModuleLoader.reload_user_modules.call_deferred()
    return true
