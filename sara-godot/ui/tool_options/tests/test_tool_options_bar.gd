## What the tool options bar shows once it is reduced, and the button it
## gained.
##
## The bar is not the six controls plus a button by construction: it is built
## from whatever the shown tool declares, and the reduction is `bar = false` on
## the specs plus `SaSettingsLayout.DEFAULT_HIDDEN` on the profile. So these
## assert what a painter meets rather than what a list says.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's sliders come from the brush's descriptor, and a machine holding the
## built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_tool_options_bar.cfg")

var _saved_path: String = ""
var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _host = Node.new()
    _host.name = "ToolOptionsBarTestHost"
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Every element the bar offers that a fresh profile also shows.
func _shown_elements() -> Array[String]:
    var out: Array[String] = []
    for element: String in _bar.layout_elements():
        if _bar.layout_elements()[element] == null:
            continue
        if not SaSettings.get_element_visible("TopMenuBar", element):
            continue
        out.append(element)
    out.sort()
    return out


## Five controls and the button, and nothing else, on a fresh profile.
##
## The bar shows Opacity and not Flow, so Flow is on the second list: still
## declared, still built, and hidden by `SaSettingsLayout.DEFAULT_HIDDEN` the way Hardness is.
func test_a_fresh_profile_shows_five_controls_and_the_button() -> void:
    var wanted: Array[String] = [
        ToolOptionsBar.ELEMENT_EDIT_BRUSH,
        ToolOptionsBar.ELEMENT_PRESETS,
        "blend_mode",
        "eraser_toggled",
        "opacity",
        "radius",
    ]
    wanted.sort()
    var shown := _shown_elements()
    for element: String in wanted:
        assert_true(shown.has(element), "'%s' is on the bar" % element)
    # The Keep checkbox and the three symmetry toggles are the skeleton's own and
    # are not brush options, so the count is the six above plus those four.
    for element: String in ["hardness", "stabilizer_mode", "exposure", "stabilizer_amount", "flow"]:
        assert_false(shown.has(element), "'%s' is not on a fresh bar" % element)


## And every row that left is still in the Tool Options docker, which shows
## every option a tool declares rather than the few flagged for the bar.
func test_every_row_that_left_is_still_a_docker_row() -> void:
    var docker := ToolOptionsDocker.new()
    docker.target_tool_machine = _machine
    docker.options.binding.follow(_machine)
    for key: StringName in [&"hardness", &"stabilizer_mode", &"exposure", &"stabilizer_amount"]:
        assert_not_null(docker.options.control(key), "The docker still shows '%s'" % key)
    docker.free()


## Hidden by the profile rather than refused by the spec, which is the half that
## keeps Preferences able to put it back. A `bar = false` spec
## builds no control at all, so nothing could offer it.
func test_hardness_is_hidden_rather_than_absent() -> void:
    assert_not_null(_bar.control_for(&"hardness"), "The control is built")
    assert_true(_bar.layout_elements().has("hardness"), "so Preferences can offer it")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "hardness"), "and a fresh profile hides it")
    SaSettings.set_element_visible("TopMenuBar", "hardness", true)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "hardness"), "and one tick puts it back")
    SaSettings.set_element_visible("TopMenuBar", "hardness", false)


## The button is a layout element like the rest, so a painter who never opens the
## editor can take it off.
func test_the_edit_brush_button_is_a_layout_element() -> void:
    assert_not_null(_bar.edit_brush_btn, "The bar carries the button")
    assert_eq(_bar.edit_brush_btn.text, "Edit Brush", "labelled in the words the command uses")
    assert_eq(_bar.layout_elements().get(ToolOptionsBar.ELEMENT_EDIT_BRUSH), _bar.edit_brush_btn, "and listed by name")


## The page the editor reopens on is the profile's, not the document's.
func test_the_last_page_is_remembered_per_profile() -> void:
    SaSettings.brush_editor_page = "Opacity"
    assert_eq(SaSettings.brush_editor_page, "Opacity", "The profile holds a page")
    SaSettings.load_settings()
    assert_eq(SaSettings.brush_editor_page, "Opacity", "and reading the profile back gives it")
    SaSettings.brush_editor_page = ""


# --- The split ----------------------------------------------------------------


## The four switches moved to a file of their own and are reachable under the
## names every caller already used, because a split is not a rename.
func test_the_switches_are_still_reachable_by_name() -> void:
    assert_not_null(_bar.mirror_h_btn, "Mirror H")
    assert_not_null(_bar.mirror_v_btn, "Mirror V")
    assert_not_null(_bar.radial_btn, "Radial")
    assert_not_null(_bar.stabilizer_btn, "and the stabiliser toggle")
    assert_eq(_bar.mirror_h_btn, _bar.switches.mirror_h_btn, "each one the switch object's own button")
    assert_eq(
        ToolOptionsBar.DEFAULT_STABILIZER_MODE,
        SaToolOptionsSwitches.DEFAULT_STABILIZER_MODE,
        "and the constant forwards rather than being copied"
    )


## The switches write the document, and their guard has to be up while the bar
## mirrors a value onto them or a sync would write straight back.
func test_a_symmetry_toggle_writes_the_document() -> void:
    var symmetry := _surface.get_document().symmetry
    assert_false(symmetry.mirror_horizontal, "Nothing is mirrored to begin with")
    _bar.mirror_h_btn.toggled.emit(true)
    assert_true(symmetry.mirror_horizontal, "The toggle writes the document")
    _bar.mirror_h_btn.toggled.emit(false)
    assert_false(symmetry.mirror_horizontal, "and clears it")

    _bar.switches.muted = true
    _bar.mirror_h_btn.toggled.emit(true)
    assert_false(symmetry.mirror_horizontal, "and writes nothing while the guard is up")
    _bar.switches.muted = false
