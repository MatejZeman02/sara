## A control made through `SaMake` carries its name and its kind, and the
## harness's walker prints any of them and moves the plain kinds, a slider, a
## spin box, a toggle, a choice and a text field.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The screen is built under `EventBus`, which is in the tree, because the
## `control` step finds a control from the tree's root the way a scenario does.
extends "res://tests/test_framework.gd"

const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

var _screen: VBoxContainer = null
var _heard: Dictionary = {}


func before_each() -> void:
    _heard = {}
    _screen = SaMake.column(EventBus, "L4WalkerScreen")
    SaMake.label(_screen, "L4Label", "Exposure")
    SaMake.button(_screen, "L4Button", "Reset")
    var row := SaMake.row(_screen, "L4Row")
    var toggle := SaMake.check_box(row, "L4Toggle", "Advanced")
    toggle.toggled.connect(func(on: bool) -> void: _heard["toggle"] = on)
    var field := SaMake.line_edit(row, "L4Text")
    field.text_changed.connect(func(text: String) -> void: _heard["text"] = text)
    field.text_submitted.connect(func(text: String) -> void: _heard["submitted"] = text)
    var spin := SaMake.spin_box(_screen, "L4Spin", 0.0, 10.0, 0.5, 1.0)
    spin.value_changed.connect(func(value: float) -> void: _heard["spin"] = value)
    var slider := SaMake.slider(_screen, "L4Slider", 0.0, 1.0, 0.25, 0.5)
    slider.value_changed.connect(func(value: float) -> void: _heard["slider"] = value)
    var choice := SaMake.choice(_screen, "L4Choice", [{"id": "strokes", "label": "Strokes"}, {"id": "tip", "label": "Tip"}])
    choice.select_value("strokes")
    choice.choice_picked.connect(func(value: Variant) -> void: _heard["choice"] = value)
    var numbers := SaMake.choice(_screen, "L4Numbers", [{"id": 1, "label": "One"}, {"id": 3, "label": "Three"}])
    numbers.select_value(1)
    numbers.choice_picked.connect(func(value: Variant) -> void: _heard["numbers"] = value)


func after_each() -> void:
    if _screen != null and is_instance_valid(_screen):
        _screen.free()
    _screen = null


func _step(spec: Dictionary) -> String:
    return ControlWalker.capture(EventBus.get_tree(), spec)


func test_every_made_control_carries_its_kind() -> void:
    var kinds := {
        "L4WalkerScreen": SaMake.Kind.COLUMN,
        "L4Label": SaMake.Kind.LABEL,
        "L4Button": SaMake.Kind.BUTTON,
        "L4Row": SaMake.Kind.ROW,
        "L4Toggle": SaMake.Kind.TOGGLE,
        "L4Text": SaMake.Kind.TEXT,
        "L4Spin": SaMake.Kind.SPIN,
        "L4Slider": SaMake.Kind.SLIDER,
        "L4Choice": SaMake.Kind.CHOICE,
        "L4Numbers": SaMake.Kind.CHOICE,
    }
    for node_name: String in kinds:
        var found := EventBus.find_child(node_name, true, false)
        assert_eq(SaMake.kind_of(found), kinds[node_name], "%s carries its kind" % node_name)
    var plain := Label.new()
    assert_eq(SaMake.kind_of(plain), -1, "and a control SaMake did not make carries none")
    plain.free()


