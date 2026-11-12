## Anything a module registers through the door is found by
## the search with no extra call.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A module should register its commands easily and automatically, as
## operators do in Blender. A module here is a
## context scoped by `SaContext.for_module`, which registers a command and a
## registry of its own and never names the search or its folder. The suite then
## opens the search as the app does and reads what it lists. What a painter
## sees is `scenarios/anything-a-module-registers-is-found-by-the-search.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const MODULE := &"probe"
const COMMAND := &"edit_probe_wash"
const COMMAND_TITLE := "Probe the wash"
const PLUMBING := &"edit_probe_plumbing"
const PLUMBING_TITLE := "Probe plumbing step"
const STAR_TITLE := "Probe Star Vega"
const STAR_KIND := "Probe Star"

var _registries: SaRegistries = null
var _host: Node = null
var _window: SaSearchWindow = null
var _actions_before: Array[StringName] = []
var _ran: Array[String] = []


## A registry of the module's own, a kind of thing no registry of the skeleton
## holds, which answers the search's contract and nothing else.
class Stars:
    extends RefCounted
    var picked: Array[String] = []

    func search_rows() -> Array[SaSearchRegistry.Row]:
        var out: Array[SaSearchRegistry.Row] = []
        for named: String in [STAR_TITLE, "Probe Star Deneb"]:
            var act := func() -> void: picked.append(named)
            out.append(SaSearchRegistry.Row.new(STAR_KIND, named, "Probe Sky", act, &"", "a star the probe charts"))
        return out


func before_each() -> void:
    _actions_before = InputMap.get_actions()
    _ran.clear()
    _host = Node.new()
    _host.name = "U132SearchHost"
    EventBus.add_child(_host)
    _registries = Fixtures.make_menu_registries()
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context))
    _host.add_child(_window)


func after_each() -> void:
    _registries.context.for_module(MODULE).remove_all_registrations()
    _host.free()
    _host = null
    _window = null
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)


## The module's door: a command, a second command that asked to stay out of the
## search with a chord of its own, and a registry of its own announced.
func _register(module: SaContext, stars: Stars) -> void:
    var wash := SaCommandDescriptor.create(COMMAND, COMMAND_TITLE, func() -> bool: return _note("wash"))
    assert_true(module.register_command(wash), "The module registers a command")
    var plumbing := SaCommandDescriptor.create(PLUMBING, PLUMBING_TITLE, func() -> bool: return _note("plumbing"))
    plumbing.show_in_search = false
    var chord := InputEventKey.new()
    chord.keycode = KEY_F11
    chord.ctrl_pressed = true
    chord.alt_pressed = true
    plumbing.default_events = [chord]
    assert_true(module.register_command(plumbing), "and a second that asked to stay out of the search")
    assert_true(module.searches.register(stars), "and announces a registry of its own")


func _note(what: String) -> bool:
    _ran.append(what)
    return true


## The rows the search lists for *query*, read as an opening reads them.
func _found(query: String) -> Array[SaSearchIndex.Entry]:
    return SaSearchIndex.narrowed(_window.index.entries(), query)


func _row(query: String, title: String) -> SaSearchIndex.Entry:
    for entry: SaSearchIndex.Entry in _found(query):
        if entry.title == title:
            return entry
    return null


## A command and a thing of a registry the module brings are found by their
## titles, and picking each runs what it was registered with.
func test_a_modules_command_and_its_own_registry_are_found_and_picked() -> void:
    var stars := Stars.new()
    _register(_registries.context.for_module(MODULE), stars)

    var wash := _row("probe the", COMMAND_TITLE)
    assert_true(wash != null, "The search finds the module's command by its title")
    assert_eq(wash.kind, SaSearchIndex.COMMAND, "as a command")
    assert_eq(wash.command, COMMAND, "standing for it, so the right press offers it")
    _window.pick(wash)
    assert_eq(_ran, ["wash"] as Array[String], "and a pick runs the command it was registered with")

    var vega := _row("vega", STAR_TITLE)
    assert_true(vega != null, "The search finds a thing of the module's own registry by its title")
    assert_eq(vega.kind, STAR_KIND, "as the kind its registry says")
    assert_eq(vega.place, "Probe Sky", "where its registry says it lives")
    assert_true(vega.enabled, "and it can be picked")
    _window.pick(vega)
    assert_eq(stars.picked, [STAR_TITLE] as Array[String], "and a pick runs what the registry gave it")

    _registries.context.for_module(MODULE).remove_all_registrations()
    assert_true(_row("vega", STAR_TITLE) == null, "Unloading the module takes its registry's rows away")


## A command that asked to stay out is not listed, still runs through
## `execute`, and keeps its chord's row on the Keyboard Shortcuts page.
func test_a_command_that_opts_out_is_not_listed_and_still_runs_and_binds() -> void:
    _register(_registries.context.for_module(MODULE), Stars.new())
    # The settings rows are built too, since the Keyboard Shortcuts page has a
    # chord row of every command and would otherwise bring this one back.
    _window.index.warm()
    var settings := 0
    for entry: SaSearchIndex.Entry in _window.index.entries():
        assert_true(entry.command != PLUMBING, "No row stands for the opted out command")
        assert_true(entry.title != PLUMBING_TITLE, "nor a Keyboard Shortcuts row of it, %s" % entry.kind)
        settings += 1 if entry.kind == SaSearchIndex.SETTING else 0
    assert_true(settings > 0, "among %d settings rows" % settings)
    assert_true(_row("probe plumbing", PLUMBING_TITLE) == null, "and its title finds nothing")
    assert_true(_registries.commands.execute(PLUMBING), "execute still runs it")
    assert_eq(_ran, ["plumbing"] as Array[String], "with its own handler")
    assert_true(SaShortcutRows.actions_for("edit_").has(PLUMBING), "Its row is on the Keyboard Shortcuts page")
    var keys := SaShortcutRows.keys_for(PLUMBING)
    assert_false(keys.is_empty(), "with its chord, %s" % keys)
    var rows := SaShortcutRows.rows_for("edit_", null, null, _registries.commands)
    assert_true(rows.has([PLUMBING_TITLE, keys]), "which the page lists under its title")


## Handed a list of sources holding only the module's registry, the search
## lists exactly that registry's rows and none of a built-in kind, so it reads
## no registry by name.
func test_handed_one_registry_the_search_lists_its_rows_alone() -> void:
    var stars := Stars.new()
    _register(_registries.context.for_module(MODULE), stars)
    var alone := SaSearchIndex.new(_registries.context, [stars])
    var titles: Array[String] = []
    for entry: SaSearchIndex.Entry in alone.entries():
        assert_eq(entry.kind, STAR_KIND, "%s is the registry's kind" % entry.title)
        titles.append(entry.title)
    var expected: Array[String] = []
    for row: SaSearchRegistry.Row in stars.search_rows():
        expected.append(row.title)
    assert_eq(titles, expected, "and the list is the registry's rows in its order")
    assert_true(_window.index.entries().size() > 100, "while the search the app opens walks every registry")


## The skeleton's registries are found among the context's own members, the
## ones that answer the contract, with no list of them written anywhere.
func test_the_built_in_registries_are_walked_from_the_contexts_own_members() -> void:
    var context := _registries.context
    var walked := SaSearchRegistry.sources_of(context)
    for registry: Object in [context.tools, context.ui, context.filters, context.commands, context.layer_types]:
        assert_true(walked.has(registry), "%s is walked" % registry.get_script().get_global_name())
    assert_false(walked.has(context.blend_modes), "and a registry that answers nothing is not")
