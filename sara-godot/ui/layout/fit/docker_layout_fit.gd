## Where a shipped layout puts each docker on the host it opens on.
##
## `docker_layout_default.cfg` is written for a 1920 by 1080 window, and opened
## as it stands on a smaller one it puts dockers over each other's titles and
## some of them off the host.
##
## The rule is the file's own arrangement, kept and fitted. A docker whose centre
## is in the left half of the host the file was written for stays at its distance
## from the left edge, and one in the right half at its distance from the right
## edge. Dockers whose spans overlap sideways are one column, unless they stand
## side by side, and a column keeps its top and its gaps and gives up height when
## its dockers do not fit, the lowest docker first and never below a docker's
## floor. On the host the file was written for, all of that is the file exactly,
## which keeps committed scenarios aiming where they always did. A column that
## loses its first docker starts where that docker did, and a docker that hands in
## a `content` height shorter than the file's opens at that height, the dockers
## under it moving up.
##
## A file that names an order leaves room to paint. A file with a `close_order`
## closes its dockers in that order until every column's floors fit its height
## and the columns leave the painting [constant PAINTING_SHARE] of the host's
## width, the columns giving up width down to their floors first. Then it closes,
## in the same order, a docker the placing laid over another. A file with no order
## is placed without closing. A docker the file keeps closed opens clear of the
## ones it placed ([method opening]).
##
## A layout the painter saved moves only when the host cannot hold it. The store
## asks this for the live layout that is still one of the four Sara ships, at a
## boot, a resize and a change of the UI scale (`SaDockerLayoutRefit`), and a
## painter's first edit forks that into `<name> (custom)`. A layout of the
## painter's stands where it was put while every docker of it keeps its title
## strip in reach, [method reached], and is placed by this over its own
## rectangles, with no close order, once one does not. The title strip is what
## stays in reach, so a docker may leave the window's border: a painter's docker
## and a drag keep [constant STRIP_IN_REACH] of the strip on the host, and a
## shipped layout, the Window menu's show and a docker of its own OS window keep
## [method kept]'s whole rule.
##
## Pure: no window, no file and no node, so a suite hands it rectangles and
## reads rectangles back.
class_name SaDockerLayoutFit
extends RefCounted

## What is kept free under the lowest docker of a column, in the units the
## rectangles are in, the margin `MainDockers` places the built-ins at.
const BOTTOM_MARGIN: int = 15

## The least share of the host's width the columns of a file with a close
## order leave the painting, the gaps between them counted as painting.
##
## **Two fifths and not half.** The default's columns stand on 680 of the
## width, and on 661 at their floors, since the Layers docker's blend row is
## cut below 310 wide. A host 1280 wide keeps 47 per cent with every docker
## open, and half closed Brush Presets and Tool Options on every screen that
## wide, where
## `ui/dockers/tests/test_the_default_layout_opens_its_columns_under_the_bar.gd`
## holds that the default opens them. On a host 640 wide the two close the same
## dockers.
##
## A file whose columns leave the painting less on the host it was written for
## asks for no more than that. Full's thirteen dockers leave it 60 of 1920, and
## two fifths closed two of them and narrowed seven more on the very screen
## the file was drawn for.
const PAINTING_SHARE: float = 0.4

## How far from a column [method opening] puts a closed docker it moves beside
## that column, the gap the default keeps between the toolbox and the column
## next to it.
const SIDE_GAP: int = 10

## How much of a floating docker's title strip [method reached] keeps on the
## host, in logical units, its width first.
##
## **128 wide, because the strip's far end is buttons.** Past the left edge the
## part left in is the strip's right end, where the maximise, the pin and the
## hide button stand at 24 each with their gaps, about 84 units a press takes
## for a button. 128 leaves some 40 of bare strip to take, and past the right
## edge the head, the lock, the grip and the title, is all bare strip. 24 high,
## the strip's 20 and the buttons' own height, so a docker let go low keeps the
## strip's buttons whole. A docker narrower than 128, the toolbox at 60, keeps its
## whole width.
const STRIP_IN_REACH := Vector2i(128, 24)

