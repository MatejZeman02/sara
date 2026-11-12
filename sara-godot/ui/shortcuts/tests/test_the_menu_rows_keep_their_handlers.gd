## File, New and File, Open did nothing, on every platform.
##
## `SaShortcutCommands.register_into` built the menu's `SaMenuCommands`, let it
## register and dropped it. The registry keeps a row's handler, and a Callable
## does not keep its object alive, so the instance was freed at once and every
## row it had bound to one of its own methods went invalid. `execute` then
## declines without a word. File, New showed it: it
## never asked about unsaved changes because it never ran. Ctrl+N kept
## working because the router answers that chord itself.
##
## What this suite holds is that every menu row in the registry has a handler
## that can still be called, while the object that registered them lives, and
## that a second registration leaves them callable too. Nothing is pressed: a
## press opens a dialog, which a headless run cannot hold.
extends "res://tests/test_framework.gd"


func _menu_ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    for command: SaCommandDescriptor in SaMenuCommands.new(Callable(), Callable(), Callable(), Callable()).commands():
        ids.append(command.id)
    return ids


func _dead_rows(registry: SaCommandRegistry) -> Array[StringName]:
    var dead: Array[StringName] = []
    for id: StringName in _menu_ids():
        var descriptor := registry.get_descriptor(id)
        if descriptor == null or not descriptor.handler.is_valid():
            dead.append(id)
    return dead


func test_every_menu_row_keeps_a_handler_it_can_call() -> void:
    var registry := SaCommandRegistry.new()
    var commands := SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    commands.register_into(registry)
    assert_true(_menu_ids().size() > 20, "the menu has its rows, New and Open among them")
    assert_true(_menu_ids().has(&"file_new") and _menu_ids().has(&"file_open"), "New and Open are menu rows")
    assert_eq(_dead_rows(registry), [] as Array[StringName], "and no row's handler was freed with the object that bound it")


func test_a_second_registration_keeps_them_callable() -> void:
    var registry := SaCommandRegistry.new()
    var commands := SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    commands.register_into(registry)
    commands.register_into(registry)
    assert_eq(_dead_rows(registry), [] as Array[StringName], "a repeat call leaves every row callable")
