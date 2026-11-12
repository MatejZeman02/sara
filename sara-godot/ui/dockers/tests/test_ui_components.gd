## Unit tests for procedural UI dockers and options bar.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")
const ColorDockerScript = preload("res://ui/dockers/color/color_docker.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const MainScript = preload("res://ui/main/main.gd")

## Overridden to pin the order: these tests share a settings file and a layout
## file, so they are not independent of each other.
##
## The list is hand-kept, which is a trap this repository has already been caught
## by once with the icon names. A test added to this file and not added here does
## not fail, it simply never runs, and the suite reports the same green line it
## always did. So anything missing is reported as a failure rather than skipped.
const ORDERED_TESTS: Array[String] = [
    "test_new_document_dialog_describes_a_document",
    "test_the_gamma_slider_is_a_choice_of_curve",
    "test_the_chooser_dialogs_draw_what_is_being_chosen",
    "test_color_space_dialog_separates_assign_from_convert",
    "test_toolbox_docker_init_and_resize",
    "test_color_docker_sync",
    "test_tool_options_bar_controls",
    "test_layers_docker_management",
    "test_global_shortcuts_and_layout_persistence",
    "test_regression_bugs",
]


func run_all_tests(suite_name: String) -> bool:
    var started := Time.get_ticks_msec()

    for method in get_method_list():
        var method_name: String = method["name"]
        if method_name.begins_with("test_") and not ORDERED_TESTS.has(method_name):
            failed_count += 1
            failure_messages.append("[FAIL] %s is missing from ORDERED_TESTS, so it never ran." % method_name)

    for method_name in ORDERED_TESTS:
        current_test_name = method_name
        call(method_name)

    duration_ms = Time.get_ticks_msec() - started
    _print_suite_line(suite_name)
    return failed_count == 0


## The dialog is built detached and freed. Adding a Window to the scene tree in a
## test maps a real OS window and hangs the run until the watchdog fires
## (a test window must never be mapped), which is why the values are readable without popping
## it.
## Picks a dropdown row the way a hand does: the row inside the list is pressed,
## so the control writes its own value and announces it in one call. Before
## the choice button that took two lines, and selecting without emitting or
## emitting without selecting each tested half of nothing.
func _choose(option: SaChoiceButton, row: int) -> void:
    option.pick_row(row)


## The same for a slider, and for the same reason: assigning `Range.value` sets it
## silently. A drag sets it and announces it.
func _slide(slider: Range, value: float) -> void:
    slider.value = value
    slider.value_changed.emit(slider.value)


func test_new_document_dialog_describes_a_document() -> void:
    var dialog := NewDocumentDialog.new()

    assert_eq(dialog.selected_size(), NewDocumentDialog.DEFAULT_SIZE, "The dialog should open on the default size")

    var space := dialog.selected_space()
    assert_not_null(space, "The dialog should always describe a colour space")
    # The default the app also builds its own document in, rather than
    # the first preset the rows happened to open on. sRGB was that answer by
    # coincidence, which is what let the two disagree the moment either moved.
    # Asked of the default rather than named, because its gamut follows the
    # display profile.
    assert_eq(str(space.id), str(SaEasel.default_space().id), "The dialog opens on the same space the app starts in")
    assert_eq(space.depth, SaEasel.default_space().depth, "at the same depth, which no preset carries")
    assert_true(space.is_specified, "A document created here was told what it is, so it is not unspecified")

    # Every preset must be offered, or a chooser silently drops a colour space
    # that the rest of the code can already read and write. Plus one row for
    # Custom, which is what a gamut and curve pair that names no preset selects,
    # and one for Profile file, which opens an ICC profile.
    assert_eq(
        dialog.row_option(&"space").choice_labels().size(),
        SaColorSpace.presets().size() + 2,
        "Every preset plus Custom should be listed"
    )
    # Plus Custom, where a painter types primaries no gamut names.
    assert_eq(dialog.row_option(&"gamut").choice_labels().size(), SaGamut.presets().size() + 1, "and every gamut on its own row")
    # Every named curve, plus one row past them for the gamma slider. A slider
    # alone could not replace the presets: sRGB is not a pure power curve, it has
    # a straight toe under one.
    var transfer_rows := dialog.row_option(&"transfer").choice_labels().size()
    assert_eq(transfer_rows, SaTransferFunction.presets().size() + 1, "and every transfer curve on its own row")

    # Every depth offered must be one chunk storage can allocate. A choice
    # that reached the descriptor and the header and never the allocation
    # would record F16 over F32 chunks.
    var depth_rows := dialog.row_option(&"depth").choice_labels()
    assert_eq(depth_rows.size(), SaColorSpace.storage_depths().size(), "Only allocatable depths should be listed")
    for index in depth_rows.size():
        _choose(dialog.row_option(&"depth"), index)
        var offered := dialog.selected_space().depth
        assert_true(
            SaColorSpace.storage_supports_depth(offered),
            "The dialog must not offer a depth storage cannot allocate (entry %d)" % index
        )
    _choose(dialog.row_option(&"depth"), 0)

    # Pressed rather than assigned, which is what a click does. The preset row is
    # only a shortcut that fills the gamut and curve rows, and `selected_space()`
    # reads those, so a write that never announced itself would test nothing.
    _choose(dialog.row_option(&"space"), 3)
    var chosen := dialog.selected_space()
    assert_eq(str(chosen.id), str(SaColorSpace.ID_ACESCG), "The space choice should reach the descriptor")
    assert_eq(chosen.gamut().id, SaGamut.ID_AP1, "and fill the gamut row")
    assert_true(chosen.transfer.is_identity(), "and the transfer row")

    # The other direction: changing an axis moves the preset row rather than
    # being overridden by it, because the preset is a label and not an input.
    var rec709_row := -1
    var curves := SaTransferFunction.presets()
    for i in curves.size():
        if curves[i].id == SaTransferFunction.ID_REC709:
            rec709_row = i
    assert_true(rec709_row >= 0, "Rec. 709 is on offer")
    _choose(dialog.row_option(&"transfer"), rec709_row)
    assert_eq(
        int(dialog.row_option(&"space").selected_value()),
        SaColorSpace.presets().size(),
        "AP1 with a Rec. 709 curve is no named preset, so the row reads Custom"
    )
    assert_eq(dialog.selected_space().transfer.id, SaTransferFunction.ID_REC709, "and the curve is what was asked for")

    dialog.free()


## The gamma slider, which exists because the named curves are five points and an
## experiment wants the space between them.
##
## Two directions, and the second is the one that breaks quietly. Moving the
## slider has to be a choice of curve by itself, or a user drags it and nothing
## happens. Picking a named curve has to move the slider onto that curve's own
## exponent without the slider then grabbing the row back, which is what the sync
## guard is for: sRGB really is a 2.4 power segment, it just has a straight toe
## under it too, and a row reading 2.40 next to "sRGB" is the truth.
func test_the_gamma_slider_is_a_choice_of_curve() -> void:
    var dialog := NewDocumentDialog.new()
    var gamma_row := SaTransferFunction.presets().size()

    _slide(dialog.picker._gamma_slider, 3.4)
    assert_eq(int(dialog.row_option(&"transfer").selected_value()), gamma_row, "Dragging the slider chooses the curve by itself")
    var chosen := dialog.selected_space()
    assert_almost_eq(chosen.transfer.exponent, 3.4, 1e-5, "and the exponent reaches the descriptor")
    assert_eq(str(chosen.transfer.id), str(SaTransferFunction.ID_GAMMA), "as a pure power curve")
    assert_eq(dialog.picker._gamma_value.text, "3.4", "and the row says what it is set to")

    _choose(dialog.row_option(&"transfer"), 0)
    assert_almost_eq(
        dialog.picker._gamma_slider.value,
        SaTransferFunction.srgb().exponent,
        1e-5,
        "Picking sRGB moves the slider to its exponent"
    )
    assert_eq(int(dialog.row_option(&"transfer").selected_value()), 0, "without the slider taking the row back")
    assert_eq(str(dialog.selected_space().transfer.id), str(SaTransferFunction.ID_SRGB), "so sRGB is what gets created")

    dialog.free()


## The browser is reachable from where the choice is made, not only from the
## info docker. It sits beside both choosers, in preview mode so there
## is one dropdown per question rather than two.
##
## The preview has to draw a space that matches no preset, because once a gamut
## and a curve are chosen separately most combinations are not presets, and
## `show_space` must not return without drawing anything in exactly that case.
func test_the_chooser_dialogs_draw_what_is_being_chosen() -> void:
    var dialog := NewDocumentDialog.new()
    assert_not_null(dialog.browser, "File > New shows what is being chosen")
    assert_true(dialog.browser.preview_only, "and does not offer a second dropdown for the same question")
    assert_false(dialog.browser.option.visible, "so the browser's own chooser is hidden")

    _choose(dialog.row_option(&"gamut"), SaGamut.presets().size() - 1)
    var curves := SaTransferFunction.presets()
    var gamma_row := -1
    for i in curves.size():
        if curves[i].id == SaTransferFunction.ID_GAMMA22:
            gamma_row = i
    _choose(dialog.row_option(&"transfer"), gamma_row)

    var shown: SaColorSpace = dialog.browser.diagram.space
    assert_not_null(shown, "A combination that names no preset is still drawn")
    assert_eq(shown.gamut().id, SaGamut.ID_REC2020, "with the gamut that was chosen")
    assert_eq(shown.transfer.id, SaTransferFunction.ID_GAMMA22, "and the curve")
    assert_true(dialog.browser.transfer_plot.space == shown, "The curve plot follows the same space")
    dialog.free()

    # The same view beside the target dropdown, where the question is "what will
    # this conversion do to my document".
    var convert_dialog := ColorSpaceDialog.new()
    assert_not_null(convert_dialog.browser, "Image > Colour Space shows its target too")
    assert_true(convert_dialog.browser.preview_only, "in preview mode as well")
    convert_dialog.page.row(&"space").drive(3)
    assert_eq(convert_dialog.browser.diagram.space.gamut().id, SaGamut.ID_AP1, "and follows the target dropdown")
    convert_dialog.free()


func test_toolbox_docker_init_and_resize() -> void:
    var canvas := SaCanvas.new()
    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    canvas.add_child(tm)
    tm._ready()

    var registry := Fixtures.make_tool_registry()
    # The machine needs the same registry, or the buttons exist but there is no
    # instance to activate.
    var tb_surface := Fixtures.make_surface()
    tm.bind(tb_surface, registry)

    var toolbox := ToolBoxDockerScript.new()
    toolbox.name = "ToolBoxDocker"
    canvas.add_child(toolbox)
    toolbox.target_tool_machine = tm
    toolbox._ready()
    # Buttons come from the registry, not from six hardcoded calls, so a module
    # tool gets one too.
    toolbox.rebuild_from_registry(registry)

    # One button per category, and fewer of them than there are tools,
    # which is the whole of what a flyout buys. Every tool still reaches one.
    assert_true(
        toolbox._buttons.size() < registry.list_ids().size(), "The toolbox groups tools rather than drawing one button each"
    )
    for descriptor: SaToolDescriptor in registry.list_tools():
        assert_not_null(toolbox.button_for_tool(String(descriptor.id)), "%s reaches a button" % descriptor.id)

    # A tool naming an icon that does not ship falls back to its display name,
    # which a one-column toolbox then clips to "Brus" / "Eyedro". test_icons.gd
    # checks a hand-kept list and so never noticed that three descriptors had
    # drifted away from the files in res://assets/icons/. Every tool is asked
    # for by name rather than only the faces, or a tool whose icon went missing
    # would hide behind whichever of its category came first.
    var textual: Array[String] = []
    for descriptor: SaToolDescriptor in registry.list_tools():
        toolbox.show_tool(String(descriptor.id))
        var tool_btn: Button = toolbox.button_for_tool(String(descriptor.id))
        if tool_btn != null and (tool_btn.icon == null or tool_btn.text != ""):
            textual.append(String(descriptor.id))
    assert_true(textual.is_empty(), "Every toolbox button must show an icon, not text: %s" % ", ".join(textual))

    # Pressing the button while the eraser is its face is the plain left press,
    # which is the gesture a painter makes most and the one the flyout does not
    # change.
    toolbox.show_tool("eraser")
    var eraser_btn: Button = toolbox.button_for_tool("eraser")
    eraser_btn.pressed.emit()
    assert_eq(tm.active_tool_name, "eraser", "Clicking eraser button should switch active tool in ToolMachine")
    tb_surface.easel.free()

    # Column resizing. The widths are logical and go through window_size_for,
    # because Window.size is physical for this detached window and logical for an
    # embedded docker, setting it in logical units gave two columns at every
    # width on a 2x display.
    var btn_w := DockerUtils.BASE_TOOL_BTN
    var margin := DockerUtils.BASE_MARGIN

    # Narrow: one button width only -> 1 column
    toolbox.size = SaUI.window_size_for(toolbox, Vector2i(btn_w + margin, 400))
    toolbox.size_changed.emit()
    assert_eq(toolbox.grid_container.columns, 1, "Should be 1 column when width is narrow")

    # Wide but tall: three button widths against 400 of height. This asks for
    # one column, because following the shape
    # answers a row or a column and the shape here is a column.
    toolbox.size = SaUI.window_size_for(toolbox, Vector2i(btn_w * 3 + margin * 2, 400))
    toolbox.size_changed.emit()
    assert_eq(toolbox.grid_container.columns, 1, "A tall docker stays one column however wide it gets")

    # Wide and short, with room for every button: the single row.
    var buttons := SaToolBoxGrid.visible_button_count(toolbox.grid_container)
    toolbox.size = SaUI.window_size_for(toolbox, Vector2i(btn_w * (buttons + 2) + margin * 2, btn_w * 2))
    toolbox.size_changed.emit()
    assert_eq(toolbox.grid_container.columns, buttons, "Should be a single row when the docker is wide and short")

    # ALT + Left Click dragging. Driven through handle_input rather than the
    # window_input signal, because the drag now consumes the press in a node's
    # _input, Viewport.push_input clears the handled flag straight after
    # emitting window_input, so a handler there could not stop the click from
    # also reaching the tool button underneath.
    var drag: DockerDragHandle = toolbox._drag_handle_input
    # The release emits `docker_layout_changed`, which tells every docker window
    # in the process that the painter has sized one, and the suites run after
    # this one would open theirs at the size they were built with. So the
    # listeners are set aside for the drag and put back after it.
    var listeners := EventBus.docker_layout_changed.get_connections()
    for listener: Dictionary in listeners:
        EventBus.docker_layout_changed.disconnect(listener["callable"])
    var ev_alt_click := InputEventMouseButton.new()
    ev_alt_click.button_index = MOUSE_BUTTON_LEFT
    ev_alt_click.pressed = true
    ev_alt_click.alt_pressed = true
    assert_true(drag.handle_input(ev_alt_click), "ALT + Left Click must be consumed, not passed to the docker")
    assert_true(drag._is_alt_dragging, "ALT + Left Click on docker must start alt dragging")

    var ev_alt_motion := DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_LEFT)
    ev_alt_motion.relative = Vector2(20, 30)
    assert_true(drag.handle_input(ev_alt_motion), "Motion during an ALT drag belongs to the drag")

    var ev_alt_release := InputEventMouseButton.new()
    ev_alt_release.button_index = MOUSE_BUTTON_LEFT
    ev_alt_release.pressed = false
    ev_alt_release.alt_pressed = true
    assert_true(drag.handle_input(ev_alt_release), "The release must be consumed too, or the button fires on it")
    assert_false(drag._is_alt_dragging, "Releasing Left Click must stop alt dragging")
    for listener: Dictionary in listeners:
        EventBus.docker_layout_changed.connect(listener["callable"], listener["flags"])

    # A plain click must still reach the docker.
    var ev_plain_click := InputEventMouseButton.new()
    ev_plain_click.button_index = MOUSE_BUTTON_LEFT
    ev_plain_click.pressed = true
    assert_false(drag.handle_input(ev_plain_click), "A click without ALT must pass through to the docker")

    # The drag is absolute, so sub-pixel motion cannot accumulate rounding error:
    # ten steps of 0.4 would round to zero every time and the docker would fall behind
    # the cursor, then lurch when a big delta finally arrived.
    var grab := Vector2(7.0, 11.0)
    var pointer := Vector2(100.0, 200.0)
    for _i in 10:
        pointer += Vector2(0.4, 0.4)
    assert_eq(
        DockerDragHandle.drag_position(pointer, grab),
        Vector2i(97, 193),
        "Dragging must land where the pointer is, not where accumulated deltas got to"
    )

    canvas.free()