## The host the dockers are placed on.
var _host: Vector2i

## The first row below the bar, where no docker's title may start above.
var _top: int

## The host the stored rectangles were written for.
var _written_for: Vector2i

## The sections closed for room, first to last. Empty keeps every docker open.
var _close_order: Array[String] = []

## What the columns of every docker [method place] was handed leave the
## painting on the host the file was written for, or -1 before it is asked.
var _left_by_the_file: int = -1

## Section to the top of the column it stands in with every docker open, which
## is where its column starts once the docker above it has closed for room.
var _column_tops: Dictionary = {}


## *close_order* is untyped because it comes straight out of a `ConfigFile`.
func _init(host: Vector2i, top: int, written_for: Vector2i, close_order: Array = []) -> void:
    _host = host
    _top = top
    _written_for = written_for
    _close_order.assign(close_order)


## Section to `Rect2i` for every docker in *dockers* that stays open, which maps
## a section to `{"rect": Rect2i, "min": Vector2i}`: the stored rectangle in this
## host's units and the smallest the docker will lay out at. An optional
## `"content": int` is the height the docker shows all it holds at, and one
## shorter than the stored height is the height it asks of its column. A
## section missing from the answer is one the close order closed.
func place(dockers: Dictionary) -> Dictionary:
    if _host.x <= 0 or _host.y <= 0 or _written_for.x <= 0:
        return {}
    var open: Array[String] = []
    open.assign(dockers.keys())
    _left_by_the_file = _written_for.x
    _column_tops.clear()
    for column: Array in _all_columns(dockers, open):
        _left_by_the_file -= _wanted_width(column, dockers)
        for section: String in column:
            _column_tops[section] = _stored(dockers, column[0]).position.y
    while true:
        var columns := _all_columns(dockers, open)
        var closing := _to_close(dockers, columns)
        if closing.is_empty():
            var out := _placed(dockers, columns)
            closing = _first_over_another(out)
            if closing.is_empty():
                return out
        open.erase(closing)
    return {}


## Every docker of *columns* stacked in its column and kept on the host.
func _placed(dockers: Dictionary, columns: Array) -> Dictionary:
    var out: Dictionary = {}
    var widths := _widths(dockers, columns)
    for i in columns.size():
        var column: Array = columns[i]
        var from_right := _in_right_half(_stored(dockers, column[0]))
        _stack(column, dockers, _host.x - _written_for.x if from_right else 0, from_right, widths[i], out)
    for section: String in out:
        var rect: Rect2i = out[section]
        out[section] = Rect2i(kept(rect.position, rect.size), rect.size)
    return out


## The first docker of the close order that *placed* lays over another, or ""
## when none is, or none of those the order names.
func _first_over_another(placed: Dictionary) -> String:
    for section: String in _close_order:
        if not placed.has(section):
            continue
        var rect: Rect2i = placed[section]
        for other: String in placed:
            if other != section and rect.intersects(placed[other]):
                return section
    return ""


