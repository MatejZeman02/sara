## A tool says where its options sit on a fresh bar.
##
## `SaSettingsLayout.DEFAULT_HIDDEN` listed thirteen option keys and
## `DEFAULT_ORDERS` seventeen, every one a module's, so the skeleton held each
## tool's judgement about its own rows and a third-party tool could make none.
## A spec says it now, `bar_hidden` and `bar_after`, and the bar hands both on
## when it registers the row. These pin the four halves the row asked for: the
## tables hold no module key, a fresh bar opens in the order it did, a stored
## profile opens unchanged, and a fixture tool hides a row of its own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from the brush's descriptor, which needs a machine, a surface
## and therefore a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_x9_rows.cfg")

## The top bar's default order as `DEFAULT_ORDERS` spelled it before the fix, the
## module keys in their places. A fresh bar has to open in exactly this.
##
## The eyedropper's Sample choice is anchored after the sample size and followed
## by the wand's Merged, so the rows after it keep their order. The Settings
## menu is off the bar and the sentinel sits after the last menu. The marquee's
## shape and the lasso's shape are tools of their own. Paint and Smudge are
## anchored after Opacity, so they follow Hardness and come before Flow, and
## Opacity comes before Radius, with Paint and Smudge anchored on Radius.
## So the list is the table's order with those rows moved.
const BEFORE_X9: Array[String] = [
    "File",
    "Edit",
    "View",
    "Window",
    "Image",
    "Layer",
    "Select",
    "Tools",
    "Filter",
    "Modules",
    "Help",
    "Second Row",
    "Brush Presets",
    "blend_mode",
    "Keep Blend Mode",
    "eraser_toggled",
    "opacity",
    "radius",
    "hardness",
    "paint_and_smudge",
    "flow",
    "exposure",
    "size_by_pressure",
    "opacity_by_pressure",
    "Environment View",
    "Double Resolution",
    "Rotation",
    "Reset Rotation",
    "stabilizer_mode",
    "stabilizer_amount",
    "Mirror H",
    "Mirror V",
    "Radial",
    "Stabilizer Toggle",
    "sample_size",
    "sample_from",
    "sample_merged",
    "selection_mode",
    "wand_tolerance",
]

## The thirteen `DEFAULT_HIDDEN` held before the fix, less the marquee's shape and
## the lasso's, which are tools of their own.
const HIDDEN_BEFORE_X9: Array[String] = [
    "stabilizer_mode",
    "stabilizer_amount",
    "hardness",
    "exposure",
    "size_by_pressure",
    "opacity_by_pressure",
    "sample_size",
    "sample_merged",
    "selection_mode",
    "wand_tolerance",
    "flow",
]

const FIXTURE_TOOL := &"x9_fixture_tool"
const FIXTURE_ROW := "x9_fixture_row"

var _saved_path: String = ""
var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _bar = null
    if _machine != null and _machine.registry != null and _machine.registry.has(FIXTURE_TOOL):
        _machine.registry.unregister(FIXTURE_TOOL)
    SaSettings.unregister_layout_element("TopMenuBar", FIXTURE_ROW)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Loads whatever profile is at `scratch_profile`, then builds the bar over the real
## modules' tools, which is when their rows are registered.
func _load_and_build_bar() -> void:
    SaSettings.load_settings()
    _host = Node.new()
    _host.name = "X9TestHost"
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()


func _declared_keys() -> Array[String]:
    var out: Array[String] = []
    for descriptor: SaToolDescriptor in _machine.registry.list_descriptors():
        for spec: SaOptionSpec in descriptor.options:
            if not out.has(String(spec.key)):
                out.append(String(spec.key))
    return out


## The aim, counted: no key a module declares in either
## table, where there were thirteen and seventeen.
func test_the_skeletons_tables_hold_no_key_a_module_declares() -> void:
    _load_and_build_bar()
    var declared := _declared_keys()
    assert_true(declared.has("radius") and declared.has("wand_tolerance"), "The modules' tools are what the bar was built over")
    var in_hidden: Array[String] = []
    var in_orders: Array[String] = []
    for key: String in declared:
        for category: String in SaSettingsLayout.DEFAULT_HIDDEN:
            if SaSettingsLayout.DEFAULT_HIDDEN[category].has(key):
                in_hidden.append(key)
        for category: String in SaSettingsLayout.DEFAULT_ORDERS:
            if SaSettingsLayout.DEFAULT_ORDERS[category].has(key):
                in_orders.append(key)
    assert_eq(in_hidden, [] as Array[String], "DEFAULT_HIDDEN names no module's option")
    assert_eq(in_orders, [] as Array[String], "and DEFAULT_ORDERS none")