func test_the_walker_prints_each_kind() -> void:
    var printed := {
        "L4Label": ["label", "Exposure"],
        "L4Button": ["button", "Reset"],
        "L4Toggle": ["toggle", false],
        "L4Text": ["text", ""],
        "L4Spin": ["spin", 1.0],
        "L4Slider": ["slider", 0.5],
        "L4Choice": ["choice", "strokes"],
        "L4Numbers": ["choice", 1],
    }
    for node_name: String in printed:
        var said := ControlWalker.describe(ControlWalker.find(EventBus, node_name))
        assert_eq(said["name"], node_name, "%s is printed under its name" % node_name)
        assert_eq(said["kind"], printed[node_name][0], "%s is printed as a %s" % [node_name, printed[node_name][0]])
        assert_eq(said["value"], printed[node_name][1], "and %s prints what it holds" % node_name)
        assert_true(bool(said["enabled"]), "and that a hand can reach it")
    assert_eq(ControlWalker.describe(ControlWalker.find(EventBus, "L4Choice"))["shows"], "Strokes", "A choice adds its words")
    var listed := ControlWalker.describe_all(_screen)
    assert_eq(listed.size(), 8, "The list holds every control, no container and nothing a control is built from")


func test_a_step_reads_a_control() -> void:
    var line := _step({"name": "L4Slider"})
    assert_true(line.begins_with("SaCapture: control 'L4Slider' reads "), "A step with no value reads: %s" % line)
    assert_true(line.contains('"kind":"slider"'), "and prints the kind")
    var listed := _step({"list": "L4WalkerScreen"})
    assert_true(listed.contains("L4Choice") and listed.contains("L4Label"), "A list step prints the screen: %s" % listed)


func test_a_step_moves_each_plain_kind() -> void:
    assert_false(_step({"name": "L4Toggle", "value": true}).contains("failed"), "The toggle takes a press")
    assert_eq(_heard.get("toggle"), true, "and fires what a click fires")
    assert_false(_step({"name": "L4Text", "value": "Nameless"}).contains("failed"), "The field takes typing")
    assert_eq(_heard.get("text"), "Nameless", "and fires what typing fires")
    assert_false(_heard.has("submitted"), "and no Enter nobody pressed")
    assert_false(_step({"name": "L4Spin", "value": 4.5}).contains("failed"), "The spin box takes a number")
    assert_eq(_heard.get("spin"), 4.5, "and fires what an arrow fires")
    assert_false(_step({"name": "L4Slider", "value": 0.8}).contains("failed"), "The slider takes a drag")
    assert_eq(_heard.get("slider"), 0.75, "and lands on its own step")
    assert_false(_step({"name": "L4Choice", "value": "tip"}).contains("failed"), "The choice takes a value")
    assert_eq(_heard.get("choice"), "tip", "and fires what a press fires")
    _step({"name": "L4Choice", "value": "Strokes"})
    assert_eq(_heard.get("choice"), "strokes", "A choice also takes the words on its row")
    _step({"name": "L4Numbers", "value": 3.0})
    assert_eq(_heard.get("numbers"), 3, "and a whole number from JSON finds a whole value")


func test_a_move_that_changes_nothing_says_nothing() -> void:
    _step({"name": "L4Choice", "value": "strokes"})
    assert_false(_heard.has("choice"), "A press on the marked row fires nothing")
    _step({"name": "L4Slider", "value": 0.5})
    assert_false(_heard.has("slider"), "and a drag to where the slider is fires nothing")


func test_a_step_that_cannot_act_says_failed() -> void:
    assert_true(_step({"name": "L4Nothing"}).contains("failed"), "A name that finds nothing fails")
    assert_true(_step({"name": "L4Choice", "value": "dab"}).contains("failed"), "A row the choice lacks fails")
    assert_true(_step({"name": "L4Label", "value": "x"}).contains("failed"), "A label is not moved")
    assert_true(_step({"name": "L4Toggle", "value": "yes"}).contains("failed"), "A toggle takes a bool alone")
    (EventBus.find_child("L4Toggle", true, false) as CheckBox).disabled = true
    assert_true(_step({"name": "L4Toggle", "value": true}).contains("failed"), "A switched off control is not moved")
    assert_false(_heard.has("toggle"), "and fires nothing")
    assert_eq(ControlWalker.read(EventBus, "L4Nothing"), null, "A control not built reads null, not off")
