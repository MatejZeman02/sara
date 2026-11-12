## Shift+W turns Wrap Around on in the Krita profile, and the
## Pop-up Palette leaves the chord to it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Krita profile gives wrap Krita's own Shift+W, with the Pop-up Palette on
## another chord in that profile. Shift+W is Wrap Around Mode in Krita and the
## palette's toggle in Sara's own map.
##
## A profile is applied the way Quick settings applies it,
## and the chord is pressed through a real router over the app's own commands.
## The wrap command reads the document of the context's easel, there being no
## front canvas in a suite, and the docker doors are the suite's, which write
## down every docker they are asked to show.
extends "res://tests/test_framework.gd"

## The easel's document lives on the device.
const REQUIRES_GPU := true

const PALETTE := &"docker_palette"

var _kept_profile: String = ""
var _registries: SaRegistries = null
var _host: Node = null
var _router: ShortcutRouter = null
var _easel: SaEasel = null
## The dockers the toggle door and the summon door were asked for, in order.
var _toggled: Array[StringName] = []
var _summoned: Array[StringName] = []


func before_each() -> void:
    _kept_profile = SaSettings.shortcuts_profile
    _toggled.clear()
    _summoned.clear()
    _easel = SaEasel.create_default(Vector2i(64, 64), null, SaColorSpace.srgb())
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _easel, func() -> Array: return [])
    _registries.register_builtins()
    SaAppCommands.register_all(
        _registries,
        func(docker_id: StringName) -> void: _toggled.append(docker_id),
        Callable(),
        func(docker_id: StringName) -> void: _summoned.append(docker_id)
    )
    SaShortcutStore.capture_defaults()
    _host = Node.new()
    _host.name = "U518TestHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.name = "U518Router"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)


func after_each() -> void:
    _apply("default" if _kept_profile.is_empty() else _kept_profile)
    SaSettings.shortcuts_profile = _kept_profile
    if _host != null:
        _host.free()
        _host = null
        _router = null
    if _easel != null:
        _easel.free()
        _easel = null
    _registries = null


## The profile applied as Quick settings applies it.
func _apply(profile: String) -> void:
    SaSettings.shortcuts_profile = profile
    SaShortcutStore.apply_profile(profile)
    EventBus.shortcuts_changed.emit()


func _press_shift_w() -> void:
    var key := InputEventKey.new()
    key.keycode = KEY_W
    key.physical_keycode = KEY_W
    key.shift_pressed = true
    key.pressed = true
    _router.handle_viewport_input(key, (Engine.get_main_loop() as SceneTree).root)


func _wraps() -> bool:
    return _easel.document.projection.wrapping != SaProjection.Wrap.NONE


func test_shift_w_under_krita_turns_the_wrap_on_and_off_and_shows_no_palette() -> void:
    _apply("Krita")
    assert_eq(SaShortcutStore.chords_for(SaTopBarPageEdgesCommand.COMMAND), ["Shift+W"], "the wrap holds Shift+W under Krita")
    assert_false(_wraps(), "a fresh document does not wrap")
    _press_shift_w()
    assert_true(_wraps(), "Shift+W turns the wrap on")
    assert_eq(_easel.document.projection.wrapping, SaProjection.Wrap.XY, "at every edge, the icon keeping no last choice")
    _press_shift_w()
    assert_false(_wraps(), "and again turns it off")
    assert_eq(_toggled, [] as Array[StringName], "no docker was toggled, the Pop-up Palette least of all")
    assert_eq(_summoned, [] as Array[StringName], "and none was summoned")


func test_the_palette_keeps_its_chords_where_the_profile_says() -> void:
    _apply("Krita")
    assert_eq(SaShortcutStore.chords_for(PALETTE), [], "the palette's toggle is unbound under Krita")
    assert_eq(
        SaShortcutStore.chords_for(SaAppCommands.summon_id(PALETTE)),
        ["Alt+Shift+W"],
        "and its summon still answers Alt+Shift+W",
    )
    assert_eq(SaShortcutStore.chords_for(SaAppCommands.locked_summon_id(PALETTE)), [], "the locked twin unbound as before")
    # Photoshop's map takes every docker toggle off Shift and a letter,
    # so the palette's is unbound there too, and the wrap is as well.
    _apply("Photoshop")
    assert_eq(SaShortcutStore.chords_for(PALETTE), [], "the palette's toggle is unbound under Photoshop")
    assert_eq(SaShortcutStore.chords_for(SaTopBarPageEdgesCommand.COMMAND), [], "and the wrap unbound under Photoshop")
    _apply("default")
    assert_eq(SaShortcutStore.chords_for(PALETTE), [], "the palette's toggle holds no chord under Sara's own map")
    assert_eq(SaShortcutStore.chords_for(SaTopBarPageEdgesCommand.COMMAND), [], "and the wrap unbound there")
    _press_shift_w()
    assert_eq(_toggled, [] as Array[StringName], "Shift+W under Sara's own map shows no palette, it steps the wand's family")
    assert_false(_wraps(), "and leaves the wrap alone")


func test_a_panorama_refuses_the_wrap_and_says_why() -> void:
    _apply("Krita")
    _easel.document.projection = SaProjection.new(SaProjection.Equirectangular.new())
    var before := _easel.document.projection.wrapping
    _press_shift_w()
    assert_eq(_easel.document.projection.wrapping, before, "a panorama's wrap is its kind's and the chord leaves it")
    assert_eq(SaTopBarPageEdgesCommand.wraps(null), false, "and no document wraps nothing")
