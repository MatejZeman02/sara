## The door answers the settings, the colour pair and the
## canvas a module reads. A fixture module reads all three through `SaInHand`,
## its answers are the skeleton's own, and its source names no class behind the
## door, which the direction suite's scan would otherwise list.
extends "res://tests/test_framework.gd"

## The surface's easel holds real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const FIXTURE_PATH := "res://tests/fixtures/modules/in-hand-fixture/module.gd"
const FIXTURE_MODULE = preload("res://tests/fixtures/modules/in-hand-fixture/module.gd")
const DIRECTION_SUITE := "res://tests/test_structure_direction.gd"

var _module: SaModule = null
var _surface: SaSurface = null
var _stops_before: float = 0.0
var _heard: Array[StringName] = []


func before_each() -> void:
    _module = FIXTURE_MODULE.new()
    _stops_before = SaSettings.display_exposure_stops
    _heard.clear()


func after_each() -> void:
    if SaSettings.changed.is_connected(_on_changed):
        SaSettings.changed.disconnect(_on_changed)
    SaSettings.display_exposure_stops = _stops_before
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null
    _module = null


func _on_changed(property: StringName) -> void:
    _heard.append(property)


func test_the_fixture_reads_the_pair_the_store_holds() -> void:
    var pair: Dictionary = _module.call(&"pair")
    assert_eq(pair["foreground"], SaColors.foreground, "The foreground is the store's")
    assert_eq(pair["background"], SaColors.background, "and the background")
    assert_almost_eq(pair["stops"], SaColors.exposure_stops, 1e-6, "and the paint exposure")
    assert_eq(SaInHand.Pair.swatches(), SaColors.swatches, "The swatches are the store's, as a copy")


func test_the_fixture_reads_and_moves_a_setting_and_hears_it_move() -> void:
    var read: Dictionary = _module.call(&"setting")
    assert_almost_eq(read["value"], SaSettings.display_exposure_stops, 1e-6, "The preference read is the profile's")
    assert_almost_eq(read["max"], SaSettings.MAX_EXPOSURE_STOPS, 1e-6, "and its bound is the skeleton's constant")
    SaInHand.Settings.changed().connect(_on_changed)
    _module.call(&"move_setting", 1.5)
    assert_almost_eq(SaSettings.display_exposure_stops, 1.5, 1e-6, "A write through the door moves the preference")
    assert_true(_heard.has(&"display_exposure_stops"), "and the door's changed signal names it")
    _module.call(&"move_setting", 999.0)
    assert_almost_eq(SaSettings.display_exposure_stops, SaPaintExposure.FLOAT_STOPS, 1e-6, "The preference's own setter clamps")


func test_a_name_that_is_no_preference_is_not_known() -> void:
    assert_true(SaInHand.Settings.knows(&"selection_feather"), "A stored preference is known")
    assert_false(SaInHand.Settings.knows(&"no_such_preference"), "A made up name is not")
    assert_eq(SaInHand.Settings.row_target(), SaSettings, "A page row binds to the profile itself")


func test_the_fixture_reads_the_canvas_of_a_surface() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    var read: Dictionary = _module.call(&"canvas", _surface)
    assert_eq(read.get("size"), Vector2i(512, 256), "The document's size is the surface's")
    assert_eq(read.get("output"), _surface.easel.output.rid, "The texture bound is the easel's output")
    assert_false(read.get("has_shader", true), "A suite's view is no canvas, so there is no shader to compose over")
    assert_eq(read.get("filter"), SaCanvas.filter_for(2.0), "The filter is the canvas's own rule")
    assert_eq(SaInHand.Canvas.texture_filter_for(0.5), CanvasItem.TEXTURE_FILTER_LINEAR, "Under a pixel a texel is filtered")


func test_the_front_canvas_is_the_one_the_documents_keep() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_eq(SaInHand.Canvas.front(), SaDocuments.front_in(tree.current_scene), "The front surface is the owner's")


func test_the_fixture_names_no_class_behind_the_door() -> void:
    var source := _code(FileAccess.get_file_as_string(FIXTURE_PATH))
    assert_true(source.contains("SaInHand"), "The fixture reads through the door")
    var reached: Array[String] = []
    for name: String in _names_behind_the_door():
        if RegEx.create_from_string("\\b%s\\b" % name).search(source) != null:
            reached.append(name)
    assert_true(reached.is_empty(), "The fixture names a class behind the door: %s" % ", ".join(reached))


func test_the_door_itself_is_inside_the_door() -> void:
    var prefixes := _door_prefixes()
    var inside := false
    for prefix: String in prefixes:
        inside = inside or "core/api/sa_in_hand.gd".begins_with(prefix)
    assert_true(inside, "core/api is one of the direction suite's door prefixes")


## Every global class and autoload whose file sits outside the direction
## suite's door prefixes, by name.
func _names_behind_the_door() -> Array[String]:
    var prefixes := _door_prefixes()
    var out: Array[String] = []
    for entry: Dictionary in ProjectSettings.get_global_class_list():
        if not _inside(String(entry["path"]), prefixes):
            out.append(String(entry["class"]))
    for property: Dictionary in ProjectSettings.get_property_list():
        var key: String = property["name"]
        if key.begins_with("autoload/"):
            var path := String(ProjectSettings.get_setting(key)).trim_prefix("*")
            if not _inside(path, prefixes):
                out.append(key.trim_prefix("autoload/"))
    return out


func _inside(path: String, prefixes: Array) -> bool:
    var relative := path.trim_prefix("res://")
    if (
        not relative.begins_with("core/")
        and not relative.begins_with("render/")
        and not relative.begins_with("tools/")
        and not relative.begins_with("ui/")
        and not relative.begins_with("harness/")
    ):
        return true
    for prefix: String in prefixes:
        if relative.begins_with(prefix):
            return true
    return false


func _door_prefixes() -> Array:
    var suite := load(DIRECTION_SUITE) as GDScript
    return suite.get_script_constant_map().get("DOOR_PREFIXES", [])


## *text* with its comments and string contents taken out, so a name in prose
## or a message is not a reference.
func _code(text: String) -> String:
    var kept: Array[String] = []
    for line in text.split("\n"):
        if line.strip_edges().begins_with("#"):
            continue
        kept.append(RegEx.create_from_string("\\s#.*$").sub(line, ""))
    var code := "\n".join(kept)
    return RegEx.create_from_string('"(?:\\\\.|[^"\\\\\n])*"').sub(code, '""', true)