## Where a docker the file keeps closed opens: *at*, the place it is kept at on
## the host, unless that lays it over a docker of *placed* which its *stored*
## rectangle stands clear of in the file. Then it opens beside that docker's
## column, on the painting's side, with its foot no lower than a column's, and
## at *at* still when that spot is taken too. *placed* is what [method place]
## answered for *dockers*.
##
## **Beside the column and not under it**, because the column has no room left
## where this is needed. At 1.25 on a 1080 screen the left column's Brush
## Presets at its floor of 329 and the 329 a Tool Options needs to show its
## Stabiliser row leave 56 units above the column's foot, for a Reference whose
## floor is 132. Closing it for room, the other way, would answer the painter's
## chord with nothing.
func opening(at: Rect2i, stored: Rect2i, dockers: Dictionary, placed: Dictionary) -> Rect2i:
    var under := ""
    for section: String in placed:
        if at.intersects(placed[section]) and not stored.intersects(_stored(dockers, section)):
            under = section
            break
    if under.is_empty():
        return at
    var sections: Array[String] = []
    sections.assign(placed.keys())
    var span := Vector2i(_host.x, 0)
    for column: Array in _all_columns(dockers, sections):
        if column.has(under):
            for section: String in column:
                var rect: Rect2i = placed[section]
                span = Vector2i(mini(span.x, rect.position.x), maxi(span.y, rect.end.x))
    var from_right := _in_right_half(_stored(dockers, under))
    var x := span.x - SIDE_GAP - at.size.x if from_right else span.y + SIDE_GAP
    var y := mini(at.position.y, _host.y - BOTTOM_MARGIN - at.size.y)
    var beside := Rect2i(kept(Vector2i(x, y), at.size), at.size)
    for section: String in placed:
        if beside.intersects(placed[section]):
            return at
    return beside


## *pos* moved as little as possible to keep a window of *size* on the host,
## with its top edge never above the first row below the bar. A host too short
## for both keeps the top, so the title strip stays where a hand can take it and
## the menus beside it stay where a press reaches them.
func kept(pos: Vector2i, size: Vector2i) -> Vector2i:
    var x := clampi(pos.x, 0, maxi(_host.x - size.x, 0))
    return Vector2i(x, maxi(mini(pos.y, _host.y - size.y), _top))


## *pos* moved as little as possible to keep [constant STRIP_IN_REACH] of the
## title strip of a window of *size* on *host*, in the space *pos* is written
## in. The window may stand past the left, the right and the bottom edge as far
## as that leaves, and its top edge never rises above *host*'s, which for a
## drag and a reflow is the window's own top row, over the bar, so the strip
## stays whole. An empty *host* is no clamp.
##
## Static, because the drag reaches it with the window's own host and no
## layout, and a suite asks it with rectangles alone.
static func reached(pos: Vector2i, size: Vector2i, host: Rect2i) -> Vector2i:
    if not host.has_area():
        return pos
    var strip := STRIP_IN_REACH.min(size.max(Vector2i.ONE))
    var left := host.position.x + strip.x - size.x
    var x := clampi(pos.x, left, maxi(host.end.x - strip.x, left))
    return Vector2i(x, clampi(pos.y, host.position.y, maxi(host.end.y - strip.y, host.position.y)))


## The columns of the left half and then of the right, each half from left to
## right, out of the *open* sections.
func _all_columns(dockers: Dictionary, open: Array[String]) -> Array:
    var left: Array[String] = []
    var right: Array[String] = []
    for section: String in open:
        if _in_right_half(_stored(dockers, section)):
            right.append(section)
        else:
            left.append(section)
    return _columns(dockers, left) + _columns(dockers, right)


func _in_right_half(rect: Rect2i) -> bool:
    return rect.position.x * 2 + rect.size.x >= _written_for.x


## *sections* cut into columns, each sorted top to bottom. A docker joins the
## column its stored span overlaps sideways and starts one of its own when it
## overlaps none.
##
## **Or when it stands beside a docker of that column.** Full's middle is two
## columns the file draws side by side, the Recorder over the Graph over the
## Recent Presets, and the Minimap over the Undo History beside them, and the
## Undo's span overlaps the Graph's by 80. Joined into one, the five were
## stacked into a single column on the host the file was drawn for, the
## Minimap under the Recorder and the Undo under the Recent Presets.
func _columns(dockers: Dictionary, sections: Array[String]) -> Array:
    var by_x := sections.duplicate()
    by_x.sort_custom(func(a: String, b: String) -> bool: return _stored(dockers, a).position.x < _stored(dockers, b).position.x)
    var columns: Array = []
    var spans: Array[Vector2i] = []
    for section: String in by_x:
        var rect := _stored(dockers, section)
        var joined := false
        for i in columns.size():
            var overlaps := rect.position.x < spans[i].y and spans[i].x < rect.end.x
            if overlaps and _stands_above_or_below(rect, columns[i], dockers):
                columns[i].append(section)
                spans[i] = Vector2i(mini(spans[i].x, rect.position.x), maxi(spans[i].y, rect.end.x))
                joined = true
                break
        if not joined:
            columns.append([section])
            spans.append(Vector2i(rect.position.x, rect.end.x))
    for column: Array in columns:
        column.sort_custom(
            func(a: String, b: String) -> bool: return _stored(dockers, a).position.y < _stored(dockers, b).position.y
        )
    return columns


