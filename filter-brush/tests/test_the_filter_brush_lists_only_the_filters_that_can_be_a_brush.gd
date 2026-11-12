## The filter brush lists only
## the filters that say they can be a brush, and every filter owns that yes or
## no.
##
## The dropdown must not offer filters that make no sense as a brush
## (gradient, kaleidoscope, ...), so every filter owns a boolean saying whether
## it could be one. Every filter answers
## `SaFilter.can_be_a_brush`, yes unless it says otherwise, the Tool Options
## list only those that say yes, every one of Sara's own answers what the
## brush finds when it records the filter's pass, and a brush saved with a
## filter that says no still opens and says why it paints nothing.
extends "res://tests/test_framework.gd"

## The registry's filters record their passes over real chunks, so this needs
## a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateScript = preload("res://modules/sara-base-modules/filter-brush/state_filter_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const StrokeScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_stroke.gd")
const ModuleScript = preload("res://modules/sara-base-modules/filter-brush/module.gd")
const FilterRegistrations = preload("res://modules/sara-base-modules/base/filter_registrations.gd")
const KaleidoscopeScript = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const OWNER: StringName = &"sara-base-modules"
## The module the door's suite registers its two filters under.
const STRANGER: StringName = &"stranger"
const CANVAS := Vector2i(256, 256)
## Sara's own filters that read the whole layer for every pixel, and the
## sentence the brush's record of their pass would have refused them with.
const WHOLE: Array[String] = [
    "kaleidoscope.kaleidoscope",
    "sara-base-modules.mirror",
    "sara-base-modules.wrap_offset",
]
const PRESET := "Brush Kaleidoscope"


## A module's filter that says nothing about the brush, a point pass in all
## but name, which is all the list asks of it.
class Quiet:
    extends SaFilter

    func title() -> String:
        return "Brush Quiet"

    func run(_ctx: SaFilterContext) -> void:
        pass


## The same filter saying no.
class Refuses:
    extends Quiet

    func title() -> String:
        return "Brush Refuses"

    func can_be_a_brush() -> bool:
        return false


## A Kaleidoscope that claims a brush can paint it, which the press's own
## guard must still refuse.
class Claims:
    extends KaleidoscopeScript

    func id() -> StringName:
        return &"claims"

    func title() -> String:
        return "Brush Claims"

    func can_be_a_brush() -> bool:
        return true


var _surface: SaSurface = null
## The door the base module registers through, with its filters and commands.
var _door: SaContext = null
var _store: SaPresetStore = null


func before_each() -> void:
    SaFilterPreset.root = SaDataRoot.path("test_filter_presets")
    _surface = Fixtures.make_surface(CANVAS)
    _door = SaContext.new(Callable(), Callable(), OWNER)
    _door.filters = SaFilterRegistry.new()
    _door.commands = SaCommandRegistry.new()
    FilterRegistrations.register(_door)
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    _door.filters.register(KaleidoscopeScript.new(), &"kaleidoscope")


func after_each() -> void:
    if _store != null:
        for preset_name in _store.list_names():
            _store.delete_preset(preset_name)
        DirAccess.remove_absolute(_store.dir)
    _store = null
    _door = null
    Fixtures.teardown(_surface)
    _surface = null


func test_the_list_holds_the_gaussian_blur_and_none_of_the_filters_that_read_the_whole_layer() -> void:
    var ids := _listed(_door)
    assert_true(ids.has("sara-base-modules.gaussian_blur"), "The Gaussian Blur is listed")
    for key in WHOLE:
        assert_true(_door.filters.has(StringName(key)), "%s is registered" % key)
        assert_false(ids.has(key), "And %s is not listed" % key)
    # The note's "gradient": the one filter of Sara's with the word is the
    # Gradient Map, a point pass a brush paints as it paints Invert.
    assert_true(ids.has("sara-base-modules.gradient_map"), "The Gradient Map, a point pass, is")
    assert_eq(ids.size(), _door.filters.list_keys().size() - WHOLE.size(), "Every other filter is listed")


