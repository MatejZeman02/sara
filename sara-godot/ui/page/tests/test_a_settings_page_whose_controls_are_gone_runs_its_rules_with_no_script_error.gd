## A settings page whose controls are gone runs its rules with no script error.
##
## A page is `RefCounted` and outlives the container it was realized into, so
## a change heard after that container is freed walks sections whose columns
## are gone. `SaPage._show_block` cast the column before asking whether it
## lived, and the cast of a freed object is a script error the runner fails a
## run over, which every area gate printed from the Preferences suites.
##
## The runner is the half of the check no assertion makes: any of these tests
## printing "Trying to cast a freed object" fails the run. The host hangs off
## `EventBus` for the case in the tree, for the reason
## `test_page_row_step.gd` gives.
extends "res://tests/test_framework.gd"


## A binding target that says when it changed, as `SaSettings` does, so the
## page's watch listens to it.
class Knobs:
    extends RefCounted

    signal changed

    var detailed: bool = true:
        set(value):
            detailed = value
            changed.emit()

    var amount: float = 0.5:
        set(value):
            amount = value
            changed.emit()


var _knobs: Knobs = null
var _page: SaPage = null


func _declare(ui: SaPage) -> void:
    var switch := ui.section("Switch")
    switch.toggle("Detailed", _knobs, ^"detailed").named(&"detailed").hides(&"amount")
    switch.toggle("Loose", null, ^"").named(&"loose")
    var detail := ui.section("Detail")
    detail.slider("Amount", 0.0, 1.0, _knobs, ^"amount").named(&"amount")


func before_each() -> void:
    _knobs = Knobs.new()
    _page = SaPage.new(_declare)
    _page.declare_rows()


func after_each() -> void:
    _page = null
    _knobs = null


## Changes a row, refreshes, runs the rules and reads the description, which
## is every path that walks the sections, and reads that the values survive.
func _use_the_page(what: String) -> void:
    _page.row(&"loose").write(true)
    _knobs.amount = 0.25
    _knobs.detailed = false
    _page.refresh()
    _page.apply_rules()
    var said := _page.describe()
    assert_eq(int(said["rows"]), 3, "%s: the page still counts its rows" % what)
    assert_eq((said["sections"] as Array).size(), 2, "%s: and its sections" % what)
    assert_eq(_page.row(&"loose").read(), true, "%s: an unbound row keeps its value" % what)
    assert_almost_eq(float(_page.row(&"amount").read()), 0.25, 0.0001, "%s: a bound row reads its target" % what)
    assert_eq(_page.rows().size(), 3, "%s: rows() answers" % what)


func test_the_rule_puts_the_detail_section_away_while_the_host_lives() -> void:
    var host := VBoxContainer.new()
    _page.realize(host)
    _knobs.detailed = false
    var sections := _page.describe()["sections"] as Array
    assert_false(bool((sections[1] as Dictionary)["shown"]), "The section whose one ruled row is hidden goes")
    _knobs.detailed = true
    sections = _page.describe()["sections"] as Array
    assert_true(bool((sections[1] as Dictionary)["shown"]), "and comes back with it")
    host.free()


func test_a_host_freed_outside_the_tree_leaves_a_page_that_still_answers() -> void:
    var host := VBoxContainer.new()
    _page.realize(host)
    host.free()
    _use_the_page("outside the tree")


func test_a_host_freed_inside_the_tree_leaves_a_page_that_still_answers() -> void:
    var host := VBoxContainer.new()
    EventBus.add_child(host)
    _page.realize(host)
    EventBus.remove_child(host)
    host.free()
    _use_the_page("inside the tree")


## The owner the Preferences suites left behind: a second realize into a host
## in the tree takes the first watch off it and only queues it for freeing, and
## a test that never yields a frame keeps that watch hearing the settings after
## the host is gone.
func test_a_watch_a_second_realize_put_away_answers_nothing() -> void:
    var host := VBoxContainer.new()
    EventBus.add_child(host)
    _page.realize(host)
    var first := host.get_node("PageWatch")
    _page.rebuild()
    assert_true(first.is_queued_for_deletion(), "The first watch is only queued")
    EventBus.remove_child(host)
    host.free()
    _use_the_page("after a second realize")


func test_a_page_emptied_and_rebuilt_into_a_second_host_answers() -> void:
    var first := VBoxContainer.new()
    _page.realize(first)
    for child in first.get_children():
        first.remove_child(child)
        child.free()
    _use_the_page("with its host emptied")
    var second := VBoxContainer.new()
    _page.host = second
    _page.rebuild()
    assert_eq(_page.host, second, "The rebuild drew into the second host")
    assert_true(second.get_child_count() > 0, "which holds the rows again")
    _use_the_page("rebuilt into a second host")
    first.free()
    second.free()
