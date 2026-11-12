## The sixth registry: view transforms register the way tools and blend modes
## do, and the canvas, the View menu and a module all reach the same list.
##
## The contract for built-ins going through the public door: a synthetic third-party mode with
## its own shader has to reach the canvas material exactly as a built-in mode
## does. The built-ins are registered through the skeleton module, so the test
## that counts them is the test that the public door is wide enough.
extends "res://tests/test_framework.gd"

const THIRD_PARTY := &"view-test-module"


func before_each() -> void:
    SaSettings.tonemap_highlights = false
    SaSettings.display_exposure_enabled = false
    SaSettings.display_exposure_stops = 0.0
    SaSettings.display_profile = "srgb"


## Back to a fresh profile's view, the rolloff on, so the
## suites after this one see the default.
func after_each() -> void:
    before_each()
    SaSettings.tonemap_highlights = true
    SaSettings.display_profile = SaSettingsValues.display_profile_default()


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


func _toggle(id: StringName, order: int = 0) -> SaViewTransformDescriptor:
    var descriptor := SaViewTransformDescriptor.create(id, String(id).capitalize(), SaViewTransformDescriptor.Kind.TOGGLE)
    descriptor.sort_order = order
    return descriptor


func _mode(id: StringName, order: int = 0) -> SaViewTransformDescriptor:
    var descriptor := SaViewTransformDescriptor.create(id, String(id).capitalize(), SaViewTransformDescriptor.Kind.MODE)
    descriptor.sort_order = order
    return descriptor


func test_the_skeleton_registers_the_nine_built_ins_through_the_api() -> void:
    var registries := _registries()
    var registry := registries.view_transforms
    var ids := [&"highlight_rolloff", &"display_exposure", &"gamut_warning", &"lightness_check", &"hdr_heatmap"]
    for id: StringName in ids + [&"soft_proof", &"encoding_off", &"shape_check", &"show_relief"]:
        assert_true(registry.has(id), "%s registered through the public API" % id)
    assert_eq(registry.list_toggles().size(), 5, "Five toggles, Gamut Mapping the fifth")
    # The shape check is a mode rather than a filter, registered here with the rest.
    assert_eq(registry.list_modes().size(), 5, "and five modes")
    assert_eq(registry.get_descriptor(&"lightness_check").view_mode, 1, "The lightness check is the shader's mode 1")
    assert_eq(registry.get_descriptor(&"hdr_heatmap").view_mode, 2, "and the heatmap its mode 2")
    assert_eq(registry.get_descriptor(&"encoding_off").view_mode, 4, "and the encoding-off mode its mode 4")
    assert_eq(registry.get_descriptor(&"hdr_heatmap").display_name, "False Colour", "The heatmap is named for what it is")


func test_a_registration_needs_an_id_and_refuses_a_duplicate() -> void:
    var registry := SaViewTransformRegistry.new()
    assert_false(registry.register(SaViewTransformDescriptor.new()), "No id, no registration")
    assert_true(registry.register(_toggle(&"one")), "The first one lands")
    assert_false(registry.register(_toggle(&"one")), "and the same id again is refused")


func test_the_list_is_in_sort_order_then_registration_order() -> void:
    var registry := SaViewTransformRegistry.new()
    registry.register(_toggle(&"late", 30))
    registry.register(_toggle(&"early", 10))
    registry.register(_toggle(&"also_early", 10))
    assert_eq(registry.list_ids(), [&"early", &"also_early", &"late"], "Sort order first, then who came first")


func test_only_one_mode_is_active_and_a_toggle_cannot_be_one() -> void:
    var registry := SaViewTransformRegistry.new()
    registry.register(_mode(&"a"))
    registry.register(_mode(&"b"))
    registry.register(_toggle(&"t"))
    assert_eq(registry.mode, SaViewTransformRegistry.NORMAL, "The picture to begin with")
    assert_true(registry.set_mode(&"a"), "A mode can be chosen")
    assert_true(registry.set_mode(&"b"), "and another replaces it")
    assert_eq(registry.mode, &"b", "so b is the one showing")
    assert_false(registry.set_mode(&"t"), "A toggle is not a mode")
    assert_false(registry.set_mode(&"nobody"), "and nor is an id nobody registered")
    assert_eq(registry.mode, &"b", "Neither refusal moved it")
    assert_true(registry.set_mode(SaViewTransformRegistry.NORMAL), "Back to the picture")


