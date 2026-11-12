## One step in, one call out.
##
## The whole of the executor's vocabulary, a hundred keys tried in order, and
## nothing else: no state of its own, no handler of its own, and no reason for
## a reader looking for what a step does to read past the line that says who
## does it.
##
## **Why the table is a class rather than a method on the runner.** As a
## method it would be the bulk of `sa_capture.gd`, and every new step kind would
## edit the file that owns the run loop. Here the loop and the vocabulary can be
## read apart, and the five drivers below hold the behaviour rather than taking
## the runner back in as a first argument.
##
## `scripts/sara_steps.py` parses this chain in order and is what a scenario
## writer reads. A branch's dispatch line has to stay one call, because that is
## what the catalogue follows to the handler's doc comment.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaStepTable
extends RefCounted

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const ScenarioStroke := preload("res://harness/scenario/sa_scenario_stroke.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const GestureDriver := preload("res://harness/drivers/sa_gesture_driver.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const CursorProbe := preload("res://harness/report/sa_cursor_probe.gd")
const StateReport := preload("res://harness/report/sa_state_report.gd")
const MenuDriver := preload("res://harness/drivers/menu/sa_menu_driver.gd")
const PreferencesDriver := preload("res://harness/drivers/sa_preferences_driver.gd")
const FilterDriver := preload("res://harness/drivers/sa_filter_driver.gd")
const DockerDriver := preload("res://harness/drivers/sa_docker_driver.gd")
const CurveOptionCapture := preload("res://harness/captures/brush_editor_capture.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const TexelProbe := preload("res://harness/report/sa_texel_probe.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const DoorErrors := preload("res://harness/report/sa_door_errors.gd")
const PenDragDriver := preload("res://harness/drivers/sa_pen_drag_driver.gd")
const ColorFind := preload("res://harness/sa_color_find.gd")
const DoorGlance := preload("res://harness/door/sa_door_glance.gd")
const HistoryMarks := preload("res://harness/sa_history_marks.gd")
const ScenarioUntil := preload("res://harness/scenario/sa_scenario_until.gd")
const BrushFieldDriver := preload("res://harness/sa_brush_field_driver.gd")

## The run every driver below is handed: the folder, the steps, the last
## pointer and what the last steps came to, with the tree asked of the engine.
##
## Not the runner itself, which would be typed `Node` because the runner
## preloads this file and a `class_name` on either side of that pair is a cycle
## the class cache resolves late. The run preloads neither, so it is typed
## by its preload like every driver here, and `sara_steps.py` follows it the way
## it follows them.
var _run: CaptureRun = null

var _input: InputDriver = null
var _stroke: ScenarioStroke = null
var _canvas: CanvasDriver = null
var _document: ScenarioDocument = null
var _cursor: CursorProbe = null
var _menus: MenuDriver = null
var _prefs: PreferencesDriver = null
var _filters: FilterDriver = null
var _dockers: DockerDriver = null
var _gestures: GestureDriver = null

## The `kernel` step's driver, held for the run so a source sent twice finds its
## compile.
var _kernels: KernelDriver = null

## The `state` step's report. Built here with the others, so the chain reads
## `_report.write(...)` and `scripts/sara_steps.py` finds a documented handler
## behind the key rather than a constructor.
var _report: StateReport = null

## The `texel` step's readback, held like the drivers rather than built per
## step by the runner with the runner handed in.
var _texel: TexelProbe = null

## The `read_pixels` and `write_pixels` steps' driver.
var _pixels: PixelDriver = null

## The `find` step's search.
var _find: ColorFind = null

## The `mark` and `rewind` steps' names, held for the run.
var _marks: HistoryMarks = null

## The `until` step's conditions.
var _until: ScenarioUntil = null


## The drivers, the probe and the report are built here rather than handed in,
## because there is exactly one of each per run and the table is the only thing
## that calls them. Every one takes the run and nothing else of the harness: the
## folder it writes into, the tree and the run's state are all members of it.
##
## The report is handed the canvas driver as well, because one line of the dump
## is that driver's own count of the selection rewrites it has watched go by.
## A constructor argument, because that is how a thing outside a class
## sets what the class then owns.
func _init(run_state: CaptureRun) -> void:
    _run = run_state
    _input = InputDriver.new(_run)
    _stroke = ScenarioStroke.new(_run, _input)
    _canvas = CanvasDriver.new(_run)
    _document = ScenarioDocument.new(_run)
    _cursor = CursorProbe.new(_run)
    _texel = TexelProbe.new(_run)
    _pixels = PixelDriver.new(_run)
    _find = ColorFind.new(_run)
    _marks = HistoryMarks.new(_run)
    _until = ScenarioUntil.new(_run)
    _report = StateReport.new(_run, _canvas)
    _menus = MenuDriver.new(_run)
    _prefs = PreferencesDriver.new(_run)
    _filters = FilterDriver.new(_run)
    _dockers = DockerDriver.new(_run)
    _gestures = GestureDriver.new(_run)
    _kernels = KernelDriver.new(_run)


## The run's own state dump, which is what the door answers with and what a
## `state` step writes to a file. One report per run, because a second
## report is a second object with none of the run behind it: the line the dump
## carries about how often a mask has been rewritten is counted by the canvas
## driver built above, and read off a fresh report it was always zero.
func state() -> Dictionary:
    return _report.state()


func run(step: Dictionary) -> void:
    if step.has("wait"):
        _run.wait(int(step["wait"]))
    elif step.has("until"):
        _until.until(String(step["until"]), int(step.get("frames", ScenarioUntil.DEFAULT_FRAMES)), int(step.get("waited", 0)))
    elif step.has("ping"):
        _ping()
    elif step.has("shot"):
        _run.shoot(String(step["shot"]))
    elif step.has("state"):
        _report.write(String(step["state"]))
    elif step.has("move"):
        _input.move_pointer(step["move"])
    elif step.has("motion_burst"):
        _input.motion_burst(step["motion_burst"])
    elif step.has("pen_in"):
        _input.pen_in(step["pen_in"])
    elif step.has("pointer_left"):
        _input.pointer_left(String(step["pointer_left"]))
    elif step.has("lock_cursor"):
        _input.lock_cursor(step["lock_cursor"])
    elif step.has("unlock_cursor"):
        _input.unlock_cursor(step["unlock_cursor"])
    elif step.has("press"):
        _press(step["press"])
    elif step.has("release"):
        _release(step["release"])
    elif step.has("stroke"):
        _stroke.stroke(step["stroke"] as Dictionary)
        SaCaptureLayers.seed_stroke(step["stroke"] as Dictionary)
    elif step.has("undo"):
        _undo(int(step["undo"]))
    elif step.has("redo"):
        _redo(int(step["redo"]))
    elif step.has("mark"):
        _marks.mark(String(step["mark"]))
    elif step.has("rewind"):
        _marks.rewind(String(step["rewind"]), bool(step.get("force", false)))
    elif step.has("drag"):
        # A docker moves on ALT plus a left drag, which `drag_window` cannot
        # hold through a motion, so a docker named by title goes through the
        # handle's own seam. An empty answer means the spec is not one that seam
        # can serve, a note window or a `via` that is testing input routing, and
        # those go on through `drag_window` as they always did.
        var dragged := DockerDragHandle.capture_move(_run.tree(), step["drag"] as Dictionary)
        if dragged.is_empty():
            _input.drag_window(step["drag"] as Dictionary)
        else:
            print(dragged)
    elif step.has("probe"):
        _cursor.probe(step["probe"])
    elif step.has("ring_predict"):
        # The samples a pointer at a known speed would have produced, and
        # what each overlay would draw with them. Wayland will not let a
        # capture move the pointer, so this is the only reading of a lead
        # available offscreen.
        print(CursorOverlay.capture_ring_predict(_run.tree(), step["ring_predict"]))
    elif step.has("ring_cost"):
        print(CursorOverlay.capture_ring_cost(_run.tree(), step["ring_cost"]))
    elif step.has("ring_dump"):
        _cursor.ring_dump(step["ring_dump"])
    elif step.has("pacer"):
        print(SaFramePacer.capture_state(_run.tree()))
    elif step.has("click"):
        _input.click(step["click"] as Dictionary)
    elif step.has("open"):
        _menus.open_dialog(
            String(step["open"]),
            String(step.get("space", "")),
            String(step.get("fit", "")),
            String(step.get("picture", "")),
            String(step.get("launch", ""))
        )
    elif step.has("menu"):
        _menus.open_menu(String(step["menu"]))
    elif step.has("menu_item"):
        print(_menus.click_menu_item(step["menu_item"] as Dictionary))
    elif step.has("file_picker"):
        print(_menus.file_picker(step["file_picker"] as Dictionary))
    elif step.has("answer"):
        print(_menus.answer_question(int(step["answer"])))
    elif step.has("blend"):
        _menus.open_blend_menu(String(step["blend"]))
    elif step.has("choice"):
        # A choice list is a Window of its own, so opening one, parking the
        # pointer on a row and pressing a row are all made from inside.
        print(SaMenuChoice.capture_choice(_run.tree(), step["choice"] as Dictionary))
    elif step.has("blend_row"):
        # The list's rows are two controls each, so a scenario has to be
        # able to say which of the two it pressed.
        print(_menus.press_blend_row(String(step["blend_row"])))
    elif step.has("dropdown"):
        _menus.open_dropdown(step["dropdown"])
    elif step.has("minimap"):
        print(MinimapDocker.capture_proof(_run.tree(), step["minimap"]))
    elif step.has("page"):
        _prefs.show_page(String(step["page"]))
    elif step.has("layout_rows"):
        print(SaLayoutPage.capture_rows(_run.tree()))
    elif step.has("performance"):
        print(SaPerformancePage.capture_page(_run.tree(), step["performance"]))
    elif step.has("half_size_view"):
        print(SaCanvas.capture_half_size_view(_run.tree(), step["half_size_view"]))
    elif step.has("light_offer"):
        print(SaLightModeOffer.capture_offer(_run.tree(), step["light_offer"]))
    elif step.has("theme_rows"):
        print(SaColorThemesPage.capture_rows(_run.tree(), step["theme_rows"] as Dictionary))
    elif step.has("control_states"):
        print(SaControlStatesStrip.capture_strip(_run.tree(), step["control_states"] as Dictionary))
    elif step.has("layout_gesture"):
        print(SaLayoutPage.capture_gesture(_run.tree(), step["layout_gesture"] as Dictionary))
    elif step.has("workspace"):
        print(SaWorkspaceCapture.capture_sliders(_run.tree(), step["workspace"] as Dictionary))
    elif step.has("news"):
        print(WelcomeNewsPane.capture_pane(_run.tree().root, step["news"] as Dictionary))
    elif step.has("tips"):
        print(WelcomeTipsPane.capture_pane(_run.tree().root, step["tips"] as Dictionary))
    elif step.has("shortcut"):
        print(_prefs.rebind_shortcut(step["shortcut"] as Dictionary))
    elif step.has("shortcut_profile"):
        print(_prefs.select_shortcut_profile(String(step["shortcut_profile"])))
    elif step.has("krita_import"):
        print(_prefs.import_krita_file(String(step["krita_import"])))
    elif step.has("new_document_gamut"):
        print(_menus.select_new_document_gamut(String(step["new_document_gamut"])))
    elif step.has("new_document_row"):
        print(NewDocumentDialog.capture_row(_run.tree(), step["new_document_row"] as Dictionary))
    elif step.has("document"):
        _document.new_document(String(step["document"]), step.get("background", {}) as Dictionary, step.get("size"))
    elif step.has("load"):
        _document.load_document(step["load"])
    elif step.has("preset"):
        _document.brush_preset(step["preset"] as Dictionary)
    elif step.has("key"):
        _input.key(step["key"])
    elif step.has("midi"):
        print(InputDriver.simulate_input(&"midi", step["midi"] as Dictionary))
    elif step.has("canvas"):
        _canvas.canvas_size(step["canvas"] as Array)
    elif step.has("zoom"):
        _canvas.zoom(float(step["zoom"]))
    elif step.has("fit"):
        _canvas.fit()
    elif step.has("checker"):
        _checker(int(step["checker"]))
    elif step.has("fine_checker"):
        _fine_checker(int(step["fine_checker"]))
    elif step.has("fill"):
        _canvas.fill(step["fill"] as Array)
    elif step.has("clear"):
        _canvas.clear()
    elif step.has("view"):
        _canvas.view_mode(String(step["view"]))
    elif step.has("view_row"):
        print(_view_row(String(step["view_row"])))
    elif step.has("control"):
        # Any control `SaMake` made, read or moved by its name.
        print(ControlWalker.capture(_run.tree(), step["control"] as Dictionary))
    elif step.has("exposure_stops"):
        print(SaDisplayPage.set_exposure_stops(_run.tree().root, float(step["exposure_stops"])))
    elif step.has("toggle"):
        _canvas.view_toggle(String(step["toggle"]))
    elif step.has("save"):
        _document.save_document(step["save"])
    elif step.has("autosave"):
        print(SaScenarioAutosave.capture(_run, bool(step.get("over_frames", false))))
    elif step.has("export"):
        # The step's other keys are the export's options, each named where they are read.
        _document.export_file(String(step["export"]), step)
    elif step.has("look"):
        _document.look(step["look"] as Dictionary)
    elif step.has("texel"):
        _texel.read(step["texel"] as Array)
    elif step.has("find"):
        _find.find(step["find"] as Dictionary)
    elif step.has("read_pixels"):
        _pixels.read(step["read_pixels"] as Dictionary)
    elif step.has("write_pixels"):
        _pixels.write(step["write_pixels"] as Dictionary)
    elif step.has("height_span"):
        print(_texel.height_span(float(step["height_span"])))
    elif step.has("measure"):
        # The class is `core/`'s because the reduction is a kernel and a
        # document, and the door is a static on it so the branch stays one call.
        print(SaMeasure.capture(_run.main_document(), step["measure"] as Dictionary))
    elif step.has("layers"):
        SaDoorVerdicts.say(_report.layers_line(step["layers"]))
    elif step.has("glance"):
        SaDoorVerdicts.say(DoorGlance.capture(_run, _report.layers_line({"alpha": false})))
    elif step.has("reduce"):
        print(SaReduce.capture(_run.main_document(), step["reduce"]))
    elif step.has("prefs"):
        _prefs.set_prefs(step["prefs"] as Dictionary)
    elif step.has("prefs_search"):
        print(_prefs.search_preferences(String(step["prefs_search"])))
    elif step.has("wheel"):
        _run.last_pointer = _canvas.wheel(step["wheel"] as Dictionary)
    elif step.has("touch"):
        _canvas.touch(step["touch"] as Array)
    elif step.has("select"):
        _canvas.select(step["select"])
    elif step.has("gradient"):
        _gestures.gradient(step["gradient"] as Dictionary)
    elif step.has("crop"):
        _gestures.crop(step["crop"] as Dictionary)
    elif step.has("transform"):
        _gestures.transform(step["transform"] as Dictionary)
    elif step.has("clipboard"):
        _canvas.clipboard(String(step["clipboard"]))
    elif step.has("path"):
        print(SaScenarioPath.path(step["path"] as Dictionary))
    elif step.has("adjust"):
        _filters.adjust(step["adjust"] as Dictionary)
    elif step.has("ramp"):
        print(SaRampCapture.edit(_run.tree(), step["ramp"] as Dictionary))
    elif step.has("docker_resize"):
        print(SaDockerEdges.capture_resize(_run.tree(), step["docker_resize"] as Dictionary))
    elif step.has("docker_page"):
        print(DockerDragHandle.capture_page(_run.tree(), step["docker_page"] as Dictionary))
    elif step.has("pen_drag"):
        print(PenDragDriver.drag(_run.tree(), step["pen_drag"] as Dictionary))
    elif step.has("docker"):
        _dockers.docker(step["docker"])
    elif step.has("presets_docker"):
        print(BrushPresetsDocker.capture_docker(_run.tree(), step["presets_docker"]))
    elif step.has("pick_preset"):
        print(SaPresetPick.capture_pick(_run.tree(), step["pick_preset"]))
    elif step.has("layout_preset"):
        print(MainDockers.capture_layout_preset(_run.tree(), step["layout_preset"] as Dictionary))
    elif step.has("option"):
        print(ToolOptionsDocker.capture_option(_run.tree(), step["option"] as Dictionary))
    elif step.has("prefs_frame"):
        print(SaSettingsFrame.capture_frame(_run.tree(), step["prefs_frame"]))
    elif step.has("reference"):
        print(SaReferenceCapture.capture_reference(_run.tree(), step["reference"]))
    elif step.has("delete_files"):
        print(SaFileDriver.delete_files(step["delete_files"]))
    elif step.has("tooltip"):
        print(SaTooltip.capture_tooltip(_run.tree(), step["tooltip"]))
    elif step.has("drop"):
        print(SaDocumentFiles.capture_drop(_run.tree(), step["drop"]))
    elif step.has("tab"):
        print(SaDocumentTabs.capture_tab(_run.tree(), step["tab"]))
    elif step.has("documents"):
        print(SaDocumentTabs.capture_documents(_run.tree()))
    elif step.has("front"):
        print(SaDocumentTabs.capture_front(_run.tree(), String(step["front"])))
    elif step.has("brush_editor"):
        print(SaBrushEditorCapture.capture_editor(_run.tree(), step["brush_editor"] as Dictionary, _run.out_dir))
    elif step.has("kpp"):
        _kpp(String(step["kpp"]))
    elif step.has("pattern"):
        _pattern(step["pattern"] as Dictionary)
    elif step.has("shape"):
        _shape(step["shape"] as Dictionary)
    elif step.has("preset_import"):
        _preset_import(String(step["preset_import"]))
    elif step.has("preset_page"):
        # Through the page rather than through `preset_import` above, because
        # what this step checks is what the page shows rather than what the
        # importer did.
        print(SaBrushPresetsPage.capture_import(_run.tree(), step["preset_page"] as Dictionary, _run.out_dir))
    elif step.has("brush_slot"):
        # Through the page rather than through the settings key, because what
        # this step checks is that a painter can fill a slot, and the page is an
        # embedded subwindow an injected click does not route into.
        print(SaBrushSlotsPage.capture_slot(_run.tree(), step["brush_slot"] as Dictionary))
    elif step.has("preset_name"):
        # The preset's name field, reached here because, like the brush
        # editor's value field, it is not reachable by an injected click or key.
        print(ToolOptionsPresets.capture_name_field(_run.tree(), step["preset_name"]))
    elif step.has("slider_edit"):
        print(SaSliderEdit.capture_edit(_run.tree(), step["slider_edit"]))
    elif step.has("curve_option"):
        print(CurveOptionCapture.capture_control(_run.tree(), step["curve_option"] as Dictionary))
    elif step.has("hide"):
        print(SaDockerWindowCapture.capture_hide(_run.tree(), step["hide"]))
    elif step.has("docker_pointer"):
        _dockers.pointer(step["docker_pointer"])
    elif step.has("docker_corners"):
        print(SaDockerWindowCapture.capture_corners(_run.tree(), step["docker_corners"]))
    elif step.has("pressure_pad"):
        print(SaTabletCalibration.capture_pad(_run.tree(), step["pressure_pad"]))
    elif step.has("sweep"):
        SaTabletSweepCapture.run(_run.tree(), step["sweep"] as Dictionary, _run.out_dir)
    elif step.has("speed_trace"):
        print(SaSpeedTraceCapture.run(_run.tree(), step["speed_trace"] as Dictionary, _run.out_dir))
    elif step.has("pressure_curve"):
        _pressure_curve(float(step["pressure_curve"]))
    elif step.has("window"):
        print(_input.resize_window(step["window"] as Array))
    elif step.has("message"):
        print(SaMessage.capture_message(_run.tree(), step["message"] as Dictionary))
    elif step.has("canvas_size"):
        print(SaCanvasSizeDialog.capture_resize(_run.tree(), step["canvas_size"] as Dictionary))
    elif step.has("image_size"):
        # For the reason the row above it exists: the dialog is a Window and an
        # injected click does not route into one.
        print(SaImageSizeDialog.capture_image_size(_run.tree(), step["image_size"] as Dictionary))
    elif step.has("curve"):
        _curve(step["curve"] as Dictionary)
    elif step.has("levels"):
        _levels(step["levels"] as Dictionary)
    elif step.has("palette"):
        _palette(step["palette"] as Dictionary)
    elif step.has("graph"):
        GraphDocker.capture_mode(_run.tree(), step["graph"])
    elif step.has("gamut_solid"):
        print(SaGamutSolid.capture_solid(_run.tree(), step["gamut_solid"] as Dictionary))
    elif step.has("preview"):
        _filters.preview(step["preview"] as Dictionary)
    elif step.has("swatch"):
        _prefs.swatch(step["swatch"] as Dictionary)
    elif step.has("layer"):
        print(SaCaptureLayers.run(_run.main_document(), step["layer"] as Dictionary, _run.layer_types()))
    elif step.has("layer_collapse"):
        print(SaLayerListCapture.collapse(_run.tree(), step["layer_collapse"]))
    elif step.has("layer_picture"):
        print(SaLayerListCapture.press_picture(_run.tree(), step["layer_picture"] as Dictionary))
    elif step.has("filter_rows"):
        print(SaFilterRowsCapture.run(_run.tree(), _run.main_document(), step["filter_rows"]))
    elif step.has("pick_rows"):
        print(SaCaptureLayers.pick_rows(_run.tree(), step["pick_rows"] as Array))
    elif step.has("shift_rows"):
        print(SaCaptureLayers.shift_rows(_run.tree(), step["shift_rows"] as Array))
    elif step.has("layer_action"):
        print(SaCaptureLayers.layer_action(_run.tree(), String(step["layer_action"])))
    elif step.has("layer_rename"):
        print(SaCaptureLayers.rename(_run.tree(), step["layer_rename"] as Dictionary))
    elif step.has("color_range"):
        print(SaColorRangeDialog.capture(_run.tree(), step["color_range"] as Dictionary))
    elif step.has("rename_dialog"):
        print(SaLayerRenameDialog.capture_dialog(_run.tree(), step["rename_dialog"] as Dictionary))
    elif step.has("drag_row"):
        print(SaCaptureLayers.drag_row(_run.tree(), step["drag_row"] as Dictionary))
    elif step.has("brush"):
        print(SaCaptureLayers.brush(_run.tree(), step["brush"] as Dictionary))
    elif step.has("cut_labels"):
        print(ControlWalker.cut_labels(_run.tree(), step["cut_labels"]))
    elif step.has("toolbox"):
        print(SaToolBoxCapture.capture_toolbox(_run.tree(), step["toolbox"]))
    elif step.has("tool"):
        print(SaCaptureLayers.set_tool(step["tool"]))
    elif step.has("bar_option"):
        print(SaCaptureLayers.bar_option(_run.tree(), step["bar_option"] as Dictionary))
    elif step.has("symmetry"):
        print(SaCaptureLayers.symmetry(_run.main_document(), step["symmetry"] as Dictionary))
    elif step.has("colour"):
        CanvasDriver.colour(step["colour"])
    elif step.has("background_colour"):
        CanvasDriver.background_colour(step["background_colour"])
    elif step.has("import") and SaImageImport.formats().layered_named(String(step["import"])) != null:
        SaDocumentFiles.in_tree(_run.tree()).import_path(ProjectSettings.globalize_path(String(step["import"])))
    elif step.has("import"):
        _import_image(String(step["import"]))
    elif step.has("recorder"):
        _canvas.recorder(step["recorder"] as Dictionary)
    elif step.has("note"):
        SaCaptureNotes.run(_run, step["note"], _run.out_dir)
    elif step.has("comment"):
        print(SaCaptureNotes.comment(String(step["comment"])))
    elif step.has("page_demo"):
        print(SaPageDemo.capture(_run.tree(), step["page_demo"]))
    elif step.has("page_row"):
        _prefs.page_row(step["page_row"])
    elif step.has("filter"):
        print(SaFilterDialogWindow.capture(_run.tree(), step["filter"]))
    elif step.has("filter_browser"):
        print(FiltersDocker.capture(_run.tree(), step["filter_browser"]))
    elif step.has("filter_edit"):
        print(SaFilterEditWindow.capture(_run.tree(), step["filter_edit"]))
    elif step.has("layer_kind_browser"):
        print(SaLayerKindBrowser.capture_browser(_run.tree(), step["layer_kind_browser"]))
    elif step.has("kernel_prompt"):
        print(SaModulesMenu.capture(step["kernel_prompt"]))
    elif step.has("kernel"):
        _kernels.kernel(step["kernel"] as Dictionary)
    elif step.has("brush_field"):
        BrushFieldDriver.run(_run.brush_fields(), step["brush_field"])
    elif step.has("errors"):
        print(DoorErrors.capture(step["errors"]))
    elif step.has("usage"):
        print(SaUsageTally.capture(_run.tree(), String(step["usage"])))
    elif step.has("simulation"):
        print(SaScenarioSimulation.run(_run.tree(), step["simulation"] as Dictionary))
    elif step.has("text"):
        _text(step["text"])
    elif step.has("font"):
        _font(step["font"])
    else:
        push_warning("SaCapture: unrecognised step %s" % JSON.stringify(step))


## Opens an image into a new layer: the way File > Open and a dropped file do,
## `{"import": "/absolute/or/res/path.png"}`.
##
## The layer is named after the file and takes the place of one already called
## that, as [method import_named] says. The verdict is JSON, `SaCapture: import
## {"layer": "chart", "path": ...}` or `{"error": ...}`, so `doc.import_image`
## in `sara.py` answers the layer or raises the refusal.
func _import_image(path: String) -> void:
    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        _import_verdict({"error": "there is no document to import %s into." % path})
        return
    if not FileAccess.file_exists(path):
        _import_verdict({"error": "There is no file %s to import." % path, "path": path})
        return
    var placed: Variant = import_named(canvas.document, path)
    canvas.request_composite()
    if placed is String:
        _import_verdict({"error": placed, "path": path})
    elif placed == null:
        _import_verdict({"error": "Sara could not read %s as a picture." % path, "path": path})
    else:
        _import_verdict({"layer": (placed as SaLayer).shown_name(), "path": path})


func _import_verdict(said: Dictionary) -> void:
    print("SaCapture: import " + JSON.stringify(said))


## *path* decoded into *document* as `SaImageImport.open_into` does, in a layer
## named after the file by `SaScenarioPixels.named_target`'s rule: a layer of
## that name already there gives way to the new one, which takes its place in
## the stack and its name, so a cell that imports twice leaves one layer. Null
## when the file cannot be read, and a String when that layer refuses paint.
##
## The painter's File > Import keeps its "color_chart 2", because two pictures
## of one name are two layers to someone who opened them both by hand.
static func import_named(document: SaDocument, path: String) -> Variant:
    var wanted := path.get_file().get_basename()
    var kept := SaScenarioPixels.named_target(document, wanted)
    if kept != null:
        var refused := SaScenarioPixels.refusal_of(kept)
        if not refused.is_empty():
            return refused
        # Above the layer it replaces, so the new one lands where that one was.
        document.set_active_layer(kept)
    var layer := SaImageImport.open_into(document, path)
    if layer == null or kept == null:
        return layer
    SaLayerOps.new(document).remove(kept)
    layer.take_name(wanted)
    # Through set_active_layer, which rebuilds the docker, because nothing
    # announces a rename, as `SaImageImport.place` says.
    document.set_active_layer(layer)
    return layer


## Resets the idle clock: `{"ping": true}` does nothing else, and keeps a quiet
## session from running out. The door resets the clock when it reads the line,
## so nothing is left to do here, and a scenario holding one raises no warning.
func _ping() -> void:
    pass


## Holds a mouse button down: at the point given or wherever the last `move`
## aimed, `{"press": "left"}` or `{"press": {"button": "left", "at": [x, y],
## "shift": true}}`.
##
## The first half of a stroke written by hand, `release` the second. A modifier
## rides on the press because that is where it decides what a drag means, and
## no key event is sent, which `mouse_button` in `sa_input_driver.gd` explains.
func _press(raw: Variant) -> void:
    _input.mouse_button(raw, true)


## Releases the mouse button: at the point given or wherever the last `move`
## aimed, which ends the drag a `press` began, `{"release": "left"}`, the argument
## `press` takes.
func _release(raw: Variant) -> void:
    _input.mouse_button(raw, false)


## Undoes history entries: that many entries, one at least, and prints how many
## it moved, `{"undo": 3}`.
##
## **Arguments.**
## - `undo` integer, how many steps back.
##
## Straight at the document's `UndoRedo` rather than through the shortcut, so
## the scenario asks whether the history is right and not whether an injected
## key reaches it. Asking for more than the history holds moves what there is.
func _undo(count: int) -> void:
    _document.history(count, true)


## Redoes history entries: that many entries, one at least, and prints how many
## it moved, the way `undo` does backwards, `{"redo": 3}`.
func _redo(count: int) -> void:
    _document.history(count, false)


## Fills a checkerboard: every chunk of the active layer, black and white, that
## many texels a cell, `{"checker": 8}`.
##
## Uploaded from the CPU the way a saved chunk is, one chunk's bytes built once
## and reused because a chunk edge is a multiple of any cell that divides it.
func _checker(cell: int) -> void:
    _canvas.checker(cell)


## Fills a fine checkerboard: the active layer gets the checkerboard `checker`
## fills, over chunks made at `resolution_scale` 2.0 in place of the layer's, 512
## texels across each, `{"fine_checker": 1}`.
##
## That is a layer at twice the document's resolution, made from its chunks
## rather than from the layer's own resolution.
func _fine_checker(cell: int) -> void:
    _canvas.checker(cell, 2.0)


## Drives the Levels row: of the filter window, opened first with an `open`
## step, `{"levels": {...}}`.
##
## *spec* is `"apply": true` or `"cancel": true` to press the window's two
## buttons, `"enabled"` to set the Preview box, and otherwise the keys the row's
## own control reads, which is the module's business. `curve` and `palette` take
## the same.
func _levels(spec: Dictionary) -> void:
    _filters.custom_row("levels", spec)


## Drives the Curves row: of the filter window, opened first with an `open`
## step, with the keys `levels` takes, handles and points among the ones its
## control reads, `{"curve": {...}}`.
func _curve(spec: Dictionary) -> void:
    _filters.custom_row("curves", spec)


## Drives the colour lookup row: of the filter window, with the keys `levels`
## takes, `{"palette": {...}}`.
##
## The one of the three that opens its own window, the palette filter, when it
## is not the one showing, as its Filter menu row would.
func _palette(spec: Dictionary) -> void:
    _filters.custom_row("palette", spec, "palette")


## Lists a Krita file's presets: it reads a `.kpp`, a `.bundle` or a folder of
## them, and prints a line for each preset it found, `{"kpp": "<path>"}`.
##
## The reader is the stamp brush module's, reached by the role it registers so
## this file names no module class, and a Sara with no module under the role
## says so and reads nothing.
func _kpp(path: String) -> void:
    var kpp_script := _role_script(&"kpp_capture")
    if kpp_script == null:
        print("SaCapture: kpp step needs a module registering the kpp_capture role")
    else:
        print(kpp_script.call("capture_read", _run.out_dir, path))


## Drives the pattern chooser: the stamp brush's, each key optional and applied in
## that order, and prints what the chooser shows, `{"pattern": {"open": true,
## "icon_size": 64, "pick": "Paper Grain", "close": true}}`.
##
## The same door as `kpp`: the chooser is the module's, reached by the role it
## registers.
func _pattern(spec: Dictionary) -> void:
    var pattern_script := _role_script(&"pattern_capture")
    if pattern_script == null:
        print("SaCapture: pattern step needs a module registering the pattern_capture role")
    else:
        print(pattern_script.call("capture", _run.tree(), _run.out_dir, spec))


## Draws a shape: a vector rectangle or ellipse with a fill and a stroke on
## the active vector layer, or on one made above the active layer, and
## prints its id, `{"shape": {"kind": "rect", "rect": [x, y, w, h], "radius":
## 12, "fill": [1, 1, 1, 1], "stroke": [0, 0, 0, 1], "stroke_width": 6}}`, or
## `"kind": "ellipse"` with `"centre": [x, y]` and `"radii": [rx, ry]`.
##
## The same door as `kpp`: the vector layers are a module's, reached by the
## role it registers.
func _shape(spec: Dictionary) -> void:
    var shape_script := _role_script(&"shape_step")
    if shape_script == null:
        print("SaCapture: shape step needs a module registering the shape_step role")
    else:
        var context: SaContext = _run.tree().current_scene.registries.context
        print(shape_script.call("capture", _run.main_document(), context, spec))


## Imports Krita brush presets: a `.kpp`, a `.bundle` or a folder of them into the
## painter's brush presets, and prints what each preset said, `{"preset_import":
## "<path>"}`.
##
## The same door as `kpp`: the importer is the module's, reached by the role it
## registers, and the docker's Import button takes it too, so the step and the
## button cannot import differently.
func _preset_import(path: String) -> void:
    var import_script := _role_script(&"preset_import")
    if import_script == null:
        print("SaCapture: preset_import step needs a module registering the preset_import role")
    else:
        print(import_script.call("capture", _run.tree(), _run.out_dir, path))


## Sets a pressure power curve: it replaces the pen's pressure correction with
## the curve `pressure` raised to that power, written and applied at once,
## `{"pressure_curve": 2.5}`.
##
## A table of 256 samples of that power goes to `SaTablet.save_correction` with
## no handles, so a scenario can feel a preset under a curve other than the
## straight one, and the Tablet page then shows a fit rather than points
## anyone placed.
##
## Refused in a run with no `--settings-dir`, a `--watch` session's, whose
## settings folder is the painter's own, so no scenario writes over the curve
## their pen was calibrated to.
func _pressure_curve(exponent: float) -> void:
    if SaDataRoot.flag().is_empty():
        print("SaCapture: refused pressure_curve, this run reads the painter's own settings and their curve is theirs")
        return
    SaTablet.save_correction(PackedFloat32Array(range(256).map(func(i: int) -> float: return pow(i / 255.0, exponent))))


## Makes or edits a text layer: `{"text": {"content": "Title", "at": [120,
## 200], "font": "Caveat", "size": 96}}` letters a new layer through the Text
## tool's session, one history step, and `"layer"` names one to edit. With
## `"caret"` it types nothing and puts the Text tool's caret by index instead,
## `{"text": {"layer": "Title", "caret": 3}}` opening the layer, so the `key`
## steps after it type there as a hand would, the page's `text_edit`. The text
## module answers through its `text_step` and `text_edit_step` roles and
## prints one line of JSON.
func _text(spec: Variant) -> void:
    if not (spec is Dictionary and (spec as Dictionary).has("caret")):
        _module_step(&"text_step", spec)
        return
    var script := _role_script(&"text_edit_step")
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine if canvas != null else null
    if script == null:
        print("SaCapture: text needs a module registering the text_edit_step role")
    elif machine == null:
        print("SaCapture: text refused, no canvas with a tool machine")
    else:
        print(script.call(&"text_edit_step", _run.main_document(), spec, machine))


## Loads or lists fonts: `{"font": {"load": "<path>"}}`, `{"font": "list"}`
## and `{"font": {"forget": "<family>"}}`, and `{"font": {"has": "abc",
## "family": "Caveat"}}` asks which characters a family has a glyph for, each
## answered by the text module's `font_step` role as one line of JSON.
func _font(spec: Variant) -> void:
    _module_step(&"font_step", spec)


## Hands *spec* and the document in front to the module registered under
## *role*, and prints its answer, or says no module registers the role.
func _module_step(role: StringName, spec: Variant) -> void:
    var script := _role_script(role)
    if script == null:
        print("SaCapture: %s needs a module registering the %s role" % [String(role).trim_suffix("_step"), role])
    else:
        print(script.call(role, _run.main_document(), spec))


## The script a module registered under *role*, or null in a host without
## registries or with nothing under the role.
func _role_script(role: StringName) -> Script:
    var main_node := _run.tree().current_scene
    if main_node == null or not ("registries" in main_node):
        return null
    return main_node.registries.roles.script_for(role)


## Picks a View transform: a row of the Canvas and colour page's View transform
## dropdown, by the label the running app draws, `{"view_row": "Tonemap
## Highlights"}`. The dropdown is a plain choice, so the walker presses it, and
## the lines are the ones the page's own hook prints, so a scenario written
## against the hook reads them unchanged.
func _view_row(label: String) -> String:
    var option := ControlWalker.find(_run.tree().root, "ViewTransformOpt")
    if option == null:
        return "SaCapture: no open Display page to pick a view row on"
    if not ControlWalker.move(option, label):
        return "SaCapture: no view row called '%s'" % label
    return "SaCapture: view row '%s'" % label
