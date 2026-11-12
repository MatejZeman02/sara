## The top bar's rotation slider and Reset Rotation turn the
## document in front.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A host stands in for main: an `SaDocuments` on the current scene, the way the
## document tabs suite stands one there, holding two surfaces whose views are fake, and
## the pair parented under a container in the tree so it asks the scene and not
## a view handed to it. Each surface's document counts its invalidations, so the
## suite can say a turn redrew the document it turned and left the other alone.
## The suite is a tool script because `SaDocument` is one, and a script that
## extends a tool script without being one draws the editor's warning.
@tool
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


## A document that only counts how often the whole of it is redrawn.
class CountingDocument:
    extends SaDocument

    var invalidated: int = 0

    func invalidate_all_allocated_chunks() -> void:
        invalidated += 1


var _documents: SaDocuments = null
var _host: HBoxContainer = null
var _easels: Array[SaEasel] = []
var _pair: SaTopBarRotation = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = HBoxContainer.new()
    _host.name = "U513Host"
    EventBus.add_child(_host)
    _easels = []
    for id: StringName in [&"first", &"second"]:
        var easel := SaEasel.new()
        easel.document = CountingDocument.new()
        _easels.append(easel)
        _documents.add(SaSurface.create(id, easel, Fixtures.FakeView.new()))
    _pair = SaTopBarRotation.new()
    _pair.attach(_host)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.current_scene.set(&"documents", null)
    _host.free()
    # A document is a node, so it goes by hand with the easel that held it.
    for easel in _easels:
        easel.document.free()
        easel.free()
    _easels = []
    _host = null
    _pair = null
    _documents = null


## Types *text* into the slider the way a painter does, which is what sends
## `value_changed`. Setting `value` sends nothing.
func _type(slider: FactorSlider, text: String) -> void:
    slider.start_editing()
    slider._line_edit.text = text
    slider._on_line_edit_submitted(text)


func _degrees(surface: SaSurface) -> float:
    return rad_to_deg(surface.view.get_rotation())


func test_the_slider_turns_the_second_document_and_reset_puts_it_back() -> void:
    var first := _documents.surfaces[0]
    var second := _documents.surfaces[1]
    first.view.set_rotation(deg_to_rad(-20.0))
    _pair.follow()
    assert_almost_eq(_pair.slider.value, -20.0, 0.01, "With the first in front the slider reads the first's angle")

    _documents.bring_to_front(second)
    assert_almost_eq(_pair.slider.value, 0.0, 0.01, "Bringing the second forward puts its own angle on the slider")

    _type(_pair.slider, "30")
    assert_almost_eq(_degrees(second), 30.0, 0.01, "The slider turns the document in front")
    assert_almost_eq(_pair.slider.value, 30.0, 0.01, "and reads that document's angle")
    assert_almost_eq(_degrees(first), -20.0, 0.01, "The first document's view is unchanged")
    var first_document := first.get_document() as CountingDocument
    var second_document := second.get_document() as CountingDocument
    assert_eq(first_document.invalidated, 0, "The turn redraws nothing of the first document")
    assert_true(second_document.invalidated > 0, "and redraws the second, the one it turned")

    _pair.reset_button.pressed.emit()
    assert_almost_eq(_degrees(second), 0.0, 0.01, "Reset Rotation puts the second document at 0 degrees")
    assert_almost_eq(_pair.slider.value, 0.0, 0.01, "and the slider with it")
    assert_almost_eq(_degrees(first), -20.0, 0.01, "leaving the first where it was")

    _documents.bring_to_front(first)
    assert_almost_eq(_pair.slider.value, -20.0, 0.01, "Bringing the first forward puts the first's own angle on the slider")
    second.view.set_rotation(deg_to_rad(45.0))
    assert_almost_eq(_pair.slider.value, -20.0, 0.01, "and a turn of the hidden second no longer moves it")
