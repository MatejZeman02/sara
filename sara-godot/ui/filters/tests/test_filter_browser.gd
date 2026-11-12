## The filter browser: every registered filter once, a search over the name and
## the sentence, and an invoke that is the registry's, in the
## Filters docker.
##
## Detached. `FiltersDocker` is a `Window`, and adding one to the tree maps a
## real OS window and hangs the runner, which is the note
## `ui/widgets/tests/test_filter_dialog.gd` opens with. Everything asserted here works
## on a detached docker: the list, the search, the detail column and the invoke
## all read the registry and the controls the constructor built, and only the
## preview needs a document, which is the scenario's.
extends "res://tests/test_framework.gd"


## A filter that answers to whatever title it is given.
##
## The member is public because `title()` reading a private back is the getter
## shape `tests/test_privates_rule.gd` counts, which is the same reason
## `ui/menus/tests/test_filter_registration.gd` writes its fixture this way. Written by
## this class alone, in `_init`.
class NamedFilter:
    extends SaFilter
    var entry_title: String
    var refusal: String

    func _init(text: String, cannot_run: String = "") -> void:
        entry_title = text
        refusal = cannot_run

    func title() -> String:
        return entry_title

    func problem() -> String:
        return refusal

    func run(_ctx: SaFilterContext) -> void:
        pass


var _docker: FiltersDocker = null
var _filters: SaFilterRegistry = null
var _commands: SaCommandRegistry = null


func after_each() -> void:
    if _docker != null:
        _docker.free()
    _docker = null
    _filters = null
    _commands = null


## A browser over two modules: one with two filters, one with a single filter
## whose command carries a sentence, and a fourth that cannot run.
func _build() -> FiltersDocker:
    _filters = SaFilterRegistry.new()
    _commands = SaCommandRegistry.new()
    _register(&"alpha", NamedFilter.new("Box blur"), "")
    _register(&"alpha", NamedFilter.new("Sharpen"), "Pull the edges of the picture apart.")
    _register(&"beta", NamedFilter.new("Posterise"), "")
    _register(&"beta", NamedFilter.new("Broken kernel", "line 4: undeclared identifier 'srcc'"), "")
    _docker = FiltersDocker.new()
    _docker.browser.watch(_filters, _commands)
    return _docker


## One filter under *module_id*, and the command that carries its sentence.
##
## Registered on the two registries by hand rather than through
## `SaContext.register_filter`, because that door writes a title and no
## sentence: the sentence half of the search has nothing to read in the tree as
## it stands.
func _register(module_id: StringName, filter: SaFilter, sentence: String) -> void:
    _filters.register(filter, module_id)
    var key := SaFilterRegistry.key_for(module_id, filter)
    var command := SaCommandDescriptor.create(SaFilterRegistry.command_id(key), filter.title(), Callable())
    command.sentence = sentence
    _commands.register(command, module_id)


func test_every_registered_filter_appears_once() -> void:
    var docker := _build()
    var listed: Array = docker.describe()["listed"]
    assert_eq(listed.size(), 4, "four filters registered, four rows")
    var seen := {}
    for key: String in listed:
        assert_false(seen.has(key), "%s is offered once" % key)
        seen[key] = true
    for key: StringName in _filters.list_keys():
        assert_true(seen.has(String(key)), "%s reached the browser" % key)


func test_the_rows_of_no_section_are_grouped_under_other() -> void:
    var docker := _build()
    var texts: Array = []
    for child in docker.browser._list.get_children():
        texts.append((child as Label).text if child is Label else (child as Button).text)
    assert_eq(
        texts,
        ["Other", "Box blur", "Sharpen", "Posterise", "Broken kernel"],
        "no section is registered, so one heading, Other, over every filter in registration order"
    )


func test_the_search_filters_by_name() -> void:
    var docker := _build()
    docker.browser.search_for("blur")
    assert_eq(docker.describe()["listed"], ["alpha.box_blur"], "the name matched, and nothing else did")


func test_the_search_filters_by_the_sentence_the_command_carries() -> void:
    var docker := _build()
    # "edges" is in no filter's title. Only the sentence on Sharpen's command
    # has it, so a row that comes back proves the second half of the search.
    docker.browser.search_for("edges")
    assert_eq(docker.describe()["listed"], ["alpha.sharpen"], "the sentence matched where the title could not")
    var said := docker.browser.sentence_for(&"alpha.sharpen")
    assert_eq(said, "Pull the edges of the picture apart.", "read off the command registry")
    assert_eq(docker.browser.sentence_for(&"alpha.box_blur"), "", "and a filter whose command carries none says so")


func test_a_search_that_drops_the_picked_row_drops_the_selection() -> void:
    var docker := _build()
    docker.browser.pick(&"beta.posterise")
    assert_eq(String(docker.browser.selected), "beta.posterise", "picked")
    docker.browser.search_for("blur")
    assert_eq(String(docker.browser.selected), "", "a row the search hid cannot stay described")
    docker.browser.search_for("")
    assert_eq(String(docker.browser.selected), "", "and clearing the search does not pick it again")


func test_the_detail_column_says_who_registered_the_filter() -> void:
    var docker := _build()
    docker.browser.pick(&"beta.posterise")
    var said := docker.describe()
    assert_eq(said["title"], "Posterise", "the filter's own title")
    assert_eq(said["owner"], "Added by beta", "and the module id, there being no loaded module to name")
    assert_true(said["can_open"], "a filter with no problem can be opened")


func test_a_filter_that_cannot_run_is_dimmed_and_says_why() -> void:
    var docker := _build()
    docker.browser.pick(&"beta.broken_kernel")
    var said := docker.describe()
    assert_eq(said["sentence"], "line 4: undeclared identifier 'srcc'", "the compiler's own first line")
    assert_false(said["can_open"], "and Open is dead, the way the menu row is dimmed")


func test_the_invoke_path_is_the_registrys() -> void:
    var docker := _build()
    var invoked: Array[StringName] = []
    _filters.invoked.connect(func(key: StringName) -> void: invoked.append(key))
    docker.browser.pick(&"alpha.sharpen")
    docker.browser.open_selected()
    assert_eq(invoked, [&"alpha.sharpen"] as Array[StringName], "the browser asked the registry, the way the menu row does")
    assert_eq(docker.browser.selected, &"alpha.sharpen", "and the docker stays on the pick, beside the dialog it opened")


func test_a_browser_with_nothing_picked_invokes_nothing() -> void:
    var docker := _build()
    var invoked: Array[StringName] = []
    _filters.invoked.connect(func(key: StringName) -> void: invoked.append(key))
    docker.browser.open_selected()
    assert_eq(invoked.size(), 0, "Open with no row picked is not an invoke of the first row")
    assert_false(docker.describe()["can_open"], "and the button was dead to begin with")


func test_a_module_unloading_takes_its_rows_with_it() -> void:
    var docker := _build()
    _filters.unregister_module(&"alpha")
    assert_eq(docker.describe()["listed"], ["beta.posterise", "beta.broken_kernel"], "the list followed the registry's change")
