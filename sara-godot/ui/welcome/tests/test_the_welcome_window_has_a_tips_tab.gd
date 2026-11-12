## The welcome window has a Tips tab. One tip at a time, with
## Previous and Next that wrap and a counter, the key of a tip's command read
## from the shortcut map as bound now, and the tip after the last one shown
## first on every open.
##
## The tab's place among the four is held in `test_welcome_window.gd` beside
## the other three. The pane is built detached, the reason that suite gives,
## except where a case needs it on screen, and then it is a `Control` under
## `EventBus`, never a `Window`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PANE_SOURCE: String = "res://ui/welcome/tips_pane.gd"

var _saved_tip: String = ""
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_tip = SaSettings.last_tip_shown
    SaSettings.last_tip_shown = ""
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    SaSettings.last_tip_shown = _saved_tip
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The app's commands in a registry of the suite's own, the way `main.gd`
## builds them: the router registers the view commands, `SaAppCommands` the
## rest. The router is freed at once, its commands stay in the registry.
func _app_commands() -> SaCommandRegistry:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    router.free()
    return registries.commands


func _index_of(pane: WelcomeTipsPane, id: String) -> int:
    for i: int in pane.tips.size():
        if String(pane.tips[i]["id"]) == id:
            return i
    return -1


func _press(pane: WelcomeTipsPane, button_name: String) -> void:
    (pane.find_child(button_name, true, false) as Button).pressed.emit()


func _counter(pane: WelcomeTipsPane) -> String:
    return (pane.find_child(WelcomeTipsPane.COUNTER, true, false) as Label).text


func test_next_and_previous_walk_the_tips_and_wrap() -> void:
    var pane := WelcomeTipsPane.new()
    assert_eq(pane.tips.size(), 15, "the three first tips and the twelve older ones")
    assert_eq(pane.current, 0, "a profile that never saw one starts on the first")
    assert_eq(_counter(pane), "1 of 15", "and the counter says so")
    _press(pane, WelcomeTipsPane.NEXT)
    assert_eq(_counter(pane), "2 of 15", "Next walks on")
    _press(pane, WelcomeTipsPane.PREVIOUS)
    _press(pane, WelcomeTipsPane.PREVIOUS)
    assert_eq(_counter(pane), "15 of 15", "Previous from the first wraps to the last")
    _press(pane, WelcomeTipsPane.NEXT)
    assert_eq(_counter(pane), "1 of 15", "and Next from the last wraps to the first")
    var title := (pane.find_child(WelcomeTipsPane.TITLE, true, false) as Label).text
    assert_eq(title, String(pane.tips[0]["title"]), "the title on screen is that tip's")
    assert_eq(SaSettings.last_tip_shown, "", "a pane never on screen remembers nothing it walked through")
    pane.free()


func test_a_reopened_window_starts_on_the_tip_after_the_last_one_shown() -> void:
    var host := Control.new()
    host.name = "D45TipsHost"
    EventBus.add_child(host)
    var shown := WelcomeTipsPane.new()
    host.add_child(shown)
    shown.step(3)
    var seen := String(shown.tips[3]["id"])
    var last := String(shown.tips[shown.tips.size() - 1]["id"])
    assert_eq(SaSettings.last_tip_shown, seen, "a tip on screen is the one remembered")
    host.free()

    var reopened := WelcomeTipsPane.new()
    assert_eq(reopened.current, 4, "the next window opens on the tip after it")
    reopened.free()

    SaSettings.last_tip_shown = last
    var wrapped := WelcomeTipsPane.new()
    assert_eq(wrapped.current, 0, "after the last tip the first comes round again")
    wrapped.free()

    SaSettings.last_tip_shown = "a_tip_a_later_build_took_out"
    var unknown := WelcomeTipsPane.new()
    assert_eq(unknown.current, 0, "and a tip this build does not carry starts the list over")
    unknown.free()


func test_a_tip_naming_a_command_shows_the_key_a_rebinding_gave_it() -> void:
    var commands := _app_commands()
    var pane := WelcomeTipsPane.new()
    pane.commands = commands
    var proof := _index_of(pane, "soft_proof")
    assert_true(proof >= 0, "the canvas proof is one of the tips")
    pane.show_tip(proof)
    var chord := pane.find_child(WelcomeTipsPane.CHORD, true, false) as Label
    assert_eq(chord.text, "Key: Ctrl+Y", "the line under it says the key Sara ships")

    var rebound := InputEventKey.new()
    rebound.keycode = KEY_P
    rebound.ctrl_pressed = true
    rebound.alt_pressed = true
    InputMap.action_erase_events(&"view_soft_proof")
    InputMap.action_add_event(&"view_soft_proof", rebound)
    pane.show_tip(proof)
    assert_eq(chord.text, "Key: Ctrl+Alt+P", "and after a rebind the key the painter gave it")
    assert_false(String(pane.tips[proof]["text"]).contains("Ctrl"), "which the sentence itself never names")

    var alt_drag := _index_of(pane, "docker_alt_drag")
    pane.show_tip(alt_drag)
    assert_false(chord.visible, "a tip that names no command shows no key line")
    pane.free()


## Every command a tip names is one the app registers with a key, so no tip
## promises a key and shows nothing under it. Focus Mode's Tab is the one the
## router reads by itself, and its tip carries the word.
func test_every_tip_that_names_a_command_has_a_key() -> void:
    var pane := WelcomeTipsPane.new()
    pane.commands = _app_commands()
    var without: Array[String] = []
    var named := 0
    for tip: Dictionary in pane.tips:
        if not tip.has("command"):
            continue
        named += 1
        if pane.chord_of(tip).is_empty():
            without.append(String(tip["id"]))
    assert_true(named >= 9, "nine tips or more name a command, %d do" % named)
    assert_true(without.is_empty(), "and every one of them has a key: %s" % ", ".join(without))
    pane.free()


## Every string a tip shows is a `tr` call, so a translated build translates
## it. Read from the source, the way `test_quick_settings_pane.gd` reads its
## pane's: the strings left once the dictionary keys and the `&` ids are set
## aside must each sit inside `tr(`.
func test_every_tip_string_goes_through_tr() -> void:
    var source := FileAccess.get_file_as_string(PANE_SOURCE)
    var start := source.find("func _tips()")
    assert_true(start >= 0, "the pane declares its tips in _tips")
    var end := source.find("\nfunc ", start + 1)
    var body := source.substr(start, end - start)
    var literal := RegEx.create_from_string('(?<![&\\w])"([^"\\\\]*)"(?!:)')
    var bare: Array[String] = []
    var through := 0
    for found: RegExMatch in literal.search_all(body):
        var before := body.substr(maxi(0, found.get_start() - 3), mini(3, found.get_start()))
        if before == "tr(":
            through += 1
        else:
            bare.append(found.get_string(1))
    assert_eq(through, 30, "fifteen titles and fifteen sentences go through tr")
    assert_true(bare.is_empty(), "and no tip string is left bare: %s" % ", ".join(bare))