## A fresh profile's bar opens where it did: every element of the old default
## order in the old sequence, with any row a tool added after the fix left to the
## end, where an unanchored row always went.
func test_a_fresh_bar_opens_in_the_order_it_had() -> void:
    _load_and_build_bar()
    var order := SaSettings.get_layout_order("TopMenuBar")
    var known: Array[String] = []
    for element: Variant in order:
        if BEFORE_X9.has(String(element)):
            known.append(String(element))
    assert_eq(known, BEFORE_X9, "The fresh bar keeps the order the skeleton's table spelled")
    # An element a module anchors may stand among them, as Page Edges does after
    # Environment View once any bar in the run has registered it.
    var anchors: Dictionary = SaSettings._layout._anchors.get("TopMenuBar", {})
    var head := order.slice(0, order.find(BEFORE_X9[-1]) + 1)
    var stray := head.filter(func(element: Variant) -> bool: return not known.has(element) and not anchors.has(element))
    assert_eq(stray, [], "and nothing unanchored lands in the middle of it")


func test_a_fresh_bar_hides_the_thirteen_it_hid() -> void:
    _load_and_build_bar()
    for element: String in HIDDEN_BEFORE_X9:
        assert_false(SaSettings.get_element_visible("TopMenuBar", element), "A fresh profile hides '%s'" % element)
    for element: String in ["blend_mode", "eraser_toggled", "radius", "opacity"]:
        assert_true(SaSettings.get_element_visible("TopMenuBar", element), "and shows '%s'" % element)
    for element: String in HIDDEN_BEFORE_X9:
        assert_true(SaSettings._layout.fresh_hidden("TopMenuBar").has(element), "'%s' is hidden by its own spec" % element)


## A profile that stored an order and a visibility opens with both: the module
## keys are no longer in the skeleton's table, and that must not move a
## painter's arrangement or undo a tick.
func test_a_stored_order_and_a_stored_hidden_row_open_unchanged() -> void:
    var stored: Array = BEFORE_X9.duplicate()
    # A painter's own arrangement: Opacity dragged to the front of the tool rows
    # and the wand's tolerance up beside it.
    stored.erase("opacity")
    stored.insert(stored.find("blend_mode"), "opacity")
    stored.erase("wand_tolerance")
    stored.insert(stored.find("opacity") + 1, "wand_tolerance")
    var cfg := ConfigFile.new()
    cfg.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    cfg.set_value("profile_order", "TopMenuBar", stored)
    cfg.set_value("profile_visibility", "TopMenuBar_hardness", true)
    cfg.set_value("profile_visibility", "TopMenuBar_radius", false)
    assert_eq(cfg.save(ProjectSettings.globalize_path(scratch_profile)), OK, "The stored profile is written")
    _load_and_build_bar()
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(order.slice(0, stored.size()), stored, "The stored order opens as it was stored")
    assert_true(SaSettings.get_element_visible("TopMenuBar", "hardness"), "A row the painter showed stays shown")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "radius"), "and one they hid stays hidden")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "flow"), "while a row they never touched keeps its default")


## The door a third party walks through: a tool of a module that is not the
## base one hides a row on a fresh bar and places it, and a tick shows it.
func test_a_fixture_tool_hides_a_row_of_its_own() -> void:
    _load_and_build_bar()
    var descriptor := Fixtures.make_tool_descriptor(FIXTURE_TOOL)
    descriptor.display_name = "Fixture"
    var row := SaOptionSpec.make_float(StringName(FIXTURE_ROW), "Amount", 0.0, 1.0, 0.1)
    row.on_tool = true
    row.bar_hidden = true
    row.bar_after = "Help"
    descriptor.options = [row]
    assert_true(_machine.registry.register(descriptor, &"x9-fixture-module"), "The fixture tool registers")
    assert_not_null(_bar.control_for(StringName(FIXTURE_ROW)), "The bar built its control")
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(order.find(FIXTURE_ROW), order.find("Help") + 1, "and the row opens after the element it named")
    assert_false(SaSettings.get_element_visible("TopMenuBar", FIXTURE_ROW), "hidden on a fresh bar, by its own spec")
    SaSettings.set_element_visible("TopMenuBar", FIXTURE_ROW, true)
    assert_true(SaSettings.get_element_visible("TopMenuBar", FIXTURE_ROW), "and one tick in Preferences shows it")


## An anchor that is itself a registered row, and one the order does not hold.
## Asked of the registry alone, so the chain does not lean on the modules.
func test_an_anchor_chain_resolves_and_a_missing_anchor_goes_last() -> void:
    SaSettings.load_settings()
    SaSettings.register_layout_element("TopMenuBar", "x9_second", "Second", false, "x9_first")
    SaSettings.register_layout_element("TopMenuBar", "x9_first", "First", false, "File")
    SaSettings.register_layout_element("TopMenuBar", "x9_lost", "Lost", false, "No Such Element")
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_eq(order.find("x9_first"), order.find("File") + 1, "A row follows the skeleton element it names")
    assert_eq(
        order.find("x9_second"), order.find("x9_first") + 1, "and a row anchored on it follows it, whatever was registered first"
    )
    assert_eq(order.back(), "x9_lost", "A row whose anchor is not in the order goes to the end")
    for element: String in ["x9_second", "x9_first", "x9_lost"]:
        SaSettings.unregister_layout_element("TopMenuBar", element)
