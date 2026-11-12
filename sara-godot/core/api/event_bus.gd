## Global signal dispatcher for cross-node communication.
##
## Acts as a central hub for decoupled components to communicate without
## direct references. Primarily handles rendering triggers and UI state updates.
##
## `@tool` because the editor instantiates the autoloads during a filesystem
## scan, and without it this one is a bare Node carrying a script path with none
## of its members resolved. Every @tool consumer that touched a signal on it then
## failed with "Invalid access to property or key", SaSettings._ready did,
## twice, on every `godot --headless --editor --quit`, which is the command
## to run after adding a class_name. Nothing here has side
## effects in the editor: the bus declares signals and does nothing else.
@tool
extends Node

## Emitted when the active tool changes in the ToolMachine.
@warning_ignore("unused_signal")
signal tool_changed(tool_name: String)

## The painter picked a tool as the permanent one: the toolbox, a chord, the
## Tools menu. Unlike [signal tool_changed] it fires when the tool picked is the
## one already in hand, and it does not fire for a tool held on a key, so a
## listener that means "the painter chose this" hears nothing else.
@warning_ignore("unused_signal")
signal tool_picked(tool_name: String)

## Emitted when a module finishes loading.
@warning_ignore("unused_signal")
signal module_loaded(module_name: String)

## The foreground colour changed: the picker, the eyedropper, a swap or a
## reset. Every tool that paints listens here, and `SaColors` keeps up.
@warning_ignore("unused_signal")
signal color_picked(color: Color)

## The background colour of the pair changed, by a swap, a reset or a pick
## into it. Nothing paints with it yet, and it exists so a tool that takes two
## colours does not need a second store when it arrives.
@warning_ignore("unused_signal")
signal background_color_changed(color: Color)

## Emitted when the temporary eraser toggle (E) is toggled on a brush.
@warning_ignore("unused_signal")
signal brush_eraser_toggled(active: bool)

## Emitted when the UI scale multiplier slider changes.
@warning_ignore("unused_signal")
signal ui_scale_changed(scale: float)

## Emitted when the Font size multiplier changes.
##
## Separate from ui_scale_changed on purpose: that one re-derives every window's
## geometry from its logical size, which snaps a docker back to the size its
## constructor gave it, and text is the only thing this one moves.
@warning_ignore("unused_signal")
signal ui_font_scale_changed(font_scale: float)

## Emitted when a docker window position or size changes (e.g. after dragging).
@warning_ignore("unused_signal")
signal docker_layout_changed

## Emitted when the user requests spawning a secondary host window (multi-monitor workspace).
@warning_ignore("unused_signal")
signal secondary_workspace_requested

## Emitted when the user requests reparenting a docker to a specific workspace host.
@warning_ignore("unused_signal")
signal docker_reparent_requested(docker_name: String, target_host: Node)

## Emitted when the user requests opening the preferences/settings window.
@warning_ignore("unused_signal")
signal preferences_requested

## Emitted when the user asks for a new document, before any size or colour space
## is chosen. Main owns the dialog, the same way it owns the settings window.
@warning_ignore("unused_signal")
signal new_document_requested

## Modules > New Module..., asked by the menu rather than the dialog so the
## request can also come from a chord or the door one day, the way the new
## document one does. The dialog writes the module and opens its folder. It
## needs no canvas or document, so it does that itself rather than asking Main.
@warning_ignore("unused_signal")
signal new_module_requested

## ALT and a double click on a docker's drag handle, which opens Preferences on
## that docker's own page. It carries the page title because the page is not
## known where the gesture is made: the handle asks the docker it belongs to for
## its settings category and reads the title back off `SaSettings`, so a docker a
## module registered at runtime reaches its own page without a signal of its own.
##
## That is why this is not `display_page_requested` a second time and not a page
## argument on `preferences_requested`, which is a toggle carrying nothing.
@warning_ignore("unused_signal")
signal settings_page_requested(page_title: String)

## A door that knows which row it is for, which opens Preferences on that page
## scrolled to the row and marked the way a search marks one. Help >
## Display Settings... is the one sender: it names the monitor's profile, row
## 13 of 18 on its page, which a painter would otherwise scroll to.
##
## Beside `settings_page_requested` rather than a second argument on it, because
## the docker handle's gesture knows its page and no row of it, and a signal
## whose every emitter passes an empty row says nothing a reader can use.
@warning_ignore("unused_signal")
signal settings_row_requested(page_title: String, row_key: StringName)

## View > Exposure Stops..., which opens Preferences on the Display page where
## the stops slider lives. Its own signal rather than a page argument on
## `preferences_requested`, the way Help > Keyboard Shortcuts already has one:
## the plain request is a toggle and carries nothing, and a menu row that names
## a page is the second caller of that shape rather than a reason to change the
## first.
@warning_ignore("unused_signal")
signal display_page_requested