func test_color_docker_sync() -> void:
    var canvas := Control.new()
    var color_docker := ColorDockerScript.new()
    color_docker.name = "ColorDocker"
    canvas.add_child(color_docker)
    color_docker._ready()
    assert_true(color_docker.color_picker != null, "ColorPicker should be initialized")

    # Simulate EventBus signal from another tool
    EventBus.color_picked.emit(Color(0.2, 0.4, 0.8, 1.0))
    assert_eq(color_docker.color_picker.color, Color(0.2, 0.4, 0.8, 1.0), "ColorPicker should update from EventBus")

    canvas.free()


func test_tool_options_bar_controls() -> void:
    var surface := Fixtures.make_surface()
    var tm := Fixtures.make_bound_machine(surface)
    var brush := tm.get_tool("brush")
    tm.set_active_tool(&"brush")

    var registries := Fixtures.make_registries()

    var host := Node.new()
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    bar.target_tool_machine = tm
    bar._ready()
    bar.bind_registries(registries.blend_modes)

    # The controls are built from the brush's option specs, and a
    # slider's signal reaches the setting the spec names.
    var size_slider := bar.control_for(&"radius") as FactorSlider
    assert_not_null(size_slider, "The brush declares a radius, so the bar built a slider for it")
    size_slider.value_changed.emit(50.0)
    assert_eq(brush.settings.radius, 50.0, "Brush radius should update from bar slider signal")

    var opacity_slider := bar.control_for(&"opacity") as FactorSlider
    opacity_slider.value_changed.emit(0.5)
    assert_eq(brush.settings.opacity, 0.5, "Brush opacity should update from bar slider signal")

    # Test changing blend mode via the menu's own signal. The mode is named,
    # never a position: the menu is built from the registry in sort order, so a
    # literal index would fail the day a mode is renumbered rather than the day
    # the signal breaks.
    var blend_menu := bar.control_for(&"blend_mode") as BlendModeButton
    assert_true(blend_menu.mode_ids().has(&"multiply"), "The menu offers Multiply")
    blend_menu.mode_selected.emit(&"multiply")
    assert_eq(brush.settings.blend_mode, SaLayer.BLEND_MODE.MULTIPLY, "Brush blend mode should update from the bar's menu")

    host.free()
    Fixtures.teardown(surface, tm)


