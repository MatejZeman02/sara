## Normalize lays the reference pictures out in a grid, not just a row.
## Nine placeholders of mixed sizes stand in a row on the
## board, as the plus lays them, and `normalise` is asked for a docker's room.
extends "res://tests/test_framework.gd"

const SIZES: Array[Vector2] = [
    Vector2(400, 500),
    Vector2(640, 480),
    Vector2(300, 300),
    Vector2(800, 900),
    Vector2(500, 400),
    Vector2(1200, 1200),
    Vector2(256, 320),
    Vector2(700, 560),
    Vector2(450, 450),
]


func _board() -> SaReferenceBoard:
    var board := SaReferenceBoard.new("Normalize Probe")
    var x := 0.0
    for index in SIZES.size():
        board.restore_path("/nonexistent/%d.png" % index, Rect2(Vector2(x, 0.0), SIZES[index]))
        x += SIZES[index].x + SaReferenceBoard.NORMAL_GAP
    return board


## The rows of the board read off the rectangles' top edges, each a list of
## the pictures' first-placed indices from left to right.
func _rows(board: SaReferenceBoard) -> Array:
    var tops: Array[float] = []
    for picture in board.pictures:
        if not tops.any(func(top: float) -> bool: return is_equal_approx(top, picture.rect.position.y)):
            tops.append(picture.rect.position.y)
    tops.sort()
    var rows: Array = []
    for top in tops:
        var row: Array = []
        for index in board.pictures.size():
            if is_equal_approx(board.pictures[index].rect.position.y, top):
                row.append(index)
        var pictures := board.pictures
        row.sort_custom(func(a: int, b: int) -> bool: return pictures[a].rect.position.x < pictures[b].rect.position.x)
        rows.append(row)
    return rows


func _overlaps(board: SaReferenceBoard) -> String:
    for a in board.pictures.size():
        for b in range(a + 1, board.pictures.size()):
            if board.pictures[a].rect.intersects(board.pictures[b].rect):
                return "%d %s and %d %s" % [a, board.pictures[a].rect, b, board.pictures[b].rect]
    return ""


func test_a_square_docker_takes_three_rows_of_three_in_their_order() -> void:
    var board := _board()
    board.normalise("height", Vector2(600, 600))
    assert_eq(_rows(board), [[0, 1, 2], [3, 4, 5], [6, 7, 8]], "Three rows of three, left to right and then top to bottom")
    for picture in board.pictures:
        assert_almost_eq(picture.rect.size.y, SaReferenceBoard.NORMAL_HEIGHT, 1e-3, "every picture at the one height")


func test_a_docker_twice_as_wide_as_tall_takes_fewer_rows_than_columns() -> void:
    var board := _board()
    board.normalise("height", Vector2(800, 400))
    var rows := _rows(board)
    var columns := 0
    for row: Array in rows:
        columns = maxi(columns, row.size())
    assert_true(rows.size() < columns, "Fewer rows than columns, %s" % [rows])
    board.fit_all(Vector2(800, 400))
    var shown := board.bounds().size * board.zoom
    assert_true(shown.x / 800.0 + shown.y / 400.0 > 1.4, "and the fit fills the docker more than a single row would, %s" % shown)


func test_no_two_pictures_overlap_under_any_mode() -> void:
    for mode in SaReferenceBoard.NORMALISE_MODES:
        for room: Vector2 in [Vector2(600, 600), Vector2(800, 400), Vector2(300, 900)]:
            var board := _board()
            board.normalise(mode, room)
            assert_eq(_overlaps(board), "", "No overlap under %s for %s" % [mode, room])


func test_one_width_stands_in_columns_filled_top_to_bottom() -> void:
    var board := _board()
    board.normalise("width", Vector2(600, 600))
    var lefts: Array[float] = []
    for picture in board.pictures:
        assert_almost_eq(picture.rect.size.x, SaReferenceBoard.NORMAL_HEIGHT, 1e-3, "One width")
        if not lefts.any(func(left: float) -> bool: return is_equal_approx(left, picture.rect.position.x)):
            lefts.append(picture.rect.position.x)
    assert_eq(lefts.size(), 3, "in three columns, %s" % [lefts])
    assert_true(board.pictures[0].rect.position.y < board.pictures[1].rect.position.y, "the first column filled top to bottom")
    assert_almost_eq(board.pictures[3].rect.position.y, 0.0, 1e-3, "and the fourth picture starts the second")


func test_one_area_rows_take_their_tallest_picture() -> void:
    var board := _board()
    board.normalise("area", Vector2(600, 600))
    var rows := _rows(board)
    assert_eq(rows.size(), 3, "Three rows, %s" % [rows])
    for index in range(rows.size() - 1):
        var tallest := 0.0
        for picture_index: int in rows[index]:
            tallest = maxf(tallest, board.pictures[picture_index].rect.size.y)
        var next_top := board.pictures[rows[index + 1][0]].rect.position.y
        var top := board.pictures[rows[index][0]].rect.position.y
        assert_almost_eq(next_top - top, tallest + SaReferenceBoard.NORMAL_GAP, 1e-3, "row %d is as tall as its tallest" % index)
