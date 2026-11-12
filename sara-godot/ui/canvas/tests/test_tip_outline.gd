## The cursor takes the image tip's shape.
##
## The brush circle cursor copies the image mask shape when a brush uses an
## image, and what it takes is a silhouette: for each of sixty-four angles, the
## furthest texel out from the centre whose coverage reaches a half.
##
## Every assertion here is about the numbers, because a cursor is drawn over the
## canvas and the shot of one is a few white pixels: `scenarios/image-tip-outline-on-the-cursor.json`
## is the half that runs on the app, and it carries the shot.
extends "res://tests/test_framework.gd"

const TipImage = preload("res://core/api/tip/sa_tip_image.gd")

static var scratch: String = SaDataRoot.path("test_a7_tips")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
    TipImage.forget_outlines()


func after_each() -> void:
    TipImage.forget_outlines()
    var dir := DirAccess.open(scratch)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)


## A tip whose coverage is *shape*, a Callable taking a texel and answering
## whether it is inside.
func _tip(side: int, shape: Callable) -> TipImage.Tip:
    var tip := TipImage.Tip.new()
    tip.size = Vector2i(side, side)
    tip.mask.resize(side * side)
    for y in side:
        for x in side:
            tip.mask[y * side + x] = 1.0 if bool(shape.call(x, y)) else 0.0
    return tip


## A disc of *radius* about the centre of a *side* square.
func _disc(side: int, radius: float) -> TipImage.Tip:
    var centre := Vector2(side, side) * 0.5
    return _tip(side, func(x: int, y: int) -> bool: return Vector2(x, y).distance_to(centre) <= radius)


## A round tip reads as a circle: every point of the silhouette is the same
## distance from the centre, which is the shape the ring already was.
func test_a_round_tip_reads_as_a_circle() -> void:
    var outline := _disc(64, 30.0).outline()

    assert_eq(outline.size(), TipImage.OUTLINE_SAMPLES, "One point per ray")
    for point: Vector2 in outline:
        assert_almost_eq(point.length(), 1.0, 0.05, "and every one is a radius out")


## A square tip reads as a square: the corners are further out than the sides by
## the root of two, which is what makes the outline a shape rather than a
## rescaled circle.
func test_a_square_tip_reads_as_a_square() -> void:
    var side := 64
    var outline := _tip(side, func(x: int, y: int) -> bool: return x >= 8 and x < 56 and y >= 8 and y < 56).outline()

    var shortest := INF
    var longest := 0.0
    for point: Vector2 in outline:
        shortest = minf(shortest, point.length())
        longest = maxf(longest, point.length())
    assert_almost_eq(longest, 1.0, 0.001, "The furthest point is the unit")
    assert_almost_eq(longest / shortest, sqrt(2.0), 0.08, "and a square's corner is root two of its side")


## A tip with nothing on it has no shape to draw, which leaves the ring a
## circle rather than drawing a point.
func test_an_empty_tip_has_no_outline() -> void:
    assert_true(_tip(16, func(_x: int, _y: int) -> bool: return false).outline().is_empty(), "No coverage, no shape")

    var refused := TipImage.Tip.new()
    refused.error = "no"
    assert_true(refused.outline().is_empty(), "and a refusal has none either")


## Built once and kept, because the ring is drawn every frame the pointer moves
## and a tip changes when a painter loads one.
func test_the_outline_is_built_once() -> void:
    var tip := _disc(48, 20.0)
    var first := tip.outline()
    assert_true(tip.outline() == first, "The second ask is the first answer")


## The transform is the tip's own: narrowed on its minor axis first, then
## turned, so a flattened tip turns as a flattened tip.
func test_the_outline_is_narrowed_then_turned() -> void:
    var path := scratch.path_join("disc.png")
    _write_disc(path, 64, 28.0)

    var plain := TipImage.cursor_outline(path, 0.0, 1.0, false)
    assert_false(plain.is_empty(), "The tip loads")
    for point: Vector2 in plain:
        assert_almost_eq(point.length(), 1.0, 0.06, "A round tip at no ratio is a circle")

    var flat := TipImage.cursor_outline(path, 0.0, 0.5, false)
    var widest := 0.0
    var tallest := 0.0
    for point: Vector2 in flat:
        widest = maxf(widest, absf(point.x))
        tallest = maxf(tallest, absf(point.y))
    assert_almost_eq(widest, 1.0, 0.06, "Half the ratio leaves the major axis alone")
    assert_almost_eq(tallest, 0.5, 0.06, "and halves the minor one")

    # A quarter turn takes the narrow axis onto x, which is the whole point of
    # narrowing before turning rather than after.
    var turned := TipImage.cursor_outline(path, PI * 0.5, 0.5, false)
    var turned_widest := 0.0
    for point: Vector2 in turned:
        turned_widest = maxf(turned_widest, absf(point.x))
    assert_almost_eq(turned_widest, 0.5, 0.06, "A quarter turn puts the narrow axis across")


