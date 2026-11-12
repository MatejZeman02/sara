## A Main a suite builds leaves the canvas's overlay lists as it found them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A suite builds a `Main`, frees it, and finds both lists as they were before.
## `SaCanvas.overlay_factories` and
## `SaCanvas.surface_overlay_factories` are static, and `main.gd`'s `_init`
## puts what the interface draws over a canvas on them. Nothing took them off,
## so after any suite that built a Main, the freeze suite's `QuietMain` among
## them, every main canvas that entered the tree called the factories, and the
## sky suite's canvas got an Environment view it never asked for. A Main now
## takes off, when it is freed, what it put on.
##
## Each test keeps the lists it found and puts them back, so a failure here
## leaves the next suite what it would have met without this one.
extends "res://tests/test_framework.gd"

const MainScript = preload("res://ui/main/main.gd")


## Main with its boot taken out, as the freeze suite builds it. A Godot 4
## override does not chain to the parent's `_ready`, so this one in the tree
## builds no window and no canvas.
class QuietMain:
    extends "res://ui/main/main.gd"

    func _ready() -> void:
        pass


var _overlays_found: Array[Callable] = []
var _surface_overlays_found: Array[Callable] = []
var _host: Node = null


func before_each() -> void:
    _overlays_found = SaCanvas.overlay_factories
    _surface_overlays_found = SaCanvas.surface_overlay_factories
    _host = Node.new()
    _host.name = "D5TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaCanvas.overlay_factories = _overlays_found
    SaCanvas.surface_overlay_factories = _surface_overlays_found


## A factory no Main registers, standing for one a module or another suite put
## on the canvas's list, which a Main's going must leave alone.
func _outsider(_canvas: SaCanvas) -> void:
    pass


## The same for the main surface's list.
func _surface_outsider(_host_control: Control, _canvas: SaCanvas) -> void:
    pass


## Both lists set to *overlays* and *surface_overlays*, fresh arrays, so what
## a test does to them never reaches the ones `before_each` kept.
func _plant(overlays: Array[Callable], surface_overlays: Array[Callable]) -> void:
    SaCanvas.overlay_factories = overlays.duplicate()
    SaCanvas.surface_overlay_factories = surface_overlays.duplicate()


## What `main.gd`'s `_init` registers on the canvas's list.
func _mains_overlays() -> Array[Callable]:
    return [SaCanvasOverlay.attach_to]


## What it registers on the main surface's list.
func _mains_surface_overlays() -> Array[Callable]:
    return [SaQuickMaskBanner.attach_to, SaEnvironmentView.attach_to]


func _assert_held(list: Array[Callable], factories: Array[Callable], words: String) -> void:
    for factory in factories:
        assert_true(list.has(factory), "%s holds %s" % [words, factory])


func test_a_main_built_and_freed_leaves_both_lists_as_they_were() -> void:
    var overlays: Array[Callable] = [_outsider]
    var surface_overlays: Array[Callable] = [_surface_outsider]
    _plant(overlays, surface_overlays)
    var main := MainScript.new()
    # While it lives the factories are on, or the check below proves nothing.
    _assert_held(SaCanvas.overlay_factories, _mains_overlays(), "the canvas's list with a Main alive")
    _assert_held(SaCanvas.surface_overlay_factories, _mains_surface_overlays(), "the surface's list with a Main alive")
    main.free()
    assert_eq(SaCanvas.overlay_factories, overlays, "The canvas's list is as it was before the Main")
    assert_eq(SaCanvas.surface_overlay_factories, surface_overlays, "The surface's list is as it was before the Main")


func test_both_lists_empty_before_are_empty_after() -> void:
    var none: Array[Callable] = []
    _plant(none, none)
    MainScript.new().free()
    assert_eq(SaCanvas.overlay_factories, none, "The canvas's list holds nothing again")
    assert_eq(SaCanvas.surface_overlay_factories, none, "The surface's list holds nothing again")


## The freeze suite's way: a Main with no boot, in a tree, freed with its host.
func test_a_main_in_a_tree_freed_with_its_host_leaves_both_lists_as_they_were() -> void:
    var none: Array[Callable] = []
    _plant(none, none)
    var main := QuietMain.new()
    main.name = "Main"
    main.is_test_environment = true
    _host.add_child(main)
    _assert_held(SaCanvas.surface_overlay_factories, _mains_surface_overlays(), "the surface's list with a Main in the tree")
    _host.free()
    _host = null
    assert_eq(SaCanvas.overlay_factories, none, "The canvas's list holds nothing again")
    assert_eq(SaCanvas.surface_overlay_factories, none, "The surface's list holds nothing again")


## Lists that already held Main's factories, as the session's own Main leaves
## them, keep them when a second Main comes and goes, because that one added
## nothing and so takes nothing off.
func test_a_main_takes_off_only_what_it_put_on() -> void:
    var overlays := _mains_overlays()
    var surface_overlays := _mains_surface_overlays()
    _plant(overlays, surface_overlays)
    MainScript.new().free()
    assert_eq(SaCanvas.overlay_factories, overlays, "The canvas's list keeps what was on it before")
    assert_eq(SaCanvas.surface_overlay_factories, surface_overlays, "The surface's list keeps what was on it before")
