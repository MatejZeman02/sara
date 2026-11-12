## The windows Sara opens on request: Preferences, New, Colour Space,
## Projection, Canvas Size, Relief Light, About, the shortcuts, the manual, the
## colour spaces, and the Filter adjustments.
##
## Each is built on first open and kept, so the second open is instant and any
## state the user left in it survives. Built with the registries and one
## callable, the canvas, rather than a reference to `Main`: a cut owns what it
## works on and takes no handle to the class it was cut from. The welcome
## window's Open asks the document flow itself.
##
## A `Node` rather than a `RefCounted`, deliberately. These methods are connected
## to `EventBus` signals, and Godot disconnects a signal automatically when its
## target `Object` is freed. A `RefCounted` target would instead be kept alive
## *by* the connection, outliving the Main it points at, and the next emission
## would reach a helper whose document and canvas are gone.
##
## The dialog windows are children of this node, and a driver that finds one
## by name finds it here.
class_name MainDialogs
extends Node

## The registries, for the Preferences pages, the tools page and the engine a
## resize dialog asks for by role.
var _registries: SaRegistries

## `func() -> SaCanvas`, the canvas the dialogs act on.
var _canvas_provider: Callable

var _settings_window: Window = null
var _new_document_dialog: NewDocumentDialog = null
var _new_module_dialog: NewModuleDialog = null
var _color_space_dialog: ColorSpaceDialog = null
var _projection_dialog: SaProjectionDialog = null
var _canvas_size_dialog: SaCanvasSizeDialog = null
var _image_size_dialog: SaImageSizeDialog = null
var _about_dialog: SaAboutDialog = null
var _tablet_sweep_dialog: SaTabletSweepDialog = null
var _welcome_window: SaWelcomeWindow = null
## The catalogues the welcome window's language row lists, or null with no
## registries.
var _catalogues: SaTranslationRegistry = null
var _color_spaces_window: SaColorSpacesWindow = null
var _relief_light_dialog: SaReliefLightDialog = null

## `func() -> int`, the first logical row below the top bar, which every dialog
## is kept under once this node is in the tree.
var _below_bar: Callable


## *welcome_window* is the one `SaBoot` opened before this node existed, or
## null. It stays where the boot put it, since moving a window that is on
## screen takes it off and puts it back, and Help shows it again from here.
## *below_bar* is `MainDockers.below_bar`, handed to every dialog the way
## `MainDockers` hands it to `DockerLayoutStore.top_inset`, so no dialog opens
## over the menus.
func _init(
    registries: SaRegistries, canvas_provider: Callable, welcome_window: SaWelcomeWindow = null, below_bar := Callable()
) -> void:
    name = "MainDialogs"
    _registries = registries
    _canvas_provider = canvas_provider
    _welcome_window = welcome_window
    _below_bar = below_bar
    if registries != null:
        _catalogues = registries.translations
    if _welcome_window != null:
        _welcome_window.follow_catalogues(_catalogues)


## The bar is the main window's, and every dialog opens over it, whoever built
## the dialog, so the row goes to the one static every dialog reads.
func _enter_tree() -> void:
    if _below_bar.is_valid():
        SaDialogWindow.top_inset = _below_bar


## Given back only while it is still this node's, so a second `Main` that has
## already handed in its own bar keeps it.
func _exit_tree() -> void:
    if SaDialogWindow.top_inset == _below_bar:
        SaDialogWindow.top_inset = Callable()


