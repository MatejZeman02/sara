## The zoom reads as the picture's size on screen, and Ctrl+0
## does what the painter set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling of 2026-10-03: "we need two percentages. One that tells
## about the pixels, and second that tells about 'zoom level'." Zoom is the
## picture against the whole picture fitted into the free rectangle, so 100% is
## the fit whatever the resolution, and Pixels is device pixels a texel. Ctrl+0
## is Reset Zoom and shows what `SaSettings.reset_zoom` names, the whole picture
## at `reset_zoom_size` per cent or actual pixels, and Ctrl+1 is actual pixels
## whatever the row says. Every one of them centres the picture in the free
## rectangle, and so do the zoom chords that come after them.
##
## The views here are fakes with a window's size, an interface scale and a free
## rectangle narrower than the window, which is what a docker column makes of
## it. The running app at an interface scale of 2 and at 1920 by 1080 is
## `scenarios/the-zoom-reads-as-the-picture-s-size-on-screen.json`.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A painter's note: a 670 by 335 picture on a 3840 by 2160 screen at an
## interface scale of 2, which is 1920 by 1080 logical units.
const SMALL := Vector2i(670, 335)
const LARGE := Vector2i(4000, 3000)

## The room the default dockers and both bars leave on that screen, read off
## the running app: the top bar to y 64, the status line from 1056, the left
## column to x 380 and the right one from 1600.
const COLUMNS := Rect2(380.0, 64.0, 1220.0, 992.0)

static var scratch_dir: String = SaDataRoot.path("test_n5_the_zoom")

var _host: Node = null
var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []
var _saved_profile: String = ""
var _commands_built: bool = false


## A view on a 1920 by 1080 window at an interface scale, with the free
## rectangle a test sets, the window's whole area until one does.
class RoomView:
    extends SaTestFixtures.FakeView

    var content_scale: float = 2.0
    var free: Rect2 = Rect2()

    func _init() -> void:
        super()
        viewport_size = Vector2(1920.0, 1080.0)

    func get_content_scale() -> float:
        return content_scale

    func get_free_rect() -> Rect2:
        return free if free.has_area() else get_visible_rect()


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "N5TestHost"
    EventBus.add_child(_host)
    SaSettings.reset_zoom = SaView.RESET_WHOLE
    SaSettings.reset_zoom_size = SaView.RESET_SIZE


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaSettings.reset_zoom = SaView.RESET_WHOLE
    SaSettings.reset_zoom_size = SaView.RESET_SIZE


func _room(free: Rect2 = Rect2()) -> RoomView:
    var view := RoomView.new()
    view.free = free
    return view


## The picture's rectangle on screen, unturned and unflipped.
func _shown(view: SaView, document: Vector2i) -> Rect2:
    return Rect2(view.get_pan(), Vector2(document) * view.get_zoom())


## The middle a chord zooms about and a placement centres on.
func _middle(view: SaView) -> Vector2:
    return view.get_free_rect().get_center()


## The Pixels figure, device pixels a texel, as the status line reads it.
func _pixels(view: SaView) -> float:
    return view.get_zoom() / view.actual_pixel_zoom() * 100.0


## The picture's middle against the free rectangle's, through the whole
## transform so a mirrored or turned view reads the same.
func _assert_centred(view: SaView, document: Vector2i, what: String) -> void:
    var middle := view.document_to_screen(Vector2(document) * 0.5)
    var free := view.get_free_rect().get_center()
    # Within a device pixel, which is half a logical unit at a scale of 2.
    var device := 1.0 / view.get_content_scale()
    assert_almost_eq(middle.x, free.x, device, "%s: centred across the free rectangle" % what)
    assert_almost_eq(middle.y, free.y, device, "%s: and down it" % what)