func test_layers_docker_management() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var doc := canvas.document

    var layers_docker := LayersDockerScript.new()
    layers_docker.name = "LayersDocker"
    canvas.add_child(layers_docker)
    layers_docker.target_canvas = canvas
    layers_docker._ready()

    assert_eq(doc.get_child_count(), 2, "Document should start with 2 layers")
    assert_eq(layers_docker.item_list.item_count, 2, "Layer list UI should show 2 layers")

    # Simulate adding a layer via button press signal
    layers_docker.actions.add_btn.pressed.emit()
    assert_eq(doc.get_child_count(), 3, "Document should have 3 layers after pressing Add button")
    assert_eq(layers_docker.item_list.item_count, 3, "Layer list UI should update to 3 items")

    # Simulate duplicating layer via button press signal
    layers_docker.actions.duplicate_layer()
    assert_eq(doc.get_child_count(), 4, "Document should have 4 layers after pressing Duplicate button")
    assert_eq(layers_docker.item_list.item_count, 4, "Layer list UI should update to 4 items")

    # Test lock buttons via toggled signal emission
    var active := doc.active_layer
    layers_docker.actions.set_paint_lock(true)
    assert_true(active.is_locked, "Paint lock should be enabled on active layer when lock button toggled")

    layers_docker.actions.set_alpha_lock(true)
    assert_true(active.alpha_locked, "Alpha lock should be enabled on active layer when alpha lock button toggled")

    # Simulate clearing layer via button press signal
    active.fill(Color(1, 0, 0, 1))
    layers_docker.actions.clear_layer()
    var chunk: SaTexture = active.get_or_create_field(Vector2i(0, 0))
    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(12), 0.0, 0.01, "Alpha channel after pressing Clear button should be ~0.0")

    # Simulate deleting layer via button press signal
    layers_docker.actions.del_btn.pressed.emit()
    assert_eq(doc.get_child_count(), 3, "Document should have 3 layers remaining after pressing Delete button")
    assert_eq(layers_docker.item_list.item_count, 3, "Layer list UI should show 3 items after deleting")

    for child: Node in doc.get_children():
        if child.is_queued_for_deletion():
            child.free()

    doc.free()
    canvas.free()


