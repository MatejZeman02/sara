## a filter may bring a widget of its own, a chord, and a command it has
## already shipped under.
##
## Three things, one fixture, and a suite for each clause of the ask. The
## fixture declares all three spelled so that the default would not do, so a
## door that fell through to the old behaviour would show here rather than in a
## painter's rebound chord going quiet.
##
## Offscreen and windowless, for the reason `test_filter_dialog.gd` gives: a
## `Window` added to the tree maps a real OS window and hangs the runner. The
## custom row's control and the step that moves it are both reachable without
## one, which is what makes the `filter` step's widget form testable here.
extends "res://tests/test_framework.gd"

const FIXTURE_MODULE = preload("res://tests/fixtures/modules/x12-fixture/module.gd")
const X12_FILTER = preload("res://tests/fixtures/modules/x12-fixture/x12_filter.gd")

const FIXTURE_ID := &"x12-fixture"
const FIXTURE_KEY := &"x12-fixture.fixture_tint"
const DECLARED_COMMAND := &"filter_x12_fixture_tint"

## What the registry would derive from the key, which is what the declared name
## is declared against.
const DERIVED_COMMAND := &"filter_x12-fixture_fixture_tint"


## A filter that answers to whatever title it is given and declares none of the
## three, for the default spelling each one falls back to.
##
## The member is public because a `title()` reading a private back is the getter
## shape `tests/test_privates_rule.gd` counts. Written by this class alone, in
## `_init`, which is what the rule asks of a member set from outside.
class BareFilter:
    extends SaFilter
    var entry_title: String

    func _init(text: String) -> void:
        entry_title = text

    func title() -> String:
        return entry_title

    func run(_ctx: SaFilterContext) -> void:
        pass


func after_each() -> void:
    ModuleLoader.loaded_modules.erase(FIXTURE_ID)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The fixture module registered through the public door, and the registries it
## registered into.
func _with_fixture() -> SaRegistries:
    var registries := _registries()
    var module := FIXTURE_MODULE.new()
    module.register(registries.context.for_module(module.get_id()))
    return registries


func _filter() -> SaFilter:
    return X12_FILTER.new()


## The dialog the fixture filter declares into, realized into a detached host.
func _dialog() -> Dictionary:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new()
    var filter := _filter()
    filter.build(dialog)
    dialog.realize(host)
    return {"host": host, "dialog": dialog, "filter": filter}


## The third declaration. A filter that has already shipped a command answers
## with that name, and one that has not keeps the spelling its key gives it.
func test_a_filter_may_declare_the_command_it_has_already_shipped_under() -> void:
    var registries := _with_fixture()
    assert_true(registries.filters.has(FIXTURE_KEY), "The fixture registers through the public door")
    assert_eq(SaFilterRegistry.command_id(FIXTURE_KEY), DERIVED_COMMAND, "and the key spells a command of its own")

    assert_true(registries.commands.has(DECLARED_COMMAND), "The command is in the registry under the declared name")
    assert_false(registries.commands.has(DERIVED_COMMAND), "and not under the name its key would have derived")
    var command := registries.commands.get_descriptor(DECLARED_COMMAND)
    assert_eq(command.title, "Fixture Tint", "under the filter's own title")
    assert_eq(command.action, DECLARED_COMMAND, "and the InputMap action is the same name, so a chord lands on it")

    var bare := registries.context.for_module(&"module-a")
    assert_true(bare.register_filter(BareFilter.new("Box blur")), "A filter that declares nothing still registers")
    assert_true(registries.commands.has(&"filter_module-a_box_blur"), "under the spelling its key gives, which is today's")
    assert_eq(X12_FILTER.new().action_name(), DECLARED_COMMAND, "and the declaration is the fixture's own")
    assert_eq(BareFilter.new("Box blur").action_name(), &"", "while empty is what every other filter answers")


## The second declaration. The events reach the command, the InputMap and the
## word the Keyboard Shortcuts page prints.
func test_a_filter_may_declare_the_chord_it_opens_on() -> void:
    var registries := _with_fixture()
    var command := registries.commands.get_descriptor(DECLARED_COMMAND)
    assert_eq(command.default_events.size(), 1, "The filter's chord is on the command it registered")

    assert_true(InputMap.has_action(DECLARED_COMMAND), "and the action was created for it")
    assert_true(registries.commands.has_chord(DECLARED_COMMAND), "so the command answers to a key")
    assert_eq(registries.commands.chord_text(DECLARED_COMMAND), "Ctrl+Shift+O", "which is the one the filter declared")

    var bare := registries.context.for_module(&"module-a")
    bare.register_filter(BareFilter.new("Box blur"))
    assert_false(registries.commands.has_chord(&"filter_module-a_box_blur"), "and a filter that declared none has none")


