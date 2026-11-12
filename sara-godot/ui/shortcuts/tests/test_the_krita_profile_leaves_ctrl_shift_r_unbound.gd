## The Krita profile leaves Ctrl+Shift+R unbound, and Reload
## Shaders keeps it in Sara's own map.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Krita's Ctrl+Shift+R is Paste as Reference Image,
## and in Sara under the Krita profile it recompiled the kernels and said "No
## shader changed." in the corner. A profile is applied the way Quick settings
## applies it, and the chord is pressed through a real router over the app's
## commands, with the corner notice installed the way the main window does, so
## a reload the chord ran would show its line there.
extends "res://tests/test_framework.gd"

## Reload Shaders recompiles kernels when the chord reaches it.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RELOAD := &"modules_reload_shaders"

var _kept_profile: String = ""
var _kept_embedding: bool = true
var _registries: SaRegistries = null
var _host: Node = null
var _router: ShortcutRouter = null
var _pending_before := PackedStringArray()
var _refusals_before := PackedStringArray()


func before_each() -> void:
    _kept_profile = SaSettings.shortcuts_profile
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _registries = Fixtures.make_registries()
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutStore.capture_defaults()
    # What `SaProblems` was keeping is set aside, because installing the notice
    # hands every kept line to the new dialog.
    _pending_before = SaProblems.pending
    _refusals_before = SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    _host = Node.new()
    _host.name = "U516TestHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    _router = ShortcutRouter.new()
    _router.name = "U516Router"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.commands = _registries.commands
    _host.add_child(_router)


func after_each() -> void:
    _apply("default" if _kept_profile.is_empty() else _kept_profile)
    SaSettings.shortcuts_profile = _kept_profile
    if _host != null and is_instance_valid(_host):
        # Freeing the host takes the problem dialog with it, which uninstalls
        # the notice and lets go of the sink.
        _host.free()
    _host = null
    _router = null
    SaProblems.pending = _pending_before
    SaProblems.pending_refusals = _refusals_before
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## The profile applied as Quick settings applies it.
func _apply(profile: String) -> void:
    SaSettings.shortcuts_profile = profile
    SaShortcutStore.apply_profile(profile)
    EventBus.shortcuts_changed.emit()


static func _ctrl_shift_r() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_R
    key.physical_keycode = KEY_R
    key.ctrl_pressed = true
    key.shift_pressed = true
    key.pressed = true
    return key


## The corner's line once *key* has gone through the router, or empty when the
## corner said nothing. The notice is cleared first, so a line left by a press
## before this one is not read as this one's.
func _corner_after(key: InputEventKey) -> String:
    var notice := SaMessage.notice_widget()
    assert_not_null(notice, "The corner notice is installed")
    if notice == null:
        return ""
    notice.label.text = ""
    notice.panel.visible = false
    _router.handle_viewport_input(key, (Engine.get_main_loop() as SceneTree).root)
    return notice.label.text if notice.showing() else ""


func test_krita_gives_reload_shaders_no_chord_and_the_chord_says_nothing() -> void:
    _apply("Krita")
    assert_eq(SaShortcutStore.chords_for(RELOAD), [], "Reload Shaders holds no chord under Krita")
    assert_eq(SaShortcutStore.conflicts("Ctrl+Shift+R", RELOAD), [], "and nothing else of Sara's answers to Ctrl+Shift+R there")
    var said := _corner_after(_ctrl_shift_r())
    var no_reload := "Ctrl+Shift+R under Krita says no 'No shader changed.' in the corner, said '%s'" % said
    assert_false(said.contains("No shader changed."), no_reload)
    assert_false(said.contains("shader"), "nor any reload's line")


func test_sara_keeps_reload_shaders_on_ctrl_shift_r() -> void:
    _apply("default")
    assert_eq(SaShortcutStore.chords_for(RELOAD), ["Ctrl+Shift+R"], "Sara's own map keeps Reload Shaders on Ctrl+Shift+R")
    # The same press reaches the reload under Sara, which is what makes the
    # silence under Krita above a cleared chord rather than a press the suite
    # never delivered.
    var said := _corner_after(_ctrl_shift_r())
    assert_true(said.contains("shader"), "Ctrl+Shift+R under Sara reloads and says so in the corner, said '%s'" % said)
