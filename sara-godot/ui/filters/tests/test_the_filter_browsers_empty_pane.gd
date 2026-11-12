## The filter browser's pane before a pick. The sentence says
## what a pick will show a painter rather than where the list comes from, the
## box under it is captioned Preview, and it holds the active layer as it stands
## until a filter is picked. The dark box is left for a document with no layer
## and for a layer with nothing painted, whose picture would draw as that box.
##
## On a detached Filters docker, like `test_filter_browser.gd`, because a
## `Window` added to the tree maps a real OS window and hangs the runner. The
## document reaches the detached docker's browser through `target_canvas`, a
## bench canvas over a bench easel, the way the layers docker's suites reach
## theirs.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const GREY := Color(0.25, 0.5, 0.75, 1.0)
const SENTENCE := "Select a filter to see what it does to the active layer."

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _docker: FiltersDocker = null


func before_each() -> void:
    # Two chunks across and two down with only (0, 0) painted, so the layer's
    # picture has bounds of one chunk and a colour to read back.
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    var layer := _easel.document.active_layer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(GREY)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel


func after_each() -> void:
    if _docker != null:
        _docker.free()
    _docker = null
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null


## A docker over one registered filter, on the bench canvas or on none, shown
## or left hidden the way the boot leaves it.
func _build(on_canvas: bool, shown: bool) -> FiltersDocker:
    _docker = FiltersDocker.new()
    if on_canvas:
        _docker.browser.target_canvas = _canvas
    # Outside the tree this only records the flag, which is all the browser's
    # `is_shown` reads, so no OS window is mapped.
    _docker.visible = shown
    var filters := SaFilterRegistry.new()
    filters.register(Bench.InvertFilter.new(), Bench.OWNER)
    _docker.browser.watch(filters, SaCommandRegistry.new())
    return _docker


func test_the_sentence_says_what_a_pick_shows() -> void:
    var said := _build(true, true).describe()
    assert_eq(said["selected"], "", "Nothing is picked")
    assert_eq(said["title"], "No filter selected", "under a heading that says where the pane stands, which its sentence does not")
    assert_eq(said["sentence"], SENTENCE, "and the sentence speaks of the layer, not of modules")
    assert_false(said["can_open"], "Open waits for a pick")


func test_the_box_is_captioned_preview() -> void:
    var docker := _build(true, true)
    var caption := docker.browser._preview.caption
    assert_not_null(caption, "The box carries a caption")
    if caption == null:
        return
    assert_eq(caption.text, "Preview", "which says what the box is")
    assert_true(caption.visible, "and is shown")
    assert_eq(caption.get_parent(), docker.browser._preview, "over the picture it names")


func test_the_box_holds_the_active_layer_before_a_pick() -> void:
    var steps := _easel.document.history.step_count()
    var docker := _build(true, true)
    var preview: Dictionary = docker.describe()["preview"]
    assert_true(preview["holds_texture"], "The box holds a picture with nothing picked")
    assert_eq(preview["rect"], [0, 0, SaChunk.SIZE, SaChunk.SIZE], "over the painted chunk")
    var held: SaTexture = docker.browser._preview._held
    if held == null:
        return
    assert_eq(held.size, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "at the layer's own density")
    var texel := Bench.texel(held, Vector2i(10, 10))
    assert_almost_eq(texel.r, GREY.r, 1e-4, "and it is the layer unfiltered: %s" % texel)
    assert_almost_eq(texel.b, GREY.b, 1e-4, "in every channel")
    assert_eq(_easel.document.history.step_count(), steps, "The picture recorded no step")
    assert_eq(_easel.document.active_layer.chunks.size(), 1, "and allocated no chunk")


func test_a_pick_and_its_clearing_come_back_to_the_layer() -> void:
    var docker := _build(true, true)
    docker.browser.pick(Bench.INVERT)
    assert_false(docker.describe()["sentence"] == SENTENCE, "A pick replaces the sentence")
    docker.browser.pick(&"")
    var said := docker.describe()
    assert_eq(said["sentence"], SENTENCE, "and clearing it brings the sentence back")
    assert_true(said["preview"]["holds_texture"], "with the layer in the box")


## Shown again with a pick, the box previews the pick again. A hide drops the
## picture, and a show no refresh came before ran nothing, so the Filters docker
## shown in its strip read "Preview" over an empty box.
func test_a_show_previews_the_pick_again() -> void:
    var docker := _build(true, true)
    docker.browser.pick(Bench.INVERT)
    assert_true(docker.describe()["preview"]["holds_texture"], "The pick is previewed")
    # Outside the tree the flag is all a show writes, so the call the docker's
    # `visibility_changed` makes is made here.
    docker.visible = false
    docker.browser.follow_window()
    assert_false(docker.describe()["preview"]["holds_texture"], "A hidden docker holds no picture")
    docker.visible = true
    docker.browser.follow_window()
    assert_true(docker.describe()["preview"]["holds_texture"], "and shown again it previews the pick again")


func test_the_dark_box_is_left_for_no_layer() -> void:
    var said := _build(false, true).describe()
    assert_eq(said["sentence"], SENTENCE, "With no document the sentence is the same")
    assert_false(said["preview"]["holds_texture"], "and the box is empty, there being no layer to show")


func test_an_empty_layer_is_the_dark_box_as_well() -> void:
    var layer := _easel.document.active_layer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    var said := _build(true, true).describe()
    assert_eq(said["sentence"], SENTENCE, "An empty layer is spoken of the same way")
    assert_false(said["preview"]["holds_texture"], "and its transparent picture is not made, the box already draws it")


func test_a_hidden_browser_holds_no_picture() -> void:
    var docker := _build(true, false)
    assert_false(docker.describe()["preview"]["holds_texture"], "Hidden at boot, the browser holds nothing")