func test_global_shortcuts_and_layout_persistence() -> void:
    var main := MainScript.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = SaDataRoot.path("test_docker_layout.cfg")
    if FileAccess.file_exists(main.dockers.layout_store.path):
        DirAccess.remove_absolute(main.dockers.layout_store.path)
    main._ready()

    # Goal 6: Color Picker is visible by default
    assert_true(main.color_docker.visible, "ColorPicker docker should be visible by default on startup")

    # Goal 4: Global shortcuts work when focusing floating docker windows
    var tm := main.get_tool_machine()
    assert_not_null(tm, "ToolMachine should exist in Main")
    if tm:
        # Simulate pressing 'E' (tool_eraser) while focused on InfoDocker
        var ev_e := InputEventKey.new()
        ev_e.physical_keycode = KEY_E
        ev_e.pressed = true
        main._shortcut_router.handle_docker_input(ev_e, main.info_docker)
        assert_true(tm.active_tool.eraser_toggled, "Pressing E while focused on InfoDocker should toggle brush eraser mode")

        # Simulate pressing 'I' (tool_eyedropper) while focused on InfoDocker
        var ev_i := InputEventKey.new()
        ev_i.physical_keycode = KEY_I
        ev_i.pressed = true
        main._shortcut_router.handle_docker_input(ev_i, main.info_docker)
        assert_eq(
            tm.active_tool_name, "eyedropper", "Pressing I while focused on InfoDocker should switch active tool to eyedropper"
        )

        # Simulate pressing 'F9' (info_docker) while focused on LayersDocker
        var ev_f9 := InputEventKey.new()
        ev_f9.physical_keycode = KEY_F9
        ev_f9.pressed = true
        var initial_vis := main.info_docker.visible
        main._shortcut_router.handle_docker_input(ev_f9, main.layers_docker)
        assert_true(
            main.info_docker.visible != initial_vis,
            "Pressing F9 while focused on LayersDocker should toggle InfoDocker visibility"
        )

    # Goal 5: Docker geometry persistence
    main.dockers.layout_store.save()
    assert_true(
        FileAccess.file_exists(SaDataRoot.path("test_docker_layout.cfg")),
        "test_docker_layout.cfg should be created when saving layout"
    )
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(SaDataRoot.path("test_docker_layout.cfg")), OK, "test_docker_layout.cfg should be loadable by ConfigFile")
    assert_true(cfg.has_section("ToolBoxDocker"), "test_docker_layout.cfg should have a ToolBoxDocker section")
    assert_true(cfg.has_section("LayersDocker"), "test_docker_layout.cfg should have a LayersDocker section")
    assert_true(cfg.has_section("ColorDocker"), "test_docker_layout.cfg should have a ColorDocker section")
    assert_true(cfg.has_section("InfoDocker"), "test_docker_layout.cfg should have an InfoDocker section")

    # Modify config and test loading
    cfg.set_value("ToolBoxDocker", "visible", false)
    cfg.save(SaDataRoot.path("test_docker_layout.cfg"))
    main.dockers.load_docker_layout()
    assert_false(main.toolbox_docker.visible, "ToolBox visibility should be updated from config")

    # Clean up config file and node
    if FileAccess.file_exists(SaDataRoot.path("test_docker_layout.cfg")):
        DirAccess.remove_absolute(SaDataRoot.path("test_docker_layout.cfg"))
    main.free()
    # The Main ran its boot by hand and loaded every module, and a Main never
    # parented never puts them down, so the linux-pen module's reader thread
    # outlived the run and threw at exit.
    ModuleLoader.unload_all()