## Connects every dialog to the signal that opens it. Guarded, because module
## reloads run the setup again.
func connect_event_bus() -> void:
    if not EventBus.preferences_requested.is_connected(open_preferences):
        EventBus.preferences_requested.connect(open_preferences)
    if not EventBus.new_document_requested.is_connected(open_new_document):
        EventBus.new_document_requested.connect(open_new_document)
    if not EventBus.new_module_requested.is_connected(open_new_module):
        EventBus.new_module_requested.connect(open_new_module)
    if not EventBus.color_space_requested.is_connected(open_color_space):
        EventBus.color_space_requested.connect(open_color_space)
    if not EventBus.projection_requested.is_connected(open_projection):
        EventBus.projection_requested.connect(open_projection)
    if not EventBus.canvas_size_requested.is_connected(open_canvas_size):
        EventBus.canvas_size_requested.connect(open_canvas_size)
    if not EventBus.image_size_requested.is_connected(open_image_size):
        EventBus.image_size_requested.connect(open_image_size)
    if not EventBus.about_requested.is_connected(open_about):
        EventBus.about_requested.connect(open_about)
    if not EventBus.shortcuts_requested.is_connected(open_shortcuts):
        EventBus.shortcuts_requested.connect(open_shortcuts)
    # `open_preferences` takes the page and the row, so the two need no method of their own.
    for request: Signal in [EventBus.settings_page_requested, EventBus.settings_row_requested]:
        if not request.is_connected(open_preferences):
            request.connect(open_preferences)
    if not EventBus.display_page_requested.is_connected(open_display_page):
        EventBus.display_page_requested.connect(open_display_page)
    if not EventBus.relief_light_requested.is_connected(open_relief_light):
        EventBus.relief_light_requested.connect(open_relief_light)
    if not EventBus.tablet_sweep_requested.is_connected(open_tablet_sweep):
        EventBus.tablet_sweep_requested.connect(open_tablet_sweep)
    # Help's door into the window. The boot's window is handed in instead.
    if not EventBus.welcome_requested.is_connected(open_welcome):
        EventBus.welcome_requested.connect(open_welcome)
        SaWelcomeWindow.read_ahead()
    if not EventBus.manual_requested.is_connected(open_manual):
        EventBus.manual_requested.connect(open_manual)
    if not EventBus.module_page_requested.is_connected(open_module_page):
        EventBus.module_page_requested.connect(open_module_page)
    if not EventBus.color_spaces_requested.is_connected(open_color_spaces):
        EventBus.color_spaces_requested.connect(open_color_spaces)


func open_about() -> void:
    if _about_dialog == null:
        _about_dialog = SaAboutDialog.new()
        add_child(_about_dialog)
    _about_dialog.refresh()
    _about_dialog.popup_centered()


## Help > Keyboard Shortcuts. The list is a Preferences page rather than a
## dialog of its own, because that is where a painter looks for it and because
## it is editable now.
func open_shortcuts() -> void:
    open_preferences("Keyboard shortcuts", StringName(SaShortcutsPage.CHORD_KEY + String(SaShortcutRows.ORDER[0])))


## View > Exposure Stops.... The menu opens the page on the slider's row rather
## than nudging the setting itself from items of its own, so the slider is the
## one place the setting is changed.
func open_display_page() -> void:
    open_preferences("Canvas and colour", SaDisplayPage.STOPS_ROW)


## View > Relief Light.... Pointed at the document on every open, for the
## reason the colour space dialog is reconfigured: the light is the document's,
## and the document may be another one by now.
func open_relief_light() -> void:
    var doc := document()
    if doc == null:
        return
    if _relief_light_dialog == null:
        _relief_light_dialog = SaReliefLightDialog.new()
        add_child(_relief_light_dialog)
    _relief_light_dialog.configure(doc)
    _relief_light_dialog.popup_centered()


## Help > Colour Spaces, the browser that was a page of Preferences, in a
## window of its own built on the first ask and kept.
func open_color_spaces() -> void:
    if _color_spaces_window == null:
        _color_spaces_window = SaColorSpacesWindow.new()
        add_child(_color_spaces_window)
    _color_spaces_window.popup_centered()


## Preferences > Pen and tablet > Calibrate by Sweeping. The dialog fits the curve and
## this stores it, so the page and the game write the same setting.
func open_tablet_sweep() -> void:
    if _tablet_sweep_dialog == null:
        _tablet_sweep_dialog = SaTabletSweepDialog.new()
        add_child(_tablet_sweep_dialog)
        _tablet_sweep_dialog.curve_accepted.connect(_on_tablet_curve_accepted)
    _tablet_sweep_dialog.restart()
    _tablet_sweep_dialog.popup_centered()


## The fitted curve is stored here rather than by the dialog, so a dialog that
## is closed without Keep leaves nothing behind.
func _on_tablet_curve_accepted(table: PackedFloat32Array) -> void:
    SaTablet.save_correction(table)