func test_every_filter_of_sara_s_own_says_what_the_brush_finds_in_its_pass() -> void:
    var document := _surface.get_document()
    for key: StringName in _door.filters.list_keys():
        var filter := _door.filters.get_filter(key)
        if filter.can_be_a_brush():
            var evaluated := StrokeScript.evaluate(_door, String(key), {}, document, null)
            assert_eq(evaluated.refusal, "", "%s says yes and the brush paints it" % key)
        else:
            assert_true(WHOLE.has(String(key)), "%s says no and reads the whole layer" % key)


func test_a_filter_that_says_yes_and_reads_the_whole_layer_is_still_refused_at_the_press() -> void:
    var registry := SaFilterRegistry.new()
    registry.register(Claims.new(), &"probe")
    var door := SaContext.new()
    door.filters = registry
    assert_true(_listed(door).has("probe.claims"), "Saying yes, it is listed")
    var guarded := StrokeScript.evaluate(door, "probe.claims", {}, _surface.get_document(), null)
    var sentence := guarded.refusal
    assert_true(sentence.contains("reads the whole layer"), "But its pass is refused with the guard's sentence: %s" % sentence)


func test_a_module_filter_that_says_nothing_is_listed_and_one_that_says_no_is_not() -> void:
    var door := SaContext.new(Callable(), Callable(), STRANGER)
    door.filters = SaFilterRegistry.new()
    door.commands = SaCommandRegistry.new()
    assert_true(door.register_filter(Quiet.new()), "The quiet filter registers through the door")
    assert_true(door.register_filter(Refuses.new()), "And so does the one that says no")
    assert_true(Quiet.new().can_be_a_brush(), "Saying nothing is yes")
    var ids := _listed(door)
    assert_true(ids.has("%s.brush_quiet" % STRANGER), "The quiet filter is listed: %s" % [ids])
    assert_false(ids.has("%s.brush_refuses" % STRANGER), "The one that says no is not")
    assert_eq(ids.size(), 1, "And nothing else is")


func test_a_brush_saved_with_a_filter_that_says_no_opens_with_a_sentence_and_no_error() -> void:
    _store = SaPresetStore.new()
    _store.dir = SaDataRoot.path("test_filter_brush_presets")
    var saved := SettingsScript.new()
    saved.filter_key = "kaleidoscope.kaleidoscope"
    saved.filter_parameters = {"mirrors": 6.0}
    assert_eq(_store.save_preset(PRESET, saved), PRESET, "The brush is saved")
    var tool := StateScript.new()
    tool.surface = _surface
    tool.settings.context = _door
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var applied := _store.apply_preset(PRESET, tool.settings)
    var note := tool.filter_note
    var row := _filter_row(ModuleScript.options(_door))
    var chosen: Dictionary = tool.settings.filter_page
    OS.remove_logger(errors)
    assert_true(applied, "It opens")
    assert_eq(tool.settings.filter_key, "kaleidoscope.kaleidoscope", "Naming the filter it was saved with")
    assert_true(note.contains("Kaleidoscope says a brush cannot paint it"), "And says why it paints nothing: %s" % note)
    assert_true(row != null and not _ids(row).has("kaleidoscope.kaleidoscope"), "The list still leaves it off")
    assert_eq(chosen.get("filter_key", ""), "kaleidoscope.kaleidoscope", "Its rows are the saved filter's")
    assert_eq(errors.texts([SaErrorCatcher.ERROR, SaErrorCatcher.SCRIPT]), PackedStringArray(), "Without an error")


## The keys the Filter row offers, read off the module's own options.
static func _listed(door: SaContext) -> Array:
    return _ids(_filter_row(ModuleScript.options(door)))


static func _filter_row(specs: Array[SaOptionSpec]) -> SaOptionSpec:
    for spec in specs:
        if spec.key == &"filter_key":
            return spec
    return null


static func _ids(row: SaOptionSpec) -> Array:
    var ids: Array = []
    for choice: Dictionary in row.choices if row != null else []:
        ids.append(choice["id"])
    return ids
