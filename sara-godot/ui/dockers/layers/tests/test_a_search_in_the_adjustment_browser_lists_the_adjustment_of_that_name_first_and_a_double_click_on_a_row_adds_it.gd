## A search in the adjustment browser lists the adjustment of
## that name first, and a double click on a row adds it.
##
## The Photoshop hour typed "levels" in the Add Adjustment Layer browser, took
## the first row and got Equalize, whose sentence ends "Opens in Levels", listed
## above Levels in Tone, and a double click on a row added nothing. A row whose
## title begins with the word is now listed first, one whose title holds it
## next and one found by its sentence or its section's words last, each rank in
## its section's order, and a double click selects the row and presses Add
## Layer. The browser is held detached, so the pick opens no settings window.
## The running app is the scenario of the same name in `scenarios/`.
extends "res://tests/test_framework.gd"

## Each filter the adjustment kind is asked about runs once over the active
## layer to learn whether it reads the whole layer.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const FilterRegistrations = preload("res://modules/sara-base-modules/base/filter_registrations.gd")

const OWNER := &"sara-base-modules"
const LEVELS := &"sara-base-modules.levels"
const EQUALIZE := &"sara-base-modules.equalize"

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _door: SaContext = null
var _types: SaLayerTypeRegistry = null
var _browser: SaLayerKindBrowser = null


func before_each() -> void:
    var registries := Fixtures.make_registries()
    _types = registries.layer_types
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(registries.blend_modes)
    _doc = _easel.document
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _door = SaContext.new(Callable(), Callable(), OWNER)
    _door.filters = SaFilterRegistry.new()
    _door.commands = SaCommandRegistry.new()
    FilterRegistrations.register(_door)
    _easel.compositor.filter_chain.registry = _door.filters
    _browser = SaLayerKindBrowser.new()
    _browser.browser.target_canvas = _canvas
    _browser.browser.watch(_door.filters, _door.commands)


func after_each() -> void:
    _browser.free()
    _canvas.free()
    _easel.free()
    _door = null
    _types = null


## Opens the browser for *kind_id* and types *word*, and answers the keys listed.
func _search(word: String, kind_id: StringName = SaBackdropLayer.TYPE_ID) -> Array:
    _browser.open_for(_doc, _types.get_descriptor(kind_id), _types)
    _browser.browser.search_for(word)
    return _browser.describe()["listed"]


func _layer_count() -> int:
    var count := 0
    for child in _doc.get_children():
        if child is SaLayer and child != _doc.stroke_layer:
            count += 1
    return count


## A double click on *row*, as the engine sends it, and the end of the frame
## the press is answered at.
func _double_click(row: Button) -> void:
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    click.double_click = true
    row.gui_input.emit(click)
    await (Engine.get_main_loop() as SceneTree).process_frame


## The browser's row for *key*.
func _row(key: StringName) -> Button:
    return _browser.browser._rows.get(key) as Button


func test_levels_lists_levels_before_equalize() -> void:
    var listed := _search("levels")
    assert_true(listed.has(String(EQUALIZE)), "Equalize is still found by its sentence")
    assert_eq(listed[0] if not listed.is_empty() else "", String(LEVELS), "and Levels is the first row")
    assert_true(listed.find(String(LEVELS)) < listed.find(String(EQUALIZE)), "listed before Equalize")
    assert_eq(_browser.describe()["headings"][0], "Tone", "under Tone's heading")


func test_equalize_lists_equalize_first() -> void:
    var listed := _search("equalize")
    assert_eq(listed[0] if not listed.is_empty() else "", String(EQUALIZE), "Equalize is the first row")


## Rows of one rank keep their section's order, and sections whose best rows
## rank alike keep the registry's, read for the adjustment kind and the
## effect kind, which holds every filter.
func test_blur_keeps_each_section_s_order_among_rows_of_equal_rank() -> void:
    for kind_id: StringName in [SaBackdropLayer.TYPE_ID, SaEffectLayer.TYPE_ID]:
        var listed := _search("blur", kind_id)
        assert_true(not listed.is_empty(), "'blur' lists rows for %s" % kind_id)
        _assert_equal_ranks_in_order(listed, "blur", kind_id)
    var effect := _search("blur", SaEffectLayer.TYPE_ID)
    assert_true(effect.has("sara-base-modules.gaussian_blur"), "Gaussian Blur is listed for an effect layer")


func _assert_equal_ranks_in_order(listed: Array, word: String, kind_id: StringName) -> void:
    var place: Dictionary = {}
    var section_of: Dictionary = {}
    var section_place: Dictionary = {}
    var sections := SaFilterMenu.sections(_door.filters)
    for at: int in sections.size():
        section_place[sections[at]["section"]] = at
        var keys: Array = sections[at]["keys"]
        for index: int in keys.size():
            place[String(keys[index])] = index
            section_of[String(keys[index])] = sections[at]["section"]
    var best: Dictionary = {}
    var ranks: Dictionary = {}
    for key: String in listed:
        var words := SaFilterBrowser.section_words(sections[section_place[section_of[key]]])
        ranks[key] = _browser.browser.rank(StringName(key), word, words)
        best[section_of[key]] = maxi(int(best.get(section_of[key], 0)), int(ranks[key]))
    var broken := 0
    for i: int in listed.size():
        for j: int in range(i + 1, listed.size()):
            var a: String = listed[i]
            var b: String = listed[j]
            if section_of[a] == section_of[b]:
                if ranks[a] < ranks[b] or (ranks[a] == ranks[b] and place[a] > place[b]):
                    broken += 1
            elif best[section_of[a]] < best[section_of[b]]:
                broken += 1
            elif best[section_of[a]] == best[section_of[b]] and section_place[section_of[a]] > section_place[section_of[b]]:
                broken += 1
    assert_eq(broken, 0, "every pair of '%s' rows for %s is in rank, then section, order" % [word, kind_id])


func test_a_double_click_on_the_first_levels_row_adds_one_levels_layer_as_one_step() -> void:
    var listed := _search("levels")
    var layers := _layer_count()
    var standing := _doc.history.position()
    var row := _row(StringName(listed[0]))
    assert_not_null(row, "The first row is on the list")
    if row == null:
        return
    await _double_click(row)
    assert_eq(_layer_count(), layers + 1, "A double click adds one layer")
    var made := _browser.made
    assert_not_null(made, "which the browser made")
    if made == null:
        return
    assert_eq(String(made.name), "Levels", "named Levels")
    assert_eq(String(made.layer_type), String(SaBackdropLayer.TYPE_ID), "an adjustment layer")
    assert_eq(_browser.describe()["holds"], [String(LEVELS)], "holding Levels")
    assert_eq(_doc.history.position(), standing + 1, "as one history step")


func test_a_single_click_selects_and_adds_nothing() -> void:
    _search("levels")
    var layers := _layer_count()
    var standing := _doc.history.position()
    var row := _row(EQUALIZE)
    row.pressed.emit()
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(_browser.describe()["selected"], String(EQUALIZE), "A single click selects the row")
    assert_eq(_layer_count(), layers, "and adds no layer")
    assert_eq(_doc.history.position(), standing, "and no step")
    assert_null(_browser.made, "and the browser made nothing")