func test_a_toggle_keeps_its_own_state_unless_it_says_where_it_lives() -> void:
    var registry := SaViewTransformRegistry.new()
    registry.register(_toggle(&"session"))
    var elsewhere := {"on": false}
    var stored := _toggle(&"stored")
    stored.read_enabled = func() -> bool: return elsewhere["on"]
    stored.on_toggle = func(enabled: bool) -> void: elsewhere["on"] = enabled
    registry.register(stored)

    assert_true(registry.set_enabled(&"session", true), "A session toggle switches on")
    assert_true(registry.is_enabled(&"session"), "and the registry remembers it")
    assert_true(registry.set_enabled(&"stored", true), "A stored toggle switches on")
    assert_true(elsewhere["on"], "by writing where it said its state lives")
    elsewhere["on"] = false
    assert_false(registry.is_enabled(&"stored"), "and reads it from there, so a change made elsewhere shows")


func test_apply_writes_the_mode_and_every_toggle_onto_the_material() -> void:
    var registry := SaViewTransformRegistry.new()
    var seen: Array = []
    var toggle := _toggle(&"t")
    toggle.apply = func(mat: ShaderMaterial, enabled: bool) -> void:
        seen.append(enabled)
        mat.set_shader_parameter("probe", 1.0 if enabled else 0.0)
    registry.register(toggle)
    var mode := _mode(&"m")
    mode.view_mode = 7
    registry.register(mode)

    var material := ShaderMaterial.new()
    registry.set_mode(&"m")
    registry.set_enabled(&"t", true)
    registry.apply_to(material)
    assert_eq(material.get_shader_parameter("view_mode"), 7, "The active mode's value")
    assert_eq(seen, [true], "and the toggle applied itself once, on")
    assert_almost_eq(material.get_shader_parameter("probe"), 1.0, 0.0, "onto the material it was handed")


func test_unregistering_a_module_takes_its_transforms_and_clears_its_active_mode() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    assert_true(ctx.register_view_transform(_mode(&"proof")), "A module may register a mode")
    assert_true(ctx.register_view_transform(_toggle(&"grid")), "and a toggle")
    registries.view_transforms.set_mode(&"proof")
    ctx.remove_all_registrations()
    assert_false(registries.view_transforms.has(&"proof"), "The mode is gone")
    assert_false(registries.view_transforms.has(&"grid"), "and the toggle")
    assert_eq(
        registries.view_transforms.mode,
        SaViewTransformRegistry.NORMAL,
        "and the view is the picture again, not a shader nobody owns"
    )
    assert_true(registries.view_transforms.has(&"hdr_heatmap"), "The skeleton's own transforms are untouched")


## Rule 6 for the display path: a module's mode reaches the canvas material
## the way a built-in one does, shader and all.
func test_a_module_mode_with_its_own_shader_reaches_the_canvas() -> void:
    var registries := _registries()
    var registry := registries.view_transforms
    var ctx := registries.context.for_module(THIRD_PARTY)
    var proof := _mode(&"proof")
    proof.shader = Shader.new()
    proof.shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 0.0, 1.0, 1.0); }\n"
    assert_true(ctx.register_view_transform(proof), "Registered")

    var canvas := SaCanvas.new()
    var easel := SaEasel.create_default(Vector2i(64, 64))
    canvas.easel = easel
    canvas.bind_view_transforms(registry)
    var mat := canvas.material as ShaderMaterial
    assert_not_null(mat, "The canvas has its view material")
    assert_eq(mat.shader, canvas.tonemap_shader, "and shows the picture with the built-in shader")

    registry.set_mode(&"proof")
    assert_eq(mat.shader, proof.shader, "The module's shader is what the canvas runs while its mode is active")
    registry.set_mode(&"hdr_heatmap")
    assert_eq(mat.shader, canvas.tonemap_shader, "A built-in mode is the built-in shader again")
    assert_eq(mat.get_shader_parameter("view_mode"), 2, "at the heatmap's value")
    registry.set_mode(SaViewTransformRegistry.NORMAL)
    assert_eq(mat.get_shader_parameter("view_mode"), 0, "and the picture is mode 0")

    canvas.free()
    easel.free()


