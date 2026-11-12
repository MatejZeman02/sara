## No command's handler dies without a word.
##
## File, New and File, Open once did nothing on every platform,
## because the object that bound their handlers was freed as soon as it had
## registered them, and `execute` declined each press with the same false it
## gives a command nobody registered. This suite holds the word it says now: an
## error naming the command and its module, once however often it is pressed,
## and nothing for a command that is not there.
extends "res://tests/test_framework.gd"


## An object with a handler, freed by hand so the test decides when it dies.
class Holder:
    extends Object

    func run() -> bool:
        return true


func _lines_naming(errors: SaErrorCatcher, needle: String) -> PackedStringArray:
    var out := PackedStringArray()
    for line in errors.texts([SaErrorCatcher.ERROR]):
        if line.contains(needle):
            out.append(line)
    return out


func test_a_freed_handler_is_reported_once_however_often_it_is_pressed() -> void:
    var registry := SaCommandRegistry.new()
    var holder := Holder.new()
    var command := SaCommandDescriptor.create(&"d1_probe_dead", "A command whose object dies", holder.run)
    command.action = &""
    registry.register(command, &"d1-probe-module")
    assert_true(registry.execute(&"d1_probe_dead"), "While its object lives the command runs")

    holder.free()
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var answers: Array = []
    for press in 5:
        answers.append(registry.execute(&"d1_probe_dead"))
    OS.remove_logger(errors)

    assert_eq(answers, [false, false, false, false, false], "A dead handler still declines every press")
    var said := _lines_naming(errors, "d1_probe_dead")
    assert_eq(said.size(), 1, "and the first press says so, the other four do not: %s" % [errors.texts([SaErrorCatcher.ERROR])])
    assert_true(said.size() == 1 and said[0].contains("d1-probe-module"), "naming the module that registered it")


func test_a_missing_command_stays_silent() -> void:
    var registry := SaCommandRegistry.new()
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var answer := registry.execute(&"d1_probe_nobody_registered")
    OS.remove_logger(errors)

    assert_false(answer, "A command nobody registered is declined")
    var caught := errors.texts([SaErrorCatcher.ERROR])
    assert_eq(caught, PackedStringArray(), "without a word, because a module that is not loaded may own it")


## Registered again under the same id with a live handler, and lost again, the
## command is reported again, because it is a second defect and not the first.
func test_a_command_registered_again_and_lost_again_is_reported_again() -> void:
    var registry := SaCommandRegistry.new()
    var errors := SaErrorCatcher.new()
    for life in 2:
        var holder := Holder.new()
        var command := SaCommandDescriptor.create(&"d1_probe_again", "A command lost twice", holder.run)
        command.action = &""
        registry.register(command, &"d1-probe-module")
        holder.free()
        OS.add_logger(errors)
        registry.execute(&"d1_probe_again")
        registry.execute(&"d1_probe_again")
        OS.remove_logger(errors)
        registry.unregister(&"d1_probe_again")

    assert_eq(_lines_naming(errors, "d1_probe_again").size(), 2, "one error for each life of the command")


func test_try_handle_input_stays_silent_over_a_dead_handler() -> void:
    var registry := SaCommandRegistry.new()
    var holder := Holder.new()
    var command := SaCommandDescriptor.create(&"d1_probe_dead_key", "A chord whose object dies", holder.run)
    var key := InputEventKey.new()
    key.keycode = KEY_F13
    command.default_events = [key]
    registry.register(command, &"d1-probe-module")
    holder.free()

    var press := InputEventKey.new()
    press.keycode = KEY_F13
    press.pressed = true
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var handled := registry.try_handle_input(press)
    OS.remove_logger(errors)
    InputMap.erase_action(&"d1_probe_dead_key")

    assert_false(handled, "A dead handler takes no key")
    var caught := errors.texts([SaErrorCatcher.ERROR])
    assert_eq(caught, PackedStringArray(), "and says nothing, because the dispatch runs on every key")