## The chord opens the filter, which is what makes it a door rather than a row
## on a list. Through `try_handle_input`, which is the call the shortcut router
## makes when a painter presses the keys.
func test_the_filter_opens_by_its_own_chord() -> void:
    var registries := _with_fixture()
    var opened: Array[StringName] = []
    registries.filters.invoked.connect(func(key: StringName) -> void: opened.append(key))

    var event := InputEventKey.new()
    event.keycode = X12_FILTER.DECLARED_KEY
    event.ctrl_pressed = true
    event.shift_pressed = true
    event.pressed = true
    assert_true(registries.commands.try_handle_input(event), "The chord is consumed by the command it belongs to")
    assert_eq(opened, [FIXTURE_KEY] as Array[StringName], "and it asks for the fixture's dialog, by key")

    # Read off the filter rather than off the return value, because the
    # registries carry the skeleton's own commands and one of them may answer
    # Ctrl+J. What is being asserted is that this filter does not.
    var wrong := InputEventKey.new()
    wrong.keycode = X12_FILTER.DECLARED_KEY
    wrong.ctrl_pressed = true
    wrong.pressed = true
    opened.clear()
    registries.commands.try_handle_input(wrong)
    assert_true(opened.is_empty(), "Ctrl+J alone does not open it, because the chord is the shift of it")


## **A chord is only a chord if nothing else already holds the keys.** The
## dispatcher gives one input event to one command, and a filter that lands on a
## built-in's chord loses in silence: the row is drawn, the suite passes, and the
## key opens the other thing.
##
## This is not hypothetical. The fixture's first chord was Ctrl+Shift+Y, which
## `view_minimap_proof` answers to, and the scenario showed a filter that never
## opened. Read against every command the skeleton registers, which is the set a
## module's chord has to be free of.
func test_the_declared_chord_is_free_of_every_built_in() -> void:
    var registries := _with_fixture()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)

    var held := SaShortcutStore.chords_for(DECLARED_COMMAND)
    assert_eq(held, ["Ctrl+Shift+O"] as Array[String], "The fixture's chord is on the command it declared")
    assert_eq(SaShortcutStore.conflicts(held[0], DECLARED_COMMAND), [] as Array[String], "and no built-in answers to it")

    # The other half, so the test says what it thinks it says: the keys the
    # fixture once declared do belong to something else.
    assert_false(
        SaShortcutStore.conflicts("Ctrl+Shift+Y", &"nobody").is_empty(),
        "while the chord this fixture first declared is held by a built-in"
    )
    router.free()


## The last clause: a name already taken refuses the registration whole, and the
## console line names both claimants.
func test_a_taken_command_is_refused_and_the_line_names_both_claimants() -> void:
    var registries := _registries()
    var taken := SaCommandDescriptor.create(DECLARED_COMMAND, "Something Else", func() -> bool: return true)
    assert_true(registries.commands.register(taken, &"someone-else"), "Another module's command lands on the name")

    var ctx := registries.context.for_module(FIXTURE_ID)
    assert_false(ctx.register_filter(_filter()), "The fixture's filter is refused")
    assert_false(registries.filters.has(FIXTURE_KEY), "with nothing left in the filter registry")

    var holder: StringName = registries.commands.get_descriptor(DECLARED_COMMAND).owner_module
    var line := SaContext.command_clash_line(FIXTURE_ID, "Fixture Tint", DECLARED_COMMAND, holder)
    assert_true(line.contains("'%s'" % FIXTURE_ID), "The console line names the module that asked")
    assert_true(line.contains("'someone-else'"), "and the module that holds it")
    assert_true(line.contains(String(DECLARED_COMMAND)), "over the name they both wanted")