func open_preferences(page: String = "", row: StringName = &"") -> void:
    if _settings_window == null:
        var ui_registry: SaUIRegistry = _registries.ui if _registries != null else null
        _settings_window = preload("res://ui/settings/sa_settings_window.gd").new(SaSettingsWindow.register_builtins(ui_registry))
        if _registries != null:
            _settings_window.tools_registry = _registries.tools
            _settings_window.filters_registry = _registries.filters
            _settings_window.commands_registry = _registries.commands
            _settings_window.translations_registry = _registries.translations
        add_child(_settings_window)
    # A request with no page is a toggle, so Ctrl+comma closes Preferences as
    # well as opening it. The window owns that decision, because only it knows
    # that being rolled up to its title bar still counts as open.
    _settings_window.toggle(page, row)


## The welcome window, built on first ask and kept, the way the others here are,
## or the boot's, when the boot showed one. Help asks whenever a painter wants
## it back.
func open_welcome() -> void:
    if _welcome_window == null:
        _welcome_window = SaWelcomeWindow.new()
        _welcome_window.follow_catalogues(_catalogues)
        add_child(_welcome_window)
    _welcome_window.open()


## Help > Manual. The window builds itself on first ask and keeps its page.
func open_manual() -> void:
    SaManualWindow.open_in(self)


## A module's row in Modules > Active Modules, the Modules window on its page.
func open_module_page(module_id: StringName) -> void:
    SaModulesWindow.open_in(self, module_id)


func open_new_document() -> void:
    if _new_document_dialog == null:
        _new_document_dialog = NewDocumentDialog.new(_registries.layer_types if _registries != null else null)
        add_child(_new_document_dialog)
        _new_document_dialog.document_requested.connect(_on_new_document_confirmed)
    _new_document_dialog.popup_centered()


func _on_new_document_confirmed(size: Vector2i, space: SaColorSpace, dpi: float, background: Dictionary = {}) -> void:
    var canvas := SaDocumentFiles.canvas_for_new(get_tree(), _canvas(), size) if is_inside_tree() else _canvas()
    if canvas == null or canvas.document == null:
        return
    # The document goes first so the full composite the resize schedules already
    # sees the new layers rather than the ones it just replaced.
    canvas.document.reset_to_default(size, space, dpi, background, _registries.layer_types if _registries != null else null)
    canvas.resize_canvas(size)
    # With New Document embedded, Create is a press on a dialog, which the
    # welcome window does not count, so the document made puts it away.
    if _welcome_window != null:
        _welcome_window.hide()


## Modules > New Module.... The dialog writes the module and opens its folder
## itself, so this only builds it and opens it blank, the way open_new_document
## opens its.
func open_new_module() -> void:
    if _new_module_dialog == null:
        _new_module_dialog = NewModuleDialog.new()
        add_child(_new_module_dialog)
    _new_module_dialog.reset()
    _new_module_dialog.popup_centered()


func open_color_space() -> void:
    if _color_space_dialog == null:
        _color_space_dialog = ColorSpaceDialog.new()
        add_child(_color_space_dialog)
        _color_space_dialog.assign_requested.connect(_on_color_space_assigned)
        _color_space_dialog.convert_requested.connect(_on_color_space_converted)

    # Reconfigured on every open rather than once, because both operations change
    # what the document is. The dialog gets the predicate itself rather than one
    # answer, so changing the target dropdown re-asks instead of keeping the
    # verdict it was handed when the window opened.
    var doc := document()
    # A lambda rather than the pass's own method: a Callable holds no reference,
    # so a pass built here would be freed before the dropdown first asked.
    var reason_for := Callable()
    if doc != null:
        reason_for = func(target: SaColorSpace) -> String: return SaColorConversion.new(doc).blocked_reason(target)
    _color_space_dialog.configure(doc.color_space if doc != null else null, reason_for)
    _color_space_dialog.popup_centered()


## Image > Projection.... Reconfigured on every open, for the reason the colour
## space dialog is, with the kinds registered now.
func open_projection() -> void:
    if _projection_dialog == null:
        _projection_dialog = SaProjectionDialog.new()
        add_child(_projection_dialog)
        _projection_dialog.assign_requested.connect(_assign_projection)
        _projection_dialog.convert_requested.connect(
            func(target: SaProjection) -> void: SaProjection.reproject(document(), target)
        )
    var doc := document()
    _projection_dialog.configure(
        doc.projection if doc != null else null,
        _registries.projections if _registries != null else null,
        func(target: SaProjection) -> String: return SaProjection.reproject_note(doc, target)
    )
    _projection_dialog.popup_centered()


