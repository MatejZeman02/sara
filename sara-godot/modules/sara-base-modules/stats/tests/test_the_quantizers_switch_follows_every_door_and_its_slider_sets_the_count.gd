## The Stats docker's quantizer: its switch turns the Shape Check view and reads
## it back whichever door turned it, and its slider sets the count of steps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The quantizer is toggled from the stats docker, with its level slider on the
## docker. The
## scenario `scenarios/the-stats-docker-turns-the-quantizer-on-and-sets-its-levels.json`
## is the running app, the bands on the canvas and the switch pressed. This is
## what the scenario reads only once each: the part on a page of its own over a
## registry the suite holds, moved by its own rows and by the registry's other
## doors, and the part inside the docker, where it registers nothing and both
## its controls work with the compute switch off.
extends "res://tests/test_framework.gd"

const Quantizer := preload("../quantizer.gd")

var _registry: SaViewTransformRegistry = null
var _part: SaStatsPart = null
var _page: SaPage = null
var _box: VBoxContainer = null
var _kept_count: int = 5
var _service: SaReductionService = null
var _docker: StatsDocker = null
var _host: Node = null
var _embedded: bool = false


func before_each() -> void:
    _kept_count = SaSettings.shape_check_level_count
    _registry = SaViewTransformRegistry.new()
    _registry.register(SaViewTransformDescriptor.create(Quantizer.MODE, "Shape Check", SaViewTransformDescriptor.Kind.MODE))
    _registry.register(SaViewTransformDescriptor.create(&"soft_proof", "Soft Proof", SaViewTransformDescriptor.Kind.MODE))
    _part = Quantizer.new(_registry)
    _page = SaPage.new(_part.declare)
    _page.declare_rows()
    _box = VBoxContainer.new()
    _page.realize(_box)


func after_each() -> void:
    SaSettings.shape_check_level_count = _kept_count
    if is_instance_valid(_docker):
        _docker.free()
    _docker = null
    if is_instance_valid(_host):
        _host.free()
    _host = null
    if _service != null:
        _service.free()
        _service = null
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _box.free()
    _page = null
    _part = null
    _registry = null


## What the switch shows the painter.
func _pressed() -> bool:
    return (_page.row(&"quantizer").control as CheckButton).button_pressed


## What the dump reads for the row *key* of the part's page.
func _dumped(key: StringName) -> Variant:
    for block: Dictionary in _page.describe()["sections"]:
        for row: Dictionary in block["rows"]:
            if row["key"] == String(key):
                return row["value"]
    return null


func test_the_switch_turns_the_view_and_reads_it_back_whichever_door_turned_it() -> void:
    assert_false(_pressed(), "The ordinary view, the switch is off")
    _page.row(&"quantizer").drive(true)
    assert_eq(_registry.mode, Quantizer.MODE, "Pressed, the canvas is in the Shape Check view")
    assert_true(_pressed(), "and the switch stays pressed")

    # Ctrl+Shift+Q and the View menu both end at `set_mode`.
    _registry.set_mode(SaViewTransformRegistry.NORMAL)
    assert_false(_pressed(), "Another door puts the ordinary view back, the switch goes off")
    assert_eq(_dumped(&"quantizer"), false, "and the dump reads it off")
    _registry.set_mode(Quantizer.MODE)
    assert_true(_pressed(), "Another door puts the view on, the switch goes on")
    assert_eq(_dumped(&"quantizer"), true, "and the dump reads it on")

    _page.row(&"quantizer").drive(false)
    assert_eq(_registry.mode, SaViewTransformRegistry.NORMAL, "Released, the ordinary view is back")


func test_off_never_takes_away_a_mode_another_door_put_on() -> void:
    _registry.set_mode(&"soft_proof")
    assert_false(_pressed(), "Another mode is not the Shape Check view, the switch is off")
    _part.set(&"showing", false)
    assert_eq(_registry.mode, &"soft_proof", "and a write of off leaves that mode on")
    _page.row(&"quantizer").drive(true)
    assert_eq(_registry.mode, Quantizer.MODE, "Pressed, the Shape Check view takes its place")


func test_the_slider_sets_the_count_and_follows_it() -> void:
    var slider := SaControlWalker.find(_box, "QuantizerLevels") as FactorSlider
    assert_true(slider != null, "The control step finds the slider by its name, the docker's own kind of slider")
    if slider == null:
        return
    assert_eq(slider.min_value, float(SaSettings.MIN_SHAPE_LEVELS), "It starts at the fewest steps the count takes")
    assert_eq(slider.max_value, float(SaSettings.MAX_SHAPE_LEVELS), "and ends at the most")
    assert_eq(slider.step, 1.0, "in whole steps")
    assert_eq(slider.value, float(SaSettings.shape_check_level_count), "and shows the count as it was")
    assert_true(slider.get_combined_minimum_size().x <= SaUI.px(Quantizer.LEVELS_WIDTH), "It asks no wider than its width")

    assert_true(SaControlWalker.move(slider, 4), "Moved to 4 as a drag moves it")
    assert_eq(SaSettings.shape_check_level_count, 4, "the count is 4")
    SaSettings.shape_check_level_count = 7
    assert_eq(slider.value, 7.0, "A count set elsewhere moves the slider")
    assert_eq(_dumped(&"quantizer_levels"), 7, "and the dump reads it")
    assert_true(SaControlWalker.move(slider, 40), "Moved past its end")
    assert_eq(SaSettings.shape_check_level_count, SaSettings.MAX_SHAPE_LEVELS, "the count is the most it takes")


func test_in_the_docker_it_registers_nothing_and_works_with_the_compute_switch_off() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _service = SaReductionService.new()
    _host = Node.new()
    _host.name = "Q2StatsHost"
    EventBus.add_child(_host)
    _docker = StatsDocker.new(_service)
    var held: SaStatsPart = null
    for part: SaStatsPart in _docker.parts:
        if part.get_script() == Quantizer:
            held = part
    assert_true(held != null, "The list names the quantizer, so the docker makes one")
    if held == null:
        return
    assert_true(held.reduction == null, "It reduces nothing")
    _host.add_child(_docker)
    _docker.show()
    assert_false(_docker.computing, "The docker is open with its compute switch off")
    assert_eq(_service.reductions.size(), 0, "and nothing is registered")

    var slider := SaControlWalker.find(_docker, "QuantizerLevels")
    assert_true(slider != null, "The control step finds the slider by its name")
    assert_true(SaControlWalker.move(slider, 3), "and moves it with the compute switch off")
    assert_eq(SaSettings.shape_check_level_count, 3, "which sets the count")
    var switch := _docker.page.row(&"quantizer")
    assert_true(switch != null and switch.control is CheckButton, "The switch is on the docker's page")
