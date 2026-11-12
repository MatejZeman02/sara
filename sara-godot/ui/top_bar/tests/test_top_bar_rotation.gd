## The rotation slider follows the view before the painter touches it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The running bar finds its view through the current scene's main canvas, and
## a suite has no scene, so the bar is handed a fake view through its
## constructor and parented under a bare container. The running app's half is
## `scenarios/a-sweep-for-faults-over-the-rest-of-the-interface.json`, which
## turns the canvas with Ctrl+] twice after a fresh start and reads the slider.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func _pair(view: SaView) -> Array:
    var host := HBoxContainer.new()
    var pair := SaTopBarRotation.new(view)
    pair.attach(host)
    return [pair, host]


func test_boot_puts_the_views_angle_on_an_untouched_slider() -> void:
    var view := Fixtures.FakeView.new()
    view.rotation = deg_to_rad(30.0)
    var made := _pair(view)
    var pair: SaTopBarRotation = made[0]
    assert_almost_eq(pair.slider.value, 0.0, 0.01, "Before boot the slider has not looked at the view")
    EventBus.boot_finished.emit()
    assert_almost_eq(pair.slider.value, 30.0, 0.01, "Boot finds the view and puts its angle on the slider")
    made[1].free()


func test_a_turn_after_boot_moves_the_slider_without_a_touch() -> void:
    var view := Fixtures.FakeView.new()
    var made := _pair(view)
    var pair: SaTopBarRotation = made[0]
    pair.follow()
    view.rotate_at(deg_to_rad(15.0), view.get_viewport_size() * 0.5)
    view.rotate_at(deg_to_rad(60.0), view.get_viewport_size() * 0.5)
    assert_almost_eq(pair.slider.value, 60.0, 0.01, "Two turns of the view leave the slider at its angle")
    made[1].free()


func test_an_opened_document_makes_the_slider_follow() -> void:
    var view := Fixtures.FakeView.new()
    var made := _pair(view)
    var pair: SaTopBarRotation = made[0]
    assert_true(EventBus.document_loaded.is_connected(pair.follow), "The bar hears a document open")
    pair.follow(null)
    view.set_rotation(deg_to_rad(-45.0))
    assert_almost_eq(pair.slider.value, -45.0, 0.01, "and follows the view from then on")
    made[1].free()


func test_without_a_view_following_is_harmless() -> void:
    var made := _pair(null)
    var pair: SaTopBarRotation = made[0]
    pair.follow()
    assert_almost_eq(pair.slider.value, 0.0, 0.01, "A detached bar with no view keeps its slider at 0")
    made[1].free()
