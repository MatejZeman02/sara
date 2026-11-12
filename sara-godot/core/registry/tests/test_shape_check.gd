## the shape check: the view mode that averages the canvas into blocks and
## snaps the lightness to the painter's count of steps, five unless set, so a
## silhouette reads without its detail.
##
## A painter's note of 2026-09-09 asked for "one tool to judge a shape:
## downscale and upscale the canvas, or quantize it", and the old backlog had already
## placed it as "a canvas view toggle, not a filter". A view mode, then, and the
## whole weight of that placement is the third case below: a mode may not move a
## texel of the document, whatever it does to the picture on the screen.
##
## The scenario `scenarios/the-shape-check.json` is the picture. This is what
## a picture cannot show: which number the shader branches on, that the chord
## names this mode and not a preference, and that the document is untouched.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")
const SHADER_PATH := "res://shaders/canvas/tonemap.gdshader"
const SHAPE_CHECK := &"shape_check"

## The mode's number, which lives in three places on purpose: here, the
## descriptor in `core/loader/skeleton_module.gd` and the branch in the shader.
## Two of the three are asserted against each other below, which is the most a
## test without a GPU readback of the screen can do about the third.
const SHAPE_VIEW_MODE := 5

## A canvas builds an easel, and the texel cases read what a fill wrote.
const REQUIRES_GPU := true

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "ShapeCheckTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


func test_the_skeleton_registers_the_shape_check_as_a_mode() -> void:
    var registry := _registries().view_transforms
    assert_true(registry.has(SHAPE_CHECK), "the shape check came through the same door a module's mode uses")
    var descriptor := registry.get_descriptor(SHAPE_CHECK)
    assert_eq(descriptor.kind, SaViewTransformDescriptor.Kind.MODE, "a mode, so it is one of a choice")
    assert_eq(descriptor.view_mode, SHAPE_VIEW_MODE, "and the shader branch it asks for")
    assert_eq(descriptor.display_name, "Shape Check", "named as the View menu shows it")
    assert_false(descriptor.tooltip.is_empty(), "with a sentence, the way every mode beside it has one")
    assert_null(descriptor.shader, "and no shader of its own: the canvas shader implements it")


## The one place the GDScript number and the GLSL number have to agree, and the
## file is read rather than reasoned about. A mode registered at 5 whose branch
## was written as 6 shows the ordinary picture and fails nothing else.
func test_the_shader_branches_on_the_number_the_descriptor_registers() -> void:
    var text := FileAccess.get_file_as_string(SHADER_PATH)
    assert_false(text.is_empty(), "the canvas shader is where it was")
    var branch := "view_mode == %d" % SHAPE_VIEW_MODE
    assert_eq(text.count(branch), 2, "the downscale reads it and the quantize reads it, and nothing else does")
    for name: String in ["shape_check_across", "SHAPE_CHECK_TAPS", "shape_check_level_count", "SHAPE_CHECK_MASS_STEPS"]:
        assert_true(text.contains("const"), "the shader still declares constants")
        assert_true(text.contains(name), "%s is the number the mode is built from" % name)


## The whole reason the note said a view toggle and not a filter. A filter
## rewrites the layer, and a painter judging a shape wants the painting back
## untouched when the check goes off.
func test_the_toggle_leaves_every_texel_of_the_layer_where_it_was() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var registries := Fixtures.make_registries(surface)
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel
    var doc := surface.easel.document

    var was := SaColors.foreground
    SaColors.foreground = Color(0.25, 0.5, 0.75, 1.0)
    assert_true(registries.commands.execute(&"fill_foreground"), "there is a painting to judge")

    var before := TexelProbe._read_point(doc, canvas, Vector2i(10, 10))
    var registry := registries.view_transforms
    assert_true(registry.set_mode(SHAPE_CHECK), "the check goes on")
    var during := TexelProbe._read_point(doc, canvas, Vector2i(10, 10))
    assert_true(registry.set_mode(SaViewTransformRegistry.NORMAL), "and off again")
    var after := TexelProbe._read_point(doc, canvas, Vector2i(10, 10))

    for channel: String in ["r", "g", "b", "a"]:
        assert_almost_eq(during["layer"][channel], before["layer"][channel], 1e-6, "%s moved while the check was on" % channel)
        assert_almost_eq(after["layer"][channel], before["layer"][channel], 1e-6, "%s moved when it went off" % channel)

    canvas.free()
    SaColors.foreground = was
    Fixtures.teardown(surface)


