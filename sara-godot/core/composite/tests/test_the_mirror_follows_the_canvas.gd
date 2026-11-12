## The symmetry's centre follows a canvas that changes size.
## The symmetry object stays for the window's life, because the tool options'
## toggles listen to it, and its centre stayed with it: a large document
## followed by a small one mirrored about a point past the small one's edge.
extends "res://tests/test_framework.gd"


func test_a_centre_left_in_the_middle_moves_to_the_new_middle() -> void:
    var easel := SaEasel.create_default(Vector2i(1024, 1024))
    var doc := easel.document
    doc.symmetry.mirror_horizontal = true
    doc.reset_to_default(Vector2i(100, 60))
    assert_eq(doc.symmetry.center, Vector2(50, 30), "The axes cross in the middle of the new canvas")
    assert_true(doc.symmetry.mirror_horizontal, "and the switch the painter pressed stays pressed")
    easel.free()


func test_a_moved_centre_inside_the_new_canvas_is_kept() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.symmetry.center = Vector2(40, 40)
    doc.canvas_size = Vector2i(256, 256)
    assert_eq(doc.symmetry.center, Vector2(40, 40), "A centre the painter placed and that still fits is theirs")
    easel.free()


func test_a_moved_centre_the_new_canvas_leaves_out_comes_back_in() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.symmetry.center = Vector2(400, 40)
    doc.canvas_size = Vector2i(256, 128)
    assert_eq(doc.symmetry.center, Vector2(128, 64), "A centre past the new edge goes to the middle")
    easel.free()
