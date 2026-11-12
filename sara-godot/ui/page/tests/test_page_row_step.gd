## The door step that moves any declared row, not only the demo's.
##
## `SaPageDrive.capture` finds its page by walking a visible `Window`, so the
## host it realizes into has to be in the tree. Never a `Window` of its own
## (adding one to the tree in a headless test hangs), and never
## `tree.root.add_child` either, which does nothing while the runner's own
## `_ready` is still setting children up. `EventBus` is in the tree already and
## readies nothing, so the host hangs there and is freed in `after_each`.
extends "res://tests/test_framework.gd"

var _host: VBoxContainer = null
var _page: SaPage = null
var _knobs: SaPageDemo.Knobs = null


func _declare(ui: SaPage) -> void:
    var section := ui.section("Kinds")
    section.toggle("Rolloff", _knobs, ^"rolloff")
    section.slider("Exposure", -5.0, 5.0, _knobs, ^"exposure").step(0.1).decimals(1)
    section.custom("Readout", Label.new())


func before_each() -> void:
    _knobs = SaPageDemo.Knobs.new()
    _host = VBoxContainer.new()
    _host.name = "C5DemoHost"
    _page = SaPage.new(_declare)
    _page.declare_rows()
    _page.realize(_host)
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
    _host = null
    _page = null
    _knobs = null


## The base class is `RefCounted`, so it carries no `get_tree()` of its own.
func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


func test_a_known_row_moves_and_writes() -> void:
    var report := SaPageDrive.capture(_tree(), {"row": "exposure", "value": 3.0})
    assert_true(report.contains("moved to 3"), "the step's own line says what happened: %s" % report)
    assert_almost_eq(_knobs.exposure, 3.0, 0.001, "the binding took the write, not only the control")


func test_a_toggle_moves_and_writes() -> void:
    SaPageDrive.capture(_tree(), {"row": "rolloff", "value": false})
    assert_false(_knobs.rolloff, "the toggle's own control drove the binding")


func test_without_a_value_the_row_is_only_read() -> void:
    _knobs.exposure = 1.5
    var report := SaPageDrive.capture(_tree(), {"row": "exposure"})
    assert_true(report.contains("reads"), "a read line, not a moved one: %s" % report)
    assert_almost_eq(_knobs.exposure, 1.5, 0.001, "reading a row never writes it")


func test_an_unknown_key_lists_the_keys_it_found() -> void:
    var report := SaPageDrive.capture(_tree(), {"row": "nope"})
    assert_true(report.contains("exposure"), "the miss names a real key so a scenario writer can read it: %s" % report)
    assert_true(report.contains("rolloff"), "and the other one: %s" % report)


func test_a_custom_row_is_refused() -> void:
    var report := SaPageDrive.capture(_tree(), {"row": "readout", "value": "x"})
    assert_true(report.contains("custom"), "a custom row is refused rather than silently ignored: %s" % report)


func test_the_page_option_picks_the_named_container() -> void:
    var report := SaPageDrive.capture(_tree(), {"row": "exposure", "value": 4.0, "page": "C5DemoHost"})
    assert_true(report.contains("C5DemoHost"), "the answer names the page it found: %s" % report)
    assert_almost_eq(_knobs.exposure, 4.0, 0.001, "and moved the row on it")


func test_a_page_named_wrong_is_not_found() -> void:
    var report := SaPageDrive.capture(_tree(), {"row": "exposure", "value": 1.0, "page": "NoSuchPage"})
    assert_true(report.contains("no page named"), "the wrong name is not silently forgiven: %s" % report)