func test_the_exposure_and_the_display_profile_reach_the_shader() -> void:
    var registries := _registries()
    var canvas := SaCanvas.new()
    var easel := SaEasel.create_default(Vector2i(64, 64))
    canvas.easel = easel
    canvas.bind_view_transforms(registries.view_transforms)
    var mat := canvas.material as ShaderMaterial

    assert_almost_eq(mat.get_shader_parameter("display_exposure"), 1.0, 0.0, "Off, the exposure is the identity")
    SaSettings.display_exposure_stops = 1.0
    registries.view_transforms.set_enabled(&"display_exposure", true)
    assert_almost_eq(mat.get_shader_parameter("display_exposure"), 2.0, 1e-6, "One stop on is a doubling")
    assert_true(SaSettings.display_exposure_enabled, "and the toggle's state lives in Preferences")

    assert_true(mat.get_shader_parameter("display_identity"), "An sRGB display is the identity, said outright")
    SaSettings.display_profile = "display_p3"
    assert_false(mat.get_shader_parameter("display_identity"), "A P3 display is not")
    var col0: Vector3 = mat.get_shader_parameter("display_col0")
    assert_true(not col0.is_equal_approx(Vector3(1, 0, 0)), "and the matrix moved off the identity")
    SaSettings.display_profile = "nowhere"
    assert_eq(
        SaSettings.display_profile, SaSettingsValues.display_profile_default(), "A profile nobody knows falls back to the default"
    )

    canvas.free()
    easel.free()


## The View menu lists what the registry holds once it is bound, and keeps
## the rolloff at the id the older suite reaches it by.
func test_the_view_menu_lists_the_registry_and_keeps_the_rolloff_id() -> void:
    var registries := _registries()
    var bar := TopMenuBar.new()
    bar._ready()
    var menu: SaViewMenu = bar.menu("View")
    menu.view_transforms = registries.view_transforms
    var popup: SaChoicePopup = bar.menus["View"]

    var texts := SaMenu.labels_of(popup)
    var named := ["Normal View", "Lightness Check", "False Colour", "Show Linear Values"]
    named.append_array(["Tonemap Highlights", "Display Exposure"])
    for expected: String in named:
        assert_true(texts.has(expected), "%s is on the menu" % expected)
    assert_true(menu.has_item(SaViewMenu.ID_TONEMAP), "The rolloff keeps ID_TONEMAP")

    menu.on_id_pressed(SaViewMenu.ID_MODE_BASE + 1)
    assert_eq(registries.view_transforms.mode, &"hdr_heatmap", "Clicking the second mode makes it the view")
    # The mark is the popup's own, so this asks the popup rather than
    # `SaMenuChoice`, which held the answer for a `PopupMenu` that had no way to
    # colour one row. The modes are a submenu's.
    popup = SaMenu.group_list(menu.popup, SaViewMenu.ID_MODE_GROUP)
    assert_eq(popup.current, SaMenu.key(SaViewMenu.ID_MODE_BASE + 1), "and its row is the marked one")
    assert_true(popup.current != SaMenu.key(SaViewMenu.ID_NORMAL_VIEW), "while Normal View is not")

    menu.on_id_pressed(SaViewMenu.ID_TONEMAP)
    assert_true(SaSettings.tonemap_highlights, "The rolloff item still writes the setting")

    bar.free()


