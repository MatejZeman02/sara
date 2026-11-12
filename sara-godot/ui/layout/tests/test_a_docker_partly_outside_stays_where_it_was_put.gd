## A docker partly outside the window stays where it was put.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker may leave the window border and stay in place even when out of
## canvas. A reflow leaves it while
## [constant SaDockerLayoutFit.STRIP_IN_REACH] of its title strip is on the
## window, moves it only as far as brings the strip back, and the store's
## intent returns it to the painter's place when the window grows. Built the
## way the intent suite beside this builds a store, over one docker embedded in
## a host viewport.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1280, 1024)
const SIZE := Vector2i(300, 400)

## Where the docker opens, whole inside, so the store notes the host the
## layout was arranged on.
const OPENED := Vector2i(600, 300)

## Where the painter puts it, 120 of its 300 past the right edge.
const PUT := Vector2i(1100, 300)

const STRIP := SaDockerLayoutFit.STRIP_IN_REACH

const SCRATCH := "test_docker_layout.cfg"

var _root: Node = null
var _viewport: SubViewport = null
var _docker: Window = null
var _store: DockerLayoutStore = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _root = Node.new()
    _root.name = "U42PartlyOutsideTestHost"
    EventBus.add_child(_root)

    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)

    var host := Control.new()
    host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(host)

    _docker = Window.new()
    _docker.size = SIZE
    host.add_child(_docker)
    _docker.position = OPENED

    _store = DockerLayoutStore.new()
    _store.path = SaDataRoot.path(SCRATCH)
    _store.dockers_provider = func() -> Array: return [{"name": "Probe", "node": _docker}]
    _store.save_allowed = func() -> bool: return true
    _root.add_child(_store)

    _store.save()
    _docker.position = PUT
    _store.save(true)


func after_each() -> void:
    if _root != null:
        _root.free()
        _root = null
    if FileAccess.file_exists(SaDataRoot.path(SCRATCH)):
        DirAccess.remove_absolute(SaDataRoot.path(SCRATCH))


## A shrink of 40 leaves 140 of the docker's 300 on the window, more than the
## 128 its strip keeps, so it does not move, and a reflow at the same size is
## none.
func test_a_shrink_that_leaves_the_strip_in_reach_moves_nothing() -> void:
    _store.reflow_to_host()
    assert_eq(_docker.position, PUT, "Partly outside, and where the painter put it")
    _resize(Vector2i(1240, HOST.y))
    assert_eq(_docker.position, PUT, "The strip is still in reach, so the docker stands")


## A shrink of 100 would leave 80 of the strip, and the docker comes in by the
## 48 that brings 128 back, sideways alone.
func test_a_shrink_past_the_strip_brings_only_the_strip_back() -> void:
    _resize(Vector2i(1240, HOST.y))
    _resize(Vector2i(1180, HOST.y))
    assert_eq(_docker.position, Vector2i(1180 - STRIP.x, PUT.y), "Only as far as the strip needs, and not up or down")
    assert_true(_docker.position.x + SIZE.x > 1180, "It still stands partly outside")


## The window grown back returns the docker to the painter's place, through the
## intent the store keeps, with a save of a lost focus between.
func test_growing_the_window_again_returns_it_to_where_it_was_put() -> void:
    _resize(Vector2i(1180, HOST.y))
    _store.save()
    _resize(HOST)
    assert_eq(_docker.position, PUT, "Back where the painter put it, partly outside")


## The foot works the same way: a docker put 300 past the window's foot keeps
## its place while the strip is in, and comes up by what a shorter window takes.
func test_a_docker_past_the_foot_stays_until_its_strip_would_leave() -> void:
    var low := Vector2i(400, 900)
    _docker.position = low
    _store.save(true)
    _resize(Vector2i(HOST.x, 940))
    assert_eq(_docker.position, low, "The strip's foot at 924, inside 940")
    _resize(Vector2i(HOST.x, 900))
    assert_eq(_docker.position, Vector2i(400, 900 - STRIP.y), "Up by what keeps the strip's height")
    _resize(HOST)
    assert_eq(_docker.position, low, "and back down when the window grows")


## A scale change is a host that keeps its pixels and changes its logical
## size, here the 1280 by 1024 window at 1.25, 1024 by 819 logical units. A
## docker standing whole at 850 keeps its place with 174 of its 300 on the host,
## the one put 120 past the edge comes in to 896 with its strip, and scale 1
## again returns both.
func test_a_scale_change_moves_a_docker_only_as_far_as_its_strip_needs() -> void:
    var whole := Vector2i(850, 300)
    _docker.position = whole
    _store.save(true)
    _scale(1.25)
    assert_eq(_docker.position, whole, "Its strip still in reach at 1.25, so it stands")
    _scale(1.0)
    _docker.position = PUT
    _store.save(true)
    _scale(1.25)
    assert_eq(_docker.position, Vector2i(1024 - STRIP.x, PUT.y), "Only as far as the strip needs at 1.25")
    _scale(1.0)
    assert_eq(_docker.position, PUT, "and back where the painter put it at 1")


func _resize(to: Vector2i) -> void:
    _viewport.size = to
    _store.reflow_to_host()


func _scale(factor: float) -> void:
    _viewport.size_2d_override = Vector2i(Vector2(HOST) / factor) if factor != 1.0 else Vector2i()
    _viewport.size_2d_override_stretch = factor != 1.0
    _store.reflow_to_host()
