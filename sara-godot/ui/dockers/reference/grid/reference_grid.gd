## The one size Normalize brings each picture to and the grid it lays them in.
##
## Given the sizes the pictures were brought to, in their order, it answers
## where each one stands: in lines that wrap, a line being a row running left
## to right, or a column running top to bottom under one width. The line
## length is the one whose whole grid comes nearest the proportions of the
## room it is asked for, so the fit that follows fills the docker. Each line is
## as deep as its deepest picture, and the gap is the same both ways.
##
## Pure arithmetic over sizes, knowing nothing of pictures or the board, so the
## board keeps what a picture is and this keeps how a set of them is laid out.
class_name ReferenceGrid
extends RefCounted


## A picture of *size* brought to one *height*, one width of that many units,
## or one area of its square, by *mode*. The proportions are kept.
static func normal_size(size: Vector2, mode: String, height: float) -> Vector2:
    var aspect := size.x / maxf(1.0, size.y)
    match mode:
        "width":
            return Vector2(height, height / maxf(0.001, aspect))
        "area":
            var tall := sqrt(height * height / maxf(0.001, aspect))
            return Vector2(tall * aspect, tall)
    return Vector2(height * aspect, height)


## The rectangles of *sizes* in a grid shaped like *room*, *gap* apart. A room
## with no size asks for a single line, the old row.
static func lay_out(sizes: Array[Vector2], room: Vector2, by_columns: bool, gap: float) -> Array[Rect2]:
    var per_line := sizes.size()
    if room.x > 0.0 and room.y > 0.0:
        var wanted := log(room.x / room.y)
        var best := INF
        for trial in range(1, sizes.size() + 1):
            var extent := Vector2.ZERO
            for rect in _lines(sizes, trial, by_columns, gap):
                extent = extent.max(rect.end)
            var miss := absf(log(extent.x / maxf(1.0, extent.y)) - wanted)
            if miss < best - 1e-6:
                best = miss
                per_line = trial
    return _lines(sizes, maxi(1, per_line), by_columns, gap)


## *sizes* laid *per_line* to a line, each line as deep as its deepest picture.
static func _lines(sizes: Array[Vector2], per_line: int, by_columns: bool, gap: float) -> Array[Rect2]:
    var out: Array[Rect2] = []
    var line_start := 0.0
    var index := 0
    while index < sizes.size():
        var along := 0.0
        var depth := 0.0
        for size: Vector2 in sizes.slice(index, mini(index + per_line, sizes.size())):
            out.append(Rect2(Vector2(line_start, along) if by_columns else Vector2(along, line_start), size))
            along += (size.y if by_columns else size.x) + gap
            depth = maxf(depth, size.x if by_columns else size.y)
        line_start += depth + gap
        index += per_line
    return out
