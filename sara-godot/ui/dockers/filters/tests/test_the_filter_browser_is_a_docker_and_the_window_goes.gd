## The filter browser is a docker and the window goes.
##
## One place lists the filters, so the window is gone and is not kept beside
## the docker. Held here: no class
## and no file of the window is left in the project, the Filters docker is a
## built-in docker a fresh profile keeps hidden until asked and holds the
## browser, and the layer kind browser, which took its list, search, detail
## and preview from the window, stands on the same browser and lists the rows
## it listed, every filter for an effect layer and every filter but one that
## reads the whole layer for an adjustment layer.
##
## The running app is `scenarios/the-filter-browser-is-a-docker-and-the-window-goes.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The kind browser runs each filter once to ask whether it reads the whole
## layer, over the easel's document.
const REQUIRES_GPU := true

const OWNER := &"r1_suite"
const WINDOW_CLASS := "SaFilterBrowserWindow"
const WINDOW_FILE := "sa_filter_browser_window"

var _easel: SaEasel = null
var _types: SaLayerTypeRegistry = null
var _filters: SaFilterRegistry = null
var _blur := StringName()
var _wrap := StringName()


func before_each() -> void:
    var registries := Fixtures.make_registries()
    _types = registries.layer_types
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(registries.blend_modes)
    _filters = SaFilterRegistry.new()
    _filters.register(SaGaussianBlurFilter.new(), OWNER)
    _filters.register(SaWrapOffsetFilter.new(), OWNER)
    _easel.compositor.filter_chain.registry = _filters
    _blur = SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    _wrap = SaFilterRegistry.key_for(OWNER, SaWrapOffsetFilter.new())


func after_each() -> void:
    _easel.free()
    _easel = null


## Every file under *dir* whose name holds *word*, the hidden folders and the
## editor's cache left out.
static func _files_named(dir: String, word: String) -> Array[String]:
    var out: Array[String] = []
    var access := DirAccess.open(dir)
    if access == null:
        return out
    for sub: String in access.get_directories():
        if not sub.begins_with("."):
            out.append_array(_files_named(dir.path_join(sub), word))
    for file: String in access.get_files():
        if file.contains(word):
            out.append(dir.path_join(file))
    return out


func test_no_class_or_file_of_the_window_is_left() -> void:
    var named: Array[String] = []
    for entry: Dictionary in ProjectSettings.get_global_class_list():
        if String(entry["class"]) == WINDOW_CLASS or String(entry["path"]).contains(WINDOW_FILE):
            named.append("%s at %s" % [entry["class"], entry["path"]])
    assert_eq(named, [] as Array[String], "No global class is the window or lives in its file")
    assert_eq(_files_named("res://", WINDOW_FILE), [] as Array[String], "and no file of the project is named for it")
    var kept := "res://ui/filters/sa_filter_browser.gd"
    assert_true(ResourceLoader.exists(kept), "The browser the window held is a file of its own")


func test_the_filters_docker_is_a_built_in_hidden_until_asked() -> void:
    var ui := SaUIRegistry.new()
    SaBuiltinDockers.register(ui)
    assert_true(ui.has_docker(SaDockerIds.FILTERS), "The Filters docker is registered with the built-ins")
    assert_eq(ui.get_docker_entry(SaDockerIds.FILTERS)["title"], "Filters", "under the title Filters")
    assert_true(SaDockerIds.ALL.has(SaDockerIds.FILTERS), "among the ids every shipped layout places")
    assert_true(DockerLayoutStore.HIDDEN_UNTIL_ASKED.has(SaDockerIds.FILTERS), "and a fresh profile keeps it hidden until asked")

    var docker := FiltersDocker.new()
    assert_false(docker.visible, "Built, it is hidden, as the window was")
    assert_true(docker.browser is SaFilterBrowser, "and it holds the browser")
    assert_eq(String(docker.browser.name), SaFilterBrowser.NODE_NAME, "by the name a scenario finds it by")
    docker.browser.watch(_filters, SaCommandRegistry.new())
    docker.browser.search_for("blur")
    assert_eq(docker.describe()["listed"], [String(_blur)], "Searching blur lists the blur alone")
    docker.free()


func test_the_layer_kind_browser_reads_its_rows_as_before() -> void:
    var browser := SaLayerKindBrowser.new()
    assert_true(browser.browser is SaFilterBrowser, "The layer kind browser stands on the same browser")
    browser.browser.watch(_filters, SaCommandRegistry.new())
    var document := _easel.document

    browser.open_for(document, _types.get_descriptor(SaEffectLayer.TYPE_ID), _types)
    var listed: Array = browser.describe()["listed"]
    listed.sort()
    var both := [String(_blur), String(_wrap)]
    both.sort()
    assert_eq(listed, both, "An effect layer lists every filter")
    assert_eq(browser.title, "Add Effect Layer", "under its own title")
    assert_eq(browser.browser.open_button.text, "Add Layer", "and its Open adds a layer")

    browser.open_for(document, _types.get_descriptor(SaBackdropLayer.TYPE_ID), _types)
    var adjusted: Array = browser.describe()["listed"]
    assert_eq(adjusted, [String(_blur)], "An adjustment layer leaves off Wrap Offset, which reads the whole layer")
    assert_true(browser.browser.pick(_blur), "The blur takes a pick")
    assert_eq(browser.describe()["selected"], String(_blur), "and is the one selected")
    assert_false(browser.browser.pick(_wrap), "A filter it does not list takes none")
    browser.free()