## The three exposure nudges are one row that opens the page holding the
## slider, and the row writes nothing itself.
##
## The press is `emit.call_deferred`, so nothing here waits for it: a test that
## awaits drops every assertion after the await (a Godot trap), and the claim that
## needs a frame is `scenarios/exposure-is-the-slider-it-already-has.json`,
## which shoots Preferences open on Display. What is synchronous is asserted
## here: which rows the menu draws, that the press moves no setting, and that
## the signal has one listener and it is the Display page.
func test_the_exposure_row_opens_preferences_rather_than_nudging() -> void:
    var registries := _registries()
    var bar := TopMenuBar.new()
    bar._ready()
    var menu: SaViewMenu = bar.menu("View")
    menu.view_transforms = registries.view_transforms
    var popup: SaChoicePopup = bar.menus["View"]

    var texts := SaMenu.labels_of(popup)
    for gone: String in ["Exposure Up", "Exposure Down", "Reset Exposure"]:
        assert_false(texts.has(gone), "%s is off the View menu" % gone)
    assert_true(texts.has("Exposure Stops..."), "and one row that names the slider took their place")
    # Named apart from the registry's own "Display Exposure" check item, which
    # is the switch and is still its neighbour on the menu.
    assert_true(texts.has("Display Exposure"), "the toggle is untouched")

    var kept_stops := SaSettings.display_exposure_stops
    var kept_on := SaSettings.display_exposure_enabled
    SaSettings.display_exposure_stops = 1.25

    menu.on_id_pressed(SaViewMenu.ID_EXPOSURE)

    assert_almost_eq(SaSettings.display_exposure_stops, 1.25, 1e-6, "the row moves the setting by nothing")
    SaSettings.display_exposure_stops = kept_stops
    SaSettings.display_exposure_enabled = kept_on

    # The other end of the deferred emit, read the way the override tests read theirs,
    # because what has to hold is that the signal reaches the Display page at
    # all and the frame that carries it belongs to the scenario.
    var dialogs := FileAccess.get_file_as_string("res://ui/main/main_dialogs.gd")
    assert_true(
        dialogs.contains("EventBus.display_page_requested.connect(open_display_page)"), "MainDialogs listens for the request"
    )
    assert_true(
        dialogs.contains('open_preferences("Canvas and colour"'), "and answers it with the Display page, Canvas and colour now"
    )

    bar.free()


## The proof is a mode with the target gamut's matrices on the
## material, and the chord flips it, whichever window has focus.
func test_soft_proofing_is_a_mode_with_the_proof_gamut_on_the_material() -> void:
    var registries := _registries()
    var registry := registries.view_transforms
    assert_true(registry.has(&"soft_proof"), "The proof registered through the public API")
    assert_true(registry.has(&"gamut_warning"), "and its warning toggle")
    assert_eq(registry.get_descriptor(&"soft_proof").view_mode, 3, "as the shader's mode 3")

    var canvas := SaCanvas.new()
    var easel := SaEasel.create_default(Vector2i(64, 64))
    canvas.easel = easel
    canvas.bind_view_transforms(registry)
    var mat := canvas.material as ShaderMaterial

    SaSettings.proof_profile = "srgb"
    var col0: Vector3 = mat.get_shader_parameter("proof_col0")
    assert_true(col0.is_equal_approx(Vector3(1, 0, 0)), "Proofing through sRGB is the identity matrix")
    SaSettings.proof_profile = "display_p3"
    col0 = mat.get_shader_parameter("proof_col0")
    var back0: Vector3 = mat.get_shader_parameter("proof_back_col0")
    assert_true(not col0.is_equal_approx(Vector3(1, 0, 0)), "and through P3 it is not")
    assert_true(not back0.is_equal_approx(col0), "with the way back a different matrix")
    SaSettings.proof_profile = "srgb"

    registry.set_enabled(&"gamut_warning", true)
    assert_true(mat.get_shader_parameter("proof_gamut_warning"), "The warning toggle reaches the shader")
    registry.set_enabled(&"gamut_warning", false)

    canvas.free()
    easel.free()