func test_zoom_is_the_picture_against_its_fit_and_pixels_against_the_screen() -> void:
    for document: Vector2i in [SMALL, LARGE]:
        var view := _room()
        view.fit(document)
        assert_almost_eq(view.zoom_per_cent(document), 100.0, 1e-4, "Fit to View reads Zoom 100%% on %s" % document)
        assert_eq(SaStatusLine.zoom_text(view, document), "Zoom 100%", "and the status line says so")
        view.zoom_by(2.0, _middle(view))
        assert_almost_eq(view.zoom_per_cent(document), 200.0, 1e-4, "twice the fit reads 200%")
        view.zoom_by(0.25, _middle(view))
        assert_almost_eq(view.zoom_per_cent(document), 50.0, 1e-4, "and half of it 50%")

    # The same picture at four times the resolution reads the same Zoom when it
    # fills the same room, and a quarter of the Pixels.
    var low := _room()
    low.fit(SMALL)
    var high := _room()
    high.fit(SMALL * 4)
    assert_almost_eq(high.zoom_per_cent(SMALL * 4), low.zoom_per_cent(SMALL), 1e-4, "Zoom is not about the resolution")
    assert_almost_eq(_pixels(high), _pixels(low) / 4.0, 1e-4, "Pixels is")


func test_pixels_is_one_texel_on_one_device_pixel_at_every_scale() -> void:
    for scale: float in [1.0, 1.25, 2.0]:
        var view := _room()
        view.content_scale = scale
        view.zoom_to_actual_pixels(_middle(view))
        assert_almost_eq(_pixels(view), 100.0, 1e-4, "Actual pixels read Pixels 100%% at %.2f" % scale)
        assert_eq(SaStatusLine.pixels_text(view), "Screen 100%", "and the status line says so at %.2f" % scale)
        assert_almost_eq(view.get_zoom() * scale, 1.0, 1e-6, "which is one device pixel a texel")


## The setting's three outcomes the note names: the whole picture a bit zoomed
## out, the whole picture a bit zoomed in, and actual pixels.
func test_ctrl_0_at_the_default_shows_the_whole_picture_with_a_margin_at_90() -> void:
    for document: Vector2i in [SMALL, LARGE]:
        var view := _room(COLUMNS)
        view.reset(document)
        assert_almost_eq(view.zoom_per_cent(document), 90.0, 1e-4, "Ctrl+0 at the default reads Zoom 90%% on %s" % document)
        assert_eq(SaStatusLine.zoom_text(view, document), "Zoom 90%", "and the status line says so")
        assert_true(COLUMNS.encloses(_shown(view, document)), "The whole picture is in the free rectangle")
        assert_false(_shown(view, document).is_equal_approx(COLUMNS), "with a margin round it")
        _assert_centred(view, document, "Ctrl+0 at 90")


func test_a_size_of_110_lets_the_picture_overflow_a_little() -> void:
    SaSettings.reset_zoom_size = 110
    for document: Vector2i in [SMALL, LARGE]:
        var view := _room(COLUMNS)
        view.reset(document)
        assert_almost_eq(view.zoom_per_cent(document), 110.0, 1e-4, "Ctrl+0 at 110 reads Zoom 110%% on %s" % document)
        var shown := _shown(view, document)
        assert_false(COLUMNS.encloses(shown), "The picture overflows the free rectangle")
        var over := maxf(shown.size.x / COLUMNS.size.x, shown.size.y / COLUMNS.size.y)
        assert_almost_eq(over, 1.1, 1e-4, "by a tenth along its tighter axis")
        _assert_centred(view, document, "Ctrl+0 at 110")


func test_a_row_set_to_actual_pixels_resets_to_pixels_100() -> void:
    SaSettings.reset_zoom = SaView.RESET_PIXELS
    for document: Vector2i in [SMALL, LARGE]:
        var view := _room(COLUMNS)
        view.zoom = 3.0
        view.reset(document)
        assert_almost_eq(_pixels(view), 100.0, 1e-4, "Ctrl+0 at actual pixels reads Pixels 100%% on %s" % document)
        _assert_centred(view, document, "Ctrl+0 at actual pixels")


func test_the_setting_keeps_to_its_two_answers_and_its_bounds() -> void:
    SaSettings.reset_zoom = "fit"
    assert_eq(SaSettings.reset_zoom, SaView.RESET_WHOLE, "An answer the row does not offer reads as the whole picture")
    SaSettings.reset_zoom_size = 10
    assert_eq(SaSettings.reset_zoom_size, SaView.RESET_SIZE_MIN, "The Size stops at 25")
    SaSettings.reset_zoom_size = 900
    assert_eq(SaSettings.reset_zoom_size, SaView.RESET_SIZE_MAX, "and at 200")
    assert_eq(SaView.RESET_SIZE, 90, "and is 90 on a fresh profile, a painter's a bit zoomed out")
    assert_eq(SaSettingsKeys.place_of(&"reset_zoom"), ["ui", "reset_zoom"], "The row is kept in the profile")
    assert_eq(SaSettingsKeys.place_of(&"reset_zoom_size"), ["ui", "reset_zoom_size"], "and so is its Size")


