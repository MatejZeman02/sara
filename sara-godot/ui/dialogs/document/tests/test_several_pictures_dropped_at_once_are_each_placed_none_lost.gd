## Several pictures dropped at once are each placed, none lost.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A drop calls `SaImportFitDialog.place` once for each picture before the
## painter has answered any, and the one window rebound itself to each call,
## so only the last picture's answer stood. The questions now wait their turn.
## The screen is a `SubViewport` with subwindows embedded, the seam
## `test_u486` uses, so the window can be shown in a headless run.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks.
const REQUIRES_GPU := true

const CANVAS := Vector2i(1920, 1080)
const RED := Vector2i(300, 200)
const BLUE := Vector2i(500, 400)

var _kept_fit: String = ""
var _kept_embedding: bool = true
var _host: Node = null
var _screen: SubViewport = null
var _easel: SaEasel = null


func before_each() -> void:
    _kept_fit = SaSettings.import_fit
    SaSettings.import_fit = "ask"
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "H901DropHost"
    EventBus.add_child(_host)
    _screen = SubViewport.new()
    _screen.size = Vector2i(1280, 800)
    _screen.gui_embed_subwindows = true
    _host.add_child(_screen)
    _easel = SaEasel.create_default(CANVAS)


func after_each() -> void:
    SaSettings.import_fit = _kept_fit
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _easel != null and is_instance_valid(_easel):
        _easel.free()
    if _host != null and is_instance_valid(_host):
        _host.free()
    _easel = null
    _host = null
    _screen = null


func _picture(size: Vector2i, colour: Color) -> Image:
    var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(colour)
    return image


func _dialog() -> SaImportFitDialog:
    return _screen.get_node_or_null(^"ImportFitDialog") as SaImportFitDialog


## Drops red and then blue, each handing its layer to its own list, as
## `_route_drop` calls `place` once per picture.
func _drop_two(placed_red: Array[SaLayer], placed_blue: Array[SaLayer]) -> void:
    var document := _easel.document
    var srgb := SaColorSpace.srgb()
    SaImportFitDialog.place(
        _screen, document, _picture(RED, Color.RED), "red", srgb, func(layer: SaLayer) -> void: placed_red.append(layer)
    )
    SaImportFitDialog.place(
        _screen, document, _picture(BLUE, Color.BLUE), "blue", srgb, func(layer: SaLayer) -> void: placed_blue.append(layer)
    )


func _press(button_name: String) -> void:
    (_dialog().find_child(button_name, true, false) as Button).pressed.emit()


## The window is shown again on the idle moment after an answer.
func _next_question() -> void:
    await (Engine.get_main_loop() as SceneTree).process_frame


func test_two_pictures_each_answered_are_both_placed() -> void:
    var before := _easel.document.get_child_count()
    var placed_red: Array[SaLayer] = []
    var placed_blue: Array[SaLayer] = []
    _drop_two(placed_red, placed_blue)
    var dialog := _dialog()
    assert_not_null(dialog, "The drop asked")
    if dialog == null:
        return
    assert_true(dialog.visible, "and one question is up")
    assert_eq(_easel.document.get_child_count(), before, "Nothing landed before an answer")
    _press("PlaceButton")
    assert_eq(placed_red.size(), 1, "The first answer placed the first picture")
    assert_eq(placed_blue.size(), 0, "and not the second")
    await _next_question()
    assert_true(dialog.visible, "The second picture is asked about in its turn")
    _press("PlaceButton")
    assert_eq(placed_blue.size(), 1, "and its answer placed it")
    assert_eq(placed_red.size(), 1, "and not the first again")
    assert_eq(_easel.document.get_child_count(), before + 2, "Two new layers, one per picture")
    if placed_red.size() == 1 and placed_blue.size() == 1:
        assert_eq(placed_red[0].shown_name(), "red", "The first is named after its file")
        assert_eq(placed_blue[0].shown_name(), "blue", "and so is the second")
    await _next_question()
    assert_false(dialog.visible, "and nothing more is asked")


func test_a_cancel_on_the_first_places_the_second_only() -> void:
    var before := _easel.document.get_child_count()
    var placed_red: Array[SaLayer] = []
    var placed_blue: Array[SaLayer] = []
    _drop_two(placed_red, placed_blue)
    if _dialog() == null:
        assert_not_null(_dialog(), "The drop asked")
        return
    _press("CancelButton")
    assert_eq(placed_red.size(), 0, "The cancelled picture is not placed")
    await _next_question()
    assert_true(_dialog().visible, "The second picture is still asked about")
    _press("PlaceButton")
    assert_eq(placed_red.size(), 0, "and nothing is said to be placed for the first")
    assert_eq(placed_blue.size(), 1, "The second is placed")
    assert_eq(_easel.document.get_child_count(), before + 1, "and is the one new layer")


func test_do_not_ask_again_answers_for_the_rest() -> void:
    var placed_red: Array[SaLayer] = []
    var placed_blue: Array[SaLayer] = []
    _drop_two(placed_red, placed_blue)
    if _dialog() == null:
        assert_not_null(_dialog(), "The drop asked")
        return
    _dialog().remember = true
    _press("PlaceButton")
    await _next_question()
    assert_false(_dialog().visible, "The stored fit answers the waiting question")
    assert_eq(placed_blue.size(), 1, "and places the second picture with it")


func test_one_picture_asks_once_and_places_once() -> void:
    var placed: Array[SaLayer] = []
    SaImportFitDialog.place(
        _screen,
        _easel.document,
        _picture(RED, Color.RED),
        "red",
        SaColorSpace.srgb(),
        func(layer: SaLayer) -> void: placed.append(layer)
    )
    assert_true(_dialog() != null and _dialog().visible, "One picture asks")
    _press("PlaceButton")
    assert_eq(placed.size(), 1, "and places once")
    await _next_question()
    assert_false(_dialog().visible, "and asks nothing more")
