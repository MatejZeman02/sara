## Help > Display Settings held a frame of 340 to 370 ms on its first
## open, and 170 ms of it was the gamut pair baking its picture on the main
## thread as it entered the tree. The page now hands the bake to
## `SaGamutPictureBake`, which runs it on a worker thread, and the pair shows a
## blank stand-in until the picture lands.
##
## A suite cannot await a frame, so it reads the two ends: a page entering the
## tree carries a texture on both halves at once, the stand-in or the picture,
## never none, which is what keeps `SaGamutPreview._enter_tree` from baking, and
## a page leaving the tree claims the bake, so the next one shows the picture
## the moment it enters.
extends "res://tests/test_framework.gd"


func _halves(page: SaDisplayPage) -> Array:
    return page.find_children("*", "SaGamutPreview", true, false)


func _host() -> Node:
    var host := Node.new()
    host.name = "DisplayHost"
    EventBus.add_child(host)
    return host


func test_both_halves_have_a_texture_the_moment_the_page_enters_the_tree() -> void:
    var host := _host()
    var page := SaDisplayPage.new()
    var halves := _halves(page)
    assert_eq(halves.size(), 2, "The page holds the operated half and the plain one")
    host.add_child(page)
    for half: SaGamutPreview in halves:
        assert_true(half.texture != null, "A half has the stand-in or the picture as it enters, so it never bakes itself")
    host.free()


func test_a_page_opened_after_one_has_closed_shows_the_picture_at_once() -> void:
    var host := _host()
    host.add_child(SaDisplayPage.new())
    # Leaving the tree claims the bake, a wait only while it still runs.
    host.free()
    host = _host()
    var page := SaDisplayPage.new()
    host.add_child(page)
    for half: SaGamutPreview in _halves(page):
        assert_true(half.texture is ImageTexture, "The second page's halves carry the baked picture")
        assert_true(half.texture == SaGamutPreview.picture(), "Both halves show the one shared picture")
    host.free()


func test_a_page_the_search_builds_off_the_tree_starts_no_bake() -> void:
    var page := SaDisplayPage.new()
    for half: SaGamutPreview in _halves(page):
        assert_true(half.texture == null, "Off the tree the halves are left as they were built")
    page.free()
