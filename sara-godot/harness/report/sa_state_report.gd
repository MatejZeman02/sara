## The state dump a capture writes beside its screenshots: the file, the writing,
## and the blocks it asks each part of the app for.
##
## **What this class owns is the report.** Where it is written, when it is
## written, and which blocks make it up. What is *in* a block is the business of
## whatever owns the numbers, and that is where the numbers are read:
## the canvas answers `capture_state`, the selection overlay and the
## adjust graph answer their own, every tool on the machine answers
## `capture_report`, and the dockers report themselves. What is left here is the
## assembly, plus the handful of blocks whose subject is the run rather than a
## node in it: the history, the document, the autosave, the windows and whatever
## the GUI thinks is under the pointer.
##
## A dump that named module classes, or preloaded a module script by path,
## would keep the skeleton from booting with `modules/` empty. The tools answer
## for themselves, which is hard rule 6 applied to a dump: a third-party tool puts
## a block in a capture the way a built-in does. The named seven are
## `NAMED_TOOL_BLOCKS`, and everything else goes under `tools`, so a tool the
## skeleton has never heard of reaches a capture too.
##
## Built with the runner and the directory it writes into, the way the harness's
## classes are built with their subject. Reached by path from `sa_capture.gd`, not by
## class name, so no editor rescan stands between a fresh checkout and a dump.
extends RefCounted

class_name SaStateReport

## Sections of the Info docker whose rows are the cumulative counters the
## top-level `gpu` block already carries, marked for `sara_findings.py`.
##
## The dump keeps them, because a scenario asked for the counters and reading
## them is the section's whole point. What the marker changes is the `no_change`
## comparison, which cannot say anything while a number that moves every frame
## sits inside it. Marked here rather than in `info_docker.gd`, so the docker
## goes on answering with what it shows and only the capture's own view of it
## carries a word about the harness.
const VOLATILE_INFO_SECTIONS: Array[String] = ["GPU"]
const CurveOptionCapture := preload("res://harness/captures/brush_editor_capture.gd")

## The run and the two drivers this is handed, typed by path, because as a
## `Node` and two `RefCounted` every read of them would be a read the parser
## could not check.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")
const LayersReport := preload("res://harness/report/sa_layers_report.gd")
const PointerAim := preload("res://harness/drivers/aim/sa_pointer_aim.gd")

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")

## The tool blocks this file reads a line of its own out of, in the order those
## lines stand in the dump.
##
## The list exists so the rest have somewhere to go. A tool answers
## [method ToolState.capture_report] with blocks under its own names, and a dump
## that took these seven and dropped everything else would keep a tool the
## skeleton has never heard of out of a capture however correctly it answered.
## Everything not named here goes under `tools`, whole.
##
## Named rather than derived from the dump's own keys, because the two kinds of
## collision are different: a tool answering `crop` is the line below asking for
## it, and a tool answering `history` is a tool that picked a name the run's own
## blocks already use, which belongs under `tools` rather than nowhere.
## `harness/report/tests/test_unnamed_tool_blocks.gd` fails when a line here is added or
## removed without this list following it.
const NAMED_TOOL_BLOCKS: Array[String] = [
    "crop",
    "transform",
    "brush_dynamics",
    "stroke_walk",
    "brush_migration",
    "brush_dabs",
    "brush_size_ramp",
]

## The run this reports on. Its fields are read, never written: `pointer_warp_works`
## says whether a pointer position means anything, `last_save` carries the timing
## of the last `save` step and `last_texel` the last `texel` step's answer. Its
## folder is where the file goes.
var _run: CaptureRun = null

## The canvas driver of the same run, read for one line of the dump and nothing
## else: how many times a mask it was watching has been rewritten.
##
## A constructor argument, because a driver is not a thing this class may go
## looking for, and null in a caller that has none, which is what the tests
## building a report by hand are.
var _canvas_driver: CanvasDriver = null


func _init(run: CaptureRun, canvas_driver: CanvasDriver = null) -> void:
    _run = run
    _canvas_driver = canvas_driver


## Writes the state dump: to `<out_dir>/<label>.json`.
##
## **Arguments.**
## - `state` string, the dump's name, and `"dump": true` beside it answers it.
func write(label: String) -> void:
    var target := _run.out_dir.path_join("%s.json" % label)
    var file := FileAccess.open(target, FileAccess.WRITE)
    if file == null:
        push_error("SaCapture: cannot write %s" % target)
        return
    file.store_string(JSON.stringify(state(), "  "))
    file.close()
    print("SaCapture: wrote %s" % ProjectSettings.globalize_path(target))


## Prints the layer stack: the `layers` step's verdict line, rather than this
## whole dump. This file is the package's face, so the step table reaches the
## layers report through here. Each layer carries its largest alpha, and
## `{"layers": {"alpha": false}}` leaves it out, the cheap listing a glance
## takes, because the reduction is felt in a stack of hundreds of layers.
func layers_line(ask: Variant = {}) -> String:
    var alpha: bool = not (ask is Dictionary and (ask as Dictionary).get("alpha", true) == false)
    return LayersReport.capture(_run.main_document(), alpha)