## Whether *rect* is wholly above or below every docker of *column*.
func _stands_above_or_below(rect: Rect2i, column: Array, dockers: Dictionary) -> bool:
    for section: String in column:
        var other := _stored(dockers, section)
        if rect.position.y < other.end.y and other.position.y < rect.end.y:
            return false
    return true


## The next docker the close order closes, or "" when there is room or no order.
##
## **Height first, and from the column that lacks it.** A column whose floors
## are more than its height closes the first docker of the order it holds, so
## the Layers docker on the right never closes for the left column's want. Then
## width: when the columns at their floors still leave the painting less than
## its share of the host, [method _columns_room], the first open docker of the
## order closes, wherever it is. The width is counted as the host less what the
## columns stand on, so the gaps between the columns are painting too.
##
## A column whose floors do not fit and which holds none of the order is laid
## over as before, which no file Sara ships has.
func _to_close(dockers: Dictionary, columns: Array) -> String:
    if _close_order.is_empty():
        return ""
    for column: Array in columns:
        if not _floors_fit(column, dockers):
            for section: String in _close_order:
                if column.has(section):
                    return section
    var least := 0
    for column: Array in columns:
        least += _least_width(column, dockers)
    if least <= _columns_room():
        return ""
    for section: String in _close_order:
        for column: Array in columns:
            if column.has(section):
                return section
    return ""


func _floors_fit(column: Array, dockers: Dictionary) -> bool:
    var floors := 0
    for section: String in column:
        var least: Vector2i = dockers[section].get("min", Vector2i.ZERO)
        floors += least.y
    return floors <= _room(column, dockers, _gaps(column, dockers))


## Each column's width: the widest docker in it, and when that leaves the
## painting less than its share of the host, cut down towards the widest floor
## in it, the rightmost column first, the way [method shared_out] cuts heights.
## With no close order a column is as wide as its widest docker, as it always
## was.
func _widths(dockers: Dictionary, columns: Array) -> Array[int]:
    var wanted: Array[int] = []
    var floors: Array[int] = []
    for column: Array in columns:
        wanted.append(_wanted_width(column, dockers))
        floors.append(_least_width(column, dockers))
    if _close_order.is_empty():
        return wanted
    return shared_out(wanted, floors, _columns_room())


## How wide the columns may be between them on a host *width* wide and still
## leave the painting its share.
static func columns_room(width: int) -> int:
    return width - int(ceil(width * PAINTING_SHARE))


## [method columns_room] on this host, with the painting asking no larger a
## share than the file's columns leave it on the host it was written for.
## Counted in whole units, so the file's own host gets the file to the unit.
func _columns_room() -> int:
    var room := columns_room(_host.x)
    if _left_by_the_file < 0:
        return room
    var left := maxi(_left_by_the_file, 0)
    return maxi(room, _host.x - ceili(float(_host.x * left) / _written_for.x))


## The widest docker of *column*, or its floor when that is wider.
func _wanted_width(column: Array, dockers: Dictionary) -> int:
    var widest := 0
    for section: String in column:
        var least: Vector2i = dockers[section].get("min", Vector2i.ZERO)
        widest = maxi(widest, maxi(_stored(dockers, section).size.x, least.x))
    return widest


func _least_width(column: Array, dockers: Dictionary) -> int:
    var widest := 0
    for section: String in column:
        var least: Vector2i = dockers[section].get("min", Vector2i.ZERO)
        widest = maxi(widest, least.x)
    return widest


