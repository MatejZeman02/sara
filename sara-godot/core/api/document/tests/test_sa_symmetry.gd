## Symmetry: the map from one point to its images, the regions the
## paint context makes of them, each with its own dirty rectangle, and the
## barrier only two images sharing a chunk need.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the document's chunks.
const REQUIRES_GPU := true


func _symmetry(center: Vector2 = Vector2(128, 128)) -> SaSymmetry:
    var symmetry := SaSymmetry.new()
    symmetry.center = center
    return symmetry


func test_a_mirror_reflects_across_the_axis_through_the_centre() -> void:
    var symmetry := _symmetry()
    symmetry.mirror_horizontal = true
    var images := symmetry.images(Vector2(10, 20))
    assert_eq(images.size(), 2, "One point becomes two")
    assert_eq(images[0], Vector2(10, 20), "the original first")
    assert_eq(images[1], Vector2(246, 20), "and its reflection across the vertical axis at 128")

    symmetry.mirror_vertical = true
    images = symmetry.images(Vector2(10, 20))
    assert_eq(images.size(), 4, "Both mirrors make four")
    assert_true(images.has(Vector2(246, 236)), "including the corner opposite")


func test_a_point_on_the_axis_is_not_doubled() -> void:
    var symmetry := _symmetry()
    symmetry.mirror_horizontal = true
    assert_eq(symmetry.images(Vector2(128, 40)).size(), 1, "A dab on the axis is one dab, not two on top of each other")


func test_radial_rotates_about_the_centre() -> void:
    var symmetry := _symmetry()
    symmetry.radial = 4
    var images := symmetry.images(Vector2(228, 128))
    assert_eq(images.size(), 4, "Four copies")
    assert_true(images[1].is_equal_approx(Vector2(128, 228)), "a quarter turn on")
    assert_true(images[2].is_equal_approx(Vector2(28, 128)), "half a turn")
    assert_true(images[3].is_equal_approx(Vector2(128, 28)), "and three quarters")

    symmetry.radial = 1
    assert_eq(symmetry.radial, 0, "Fewer than two copies is off")
    symmetry.radial = 100
    assert_eq(symmetry.radial, SaSymmetry.MAX_RADIAL, "and the count is capped")


func test_every_setter_announces() -> void:
    var symmetry := _symmetry()
    var heard: Array[bool] = []
    symmetry.changed.connect(func() -> void: heard.append(true))
    symmetry.mirror_horizontal = true
    symmetry.mirror_horizontal = true
    symmetry.radial = 6
    symmetry.center = Vector2(10, 10)
    assert_eq(heard.size(), 3, "Each change once, and a repeat not at all")
    assert_true(symmetry.is_active(), "and the switches say so")


## The check the unit is done on: a mirrored dab computes its own dirty rect.
func test_a_mirrored_dab_computes_its_own_dirty_rect() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    var doc := easel.document
    doc.symmetry.mirror_horizontal = true
    doc.consume_dirty_chunks()

    var paint := SaPaintContext.for_region(doc, Rect2(20, 100, 20, 20), false, 0.0)
    assert_eq(paint.targets.size(), 2, "Two targets, one per image")
    assert_eq(paint.targets[0].grid_pos, Vector2i(0, 0), "the dab's own chunk")
    assert_eq(paint.targets[1].grid_pos, Vector2i(1, 0), "and the chunk its reflection lands in")
    assert_true(paint.targets[1].local_center.is_equal_approx(Vector2(226, 110)), "centred on the reflection, chunk local")
    assert_eq(paint.passes(), 1, "Disjoint chunks share one list")

    paint.commit_invalidation()
    var dirty := doc.consume_dirty_chunks()
    assert_eq(dirty.size(), 2, "Two chunks dirty")
    var right: Rect2i = dirty[Vector2i(1, 0)]
    assert_true(right.size.x <= 32 and right.size.y <= 32, "each by its own small box, not the union: %s" % right)
    assert_true(right.position.x >= 208 and right.end.x <= 248, "around the reflection at 226")

    easel.free()


## Two images in one chunk would write the same texels inside one list, so the
## second waits for a barrier. Only then.
func test_images_that_share_a_chunk_get_a_barrier_between_them() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    var doc := easel.document
    # The axis inside a chunk rather than on its boundary, so both images of a
    # dab beside it land in the one chunk.
    doc.symmetry.center = Vector2(128, 128)
    doc.symmetry.mirror_horizontal = true

    var near_axis := SaPaintContext.for_region(doc, Rect2(100, 100, 20, 20), false, 0.0)
    assert_eq(near_axis.targets.size(), 2, "Two images")
    assert_eq(near_axis.targets[1].grid_pos, near_axis.targets[0].grid_pos, "in the same chunk")
    assert_eq(near_axis.passes(), 2, "so two lists")

    doc.symmetry.mirror_horizontal = false
    var alone := SaPaintContext.for_region(doc, Rect2(100, 100, 20, 20), false, 0.0)
    assert_eq(alone.passes(), 1, "and one image is one list, as before")

    easel.free()


func test_the_commands_flip_the_document_switches() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    assert_true(registries.commands.execute(&"symmetry_horizontal"), "The command runs")
    assert_true(doc.symmetry.mirror_horizontal, "and mirrors")
    registries.commands.execute(&"symmetry_radial")
    assert_eq(doc.symmetry.radial, doc.symmetry.radial_count, "Radial takes the count")
    registries.commands.execute(&"symmetry_radial")
    assert_eq(doc.symmetry.radial, 0, "and off again")
    Fixtures.teardown(surface)