## Everything worth knowing about the run, as the dump writes it.
##
## Free of node state beyond the tree and the runner's own fields, so a test can
## assert on it. The tools' blocks are collected once above the dictionary rather
## than asked for inside it, so each key sits where it always sat: the order a
## dump is written in is what a reader diffing two runs walks down.
func state() -> Dictionary:
    var root: Window = _run.tree().root
    var canvas := CanvasDriver.main_canvas()
    var tools := _tool_blocks()
    var dump := {
        # Cumulative, so a scenario measures a stroke by taking a state either
        # side of it and subtracting. That needs no step of its own, and two
        # numbers from the same run are comparable in a way one number is not.
        "build": SaBuildInfo.read(),
        "gpu": SaCompute.counters(),
        # The last measuring window, empty until a `measure` step closes one.
        "perf": SaPerfWindow.last_block,
        # Every SaTexture alive, history included, which is the number a layer
        # schema cannot see.
        "vram_bytes": SaTexture.allocated_bytes,
        "history": _history_state(),
        "document": _document_state(),
        "documents": SaDocuments.state_in(_run.tree().current_scene),
        "modules":
        {
            "loaded": ModuleLoader.loaded_modules.keys().map(func(id: StringName) -> String: return String(id)),
            "failed": ModuleLoader.failed_modules.duplicate(),
            "off": ModuleLoader.off_modules.duplicate(),
            "user_root": ModuleLoader.user_modules_root,
        },
        "last_save": _run.last_save,
        # E2. The export a scenario asked for last, which the `save` step above
        # has and an export had no equivalent of until the sixteen-bit writer
        # needed one: a scenario proving a TIFF reached the disk asserts this
        # rather than reading the run log.
        "last_export": _run.last_export,
        # The last `texel` step's answer, a point's own value and the
        # canvas's composited one, so a scenario asserts a number rather than
        # a screenshot.
        "texel": _run.last_texel,
        "colors":
        {
            "foreground": SaColors.foreground.to_html(false),
            "background": SaColors.background.to_html(false),
            "recent": SaColors.recent.size(),
            "swatches": SaColors.swatches.size(),
        },
        "autosave": _autosave_state(),
        "display_server": DisplayServer.get_name(),
        "mouse_mode": _mouse_mode_name(Input.get_mouse_mode()),
        "pointer_screen": SaReportShapes.vec(Vector2(DisplayServer.mouse_get_position())),
        "pointer_warp_works": _run.pointer_warp_works,
        # The motions the door's last press heard and the warp's answers taken.
        "door_pointer": PointerAim.WarpAnswers.report(),
        "software_cursor_setting": SaSettings.software_cursor,
        # The version the welcome window's News pane last showed a painter,
        # which is what decides the sections it opens on next time. Two strings
        # a shot cannot carry, and a settings file the reader of a dump should
        # not have to go and open. They are read off the settings rather than
        # off the pane, because the pane is gone by the time a scenario has
        # closed the window and that close is the write.
        "news": {"running": SaBuildInfo.version(), "last_version_seen": SaSettings.last_version_seen},
        "welcome_layout": SaWelcomeWindow.layout_state(root),
        # The welcome window's recent cards, one row each. A shot shows a
        # card with a picture and cannot say whether the picture came out of the
        # file, out of the cache the document was read back into, or nowhere at
        # all, which are three different states of the same card. The grid
        # reports itself.
        "recent": WelcomeRecentGrid.capture_state(root),
        "manual": SaManualWindow.capture_state(root),
        "modules_window": SaModulesWindow.capture_state(root),
        "embed_subwindows": SaSettings.embed_subwindows,
        "sa_ui_scale": SaUI.scale(),
        "sa_ui_user_scale": SaUI.user_scale,
        "screen_scale": DisplayServer.screen_get_scale(),
        "screen_dpi": DisplayServer.screen_get_dpi(),
        "screen_size": SaReportShapes.vec(Vector2(DisplayServer.screen_get_size())),
        "root_content_scale_factor": root.content_scale_factor,
        "root_window_size": SaReportShapes.vec(Vector2(DisplayServer.window_get_size())),
        "main_window": TopMenuBar.capture_main_window(root),
        "root_viewport_rect": SaReportShapes.vec(root.get_visible_rect().size),
        "hovered_control": _hovered_path(root),
        # Which control has the keyboard, which is the only thing that says
        # whether Tab reached anything. A screenshot cannot show it.
        "focused_control": _focused_path(root),
        # Which choice lists are open, as the choice button reports them.
        "choice_lists_open": SaChoiceButton.open_lists(root),
        # Where the ring is actually drawn, which is not the OS pointer while a
        # gesture has pinned it.
        "cursor_overlays": CursorOverlay.state_of(root),
        "pen_source": SaPenSource.capture_state(),
        "canvases": SaCanvas.capture_state_all(),
        # The layers docker's rows, so a scenario can press one with the mouse
        # and read what the press did. A row that took no press and an eye
        # that did not toggle are the same picture.
        "layers_docker": _layers_docker_state(root),
        # A screenshot says the grid is there and cannot say it kept one
        # screen pixel, which is a number about the step and the zoom.
        "grid_overlay": SaGridOverlay.capture_state(root),
        # The slider's own value against the view's angle is the only way to
        # say the bar and the canvas agree, and a picture cannot say it.
        "top_bar_rotation": TopMenuBar.capture_rotation(root),
        # The first row's children with their rects, which is what says *which*
        # control overruns rather than only by how much.
        "top_bar_rows": TopMenuBar.capture_rows(root),
        # Which edge the three window buttons sit on, in what order, and
        # whether each is a macOS traffic light or an icon. Twelve pixels of a
        # 1920 wide shot, so the order and the colours are numbers here.
        "window_buttons": TopMenuBar.capture_window_buttons(root),
        # The fit dialog reports itself, because whether two rows share a
        # left edge is a number rather than something to read off a screenshot.
        "import_fit_dialog": SaImportFitDialog.capture_state(root),
        # What the curve option control shows beside what the option holds.
        # A graph in a PNG cannot be read back to four control points, and the
        # bug the control invites is exactly the two disagreeing.
        "curve_option": _curve_option_state(),
        # The minimap's mirror buttons, because a flip is a view property that
        # only a screenshot would otherwise show.
        "minimap": _minimap_state(root),
        # The Info docker's sections and the rows in them, because which sections
        # a panel has and what its colour rows say are both small grey numbers
        # in a PNG.
        "info_docker": _info_docker_state(root),
        # The same pair as numbers rather than as the strings the docker
        # draws. The stops row is a claim about arithmetic, and a scenario that
        # has to parse "+3.00" out of a label is checking the format string.
        "selected_colours": InfoDocker.capture_selected_colours(),
        # Which shape the colour picker is in and what its two cursors read.
        # A screenshot shows a triangle without naming it, and the list
        # of shapes on offer is not in the picture at all.
        "color_picker": ColorDocker.capture_state(root),
        # Which named layouts are offered, which is in use, and the three
        # things a preset holds that a screenshot of the Layouts submenu cannot
        # show at all: the UI scale and every hidden and reordered element.
        # The resize grip is drawn on top of whatever the content put in
        # the corner, and a press there resizes the window instead. Which
        # control is under it is a rect against a rect rather than anything a
        # screenshot of a 24 unit square could settle.
        "docker_grips": SaDockerWindowCapture.capture_grip_state(root),
        "docker_layout": MainDockers.capture_layout_state(root),
        # The dialogs on screen bottom to top with where each sits, which
        # says a second one opened cascaded off the first and above it.
        "open_dialogs": SaDialogWindow.capture_open(root),
        # The dialog's white point row is read-only, so a picture cannot say
        # whether it followed the gamut or was written once and left.
        "new_document": NewDocumentDialog.capture_state(root),
        # The dialog reports itself, because the depth row's mark is a few texels in a shot and
        # the note under it is what the file will be written with, so the depth,
        # the row's own label and the sentence are read as text rather than off a
        # picture of a dropdown.
        "export_dialog": SaExportDialog.capture_state(root),
        # The Tool Options docker's rows, the text on each and the text behind
        # it. What a row says is not a number it holds, and a tooltip is
        # invisible in a screenshot.
        "tool_options": ToolOptionsDocker.capture_state(root),
        # The active layer's simulation, its count, whether it plays, and
        # what its panel in Tool Options shows, read as text and not off a shot.
        "simulation": SaSimulationPanel.capture_state(root),
        # The docker's check, the Preferences row's check and the setting
        # both write, so a scenario reads the two controls as one switch. A
        # check that is not built reads null, because a closed Preferences
        # window is not a check that is off. Read by the walker.
        "advanced_checks":
        {
            "setting": SaSettings.advanced_options,
            "docker_check": ControlWalker.read(root, ToolOptionsHeader.CHECK_NAME),
            "preferences_check": ControlWalker.read(root, "AdvancedOptionsCheck"),
        },
        # The Exposure docker's three stops fields and the homes they
        # write, null for a field not built, so a scenario reads a typed
        # number in both places.
        "exposure_docker":
        {
            "view": ControlWalker.read(root, "ExposureViewSlider"),
            "paint": ControlWalker.read(root, "ExposurePaintSlider"),
            "paint_refused": ControlWalker.read(root, "ExposurePaintRefusal"),
            "layer": ControlWalker.read(root, "ExposureLayerSlider"),
            "view_setting": SaSettings.display_exposure_stops,
            "paint_pair": SaColors.exposure_stops,
        },
        # Which row the bar's own switches are on and what the row is
        # spending, because a row that scrolls photographs as a row that fits.
        "tool_options_bar": ToolOptionsBar.capture_state(root),
        # The rectangle the crop tool would commit and the shape it is
        # locked to. The overlay draws a dimmed box, and whether that box is
        # exactly 16:9 is arithmetic rather than something to read off a PNG.
        "crop": tools.get("crop", {}),
        # The box the transform tool would act on. A screenshot shows a
        # white rectangle without saying whether it came from the selection or
        # from the layer's chunks, and an empty box and a dropped one look the
        # same in a picture.
        "transform": tools.get("transform", {}),
        # The Colour Themes page's rows, because folding twenty-one swatches
        # into twelve means only numbers say which colour landed in which row.
        "color_theme": SaColorThemesPage.capture_state(root),
        # Which categories the search left showing, out of how many, and
        # which row it marked. A picture of a narrowed list cannot say what it
        # was narrowed from, and a focus ring is not in a screenshot at all.
        "preferences_search": SaSettingsSearch.capture_state(root),
        # The open Preferences page's own rows, section by title by value,
        # the record a page conversion later has to match row for row.
        "preferences_page": SaSettingsRowReport.capture_state(root),
        # The two shapes each of the gamut drawings holds, and how far
        # apart they are. Two nested wireframes and one wireframe drawn twice
        # are the same picture, so only the numbers tell them apart.
        "color_space_browser": SaColorSpaceBrowser.capture_front_state(root),
        # The View transform dropdown's rows and the sentence on each. The
        # page reports itself, the way the minimap and the Colour Themes page do.
        "display_page": SaDisplayPage.capture_state(root),
        # What the Brush Presets page says an import brought in and refused.
        # A count and a list of sentences, which is what the page exists to show
        # and what a screenshot of a scrolled list cannot be read back from.
        "brush_presets_page": SaBrushPresetsPage.capture_state(root),
        # Every bundle the library holds, ticked or not, and its presets,
        # since a menu's ticks and the names under each are not in a picture.
        "preset_bundles": SaBrushPresetBundles.capture_state(root),
        # The Canvas Size dialog's two numbers and which anchor cell is
        # down, because nine dark squares in a screenshot do not say which.
        "canvas_size": SaCanvasSizeDialog.capture_state(root),
        # The dialog reports its three buttons' rects against its own, and a row half off the bottom edge and a row whole
        # differ by a few dozen texels in a picture.
        "color_space_dialog": ColorSpaceDialog.capture_state(root),
        "color_space_picker_dialog": SaColorSpaceRow.capture_dialog(root),
        # Every declared page on screen, saying what it is: its sections,
        # its rows, each row's label, kind, value, bound target and whether it
        # reads as live. A page that cannot say what it is is the thing the
        # declarative layer exists to stop.
        "pages": SaPage.capture_state(root),
        # Every choice list that is open, with the row that is marked and
        # the row the pointer is on. The whole of that row is that the two are
        # different questions, and a screenshot of a highlighted row cannot say
        # which of the two it is showing.
        "choice_lists": _choice_lists(root),
        # The dynamics vocabulary, as the running app sees it. Nothing reads
        # a sensor yet, so this is the one thing a capture can say about the new
        # files that the suite cannot: they load in the real process, under the
        # real module loader, and answer.
        "brush_dynamics": tools.get("brush_dynamics", {}),
        # How many dabs the last stroke actually painted, and how far it
        # travelled to paint them. The one number that says the spacing walk
        # works, and a screenshot of a solid bar cannot say it: two spacings
        # five times apart both draw a solid bar and differ only in the count.
        "stroke_walk": tools.get("stroke_walk", {}),
        # What the migration makes of each shipped preset, and how far the
        # migrated curve is from the response the old exponent gave. A number a
        # test can also compute, in a place a reader can compare two runs at.
        "brush_migration": tools.get("brush_migration", {}),
        # The last dabs the evaluator answered with, the sample they were
        # read from and which options were in play. The dynamics half has no
        # picture of its own, so a stroke that came out wrong is a number a
        # screenshot cannot name.
        "brush_dabs": tools.get("brush_dabs", {}),
        # The diameter along a ramp with size by pressure on, which no
        # capture step can switch on for a real stroke because the bar's boolean
        # rows have no door yet (f16).
        "brush_size_ramp": tools.get("brush_size_ramp", {}),
        # The grey graph under the Adjust dialog's sliders, which reports
        # itself the way the Display page and the toolbox do. A picture of a
        # histogram is a poor way to grade "the graph followed the slider", so
        # the widget answers with its bins.
        "adjust_graph": _adjust_graph_state(root),
        # What the marching ants are being drawn from. The dash lengths are
        # measured off the shot beside this, because reading them back off the
        # frame is the readback hard rule 1 forbids.
        "selection_overlay": canvas.selection_overlay_report() if canvas != null else {},
        # How many times the mask has been rewritten since the run's first
        # selection step. The overlay above says which chunks are covered and
        # where the two boxes are, and a feather, a border and an invert can
        # all leave every one of those where it was, so without this line a
        # step that rewrote the whole mask would read as a step that did nothing
        # and `sara_findings.py` would raise a `no_change` on it.
        "selection_changes": _canvas_driver.selection_changes if _canvas_driver != null else 0,
        # Which way round the toolbox laid itself out, and where each button
        # landed. A shot of a wide docker and a shot of a tall one differ in more
        # than the grid, so the claim is graded on the rects rather than the eye.
        "toolbox": ToolBoxDocker.capture_state(root),
        # The rows of whatever menu is open, because a screenshot of a menu is
        # pixels and a row whose label is the empty string draws nothing.
        "open_menus": _open_menu_state(root),
        # Where the last pointer step aimed, in the main window's logical
        # units, so a menu's `at` above reads against the press.
        "pointer_aimed": [snappedf(_run.last_pointer.x, 0.01), snappedf(_run.last_pointer.y, 0.01)],
        # The short lived notice, because a message that takes itself away is
        # gone from any shot taken after it, and what it said matters as much
        # as whether it appeared.
        "notice": SaMessage.notice_state(),
        # The message window's text, whether it can be selected, and whether
        # the clipboard holds it. The dialog reports itself, the way the toolbox
        # and the Display page do.
        "message": SaMessage.message_state(),
        # The reference picture, the view over it and the colour last
        # taken off it. The docker reports itself, the way the Display page and
        # the Minimap do, and none of the three numbers a sample produces is in
        # a screenshot.
        "reference": ReferenceDocker.capture_state(root),
        # The undo stack's rows, which one is marked and what each says.
        # A picture of this docker is a column of words and a pressed state, so
        # a claim about where the stack is standing is graded on the words.
        "undo_docker": UndoDocker.capture_state(root),
        # The pop-up palette's switch, where its ring's cells and
        # wheel are, and what each cell reads, so a scenario presses them.
        "palette_docker": PaletteDocker.capture_state(root),
        # Every toggle button on screen, whether it is down, and whether it
        # carries a pressed box of its own. A screenshot says what a toggle looks
        # like and only this says whether the door was walked through.
        "toggles": SaToggleReport.of(root),
        # Where the Oklab cloud is being looked at from. A picture of a
        # turned cloud and a picture of an unturned one are two pictures, and
        # only the numbers say which is which.
        "graph_view": GraphDocker.capture_state(root),
        "windows": _window_state(root),
    }
    # Every block the tools answered that no line above asks for, under the
    # names the tools gave them. Last, so the seven named lines keep the places
    # a reader diffing two runs walks down, which is what naming them is for.
    dump["tools"] = _unnamed_tool_blocks(tools)
    dump.merge(input_source_blocks(SaInputSourceRegistry.in_app()))
    return dump