## The centre is the free rectangle's, not the window's, for every placement and
## for the chords pressed after one. The note's shot had the picture centred on
## the whole window and running under the dockers.
func test_every_placement_centres_the_picture_in_a_narrowed_free_rectangle() -> void:
    var narrowed: Array[Rect2] = [COLUMNS, Rect2(0.0, 64.0, 1600.0, 992.0), Rect2(380.0, 40.0, 1540.0, 1016.0)]
    for free: Rect2 in narrowed:
        var view := _room(free)
        view.reset(SMALL)
        _assert_centred(view, SMALL, "Ctrl+0 in %s" % free)
        view.fit(SMALL)
        _assert_centred(view, SMALL, "F in %s" % free)
        view.zoom_to_actual_pixels(_middle(view))
        view.center(SMALL)
        _assert_centred(view, SMALL, "Ctrl+1 in %s" % free)

        # A painter's own habit, Ctrl+0 and then a step or two out.
        view.reset(SMALL)
        for step in 6:
            view.zoom_by(1.0 / SaView.ZOOM_STEP, _middle(view))
        _assert_centred(view, SMALL, "Six steps out after Ctrl+0 in %s" % free)
        view.flip_view(true)
        _assert_centred(view, SMALL, "and a mirror after them")


## A docker column opening leaves the picture where it is and moves the Zoom
## figure, and Ctrl+0 then shows the whole picture beside the column.
func test_a_docker_column_opening_moves_the_figure_and_not_the_picture() -> void:
    var view := _room()
    view.reset(SMALL)
    var before := _shown(view, SMALL)
    var figure := view.zoom_per_cent(SMALL)
    assert_almost_eq(figure, 90.0, 1e-4, "With no dockers Ctrl+0 reads 90%")

    view.free = Rect2(0.0, 64.0, 1600.0, 992.0)
    assert_true(_shown(view, SMALL).is_equal_approx(before), "A column on the right leaves the picture where it was")
    assert_true(view.zoom_per_cent(SMALL) > figure, "and the figure grows, the fit it is read against having shrunk")

    view.reset(SMALL)
    assert_true(view.free.encloses(_shown(view, SMALL)), "Ctrl+0 then shows the whole picture beside the column")
    _assert_centred(view, SMALL, "Ctrl+0 beside the column")


## A fit taken again after a change of interface scale lands on the share it
## was taken at, so Ctrl+0's 90 stays 90 and Fit to View's 100 stays 100, and
## actual pixels stay actual.
func test_a_change_of_interface_scale_keeps_each_placement() -> void:
    var view := _room()
    view.reset(SMALL)
    view.content_scale = 1.0
    view.follow_scale(SMALL, 2.0, 1.0)
    assert_almost_eq(view.zoom_per_cent(SMALL), 90.0, 1e-4, "Ctrl+0's 90 after the scale moves")
    view.fit(SMALL)
    view.content_scale = 2.0
    view.follow_scale(SMALL, 1.0, 2.0)
    assert_almost_eq(view.zoom_per_cent(SMALL), 100.0, 1e-4, "Fit to View's 100 after it moves back")

    SaSettings.reset_zoom = SaView.RESET_PIXELS
    view.reset(SMALL)
    view.content_scale = 1.0
    view.follow_scale(SMALL, 2.0, 1.0)
    assert_almost_eq(_pixels(view), 100.0, 1e-4, "and actual pixels after the scale moves")