func _assign_projection(target: SaProjection) -> void:
    SaProjection.assign(document(), target)


## Image > Canvas Size. Reconfigured on every open, for the reason the colour
## space dialog is: the two spinboxes start at what the canvas is now and the
## canvas has moved on since the last open.
func open_canvas_size() -> void:
    if _canvas_size_dialog == null:
        _canvas_size_dialog = SaCanvasSizeDialog.new()
        add_child(_canvas_size_dialog)
        _canvas_size_dialog.resize_requested.connect(_on_canvas_size_confirmed)
    var doc := document()
    _canvas_size_dialog.configure(doc.canvas_size if doc != null else Vector2i(1920, 1080))
    _canvas_size_dialog.popup_centered()


## `SaCrop` does the work and announces `document_resized`, which the canvas view
## is already listening to, so there is no `resize_canvas` call here the way
## there is after File > New: this changes the document Sara is showing rather
## than replacing it.
func _on_canvas_size_confirmed(size: Vector2i, anchor: Vector2i) -> void:
    var doc := document()
    if doc == null:
        return
    _engine_for(&"crop").new(doc).resize_to(size, anchor)


## Image > Image Size. Reconfigured on every open for the same reason the
## sibling above is.
func open_image_size() -> void:
    if _image_size_dialog == null:
        _image_size_dialog = SaImageSizeDialog.new()
        add_child(_image_size_dialog)
        _image_size_dialog.resample_requested.connect(_on_image_size_confirmed)
    var doc := document()
    _image_size_dialog.configure(doc.canvas_size if doc != null else Vector2i(1920, 1080))
    _image_size_dialog.popup_centered()


## `SaResample` does the work and announces `document_resized`, which the canvas
## view already listens to, so there is no `resize_canvas` call here either.
func _on_image_size_confirmed(size: Vector2i, filter: int) -> void:
    var doc := document()
    if doc == null:
        return
    var pass_over: SaResample = _engine_for(&"resample").new(doc)
    pass_over.filter = filter
    pass_over.resample_to(size)


func _on_color_space_assigned(space: SaColorSpace) -> void:
    var doc := document()
    if doc != null:
        SaColorConversion.new(doc).assign(space)


func _on_color_space_converted(space: SaColorSpace) -> void:
    var doc := document()
    if doc != null:
        SaColorConversion.new(doc).convert_to(space)


## Asks about each recovery copy *autosave* found, one window at a time. Open
## loads the copy into the document as the original file with unsaved changes,
## Delete removes it, Later leaves it for the next launch. The question and its
## strings stand here rather than in the autosave, because a class under `core`
## asks a painter nothing. The arguments are in the order a signal's `bind` leaves
## them.
func offer_recoveries(pending: Array, autosave: SaAutosave) -> void:
    if pending.is_empty() or not is_instance_valid(autosave):
        return
    var entry: Dictionary = pending.pop_front()
    var copy: String = entry["copy"]
    var original: String = entry["original"]
    var what := original.get_file() if not original.is_empty() else tr("an unsaved document")
    SaMessage.confirm(
        self,
        tr("Recovered work"),
        tr("Sara kept a recovery copy of %s from a session that did not end properly:\n%s") % [what, copy],
        PackedStringArray([tr("Open", "open a document"), tr("Delete"), tr("Later")]),
        _on_recovery_answered.bind(entry, pending, autosave),
        2,
        0
    )


func _on_recovery_answered(index: int, entry: Dictionary, pending: Array, autosave: SaAutosave) -> void:
    if index == 0 and is_instance_valid(autosave):
        autosave.open_recovery(_canvas(), entry["copy"], entry["original"])
    elif index == 1:
        SaAutosave.delete_recovery(entry["copy"])
    offer_recoveries(pending, autosave)


## The engine registered under *role*: the skeleton's own unless a module
## registered a subclass over it, which is the whole reason the two resize
## handlers above ask rather than name a class.
func _engine_for(role: StringName) -> Script:
    return _registries.roles.script_for(role)


## The document these dialogs act on: whatever the main canvas is showing.
func document() -> SaDocument:
    var canvas := _canvas()
    return canvas.document if canvas != null else null


func _canvas() -> SaCanvas:
    return _canvas_provider.call() if _canvas_provider.is_valid() else null