## The gap above each docker of *column*, 0 for the first.
func _gaps(column: Array, dockers: Dictionary) -> Array[int]:
    var gaps: Array[int] = []
    var previous_end := -1
    for section: String in column:
        var rect := _stored(dockers, section)
        gaps.append(0 if previous_end < 0 else maxi(rect.position.y - previous_end, 0))
        previous_end = rect.end.y
    return gaps


## The height *column* has for its dockers below its top and above the margin,
## its gaps taken out.
func _room(column: Array, dockers: Dictionary, gaps: Array[int]) -> int:
    var room := _host.y - BOTTOM_MARGIN - _first(column, dockers)
    for gap in gaps:
        room -= gap
    return room


## Where *column* starts: the top of the column it was drawn as, so a column
## whose first docker closed for room starts where that docker did and the
## docker under it does not hang from a hole.
func _first(column: Array, dockers: Dictionary) -> int:
    var drawn: int = _column_tops.get(column[0], _stored(dockers, column[0]).position.y)
    return maxi(mini(drawn, _stored(dockers, column[0]).position.y), _top)


## Places one column, moved sideways by *shift* and *width* wide, into *out*. A
## column of the right half keeps its right edges where they were, so a docker
## its floor widened, or the width cut, moves at its inner edge rather than off
## the host.
func _stack(column: Array, dockers: Dictionary, shift: int, from_right: bool, width: int, out: Dictionary) -> void:
    var wanted: Array[int] = []
    var floors: Array[int] = []
    for section: String in column:
        var least: Vector2i = dockers[section].get("min", Vector2i.ZERO)
        wanted.append(maxi(_asked_height(dockers, section), least.y))
        floors.append(least.y)
    var gaps := _gaps(column, dockers)
    var heights := shared_out(wanted, floors, _room(column, dockers, gaps))
    var y := _first(column, dockers)
    for i in column.size():
        var section: String = column[i]
        var rect := _stored(dockers, section)
        var least: Vector2i = dockers[section].get("min", Vector2i.ZERO)
        y += gaps[i]
        var own := mini(maxi(rect.size.x, least.x), width)
        var x := rect.end.x + shift - own if from_right else rect.position.x + shift
        out[section] = Rect2i(Vector2i(x, y), Vector2i(own, heights[i]))
        y += heights[i]


## *wanted* heights cut down to fit *room*, the lowest docker of the column
## first and each down to its floor in *floors* before the one above it gives
## anything. Unchanged when they fit, and every floor when even the floors do
## not.
##
## **The lowest first rather than in proportion**, because a host a little
## shorter than the file's then changes one height and moves nothing. A
## capture's window is 1920 by 1048, not the 1080 the file was written for,
## and the Reference, the lowest docker on the left, ran 12 pixels off it in
## every capture. Cut in proportion, the Tool Options above it moved up by
## seven and a thousand committed scenarios aim at where it was.
static func shared_out(wanted: Array[int], floors: Array[int], room: int) -> Array[int]:
    var heights: Array[int] = wanted.duplicate()
    var excess := -room
    for height in heights:
        excess += height
    for i in range(heights.size() - 1, -1, -1):
        if excess <= 0:
            break
        var given := mini(excess, maxi(heights[i] - floors[i], 0))
        heights[i] -= given
        excess -= given
    return heights


func _stored(dockers: Dictionary, section: String) -> Rect2i:
    return dockers[section]["rect"]


## The height *section* asks of its column: the stored one, or its content's
## when the docker gave one, shorter or taller. A docker that says how tall its
## buttons are, the toolbox, opens at all of them even where a tool added since
## the file was written made the column longer than the file's guess, and the
## column's floors still take the height back where the host has no room.
func _asked_height(dockers: Dictionary, section: String) -> int:
    var stored := _stored(dockers, section).size.y
    var content: int = dockers[section].get("content", 0)
    return content if content > 0 else stored