## A new document opens the way Ctrl+0 shows it, on a real canvas.
func test_a_new_document_opens_the_way_ctrl_0_shows_it() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    var view := SaCanvasView.for_canvas(canvas)

    canvas.scale = Vector2(9.0, 9.0)
    canvas.resize_canvas(Vector2i(256, 256))
    assert_almost_eq(view.zoom_per_cent(Vector2i(256, 256)), 90.0, 1e-3, "A 256 square opens at Zoom 90%")
    var middle := canvas.position + Vector2(128.0, 128.0) * canvas.scale.x
    assert_almost_eq(middle.x, 400.0, 1e-3, "centred across")
    assert_almost_eq(middle.y, 300.0, 1e-3, "and down")

    canvas.resize_canvas(LARGE)
    assert_almost_eq(view.zoom_per_cent(LARGE), 90.0, 1e-3, "and a 4000 by 3000 one at Zoom 90% as well")

    SaSettings.reset_zoom = SaView.RESET_PIXELS
    canvas.resize_canvas(SMALL)
    assert_almost_eq(_pixels(view), 100.0, 1e-3, "With the row at actual pixels it opens at Pixels 100%")


## Ctrl+0 through the router does what the row says, and Ctrl+1 is actual
## pixels with the row at either answer, on the digit row and on the numpad.
func test_the_two_chords() -> void:
    var surface := Fixtures.make_surface(SMALL)
    var view := surface.view as SaTestFixtures.FakeView
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.surface = surface
    machine.register_tool(&"fake", SaTestFixtures.FakeTool.new())
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    router.bind_commands(SaCommandRegistry.new())

    view.zoom = 7.0
    assert_true(router.handle(_chord(KEY_0)), "Ctrl+0 is taken")
    assert_almost_eq(view.zoom_per_cent(SMALL), 90.0, 1e-4, "and shows the whole picture at 90")
    assert_true(router.handle(_chord(KEY_1)), "Ctrl+1 is taken")
    assert_almost_eq(_pixels(view), 100.0, 1e-4, "and shows actual pixels")
    _assert_centred(view, SMALL, "Ctrl+1")

    SaSettings.reset_zoom = SaView.RESET_PIXELS
    view.zoom = 7.0
    router.handle(_chord(KEY_KP_0))
    assert_almost_eq(_pixels(view), 100.0, 1e-4, "With the row at actual pixels, the numpad's Ctrl+0 is Pixels 100%")
    view.zoom = 7.0
    router.handle(_chord(KEY_KP_1))
    assert_almost_eq(_pixels(view), 100.0, 1e-4, "and so is the numpad's Ctrl+1, with the row at either answer")

    router.free()
    Fixtures.teardown(surface, machine)


## Ctrl+1 was free in the shipped set and in Krita's before Actual Pixels took
## it, and each shipped profile gives Actual Pixels Ctrl+1 and Reset Zoom
## Ctrl+0 with nothing else on either.
func test_ctrl_1_is_actual_pixels_and_nothing_else_in_every_shipped_profile() -> void:
    _save_input_map()
    for profile: String in [SaShortcutStore.DEFAULT_PROFILE, "Krita", "Photoshop"]:
        SaShortcutStore.apply_profile(profile)
        assert_true(SaShortcutStore.chords_for(&"view_actual_pixels").has("Ctrl+1"), "%s: Ctrl+1 is Actual Pixels" % profile)
        var taken := SaShortcutStore.conflicts("Ctrl+1", &"view_actual_pixels")
        assert_eq(taken, [] as Array[String], "%s: and nothing else" % profile)
        assert_true(SaShortcutStore.chords_for(&"view_zoom_100").has("Ctrl+0"), "%s: Ctrl+0 is Reset Zoom" % profile)
        assert_eq(SaShortcutStore.conflicts("Ctrl+0", &"view_zoom_100"), [] as Array[String], "%s: and nothing else" % profile)
    for action: String in SaShortcutKritaTable.CHORDS:
        var chords := SaShortcutStore.entry_chords(SaShortcutKritaTable.CHORDS[action])
        assert_false(chords.has("Ctrl+1"), "Krita's table puts no Ctrl+1 of its own on %s" % action)
    _restore_input_map()


func _chord(keycode: int) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode as Key
    key.physical_keycode = keycode as Key
    key.ctrl_pressed = true
    key.pressed = true
    return key


## `main.gd`'s startup as far as the `InputMap` is concerned, the way
## `core/registry/tests/test_the_numpad_chords_in_two_steps.gd` builds it, and
## the map and the profile saved round it for the reason that suite gives.
func _save_input_map() -> void:
    if not _commands_built:
        _commands_built = true
        var registries := Fixtures.make_registries()
        SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
        var router := ShortcutRouter.new()
        router.bind_commands(registries.commands)
        router.free()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


func _restore_input_map() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)