## View > Relief Light..., the small window that moves the open document's own
## light on its impasto. `MainDialogs` owns the window, since a menu holds no
## document.
@warning_ignore("unused_signal")
signal relief_light_requested

## The welcome window, asked for from Help. `MainDialogs` owns the window. The
## boot builds the one it shows before `MainDialogs` exists and hands it over,
## so this is Help's door alone.
@warning_ignore("unused_signal")
signal welcome_requested

## Help > Manual, the painter's manual in a window of Sara's own.
## `MainDialogs` owns the window.
@warning_ignore("unused_signal")
signal manual_requested

## The Modules window turned to *module_id*'s page, the first module's when it
## is empty. A module's row in Modules > Active Modules asks it, and
## `MainDialogs` owns the window.
@warning_ignore("unused_signal")
signal module_page_requested(module_id: StringName)

## Help > Colour Spaces, the colour space browser in a window of its own.
## `MainDialogs` owns the window.
@warning_ignore("unused_signal")
signal color_spaces_requested

## Modules > Local Server pressed: the door opened, or closed when it listens.
## `Main` answers through the capture harness, which core never names.
@warning_ignore("unused_signal")
signal local_server_requested

## Sara is whole: the last stage of `Main`'s boot has run, the modules are
## registered and the layout is restored. A recent document chosen on the
## welcome window before this opens on it, and the capture harness, the door
## and every suite that builds a `Main` wait on it rather than on `_ready`
## returning, which is the first stage and not the boot.
@warning_ignore("unused_signal")
signal boot_finished

## Help > About, and Help > Keyboard Shortcuts. Main owns both dialogs.
@warning_ignore("unused_signal")
signal about_requested
@warning_ignore("unused_signal")
signal shortcuts_requested

## A chord was rebound or a shortcut profile switched. Every surface that
## prints a chord has to say it again: the menus follow the command registry,
## the toolbox tooltips follow this.
@warning_ignore("unused_signal")
signal shortcuts_changed

## Emitted when the user asks to assign or convert the document's colour space.
## Main owns the dialog, the same way it owns the settings window.
@warning_ignore("unused_signal")
signal color_space_requested

## Image > Projection..., which Main opens as it does Colour Space's.
@warning_ignore("unused_signal")
signal projection_requested

## Image > Canvas Size: open the dialog that grows or trims the document
## about an anchor. Main owns the dialog, as it does the colour space one.
@warning_ignore("unused_signal")
signal canvas_size_requested

## Image > Image Size, asking for the dialog that scales the picture. Main owns
## the dialog, as it does Canvas Size's.
@warning_ignore("unused_signal")
signal image_size_requested

## File > Quit: the menu row asking for the way out the chord already takes.
## Main owns quitting, because it is the only node that knows whether a
## recovery copy has done its job, so the row asks rather than quits.
@warning_ignore("unused_signal")
signal quit_requested

## Preferences > Tablet asks for the sweep calibration dialog. A signal
## rather than a call, because the page is built inside Preferences and the
## dialog is Main's.
@warning_ignore("unused_signal")
signal tablet_sweep_requested

## The highlight tonemapper was switched on or off. A view mode: it changes what
## the canvas shows and never what it stores, so nothing outside render/ and ui/
## needs to hear it.
@warning_ignore("unused_signal")
signal tonemap_changed(enabled: bool)

## Preferences changed what Ctrl+Y proofs the canvas to. Carries the old id as
## well as the new one, because the only honest rule for a proof already on the
## screen is to move it when it is showing exactly the mode that changed, and
## to leave a canvas showing something else alone.
@warning_ignore("unused_signal")
signal canvas_proof_mode_changed(previous: StringName, current: StringName)

## A document finished loading from disk, with every layer and chunk in place.
##
## What a `.sad` records about a layer type is its id, never the Callable that
## resolves it, so a freshly loaded layer has its fields and nothing to recompute
## the derived ones with. Whoever holds the layer type registry listens here and
## rebinds. A signal rather than a parameter threaded through `load_sad`, because
## the call site is a file dialog in a menu and the registry lives in main: this
## is exactly the seam an event bus is for.
@warning_ignore("unused_signal")
signal document_loaded(document: SaDocument)

## A document's colour space is now something else: File > New, Image > Assign or
## Convert, or a file being opened.
##
## The payload is the document whose space changed, its new space on
## `document.color_space`. Sara runs more than one easel, the info docker's
## scratchpad and every open document, so a listener showing one document
## returns at once for any other, and a change behind a tab moves nothing in
## front.
##
## The blend mode dropdowns need it: plain Normal mixes in whatever the document
## stores, so its label carries the space, and a label that went stale on File > New
## would name the space of a document that no longer exists.
@warning_ignore("unused_signal")
signal document_color_space_changed(document: SaDocument)