## The first declaration. The builder runs at realize, and what it answers is
## the control the row draws.
func test_a_custom_row_builds_at_realize_and_is_described() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new()
    var calls := [0]
    var handed: Array = []
    dialog.custom("Stops", func(rerun: Callable) -> Control: return _bar(calls, handed, rerun))

    assert_eq(calls[0], 0, "Declaring the row builds nothing")
    dialog.realize(host)
    assert_eq(calls[0], 1, "and realizing it builds the control once")
    assert_true(handed[0] is Callable, "handed the call that asks for the rerun")

    var row := dialog.row(&"stops")
    assert_eq(row.kind, SaPageRow.Kind.CUSTOM, "The row is the page's own escape hatch")
    assert_true(row.control is HSlider, "with the control the builder answered on it")
    assert_eq(dialog.widget_name(&"stops"), "custom", "and the dump names the widget that declared it")
    assert_eq(String((row.describe() as Dictionary)["kind"]), "custom", "beside the dump's kind, which is the same word here")

    # A second realize clears the host, which frees the control the first one put
    # there. The builder runs again rather than the row keeping a freed one,
    # which is what the call order in `SaDialog.realize` is for.
    dialog.realize(host)
    assert_eq(calls[0], 2, "A second realize builds again, because the first control went with the host")
    assert_true(is_instance_valid(dialog.row(&"stops").control), "and the row holds a live one")
    host.free()


## The call the builder was handed is the dialog's own, so a widget the page
## cannot read is what says the filter's result is stale.
func test_the_builder_is_handed_the_dialogs_own_rerun() -> void:
    var built := _dialog()
    var dialog: SaDialog = built["dialog"]
    var bar: HSlider = built["filter"].bar
    assert_not_null(bar, "The fixture's build kept the control it was handed")

    bar.value = 6.0
    bar.value_changed.emit(bar.value)
    assert_true(dialog.rerun_pending, "Moving the bar asks for a rerun")
    assert_eq(dialog.runs, 0, "which waits for the end of the frame")
    dialog.flush_rerun()
    assert_eq(dialog.runs, 1, "and then runs the filter once")
    (built["host"] as Node).free()


## The second half of the first clause: the `filter` step's widget form reaches
## a custom row through `capture_option_edit` on its control, which is the door.
func test_the_widget_form_moves_a_custom_row_through_its_own_door() -> void:
    var built := _dialog()
    var dialog: SaDialog = built["dialog"]
    var filter: Object = built["filter"]
    assert_almost_eq(float(filter.bar.value), 2.0, 0.001, "The bar opens where the filter declared it")

    var said := SaFilterDialogWindow._drive(dialog.row(&"stops"), {"widget": "stops", "stop": 5})
    assert_true(said.contains("x12 stops bar"), "The step was answered by the control's own door")
    assert_eq(filter.bar.moved, 1, "which the widget counted")
    assert_almost_eq(float(filter.bar.value), 5.0, 0.001, "and the step's own word moved it")

    var by_name := SaFilterDialogWindow._drive(dialog.row(&"amount"), {"widget": "amount", "value": 9})
    assert_true(by_name.begins_with("amount -> 9"), "A row of the six still moves by value and says so")
    assert_almost_eq(float((dialog.row(&"amount") as SaSlider).value), 9.0, 0.001, "which is what the filter reads back")
    (built["host"] as Node).free()


## A `CUSTOM` control that answers no door is not lost, it is driven the way a
## custom row always was, so a page whose widget predates the door still moves.
func test_a_custom_row_with_no_door_is_left_to_the_ordinary_path() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new()
    dialog.custom("Plain", func(_rerun: Callable) -> Control: return Label.new())
    dialog.realize(host)

    var said := SaFilterDialogWindow._drive(dialog.row(&"plain"), {"widget": "plain", "value": null})
    assert_eq(said, "plain -> <null>", "A control with no door writes the row and reports it")
    host.free()


## A row declared with no builder at all is a row that draws nothing, rather
## than a crash at realize: `SaSettingsRows.row` takes a null control, and the
## page's own preview and buttons are declared through the same call.
func test_a_custom_row_declared_with_no_builder_draws_nothing_and_survives() -> void:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new()
    dialog.custom("Empty", Callable())
    dialog.realize(host)
    assert_null(dialog.row(&"empty").control, "A row with no builder has no control")
    dialog.show_texture(null, Rect2i())
    host.free()


## One wrapper so the three assertions above read as one call each: the counter,
## the argument it was handed, and the control.
func _bar(calls: Array, handed: Array, rerun: Callable) -> Control:
    calls[0] += 1
    handed.append(rerun)
    var bar := HSlider.new()
    bar.min_value = 0.0
    bar.max_value = 8.0
    return bar
