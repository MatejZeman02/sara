## Every row of every top menu carries a sentence.
##
## This is the check that keeps the number of rows with no sentence at zero: a
## row added later without a sentence fails the run here rather than in a
## capture nobody reruns.
##
## **The bar is built with the commands bound.** The
## sentence of a row that runs a registered command is a property of the
## command, so a bar with no registry is a bar where thirty-three rows
## have nothing to read, and this suite would have been measuring the
## registry's absence rather than the menus. It binds what the running app
## binds: the skeleton's built-ins, `SaAppCommands`, the router's own chords
## and the note mode's.
##
## Built detached and `_ready()`ed by hand, the way `test_menus.gd` does it: a
## PopupMenu is a Window, and one in the tree hangs a headless run. A submenu
## row counts as a row, because a painter hovers it like any other, and a
## separator does not, because there is nothing there to explain.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


## Every command the running app registers, in one registry. The router and the
## note mode go into *held* for the caller to free, because the registry holds
## handlers bound to both and freeing them first would leave it pointing at
## nothing.
func _app_commands(held: Array) -> SaCommandRegistry:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    held.append(router)
    # The Help menu's own row. `SaNoteMode.install` wants a Main to put the mode
    # under and a detached bar has none, so the command is registered on its own,
    # which is what `register_command` is for.
    var mode := SaNoteMode.new()
    SaNoteMode.register_command(registries.commands, mode)
    held.append(mode)
    return registries.commands


func _make_bar(commands: SaCommandRegistry) -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    if commands != null:
        bar.bind_commands(commands)
    return bar


func test_no_menu_row_explains_nothing() -> void:
    var held: Array = []
    var bar := _make_bar(_app_commands(held))
    var rows := 0
    var silent: Array[String] = []
    for menu_name: String in bar.menus:
        var popup: SaChoicePopup = bar.menus[menu_name]
        # `row_ids` holds rows and never a separator or a heading, so the skip
        # the `PopupMenu` walk needed is what the list answers with.
        for row_id: StringName in popup.row_ids():
            rows += 1
            var button := popup.label_button(row_id)
            if button == null or button.tooltip_text.strip_edges().is_empty():
                silent.append("%s > %s" % [menu_name, button.text if button != null else String(row_id)])
    assert_eq(silent, [] as Array[String], "Every top menu row carries a sentence")
    # The count guards the other way round: a menu that stopped populating
    # would pass the emptiness check above with nothing in it at all.
    #
    # 65 here and 75 in the running app, which is not a disagreement. A
    # detached bar has no view transform registry, so the View menu falls back
    # to its one Tonemap row in place of the ten the registry contributes.
    # `scenarios/menus-explain-nothing.json` is what reads the other ten.
    assert_true(rows >= 65, "and every menu is still populated, 65 rows on a detached bar (%d)" % rows)
    bar.free()
    for node: Node in held:
        node.free()


## The registry is where the sentence comes from, and this is what says so: a
## menu is a list of commands, so the same bar with nothing bound draws none of
## the command rows, and bound it reads each sentence off its command.
##
## Without it the suite above could pass on sentences typed back into the menu
## files, which the commands' own sentences replace.
func test_a_command_row_says_nothing_until_the_registry_is_bound() -> void:
    var unbound := _make_bar(null)
    var bare: SaChoicePopup = unbound.menus["Layer"]
    assert_null(bare.label_button(SaMenu.key(400)), "an unbound bar has no New Layer row to explain")
    assert_null(bare.label_button(SaMenu.key(406)), "and no Flatten row either, whose sentence is its command's too")
    unbound.free()

    var held: Array = []
    var bar := _make_bar(_app_commands(held))
    var layer: SaChoicePopup = bar.menus["Layer"]
    assert_true(
        layer.label_button(SaMenu.key(406)).tooltip_text.begins_with("Merge all layers"),
        "bound, the Flatten row reads the sentence `layer_flatten` registered"
    )
    bar.free()
    for node: Node in held:
        node.free()


## A module's action is explained by the module, which is the half no
## built-in can prove: the Modules menu reads the sentence off the descriptor
## rather than saying the one thing that is true of every module action.
func test_a_module_command_shows_the_sentence_it_registered() -> void:
    var commands := SaCommandRegistry.new()
    var spoken := SaCommandDescriptor.create(&"test_module_spoken", "Spoken Action", func() -> bool: return true)
    spoken.show_in_modules_menu = true
    spoken.sentence = "What this action does, in the module's own words."
    commands.register(spoken, &"test-module")
    var silent := SaCommandDescriptor.create(&"test_module_silent", "Silent Action", func() -> bool: return true)
    silent.show_in_modules_menu = true
    commands.register(silent, &"test-module")

    var bar := _make_bar(commands)
    var modules: SaChoicePopup = bar.menus["Modules"]
    var tooltips := {}
    for row_id: StringName in modules.row_ids():
        var button := modules.label_button(row_id)
        if button != null:
            tooltips[button.text] = button.tooltip_text
    assert_eq(
        tooltips.get("Spoken Action", ""),
        "What this action does, in the module's own words.",
        "the module's own sentence reaches the row"
    )
    assert_true(
        tooltips.get("Silent Action", "").begins_with("Added by "),
        "and one that registered none keeps the line that names who added it"
    )
    bar.free()