## A document is a different size: a crop, and whatever else moves the canvas
## rectangle later.
##
## The payload names which document, because Sara runs more than one easel and
## the info docker's scratchpad owns its own. A view bound to that document
## resizes its output and rebinds, which is what `SaCanvas.resize_canvas` does
## for File > New and File > Open at their own call sites. Undo fires it too,
## so the view follows the size back.
@warning_ignore("unused_signal")
signal document_resized(document: SaDocument, size: Vector2i)

## Another surface is in front: the document the painter works on is now the
## one it holds, or none when the payload is null. `SaDocuments` sends it once
## per change, after the outgoing surface's tool session closed, so a listener
## that rebinds to the new front reads a document nothing is still writing.
@warning_ignore("unused_signal")
signal active_document_changed(surface: SaSurface)

## The interface palette changed, with the id of the one now active. A control
## that draws with SaTheme's colours redraws on it.
@warning_ignore("unused_signal")
signal theme_changed(theme_id: String)
## The interface font switched to the family with this id.
@warning_ignore("unused_signal")
signal ui_font_changed(font_id: String)
## A brush preset was loaded, by its stored name. The History docker records
## it. On the bus rather than a direct call, because the bar is built before
## the dockers and a preset may one day be loaded from a chord as well.
@warning_ignore("unused_signal")
signal preset_loaded(preset_name: String)

## The set of stored brush presets changed, by the name that was written or
## removed and which way.
##
## Without it a surface finds out only by asking again: the presets docker
## rebuilds its grid when it is shown, when the tool changes and when a preset
## is loaded, and would be a preset short between a save and the next of those,
## or keep a cell for a deleted preset that is no longer on disk.
##
## *saved* is false for a delete, so one connection covers both and a listener
## that only cares about one can say so. On the bus for the same reason
## [signal preset_loaded] is: the bar is built before the dockers.
@warning_ignore("unused_signal")
signal preset_store_changed(preset_name: String, saved: bool)

## A drawing tool turned an attempt away and nothing on the canvas changed,
## with the line the painter reads. A stroke refused on a locked layer is the
## first sender: without this the pen simply did nothing and the lock was
## invisible. On the bus rather than a call into the window, because a tool
## lives in a module and knows nothing about where a message is drawn.
@warning_ignore("unused_signal")
signal paint_refused(reason: String)

## Why the stroke just committed changed nothing, or an empty line once a
## stroke changes something again. `SaStrokeNote` says each cause once and the
## status line shows it.
@warning_ignore("unused_signal")
signal stroke_explained(line: String)

## How far a save running in the background has gone, or that it ended, and an
## empty line when there is nothing to say. `SaSadSave` sends it and the status
## line shows it.
@warning_ignore("unused_signal")
signal save_progressed(line: String)

## The lock on the system's mouse and pen was taken or let go, with who holds
## it, an empty string once it is free. `SaPointerLock` sends it and the status
## line shows it, so a painter is told why the mouse does nothing.
@warning_ignore("unused_signal")
signal pointer_lock_changed(locked: bool, by: String)

## Something did what was asked and the painter is told how it read the ask,
## in the corner the refusals use. Not a refusal, which is why it is not
## [signal paint_refused]: a listener that counts refusals, or a test that
## asserts a fill was refused, would read this one as a fault. The fill with
## nothing selected is the first sender, because it fills the whole layer and
## says so.
@warning_ignore("unused_signal")
signal corner_notice(line: String)

## The Advanced options check in Preferences moved, with what it is now. The
## Tool Options docker listens: `SaOptionSpec.advanced` decides whether a row
## is drawn, and the page and the docker have no reference to each other.
@warning_ignore("unused_signal")
signal advanced_options_changed(enabled: bool)

## A tool moved values its own option rows read, without either surface having
## written them.
##
## The Tool Options docker syncs on `tool_changed` and on a rebuild, so nothing
## told it the tool had moved under it. A transform handle drag left all six of
## its rows on the numbers they were built with for the whole gesture:
## `transform.offset` read (200, 100) beside a `Position X` of 0. The getters
## were right the whole time, and the announcement was what was missing.
##
## No argument, because the listener re-reads every row off the tool anyway and
## a key per moved value would be four signals for one drag.
##
## Also what the shift-drag over the canvas and the bracket keys emit when they
## move the brush size. They emitted `tool_changed`, which made every surface
## rebind per motion event, the presets docker rebuilding its grid each time,
## and a drag on a tablet pinned one core.
@warning_ignore("unused_signal")
signal tool_options_moved


## Nothing to build, and here for the boot mark alone, whose gap since the
## autoload before it is this script's own load.
func _init() -> void:
    SaBootMarks.mark(&"event_bus_init")
