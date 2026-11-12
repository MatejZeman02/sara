## A menu is a list of commands.
##
## A menu row that runs something is a command id in a list, and everything the
## row shows, its words, its chord, its sentence, its tick and whether it can be
## pressed, is the command's own answer. These cases build a menu out of a list
## the way every built-in menu is built now, and read each of those back off the
## row, then press one and watch the command run.
##
## Built detached, the way `test_menus.gd` builds its bar: a popup is a `Window`,
## and one in the tree hangs a headless run.
extends "res://tests/test_framework.gd"


## The smallest menu there is: one list and nothing of its own.
class ListMenu:
    extends SaMenu

    const ROWS := [[1, &"test_l5_paint"], SaMenu.LINE, [2, &"test_l5_lamp"], [3, &"test_l5_idle"], [4, &"test_l5_absent"]]

    func _add_items() -> void:
        add_commands(ROWS)


var _registry: SaCommandRegistry
var _popup: SaChoicePopup
var _menu: ListMenu
var _runs: Array[StringName] = []
var _lamp_on := false
var _idle_ready := false


func before_each() -> void:
    _runs.clear()
    _lamp_on = false
    _idle_ready = false
    _registry = SaCommandRegistry.new()
    var paint := SaCommandDescriptor.create(&"test_l5_paint", "Paint the thing", func() -> bool: return _ran(&"test_l5_paint"))
    paint.label = "Paint"
    # No action, so the chord comes off the command's own default events and the
    # suite leaves no key behind in the InputMap for the shortcut page to find.
    paint.action = &""
    paint.sentence = "Paints the thing, which is what this row is for."
    var key := InputEventKey.new()
    key.keycode = KEY_P
    key.ctrl_pressed = true
    paint.default_events = [key]
    _registry.register(paint, &"test")
    var lamp := SaCommandDescriptor.create(&"test_l5_lamp", "Lamp", func() -> bool: return _flip_lamp())
    lamp.action = &""
    lamp.checked = func() -> bool: return _lamp_on
    _registry.register(lamp, &"test")
    var idle := SaCommandDescriptor.create(&"test_l5_idle", "Idle", func() -> bool: return _ran(&"test_l5_idle"))
    idle.action = &""
    idle.enabled = func() -> bool: return _idle_ready
    _registry.register(idle, &"test")
    _popup = SaChoicePopup.new()
    _menu = ListMenu.new(_popup)
    _menu.bind_commands(_registry)


func after_each() -> void:
    _menu = null
    _popup.free()
    _registry = null


func _ran(command_id: StringName) -> bool:
    _runs.append(command_id)
    return true


func _flip_lamp() -> bool:
    _lamp_on = not _lamp_on
    return true


## Row key to what the row reports, for the words at its right and its tick.
func _report() -> Dictionary:
    var out := {}
    for entry: Dictionary in _popup.row_report():
        out[StringName(entry.get("id", ""))] = entry
    return out


func test_a_row_shows_the_commands_words_chord_and_sentence() -> void:
    var row: Dictionary = _report().get(SaMenu.key(1), {})
    assert_eq(String(row.get("label", "")), "Paint", "the row reads the command's menu words, not its title")
    assert_eq(String(row.get("hint", "")), "Ctrl+P", "and its chord in the column at the right")
    assert_eq(
        _popup.label_button(SaMenu.key(1)).tooltip_text,
        "Paints the thing, which is what this row is for.",
        "and its sentence on hover"
    )
    var lamp: Dictionary = _report().get(SaMenu.key(2), {})
    assert_eq(String(lamp.get("label", "")), "Lamp", "a command with no menu words shows its title")


func test_a_command_the_registry_does_not_hold_draws_nothing() -> void:
    assert_false(_menu.has_item(4), "the absent command has no row")
    assert_eq(_menu.command_at(1), &"test_l5_paint", "and each drawn row knows its command")
    assert_eq(_popup.row_ids(), [SaMenu.key(1), SaMenu.key(2), SaMenu.key(3)] as Array[StringName], "in the list's order")


func test_a_press_runs_the_command() -> void:
    _menu.on_id_pressed(1)
    assert_eq(_runs, [&"test_l5_paint"] as Array[StringName], "the press ran the command the row names")


func test_a_row_follows_the_commands_enabled_state() -> void:
    assert_true(_popup.is_disabled(SaMenu.key(3)), "a command that cannot run now draws a dimmed row")
    _idle_ready = true
    _menu.populate()
    assert_false(_popup.is_disabled(SaMenu.key(3)), "and the next build draws it live once it can")
    assert_false(_popup.is_disabled(SaMenu.key(1)), "a command that says nothing about it is always live")


func test_a_tick_follows_the_command_and_the_press_moves_it() -> void:
    assert_false(_menu.is_item_checked(2), "the lamp is off and the row says so")
    _menu.on_id_pressed(2)
    assert_true(_lamp_on, "the press ran the lamp's command")
    assert_true(_menu.is_item_checked(2), "and the tick caught up with it")
    _lamp_on = false
    _menu.sync_ticks()
    assert_false(_menu.is_item_checked(2), "a change made elsewhere reaches the tick on sync, without running anything")


func test_an_unbound_menu_draws_no_command_rows() -> void:
    var popup := SaChoicePopup.new()
    var menu := ListMenu.new(popup)
    menu.populate()
    assert_eq(menu.item_count(), 0, "no registry, no commands, no rows and no stray line")
    popup.free()


## The real Layer menu, bound the way the app binds it and with no document:
## the mask rows are the mask commands, and with no layer to act on they dim.
func test_the_layer_menus_mask_rows_dim_with_nothing_to_mask() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    var layer := bar.menu("Layer") as SaLayerMenu
    for index: int in SaMaskOps.ALL.size():
        var item_id := SaLayerMenuRows.number_of(SaMaskOps.ALL[index])
        assert_eq(layer.command_at(item_id), SaMaskOps.ALL[index], "row %d is the mask command in order" % item_id)
        assert_true(layer.popup.is_disabled(SaMenu.key(item_id)), "and %s is dimmed with no layer" % SaMaskOps.ALL[index])
    bar.free()


## Every shortcut the Settings page lists reads as words once the whole app's
## commands are bound, which is the page taking its words from the commands. A
## filter's words are the filter registry's, which `test_d19_*` holds, so the
## filters are left to it.
func test_the_shortcut_page_reads_a_word_for_every_listed_shortcut() -> void:
    var note_mode := SaNoteMode.new()
    var commands := SaTestFixtures.make_menu_registries(note_mode).commands
    var raw: Array[String] = []
    for action: StringName in SaShortcutRows.ORDER:
        if String(action).begins_with("filter_"):
            continue
        var label := SaShortcutRows.label_for(action, null, null, commands)
        if label == String(action).capitalize() or label.contains("_"):
            raw.append("%s -> %s" % [action, label])
    assert_eq(raw, [] as Array[String], "no listed shortcut falls back to its identifier")
    note_mode.free()