## F3, the note's "or" turned into the painter's choice, and the method
## beside Blocks. One case per method, with the posterise on and off: the
## material carries the method's number and the switch the settings name, and
## the layer is untouched by every one of them, which is what makes these rows
## and not a filter.
##
## The shader is read rather than reasoned about, because a uniform the canvas
## writes and the shader never declares is a parameter that goes nowhere, and
## nothing else fails when it does.
func test_each_shape_check_value_reaches_the_material_and_moves_no_texel() -> void:
    var text := FileAccess.get_file_as_string(SHADER_PATH)
    for uniform: String in SaSettings.shape_check_uniforms():
        var declared := RegEx.create_from_string("uniform \\w+ %s =" % uniform)
        assert_not_null(declared.search(text), "the shader declares %s" % uniform)

    var was_color := SaColors.foreground
    var was_method := SaSettings.shape_check_method
    var was_levels := SaSettings.shape_check_levels
    SaColors.foreground = Color(0.25, 0.5, 0.75, 1.0)

    for value: String in SaSettings.SHAPE_METHODS:
        for levels: bool in [true, false]:
            var surface := Fixtures.make_surface(Vector2i(256, 256))
            var registries := Fixtures.make_registries(surface)
            var canvas := SaCanvas.new()
            canvas.easel = surface.easel
            var doc := surface.easel.document
            assert_true(registries.commands.execute(&"fill_foreground"), "%s: there is a painting to judge" % value)
            var before := TexelProbe._read_point(doc, canvas, Vector2i(10, 10))

            SaSettings.shape_check_method = value
            SaSettings.shape_check_levels = levels
            canvas.sync_tonemap()
            var material := canvas.material as ShaderMaterial
            assert_not_null(material, "%s: the view has a material" % value)
            assert_eq(
                material.get_shader_parameter("shape_check_method"),
                SaSettings.SHAPE_METHODS.find(value),
                "%s: the material carries the method's number" % value
            )
            assert_eq(material.get_shader_parameter("shape_check_levels"), levels, "%s: and the posterise switch" % value)

            var after := TexelProbe._read_point(doc, canvas, Vector2i(10, 10))
            for channel: String in ["r", "g", "b", "a"]:
                assert_almost_eq(after["layer"][channel], before["layer"][channel], 1e-6, "%s: %s moved" % [value, channel])

            canvas.free()
            Fixtures.teardown(surface)

    SaSettings.shape_check_method = was_method
    SaSettings.shape_check_levels = was_levels
    SaColors.foreground = was_color


## The mode is a property of the view and not of the frame, so turning the paper
## or leaning in must not put the picture back. Both are written through
## `SaCanvasView`, which is what the canvas's zoom and rotation actually are.
func test_the_mode_survives_a_zoom_and_a_rotate() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)

    var registry := _registries().view_transforms
    canvas.bind_view_transforms(registry)
    assert_true(registry.set_mode(SHAPE_CHECK), "the check goes on")
    var material := canvas.material as ShaderMaterial
    assert_eq(material.get_shader_parameter("view_mode"), SHAPE_VIEW_MODE, "and reaches the canvas material")

    var view := SaCanvasView.for_canvas(canvas)
    view.set_zoom(3.5)
    view.set_rotation(deg_to_rad(30.0))
    canvas.sync_tonemap()

    assert_eq(registry.mode, SHAPE_CHECK, "a zoom and a rotate are not a request to stop checking")
    assert_eq(material.get_shader_parameter("view_mode"), SHAPE_VIEW_MODE, "and the material still says so")
    assert_almost_eq(view.get_zoom(), 3.5, 1e-4, "the zoom did land")
    assert_almost_eq(view.get_rotation(), deg_to_rad(30.0), 1e-4, "and the rotation with it")


## Ctrl+Shift+Q names this mode outright. Ctrl+Y beside it names whatever the
## Canvas proof preference holds, which is the ruling and not this chord's.
func test_the_chord_names_the_shape_check_itself() -> void:
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    var modes := _registries().view_transforms
    var registry := SaCommandRegistry.new()
    router.bind_commands(registry, modes)

    assert_true(registry.has(&"view_shape_check"), "the chord is a command like every other")
    var event := InputEventKey.new()
    event.keycode = KEY_Q
    event.physical_keycode = KEY_Q
    event.ctrl_pressed = true
    event.shift_pressed = true
    event.pressed = true
    assert_true(router.handle(event), "Ctrl+Shift+Q is consumed")
    assert_eq(modes.mode, SHAPE_CHECK, "and asks for this mode by name")

    var was := SaSettings.canvas_proof_mode
    SaSettings.canvas_proof_mode = "lightness_check"
    modes.set_mode(SaViewTransformRegistry.NORMAL)
    router.handle(event)
    assert_eq(modes.mode, SHAPE_CHECK, "a preference that moves the proof chord does not move this one")
    SaSettings.canvas_proof_mode = was
    router.free()


## A mode row shows its chord when a command answers for exactly that mode, and
## the soft proof's row shows none, because Ctrl+Y follows a preference and a
## row that draws a chord it cannot honour is worse than a bare row.
func test_the_menu_row_shows_the_chord_and_the_proof_row_does_not() -> void:
    var registries := _registries()
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    router.bind_commands(registries.commands)

    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("View") as SaViewMenu
    assert_not_null(menu, "the View menu is one of the bar's")
    bar.bind_commands(registries.commands)
    menu.view_transforms = registries.view_transforms

    var chord := registries.commands.chord_text(&"view_shape_check")
    assert_false(chord.is_empty(), "the command answers to a key")
    assert_eq(_row_text(menu, "Shape Check"), "Shape Check", "the label is the mode's name alone")
    assert_eq(_row_hint(menu, "Shape Check"), chord, "and the chord column says which key")
    assert_eq(_row_hint(menu, "Soft Proof"), "", "while the proof row's column stays empty")
    bar.free()
    router.free()


## The label of the row whose text starts with *name*, or "" for no such row.
##
## Off `row_labels()` rather than off `item_count` and `get_item_text`, which
## is what a `PopupMenu` answered and what this suite was written against. A row is a
## `Button` and the menu a `SaChoicePopup`, so the suite reads the row's own text.
func _row_text(menu: SaViewMenu, name: String) -> String:
    for text in SaMenu.labels_of(menu.popup):
        if text.begins_with(name):
            return text
    return ""


## The chord column of the row whose label starts with *name*, or "" for no
## such row. A mode's chord sits in
## that column, the one every other row of the menus writes it in, not in its label.
func _row_hint(menu: SaViewMenu, name: String) -> String:
    for list: SaChoicePopup in SaMenu.lists_of(menu.popup):
        for id: StringName in list.row_ids():
            var row := list.row_of(id)
            if row != null and row.label_button().text.begins_with(name):
                return row.hint_text()
    return ""
