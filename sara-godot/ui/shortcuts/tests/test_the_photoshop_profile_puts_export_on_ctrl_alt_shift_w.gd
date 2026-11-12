## The Photoshop profile puts Export on Ctrl+Alt+Shift+W, and
## the Pop-up Palette's locked summon leaves that chord to it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Photoshop's Alt+Shift+Ctrl+W for Export As did nothing in the Photoshop
## layout. Sara spells that chord
## Ctrl+Alt+Shift+W, which on Sara's own map is the palette's locked summon.
##
## A profile is applied the way Quick settings applies it, the three lines of
## `SaComingFromRow._apply`: the setting, `apply_profile` and the bus's
## `shortcuts_changed`. The chord is pressed through a real router over the
## app's commands, and Export's own handler runs, which finds the files flow
## the way main holds it, a child of the current scene, and opens the real
## Export dialog over a canvas of the suite's own.
extends "res://tests/test_framework.gd"

## The Export dialog's page draws a preview of the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const EXPORT := &"file_export"
const PALETTE := &"docker_palette"

var _kept_profile: String = ""
var _kept_embedding: bool = true
var _registries: SaRegistries = null
## Held for the run, because Export's handler is bound to the menu commands
## this object builds, and `Fixtures.make_menu_registries` keeps none.
var _shortcut_commands: SaShortcutCommands = null
var _host: Node = null
var _router: ShortcutRouter = null
var _canvas: SaCanvas = null
var _flow: SaDocumentFiles = null


func before_each() -> void:
    _kept_profile = SaSettings.shortcuts_profile
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _registries = Fixtures.make_registries()
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _shortcut_commands = SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    _shortcut_commands.register_into(_registries.commands)
    SaShortcutStore.capture_defaults()
    _host = Node.new()
    _host.name = "U504TestHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.name = "U504Router"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.easel = SaEasel.create_default(_canvas.canvas_size, null, SaColorSpace.srgb())
    _canvas.add_child(_canvas.easel)
    _canvas.document.fill_layer(Color(0.5, 0.5, 0.5, 1.0))
    _flow = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)
    if tree.current_scene != null and SaDocumentFiles.in_tree(tree) == null:
        tree.current_scene.add_child(_flow)


func after_each() -> void:
    _apply("default" if _kept_profile.is_empty() else _kept_profile)
    SaSettings.shortcuts_profile = _kept_profile
    var tree := Engine.get_main_loop() as SceneTree
    if _flow != null:
        _flow.free()
        _flow = null
    if _host != null:
        _host.free()
        _host = null
        _router = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    _shortcut_commands = null
    _registries = null
    tree.root.gui_embed_subwindows = _kept_embedding


## The profile applied as Quick settings applies it.
func _apply(profile: String) -> void:
    SaSettings.shortcuts_profile = profile
    SaShortcutStore.apply_profile(profile)
    EventBus.shortcuts_changed.emit()


static func _chord_of_the_twin() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_W
    key.physical_keycode = KEY_W
    key.ctrl_pressed = true
    key.alt_pressed = true
    key.shift_pressed = true
    key.pressed = true
    return key


func _locked() -> StringName:
    return SaAppCommands.locked_summon_id(PALETTE)


func _export_dialog_open() -> bool:
    for child: Node in _flow.get_children():
        if child is SaExportDialog:
            return (child as Window).visible
    return false


func test_photoshop_puts_export_on_the_chord_and_clears_the_twin() -> void:
    _apply("Photoshop")
    assert_eq(SaShortcutStore.chords_for(EXPORT), ["Ctrl+Alt+Shift+W"], "Export holds Ctrl+Alt+Shift+W under Photoshop")
    assert_eq(SaShortcutStore.chords_for(_locked()), [], "the palette's locked summon holds no chord")
    assert_eq(
        SaShortcutStore.conflicts("Ctrl+Alt+Shift+W", EXPORT),
        [],
        "and nothing else answers to the chord",
    )
    # The palette's own summon is what it was under this profile as it is under every profile:
    # the store leaves every summon unbound in a shipped Krita or Photoshop map
    # (`SUMMON_PREFIX`), and the Export chord changes neither the summon nor that rule.
    assert_eq(
        SaShortcutStore.chords_for(SaAppCommands.summon_id(PALETTE)),
        [],
        "the palette's summon stays as the profile's summon rule left it",
    )


func test_sara_and_krita_keep_export_unbound_and_the_twin_on_its_chord() -> void:
    for profile: String in ["default", "Krita"]:
        _apply(profile)
        assert_eq(SaShortcutStore.chords_for(EXPORT), [], "Export holds no chord under %s" % profile)
    _apply("default")
    assert_eq(
        SaShortcutStore.chords_for(_locked()),
        ["Ctrl+Alt+Shift+W"],
        "Sara's own map keeps the locked summon on Ctrl+Alt+Shift+W",
    )
    assert_eq(
        SaShortcutStore.chords_for(SaAppCommands.summon_id(PALETTE)),
        ["Alt+Shift+W"],
        "and the palette's summon on Alt+Shift+W",
    )


func test_the_chord_under_photoshop_opens_the_export_dialog() -> void:
    assert_not_null(SaDocumentFiles.in_tree(Engine.get_main_loop() as SceneTree), "The files flow is where Export finds it")
    _apply("Photoshop")
    assert_false(_export_dialog_open(), "No Export dialog is open to begin with")
    _router.handle_viewport_input(_chord_of_the_twin(), (Engine.get_main_loop() as SceneTree).root)
    assert_true(_export_dialog_open(), "Ctrl+Alt+Shift+W under Photoshop opens the Export dialog")