## Each input source's own block under its id, the `midi`
## block the MIDI source answers the first, asked of *sources* so no source is
## named here. Last in the dump since the sources are what registered, and a
## block keeps its key, so `midi.listening` reads as it did. Empty where no app
## holds a registry, as in a suite, and a block never overwrites a named line.
static func input_source_blocks(sources: SaInputSourceRegistry) -> Dictionary:
    return sources.capture_states() if sources != null else {}


## The tool blocks no line of the dump names, out of every block *tools* holds.
##
## The Info docker's own sections, with the counters `VOLATILE_INFO_SECTIONS`
## names marked for the comparison that cannot read them.
static func _info_docker_state(root: Window) -> Array:
    var sections := InfoDocker.capture_state(root)
    for entry: Variant in sections:
        var section := entry as Dictionary
        if section != null and VOLATILE_INFO_SECTIONS.has(String(section.get("section", ""))):
            section["volatile"] = true
    return sections


## The other half of the door a tool answers for itself through. Hard rule 6
## says a third-party tool does that the way a built-in does, so the dump takes
## every block a tool answers rather than a list of the blocks it wants by name,
## under which a block with any other key, a patch tool's `patch` or a module
## nobody here has heard of, would be collected and thrown away.
##
## The order is the machine's registration order, because that is the order
## [method _tool_blocks] merged them in, so two runs of the same scenario walk
## down the same list.
static func _unnamed_tool_blocks(tools: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for block_name: Variant in tools:
        if not NAMED_TOOL_BLOCKS.has(String(block_name)):
            out[String(block_name)] = tools[block_name]
    return out


## Every block the tools on the front document's canvas contribute, merged in
## the order the machine registered them.
##
## The door hard rule 6 asks for: a tool answers [method ToolState.capture_report]
## and its blocks land in the dump, so the crop rectangle, the transform quad and
## the brush's five blocks arrive without this file naming a module class or
## preloading a module path, where reading them off the active tool by method
## name from here would mean preloading the stamp brush's settings script by its
## path under the modules directory.
##
## Every registered tool is asked, not only the active one, because three of the
## brush's blocks are arithmetic over its own resource and are in every dump. The
## tool is told whether it is the active one, so the two blocks that describe a
## stroke in progress can be empty when there is none.
func _tool_blocks() -> Dictionary:
    var canvas := CanvasDriver.main_canvas()
    return _blocks_of(canvas.tool_machine() if canvas != null else null)


## The same, given the machine rather than the window it hangs under, so a suite
## can register a tool the skeleton has never heard of and read what a dump would
## carry without building a canvas.
static func _blocks_of(machine: ToolMachine) -> Dictionary:
    var out: Dictionary = {}
    if machine == null:
        return out
    for tool_name: StringName in machine.registered_tools:
        var tool_state: ToolState = machine.registered_tools[tool_name]
        if tool_state == null:
            continue
        out.merge(tool_state.capture_report(tool_name, tool_state == machine.active_tool))
    return out


## The Adjust dialog's value graph, reporting itself, empty when the dialog is not
## up. Found by class rather than by path, because the dialog is an embedded
## subwindow and `get_children()` on the root never mentions one. The graph
## on screen wins over a hidden one, since the Filter dialog and an attached
## record's edit window each keep a graph and only one is up.
func _adjust_graph_state(root: Window) -> Dictionary:
    var hidden: Dictionary = {}
    for child in root.get_children():
        for graph: Node in (child as Node).find_children("ValueGraph", "", true, false) if child is Node else []:
            if not graph.has_method("capture_state"):
                continue
            var answer: Dictionary = graph.call("capture_state")
            if bool(answer.get("showing", false)):
                return answer
            if hidden.is_empty():
                hidden = answer
    return hidden


## The minimap docker's flip buttons and which way round the map is. Empty when
## the docker is not built. `origin` is what a scenario adds to a button's rect
## to press it, exactly as the layers docker's is.
func _minimap_state(root: Window) -> Dictionary:
    var docker := CaptureRun.DockerLookup.window(root.get_tree(), DockerIds.MINIMAP) as MinimapDocker
    if docker == null:
        return {}
    var out := {"origin": SaReportShapes.vec(Vector2(docker.position) if docker.is_embedded() else Vector2.ZERO)}
    out.merge(docker.flip_report())
    return out


## What the undo history is holding, so a scenario can watch a budget bite, and
## where its cursor is, so a scenario can watch an undo. `steps` and
## `bytes` count snapshots and stay put when the cursor moves, so a successful undo moves no key of the
## dump but `version`. `version` is the cursor, `can_undo` and `can_redo` are the two ends of the walk.
func _history_state() -> Dictionary:
    var document: SaDocument = _run.main_document()
    if document == null or document.history == null:
        return {}
    var undo_redo: UndoRedo = document.undo_redo
    return {
        "steps": document.history.step_count(),
        "bytes": document.history.total_bytes(),
        # The budget as it stands, which follows the document. The floor
        # under it is beside it, so a dump says which of the two is biting.
        "budget_bytes": document.history.effective_budget(),
        "budget_floor_bytes": document.history.budget_bytes,
        "largest_step_bytes": document.history.largest_step_bytes,
        "dropped": document.history.dropped_steps,
        "version": int(undo_redo.get_version()) if undo_redo != null else 0,
        "can_undo": undo_redo != null and undo_redo.has_undo(),
        "can_redo": undo_redo != null and undo_redo.has_redo(),
        "last_step": undo_redo.get_current_action_name() if undo_redo != null else "",
    }


## Where the main document lives and whether it has unsaved work, which is what
## the quit prompt and the title bar read.
func _document_state() -> Dictionary:
    var document: SaDocument = _run.main_document()
    if document == null:
        return {}
    return {
        "path": document.file_path,
        "modified": document.modified,
        # What File > Open on a picture leaves behind is a layer count, and
        # the layers docker's own rows are the thing being checked rather than
        # the thing to check with.
        "layers": SaLayerOps.new(document).layers().size(),
        # Each drawn layer by its name and what its recipe says of itself, a
        # text layer's words, lines and fonts, so a layout is checked without
        # a picture.
        "drawn": _drawn_state(document),
        "canvas_size": SaReportShapes.vec(Vector2(document.canvas_size)),
        "projection": document.projection.to_header(),
        # The infinite canvas's switch, its grows, and the document point under
        # the pointer, which a scenario reads before and after a grow at the
        # top to say the picture did not jump.
        "infinite_canvas": _infinite_canvas_state(document),
        "relief_light": document.relief_light.to_header(),
        # F16 or F32, the word the `.sad` header writes, which is how a
        # scenario reads what Image > Depth converted the document to.
        "depth": str(document.color_space.to_header().get("depth", "F32")) if document.color_space != null else "F32",
        # The selection tools' Feather, as it is stored and as this document
        # spends it. A PNG of a soft edge cannot be measured, and the
        # whole claim is that the second number follows the canvas while the
        # first one does not.
        "selection_feather":
        {
            "fraction": SaSettings.selection_feather,
            "pixels": SaSelectionFilters.feather_radius(SaSettings.selection_feather, document.brush_side),
        },
    }


## Every drawn layer of *document*, bottom first, with its type and its
## recipe's own report.
func _drawn_state(document: SaDocument) -> Array:
    var out: Array = []
    for layer: SaLayer in SaLayerOps.new(document).layers():
        if layer.recipe != null:
            var entry := {"name": layer.shown_name(), "type": String(layer.layer_type)}
            entry.merge(layer.recipe.report())
            out.append(entry)
    return out


## The infinite canvas's switch and grows on *document*, and the point of it
## under the pointer, as the tools read it, on the canvas in front.
func _infinite_canvas_state(document: SaDocument) -> Dictionary:
    var canvas := SaCanvasView.front_canvas()
    var under := SaCanvasView.for_canvas(canvas).get_document_mouse_position() if canvas != null else Vector2.ZERO
    return {
        "on": document.infinite_canvas.on, "grows": document.infinite_canvas.grows, "pointer_document": SaReportShapes.vec(under)
    }


## What the autosave has written this session, read off main's node.
func _autosave_state() -> Dictionary:
    var main_node := _run.tree().current_scene
    if main_node == null or not ("autosave" in main_node) or main_node.autosave == null:
        return {}
    var report := {"last_written": main_node.autosave.last_written, "interval_minutes": SaSettings.autosave_interval_minutes}
    return report.merged(WelcomeRecoveryRow.capture_state(_run.tree().root, main_node.autosave))


## What the GUI thinks is under the pointer, which is how a routing failure is
## told apart from an injection that never reached the GUI at all.
## The curve option control on screen, or an empty dictionary when none is.
##
## Empty rather than absent, so a scenario that expects one and finds none reads
## a key it can assert on rather than a missing one it has to guess about.
func _curve_option_state() -> Dictionary:
    var control := CurveOptionCapture.live_control(_run.tree())
    return control.call("option_report") if control != null else {}


static func _hovered_path(root: Window) -> String:
    var hovered := root.gui_get_hovered_control()
    return String(hovered.get_path()) if hovered != null else "<none>"


## What has the keyboard in *root*. A dialog driven by Tab is unphotographable
## otherwise: the focus ring is a theme detail and the pointer is elsewhere.
static func _focused_path(root: Window) -> String:
    var focused := root.gui_get_focus_owner()
    return String(focused.get_path()) if focused != null else "<none>"


## The layers docker: where it sits, and what each of its rows is. The rects the
## list reports are in the docker's own window, and `origin` is what a scenario
## adds to reach them from the root, which is the sum a routed press has to make.
func _layers_docker_state(root: Window) -> Dictionary:
    var docker := CaptureRun.DockerLookup.window(root.get_tree(), DockerIds.LAYERS)
    if docker == null or not ("item_list" in docker):
        return {}
    var list := docker.get("item_list") as SaLayerList
    var window := docker as Window
    if list == null or window == null:
        return {}
    var out := {
        "origin": SaReportShapes.vec(Vector2(window.position) if window.is_embedded() else Vector2.ZERO),
        "dragging": list.dragging,
        "drop_row": list.drop_row,
        "rows": list.row_report(),
        "blend_label": _blend_label_text(docker),
        "tooth": {"shown": docker.tooth_slider.is_visible_in_tree(), "value": docker.tooth_slider.value},
    }
    out.merge(_corner_state(docker))
    return out


## What the Layers docker's blend row says, which is the dropdown's own label,
## with no "Blend:" in front of it.
##
## The "Layer" in front of the dropdown says whose mode it is, not which, so the
## dropdown is what the row says and a label is read only in a row without one.
static func _blend_label_text(docker: Node) -> String:
    var box := docker.find_child("BlendBox", true, false)
    if box == null:
        return ""
    for child in box.get_children():
        # The dropdown first, and asked by method rather than by cast, for the
        # reason `_color_theme_state` gives: a cast to a `class_name` in a
        # static function leaks the script. A `BlendModeButton` carries the
        # mode's own display name as its `text`, which is the whole of what the
        # row says.
        if child.has_method("select_mode"):
            return String(child.get("text"))
    for child in box.get_children():
        var label := child as Label
        if label != null:
            return label.text
    return ""


## The More button against the resize grip, both in the docker's own window.
## The two can overlap at the docker's smallest width, so the dump reports
## the rects and the answer rather than leaving it to a reader of the PNG.
func _corner_state(docker: Node) -> Dictionary:
    var actions := docker.get("actions") as Control
    var resizer := docker.get("resizer") as Control
    if actions == null or resizer == null:
        return {}
    var more := actions.get("more_btn") as Control
    if more == null:
        return {}
    var more_rect := more.get_global_rect()
    var grip_rect := resizer.get_global_rect()
    return {
        "more_button": SaReportShapes.rect(more_rect),
        "resizer": SaReportShapes.rect(grip_rect),
        "more_over_resizer": resizer.visible and more.visible and more_rect.intersects(grip_rect),
        "actions_row": actions.call("button_report"),
    }


## Every menu open at the moment of the dump, with the label and the chord of
## each of its rows. A `PopupMenu` is an internal child of whoever owns it, so
## the walk has to ask for internal children or it finds no menu at all.
static func _open_menu_state(root: Window) -> Array:
    var out: Array = []
    for menu: PopupMenu in _popup_menus(root):
        if not menu.visible:
            continue
        var rows: Array = []
        for i in menu.item_count:
            var accel := ""
            var shortcut := menu.get_item_shortcut(i)
            if shortcut != null:
                accel = shortcut.get_as_text()
            (
                rows
                . append(
                    {
                        "text": menu.get_item_text(i),
                        "accel": accel,
                        "checked": menu.is_item_checked(i),
                        "radio": menu.is_item_radio_checkable(i),
                        "separator": menu.is_item_separator(i),
                        # A dimmed row is a disabled one, a standing rule of
                        # the interface, and a dump has to say which is
                        # which: a filter whose kernel did not compile keeps its
                        # entry and is greyed rather than dropped.
                        "disabled": menu.is_item_disabled(i),
                        # A row's own sentence, so "every row explains itself"
                        # is a claim a dump can answer. One key rather
                        # than a block of its own, so a row keeps its shape.
                        "tooltip": menu.get_item_tooltip(i),
                    }
                )
            )
        # `radio` is what a one-of row is read from: no row draws a dot. No
        # `selected` key, because a `PopupMenu` left in the tree by a module has
        # no one-of group of Sara's to answer for.
        (
            out
            . append(
                {
                    "name": String(menu.name),
                    "selected": -1,
                    "focused": menu.get_focused_item(),
                    # Its top-left in the main window's logical coordinates,
                    # where a scenario aims the press that opened it.
                    "at": _corner(menu),
                    "rows": rows,
                }
            )
        )
    out.append_array(_open_choice_menus(root))
    return out


## The bar's own menus, which are `SaChoicePopup`s and therefore not
## `PopupMenu`s the walk above can find.
##
## Reported into `open_menus` beside them rather than left to `choice_lists`,
## because every scenario and suite that asks what a menu is showing asks that
## key, and a row's shape is kept: `text`, `accel`, `checked` and `disabled`
## are what those readers name, whatever the control underneath is now. The
## popup's own `row_report` is carried whole under `rows_report`, so a reader
## that wants the icon, the mark or the highlight has them without this file
## having to keep a second list of what a row can say.
static func _open_choice_menus(root: Window) -> Array:
    var out: Array = []
    for node in root.find_children("*", "SaChoicePopup", true, false):
        var popup := node as SaChoicePopup
        if popup == null or not popup.visible:
            continue
        var rows: Array = []
        for entry: Dictionary in popup.row_report():
            (
                rows
                . append(
                    {
                        "text": String(entry.get("label", "")),
                        "accel": String(entry.get("hint", "")),
                        "checked": bool(entry.get("checked", false)),
                        "radio": false,
                        "separator": false,
                        "disabled": bool(entry.get("disabled", false)),
                        "tooltip": _row_tooltip(popup, StringName(entry.get("id", ""))),
                    }
                )
            )
        (
            out
            . append(
                {
                    "name": String(popup.name),
                    "at": _corner(popup),
                    "selected": popup.row_ids().find(popup.current),
                    "focused": popup.row_ids().find(popup.highlighted()),
                    "rows": rows,
                    "rows_report": popup.row_report(),
                    "sections": popup.section_titles(),
                    "search": popup.search.text,
                }
            )
        )
    return out


## A row's own sentence, which lives on its label button: the popup
## hands the button out and a tooltip is the button's own property.
static func _row_tooltip(popup: SaChoicePopup, row_id: StringName) -> String:
    var button := popup.label_button(row_id)
    return button.tooltip_text if button != null else ""


## *menu*'s top-left corner in the main window's logical coordinates.
static func _corner(menu: Window) -> Array:
    var at := SaPopupRect.in_main_window(menu)
    return [snappedf(at.x, 0.01), snappedf(at.y, 0.01)]


## Every `PopupMenu` under *node*, internal children included.
static func _popup_menus(node: Node) -> Array:
    var found: Array = []
    if node is PopupMenu:
        found.append(node)
    for child in node.get_children(true):
        found.append_array(_popup_menus(child))
    return found


## Every Window in the tree, with the two numbers that distinguish the embedded
## and OS-window scaling rules from each other.
func _window_state(root: Window) -> Array:
    var out: Array = []
    for window: Window in _run.all_windows(root):
        (
            out
            . append(
                {
                    "title": window.title,
                    "embedded": window.is_embedded(),
                    "visible": window.visible,
                    "position": SaReportShapes.vec(Vector2(window.position)),
                    "size": SaReportShapes.vec(Vector2(window.size)),
                    # The size the window is at is not the size it thinks it
                    # is, and the whole of that defect is the gap between them, so
                    # both are reported. Off any window that keeps one, and `size`
                    # for the root, which does not.
                    "logical_size": SaReportShapes.vec(Vector2(window.logical_size if "logical_size" in window else window.size)),
                    "min_size": SaReportShapes.vec(Vector2(window.min_size)),
                    "content_scale_factor": window.content_scale_factor,
                    "sa_window_scale": SaUI.window_scale(window),
                    "hovered": _hovered_path(window),
                    "focused": _focused_path(window),
                    "has_focus": window.has_focus(),
                    "mode": window.mode,
                }
            )
        )
    return out


static func _mouse_mode_name(mode: int) -> String:
    match mode:
        Input.MOUSE_MODE_VISIBLE:
            return "VISIBLE"
        Input.MOUSE_MODE_HIDDEN:
            return "HIDDEN"
        Input.MOUSE_MODE_CAPTURED:
            return "CAPTURED"
        Input.MOUSE_MODE_CONFINED:
            return "CONFINED"
        Input.MOUSE_MODE_CONFINED_HIDDEN:
            return "CONFINED_HIDDEN"
    return "UNKNOWN(%d)" % mode


## Every `SaChoicePopup` on screen, each reporting itself.
##
## Keyed by the control the list belongs to rather than by the list's own name,
## because two dropdowns both call theirs `ChoiceList` and the question a reader
## has is which control was open. Empty in a run where nothing is open, which is
## every dump but the ones taken with a choice list open.
static func _choice_lists(root: Window) -> Dictionary:
    var out: Dictionary = {}
    for node in root.find_children("*", "SaChoicePopup", true, false):
        var popup := node as SaChoicePopup
        if popup == null or not popup.visible:
            continue
        # A control's dropdown is filed under that control, because two of them
        # both call their list `ChoiceList` and the question a reader has is
        # which control is open. A popup that is a menu in its own right is
        # filed under itself: `ToolContextMenu` is a child of the main
        # node, and keying every popup on its parent would file it under `Main`.
        var owner_node := popup.get_parent()
        var key := String(owner_node.name) if owner_node is Button else String(popup.name)
        out[key] = {"one_of": popup.one_of, "current": String(popup.current), "rows": popup.row_report()}
    return out
