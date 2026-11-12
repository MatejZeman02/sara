## The brush editor names one control Spacing.
##
## The Brush Tip page has a Spacing slider, the distance between dabs as a
## share of the tip, and the curve page that multiplies it by the sensors was
## also called Spacing, so a painter opening the editor met two controls with
## one name and asked which was which. The curve page is "Spacing Dynamics"
## now, and its help line says what it multiplies. A Krita preset whose Spacing
## sensor was imported before the rename still lands on that page, because the
## sensor's stem is Krita's and the page's title is only what it is called.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")

## The editor builds a `SaCurveOptionControl` for every curve page, which
## builds an `SaCurveEditor`.
const REQUIRES_GPU := true

static var scratch_preset_dir: String = SaDataRoot.path("test_o1_presets")
static var scratch_dir: String = SaDataRoot.path("test_o1_kpp")

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _clear()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _clear()


## Every page title and every row label the editor holds, read off the pages
## the window builds and not off the specs, and "Spacing" is among them once:
## the Brush Tip page's slider. The curve page is its own title and is not it.
func test_the_editor_holds_one_control_called_spacing() -> void:
    var window := _window()
    var named: Array[String] = []
    var curve_page := -1
    for i in window.pages.count():
        var title := window.pages.title_at(i)
        named.append(title)
        if title == "Spacing Dynamics":
            curve_page = i
        window.show_page(i)
        for row: Dictionary in window.pages.row_report():
            if bool(row["in_editor"]):
                named.append(String(row["label"]))
    var mentions := named.filter(_mentions_spacing)
    assert_eq(named.count("Spacing"), 1, "One page title or row label reads exactly Spacing, %s" % [mentions])
    assert_eq(named.count("Spacing Dynamics"), 2, "and Spacing Dynamics is the curve page's title and its one row")
    assert_true(curve_page >= 0, "The curve page is in the editor's list")

    window.show_page(0)
    assert_eq(window.pages.title_at(0), "Brush Tip", "The first page is the Brush Tip")
    var on_tip: Array[String] = []
    for row: Dictionary in window.pages.row_report():
        if bool(row["in_editor"]):
            on_tip.append(String(row["label"]))
    assert_true(on_tip.has("Spacing"), "and the one Spacing is a row of it: %s" % [on_tip])
    assert_not_null(window.pages.page_controls.control(&"spacing"), "which built its slider")
    window.free()


## The same count on the specs the module declares, which is what the Tool
## Options docker draws its rows from, so the docker has the one too.
func test_the_declared_specs_hold_one_control_called_spacing() -> void:
    var labels: Array[String] = []
    for spec: SaOptionSpec in _specs():
        labels.append(spec.label)
    assert_eq(labels.count("Spacing"), 1, "One declared option is labelled Spacing: %s" % [labels.filter(_mentions_spacing)])
    assert_eq(labels.count("Spacing Dynamics"), 1, "and one is Spacing Dynamics")


## The curve page's help line says what it multiplies, the Brush Tip's Spacing
## by the sensors, and does not call itself the distance between dabs.
func test_the_curve_pages_help_line_says_what_it_multiplies() -> void:
    var found := 0
    for spec: SaOptionSpec in _specs():
        if spec.label != "Spacing Dynamics":
            continue
        found += 1
        assert_true(spec.tooltip.contains("Multiplies"), "It says it multiplies: %s" % spec.tooltip)
        assert_true(spec.tooltip.contains("Brush Tip"), "names the Brush Tip page: %s" % spec.tooltip)
        assert_true(spec.tooltip.contains("Spacing"), "names its Spacing: %s" % spec.tooltip)
        assert_true(spec.tooltip.contains("sensors"), "and the sensors: %s" % spec.tooltip)
    assert_eq(found, 1, "There is one such page")


## A Krita preset with a Spacing sensor reads on the renamed page: the import
## lands the stem on the settings' `spacing_option`, and the editor opens that
## option on the page called Spacing Dynamics, switched on, with the preset's
## curve.
func test_a_krita_spacing_sensor_reads_on_the_renamed_page() -> void:
    var store := _store()
    var results := SaKppImport.import_path(_write_kpp(), store)
    assert_eq(results.size(), 1, "The fixture imports as one preset")
    var loaded: SaStampBrushSettings = store.load_preset(String(results[0]["name"]))
    assert_not_null(loaded, "and loads back from the store")
    var option: SaCurveOption = loaded.spacing_option
    assert_true(option.enabled, "The spacing option is switched on by the preset")
    assert_not_null(option.sensor_for(SaSensor.Id.SPEED), "and follows speed")

    _brush().settings = loaded
    var window := _window(String(results[0]["name"]))
    var index := window.pages.index_of("Spacing Dynamics")
    assert_true(index >= 0, "The editor lists the page as Spacing Dynamics")
    assert_eq(window.pages.index_of("Spacing"), -1, "and has no page called Spacing")
    assert_true(window.pages.curve_option_at(index) == option, "The page is the preset's own Spacing option")
    assert_eq(window.pages.tick_at(index), true, "its switch reads on")
    window.show_page(index)
    assert_true(window.pages.curve_control != null, "and the page draws a curve")
    var expected := SaKppSensors.parse_curve(KppFixtures.SPACING_CURVE)
    assert_eq(option.common_curve.size(), expected.size(), "The option's curve has the preset's points")
    for i in mini(option.common_curve.size(), expected.size()):
        assert_almost_eq(option.common_curve[i].x, expected[i].x, 1e-5, "point %d x" % i)
        assert_almost_eq(option.common_curve[i].y, expected[i].y, 1e-5, "point %d y" % i)
    window.free()


# --- Helpers ------------------------------------------------------------------


static func _mentions_spacing(label: String) -> bool:
    return label.contains("Spacing")


func _brush() -> ToolState:
    return _machine.get_tool("brush")


func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(_machine.get_descriptor(&"brush").options)
    return out


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _window(loaded: String = "") -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store(), loaded)
    return window


func _write_kpp() -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("sara-spacing.kpp")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(KppFixtures.spacing_kpp())
    file.close()
    return path


func _clear() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