## One mirrored axis turns a right-handed frame left-handed, so the angle
## measured in it runs the other way. The same seam the dab's own box has.
func test_a_mirrored_tip_turns_the_other_way() -> void:
    var path := scratch.path_join("wide.png")
    _write_rect(path, 64, 26, 10)

    var turned := TipImage.cursor_outline(path, 0.4, 1.0, false)
    var flipped := TipImage.cursor_outline(path, 0.4, 1.0, true)

    assert_eq(turned.size(), flipped.size(), "Same shape, same points")
    var mirrored_back := PackedVector2Array()
    for point: Vector2 in flipped:
        mirrored_back.append(point)
    var matched := 0
    for point: Vector2 in turned:
        for other: Vector2 in mirrored_back:
            if point.distance_to(Vector2(other.x, -other.y)) < 0.02:
                matched += 1
                break
    assert_true(matched * 2 > turned.size(), "and one is the other reflected: %d of %d" % [matched, turned.size()])


## A path that is not a tip answers nothing, which is what leaves the ring a
## circle for a procedural brush and for a load that failed.
func test_a_path_that_is_not_a_tip_answers_nothing() -> void:
    assert_true(TipImage.cursor_outline("", 0.0, 1.0, false).is_empty(), "No path, no shape")
    assert_true(TipImage.cursor_outline(SaDataRoot.path("nothing.png"), 0.0, 1.0, false).is_empty(), "and no file, no shape")


## Settings holding a procedural tip answer nothing, and settings holding an
## image tip answer its shape. The door the descriptor binds.
func test_settings_answer_for_the_tip_they_hold() -> void:
    var path := scratch.path_join("disc.png")
    _write_disc(path, 64, 28.0)

    var settings := SaStampBrushSettings.new()
    assert_true(TipImage.outline_of(settings).is_empty(), "A procedural tip has no shape of its own")
    assert_true(TipImage.outline_of(null).is_empty(), "and no settings at all is not a crash")

    settings.tip.generator = SaDabGeometry.Generator.IMAGE
    settings.tip.image_path = path
    assert_true(settings.tip.uses_image(), "The tip is an image one now")
    assert_false(TipImage.outline_of(settings).is_empty(), "so the settings answer its shape")


## A PNG whose alpha is a disc of *radius* about the centre of a *side* square.
func _write_disc(path: String, side: int, radius: float) -> void:
    var centre := Vector2(side, side) * 0.5
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
    for y in side:
        for x in side:
            var inside := Vector2(x, y).distance_to(centre) <= radius
            image.set_pixel(x, y, Color(0, 0, 0, 1.0 if inside else 0.0))
    image.save_png(ProjectSettings.globalize_path(path))


## A PNG whose alpha is a *half_width* by *half_height* rectangle about the
## centre of a *side* square.
func _write_rect(path: String, side: int, half_width: int, half_height: int) -> void:
    @warning_ignore("integer_division")
    var centre := Vector2i(side / 2, side / 2)
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
    for y in side:
        for x in side:
            var inside := absi(x - centre.x) <= half_width and absi(y - centre.y) <= half_height
            image.set_pixel(x, y, Color(0, 0, 0, 1.0 if inside else 0.0))
    image.save_png(ProjectSettings.globalize_path(path))


## The points the overlay draws: the silhouette placed at the pointer, scaled
## by the radius the circle would have had, and closed.
func test_the_drawn_points_are_the_outline_at_the_radius() -> void:
    var outline := PackedVector2Array([Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)])
    var points := CursorOverlay.outline_points(Vector2(100, 200), 20.0, outline)

    assert_eq(points.size(), 5, "Four points and the first again, which closes it")
    assert_eq(points[0], Vector2(120, 200), "scaled by the radius and put at the pointer")
    assert_eq(points[1], Vector2(100, 220), "every one of them")
    assert_eq(points[4], points[0], "and the last is the first, or the shape has a bite out of it")

    assert_true(CursorOverlay.outline_points(Vector2.ZERO, 20.0, PackedVector2Array()).is_empty(), "No shape, no points")
    var two := PackedVector2Array([Vector2(1, 0), Vector2(-1, 0)])
    assert_true(CursorOverlay.outline_points(Vector2.ZERO, 20.0, two).is_empty(), "and two points are a line, not a shape")
