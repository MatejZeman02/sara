## A welcome opening composes its picture off the frame and builds its news once.
##
## The Welcome window's first open held a frame of 496 ms. The time a frame takes is
## the `...` scenario's to read, so
## this suite holds what the cut rests on: the news rows wait for their tab,
## a picture whose parts are kept is composed on the pool into the same
## picture the frame composed itself, and a band freed while it
## composes waits for its task rather than leaving it running.
extends "res://tests/test_framework.gd"

## An hour the shipped picture shows in parts, as the clouds suite reads it.
const HOUR: float = 13.0


func after_each() -> void:
    PictureParts.keep_only(PackedStringArray())


## The parts the shipped picture shows at `HOUR`, which `PictureParts` then
## holds decoded.
func _keep_the_parts_of(band: WelcomePicture) -> void:
    for file in WelcomePicture.parts_at(band.lights, band.parts, band.beneath.overlays, HOUR, "", null):
        PictureParts.keep(file)


func test_a_lazy_news_pane_builds_its_sections_when_its_tab_comes_to_the_front() -> void:
    var tabs := TabContainer.new()
    var first := Control.new()
    first.name = "First"
    tabs.add_child(first)
    var pane := WelcomeNewsPane.new(true)
    assert_true(pane._built_for.is_empty(), "built with lazy, the pane reads nothing")
    tabs.add_child(pane)
    var tree := Engine.get_main_loop() as SceneTree
    # The root is busy adding the run's own nodes until a frame has passed.
    await tree.process_frame
    tree.root.add_child(tabs)
    await tree.process_frame
    assert_true(pane._built_for.is_empty(), "nor once in a tab behind another")
    tabs.current_tab = 1
    await tree.process_frame
    assert_eq(pane._built_for, pane._reading(), "and reads the sections when its tab is in front")
    tabs.free()


func test_a_news_pane_built_on_its_own_builds_at_once() -> void:
    var pane := WelcomeNewsPane.new()
    assert_eq(pane._built_for, pane._reading(), "a suite's pane is read at construction, as it always was")
    pane.free()


func test_a_picture_whose_parts_are_kept_is_composed_on_the_pool_into_the_same_picture() -> void:
    var band := WelcomePicture.new()
    band.settle()
    band.drift = 0.4
    PictureParts.keep_only(PackedStringArray())
    band.show_at(HOUR, "", null)
    assert_true(band.picture.texture is ImageTexture, "with nothing kept, the frame composes the picture itself")
    var here := (band.picture.texture as ImageTexture).get_image()
    _keep_the_parts_of(band)
    band.show_at(HOUR, "", null)
    assert_null(band.picture.texture, "with every part kept, the frame leaves it to the pool")
    band.settle()
    assert_true(band.picture.texture is ImageTexture, "and shows it once it is made")
    var pooled := (band.picture.texture as ImageTexture).get_image()
    assert_eq(pooled.get_size(), here.get_size(), "at the size the frame made it")
    assert_true(pooled.get_data() == here.get_data(), "texel for texel")
    band.free()


func test_a_picture_composing_on_the_pool_is_shown_by_a_frame() -> void:
    var band := WelcomePicture.new()
    band.settle()
    _keep_the_parts_of(band)
    var tree := Engine.get_main_loop() as SceneTree
    # The root is busy adding the run's own nodes until a frame has passed.
    await tree.process_frame
    tree.root.add_child(band)
    band.show_at(HOUR, "", null)
    for frame in 60:
        if band.picture.texture != null:
            break
        await tree.process_frame
    assert_true(band.picture.texture is ImageTexture, "a band in the tree shows the picture within a second")
    band.free()


func test_a_band_freed_while_its_picture_composes_waits_for_the_task() -> void:
    var band := WelcomePicture.new()
    band.settle()
    _keep_the_parts_of(band)
    band.show_at(HOUR, "", null)
    assert_true(band._task >= 0, "the picture is composing on the pool")
    band.free()
    assert_true(true, "and freeing the band waited for it rather than leaving the task to a freed band")
