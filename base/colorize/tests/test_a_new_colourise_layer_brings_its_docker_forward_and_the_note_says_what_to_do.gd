## Making a Colourise layer brings its docker to the painter, once, and the
## docker says in plain words what to do and when the layer has no line art.
##
## The host that holds the dockers is a stand-in found by name, as the real
## one is, that counts the toggles it is asked for. A layer that already holds
## scribbles, which is a file that was opened, does not ask for the docker, and
## neither does a second look at a layer the docker was brought for once.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SaColorize = preload("res://modules/sara-base-modules/base/colorize/sa_colorize.gd")
const SaColorizeDocker = preload("res://modules/sara-base-modules/base/colorize/sa_colorize_docker.gd")
const MODULE := &"sara-base-modules"


class StubManager:
    extends Node

    var asked: Array[StringName] = []

    func toggle_docker_by_id(docker_id: StringName) -> void:
        asked.append(docker_id)


var _surface: SaSurface = null
var _registries: SaRegistries = null
var _colorize: SaColorize = null
var _manager: StubManager = null
var _docker: Window = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _registries = Fixtures.make_registries(_surface)
    var ctx := _registries.context.for_module(MODULE)
    _colorize = SaColorize.new(ctx)
    ctx.register_layer_type(_colorize.descriptor())
    _manager = StubManager.new()
    _manager.name = "MainDockers"
    EventBus.add_child(_manager)
    _docker = SaColorizeDocker.new(_colorize)
    EventBus.add_child(_docker)


func after_each() -> void:
    if _docker != null:
        _docker.free()
        _docker = null
    if _manager != null:
        _manager.free()
        _manager = null
    Fixtures.teardown(_surface)
    _surface = null
    _registries = null
    _colorize = null


func test_a_new_colourise_layer_asks_for_its_docker_once() -> void:
    var layer := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, _surface.get_document())
    _docker.introduce(layer)
    assert_eq(_manager.asked, [SaColorizeDocker.DOCKER_ID] as Array[StringName], "The docker is brought forward")
    _docker.introduce(layer)
    assert_eq(_manager.asked.size(), 1, "and only once for the layer, so closing it is final")


func test_a_layer_that_holds_scribbles_or_is_not_colourise_asks_for_nothing() -> void:
    var doc := _surface.get_document()
    var held := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, doc)
    held.get_or_create_chunk(Vector2i.ZERO)
    _docker.introduce(held)
    _docker.introduce(doc.active_layer)
    assert_eq(_manager.asked.size(), 0, "An opened layer and a paint layer leave the docker where it was")


func test_the_note_says_what_to_do_and_that_a_layer_needs_line_art() -> void:
    var doc := _surface.get_document()
    var layer := _registries.context.for_module(MODULE).create_layer(SaColorize.TYPE, doc)
    _docker.follow(layer)
    var howto: SaPageRow = _docker.page.row(&"howto")
    var needs: SaPageRow = _docker.page.row(&"needs_lines")
    assert_not_null(howto, "The page has the how-to note")
    assert_true("Update" in howto.explanation, "which names the Update button")
    assert_true(howto.line.visible, "and shows while a Colourise layer is active")
    _docker.call("_show_active")
    assert_true(needs.line.visible, "A layer reading nothing is told it needs line art")
    var art := SaLayerOps.new(doc).add()
    art.name = "Ink"
    art.get_or_create_chunk(Vector2i.ZERO)
    _colorize.choose(layer, "line_art", "Ink")
    _docker.call("_show_active")
    assert_false(needs.line.visible, "and the warning goes once there is paint to read")