func test_regression_bugs() -> void:
    # 1. Test make_drag_bar doesn't crash and returns valid PanelContainer
    var drag_bar := DockerUtils.make_drag_bar("Test Drag Bar")
    assert_not_null(drag_bar, "make_drag_bar should return a valid PanelContainer")
    assert_eq(drag_bar.name, "DragHandle", "Drag bar should be named DragHandle")
    drag_bar.free()

    # 2. Test Ctrl+Q vs Q exact modifier matching so Ctrl+Q does not toggle pan tool
    var ctrl_q := InputEventKey.new()
    ctrl_q.physical_keycode = KEY_Q
    ctrl_q.ctrl_pressed = true
    ctrl_q.pressed = true
    assert_false(
        ctrl_q.is_action_pressed("tool_pan", false, true), "Ctrl+Q should NOT match tool_pan under exact modifier matching"
    )

    # 3. Test quick tools event forwarding when focusing on a docker window
    var main := MainScript.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = SaDataRoot.path("test_docker_layout.cfg")
    main._ready()
    var tm := main.get_tool_machine()
    assert_not_null(tm, "ToolMachine should exist in Main")
    if tm:
        tm.set_active_tool("brush")
        assert_eq(tm.active_tool_name, "brush", "Initial permanent tool is brush")

        # Simulate Space press on docker window -> should switch to pan
        var ev_space_down := InputEventKey.new()
        ev_space_down.physical_keycode = KEY_SPACE
        ev_space_down.pressed = true
        main._shortcut_router.handle_docker_input(ev_space_down, main.info_docker)
        assert_eq(tm.active_tool_name, "pan", "Space press on docker window should quick-switch active tool to pan")

        # Simulate Space release on docker window -> should switch back to brush
        var ev_space_up := InputEventKey.new()
        ev_space_up.physical_keycode = KEY_SPACE
        ev_space_up.pressed = false
        main._shortcut_router.handle_docker_input(ev_space_up, main.info_docker)
        assert_eq(tm.active_tool_name, "brush", "Space release on docker window should restore brush")

    # 4. Test button icon sizing has max width constraint
    var test_btn := Button.new()
    DockerUtils.set_button_icon(test_btn, "Unlock", "Lock")
    assert_eq(
        test_btn.get_theme_constant("icon_max_width"),
        DockerUtils.px(DockerUtils.BASE_ICON_SIZE),
        "Button icon should have maximum width constrained by BASE_ICON_SIZE"
    )
    test_btn.free()

    main.free()
    # The Main ran its boot by hand and loaded every module, and a Main never
    # parented never puts them down, so the linux-pen module's reader thread
    # outlived the run and threw at exit.
    ModuleLoader.unload_all()


## Assign and Convert are different operations and the dialog must not blur them.
##
## Built detached and freed, like the New Document dialog: adding a Window to the
## scene tree maps a real OS window and hangs the run.
func test_color_space_dialog_separates_assign_from_convert() -> void:
    var dialog := ColorSpaceDialog.new()

    # Every preset, then the saved spaces, then Custom and Profile file, because
    # the Target is the colour space picker File > New has.
    assert_eq(
        (dialog.page.row(&"space").control as SaChoiceButton).choice_values().size(),
        SaColorSpace.presets().size() + dialog.picker.saved.size() + 2,
        "Every preset should be offered as a target"
    )
    assert_eq(str(dialog.selected_space().id), str(SaColorSpace.ID_SRGB), "sRGB is the first preset and the default target")

    # A document that never declared a space can be assigned but not converted,
    # and the dialog has to say which, not just grey a button out.
    dialog.configure(
        SaColorSpace.unspecified(), func(_target: SaColorSpace) -> String: return "this document never declared a colour space"
    )
    assert_true(dialog.convert_button.disabled, "Convert is unavailable for an undescribed document")
    assert_false(dialog.assign_button.disabled, "while Assign is exactly what it needs")
    assert_true(dialog._current_label.text.contains("unspecified"), "and the window says the file never said")
    assert_false(dialog._status_label.text.is_empty(), "with the reason spelled out rather than left blank")

    dialog.configure(SaColorSpace.srgb(), func(_target: SaColorSpace) -> String: return "")
    assert_false(dialog.convert_button.disabled, "A described document can be converted")
    assert_true(dialog._status_label.text.is_empty(), "and nothing needs explaining")
    assert_true(dialog._current_label.text.contains("sRGB"), "The current space is named")

    # The two buttons must emit different signals. One that emitted the same
    # signal for both would silently recolour a document the user meant to label.
    var assigned: Array = []
    var converted: Array = []
    dialog.assign_requested.connect(func(space: SaColorSpace) -> void: assigned.append(space))
    dialog.convert_requested.connect(func(space: SaColorSpace) -> void: converted.append(space))

    # Changing the target must re-ask, not reuse the verdict from when the window
    # opened. Configured against a document already in sRGB, Convert is correctly
    # disabled for sRGB and must become available the moment another target is
    # picked. Evaluating once left the feature unreachable for every space.
    var only_srgb_is_blocked := func(target: SaColorSpace) -> String:
        return "already in that colour space" if target.id == SaColorSpace.ID_SRGB else ""
    dialog.configure(SaColorSpace.srgb(), only_srgb_is_blocked)
    assert_true(dialog.convert_button.disabled, "Convert is unavailable while the target is the current space")
    dialog.page.row(&"space").drive(3)
    assert_false(dialog.convert_button.disabled, "and becomes available when the target changes")
    assert_true(dialog._status_label.text.is_empty(), "with the stale explanation cleared")

    dialog.page.row(&"space").drive(3)
    dialog._on_assign()
    assert_eq(assigned.size(), 1, "Assign emits assign_requested")
    assert_eq(converted.size(), 0, "and not convert_requested")
    assert_eq(str(assigned[0].id), str(SaColorSpace.ID_ACESCG), "carrying the chosen target")

    dialog._on_convert()
    assert_eq(converted.size(), 1, "Convert emits convert_requested")
    assert_eq(assigned.size(), 1, "and does not also assign")

    dialog.free()
