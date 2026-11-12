## A text layer's recipe: one block of point text in one font, size and colour,
## drawn from its glyphs' outlines through `SaVectorFill` at their exact
## coverage.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **It keeps what it drew, not only what it says.** Beside the text, the
## family, the size, the colour and where the first baseline starts, the recipe
## keeps the shaped glyphs, each a glyph of a font at a place, and the outline
## of every glyph used, as path data. It draws from those alone, so a `.sad`
## opened where the font is missing draws the same pixels, and only an edit
## asks for the font again. Its JSON is what the `.sad` and the history keep.
##
## **Fonts are named, never stored whole**, by the family, style, PostScript
## name and the SHA-256 the fonts table reads, the first of them the font the
## block is set in and any after it a font the shaper fell back to.
##
## Every edit goes through [method set_block], which lays the text out again
## and says the old and the new bounds, so `SaDrawnLayer` redraws those and
## nothing else.
@tool
extends SaDrawnRecipe

const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")
const Glyphs = preload("res://modules/sara-base-modules/text/layout/sa_text_glyphs.gd")
const Layout = preload("res://modules/sara-base-modules/text/layout/sa_text_layout.gd")

## The size a new block is set at, in document pixels an em.
const DEFAULT_SIZE := 72.0
## Steps of a document pixel a glyph's place is kept in, a whole number of
## them, so the place a file or the history gives back is the place drawn to
## the bit and a block opened draws what it drew.
const PLACE_STEPS := 1024.0

## What the block says, newlines and all.
var text: String = ""
## The family it is set in, a name the fonts table knows.
var family: String = Fonts.DEFAULT_FAMILY
## Its size in document pixels an em.
var size: float = DEFAULT_SIZE
## Its colour in the document's own space, alpha its opacity, never clamped.
var paint: Color = Color(0.0, 0.0, 0.0, 1.0)
## Where the first line's baseline starts, in document pixels.
var origin: Vector2 = Vector2.ZERO
## Each font a glyph came from, by what names it, the block's own first.
var fonts: Array[Dictionary] = []
## The glyphs drawn, each `[key, x, y]`: the key of its outline and its origin
## from [member origin] in [constant PLACE_STEPS] of a document pixel.
var runs: Array = []
## Every outline [member runs] names, by key, as path data in thousandths of an
## em. A key is the font's place in [member fonts] and the glyph's index.
var outlines: Dictionary[String, String] = {}
## Whether the family the block names cannot be shaped here, a file opened
## without its font. It still draws as it was set.
var missing: bool = false

## Each run's box in document pixels, the glyph's outline at its place.
var _boxes: Array[Rect2] = []
## Each run's glyph and place as one string, which says what is drawn there.
var _identity: Array[String] = []
## The runs whose boxes overlap, drawn together.
var _groups: Array[Group] = []
## What each group drawn so far was drawn with, by [member Group.key], so a
## key typed at the end of a line finds every other letter's outline made
## already and resolves only its own. Only the groups the layout has now are
## kept.
var _drawn: Dictionary[String, Drawn] = {}
## The one fill kernel every group's renderer dispatches.
var _kernel: SaCompute = null
## The layout of the last edit, kept for the editor's carets, or null until
## [method laid_out] asks for one.
var _layout: Layout = null


## Sets the block to *said* in *in_family* at *em* pixels in *colour* with its
## first baseline at *at*, lays it out, and says what it touched: the boxes of
## the glyphs that came, went or moved, so a key typed at the end of a line
## redraws the letter it typed and not the line. A change of colour, size,
## family or place touches the whole block before and after.
func set_block(said: String, in_family: String, em: float, colour: Color, at: Vector2) -> void:
    var before := bounds()
    var was := _drawn_glyphs()
    var restyled := colour != paint or not is_equal_approx(maxf(em, 0.01), size) or at != origin
    restyled = restyled or (in_family if Fonts.has_family(in_family) else Fonts.DEFAULT_FAMILY) != family
    text = said
    family = in_family if Fonts.has_family(in_family) else Fonts.DEFAULT_FAMILY
    size = maxf(em, 0.01)
    paint = colour
    origin = at
    missing = false
    _lay_out()
    var touched: Array[Rect2i] = [before, bounds()]
    if not restyled:
        touched.clear()
        var now := _drawn_glyphs()
        for glyph: String in was:
            if not now.has(glyph):
                touched.append(_edged(was[glyph]))
        for glyph: String in now:
            if not was.has(glyph):
                touched.append(_edged(now[glyph]))
    changed.emit(touched)


## Each glyph drawn now, by its outline and its place, to its box.
func _drawn_glyphs() -> Dictionary[String, Rect2]:
    var out: Dictionary[String, Rect2] = {}
    for i in runs.size():
        out[_identity[i]] = _boxes[i]
    return out


## *box* grown by a pixel of edge to the whole pixels round it.
static func _edged(box: Rect2) -> Rect2i:
    var start := Vector2i(floori(box.position.x), floori(box.position.y)) - Vector2i.ONE
    var end := Vector2i(ceili(box.end.x), ceili(box.end.y)) + Vector2i.ONE
    return Rect2i(start, end - start)


## The layout an editor walks, made when an edit or an open left none: in the
## block's family, or in the default one where that family is missing.
func laid_out() -> Layout:
    if _layout == null or _layout.text != text or _layout.size != size:
        var font := Fonts.font_for(family)
        _layout = Layout.new(font if font != null else Fonts.font_for(Fonts.DEFAULT_FAMILY), text, size)
    return _layout


func _lay_out() -> void:
    _layout = null
    var layout := laid_out()
    fonts.clear()
    runs.clear()
    outlines.clear()
    var font := Fonts.font_for(family)
    var main_rid: RID = font.get_rids()[0] if font != null else RID()
    fonts.append(Fonts.identity(font))
    var places: Dictionary[int, int] = {main_rid.get_id(): 0}
    var server := TextServerManager.get_primary_interface()
    for glyph: Array in layout.glyphs():
        var rid: RID = glyph[0]
        if not places.has(rid.get_id()):
            places[rid.get_id()] = fonts.size()
            fonts.append({"family": server.font_get_name(rid), "style": server.font_get_style_name(rid)})
        var key := "%d.%d" % [places[rid.get_id()], glyph[1]]
        if not outlines.has(key):
            var data := Glyphs.outline_of(rid, glyph[1])
            if data.is_empty():
                continue
            outlines[key] = data
        var at: Vector2 = glyph[2]
        runs.append([key, roundf(at.x * PLACE_STEPS), roundf(at.y * PLACE_STEPS)])
    _box_runs()


## Each run's box from its outline, kept so a draw takes only the glyphs
## under its region and [method bounds] is a union of boxes, and the runs
## whose boxes overlap gathered into groups.
func _box_runs() -> void:
    _boxes.clear()
    var scale := size / Glyphs.UNITS
    var by_key: Dictionary[String, Rect2] = {}
    var ids: Dictionary[String, String] = {}
    _identity.clear()
    for run: Array in runs:
        var key := String(run[0])
        if not by_key.has(key):
            var data: String = outlines.get(key, "")
            by_key[key] = Glyphs.box_of(data)
            ids[key] = "%d:%d" % [data.hash(), data.length()]
        var box: Rect2 = by_key[key]
        _boxes.append(Rect2(_place(run) + box.position * scale, box.size * scale))
        _identity.append("%s@%d,%d" % [ids[key], int(run[1]), int(run[2])])
    _group_runs()


## Gathers the runs whose boxes overlap into groups. Letters that overlap, a
## script face's joins, have to be covered by one path or their shared pixels
## would be laid twice, and a letter that overlaps none is a group of its own,
## so the work of resolving crossings, which grows with the square of a path's
## edges, is never spent on a whole line at once.
func _group_runs() -> void:
    _groups.clear()
    var count := runs.size()
    var parent := PackedInt32Array()
    parent.resize(count)
    var by_left: Array[int] = []
    for i in count:
        parent[i] = i
        by_left.append(i)
    by_left.sort_custom(func(a: int, b: int) -> bool: return _boxes[a].position.x < _boxes[b].position.x)
    for m in count:
        var i := by_left[m]
        var reach := _boxes[i]
        for n in range(m + 1, count):
            var j := by_left[n]
            if _boxes[j].position.x > reach.end.x:
                break
            if reach.intersects(_boxes[j]):
                var root_i := _root_of(parent, i)
                var root_j := _root_of(parent, j)
                if root_i != root_j:
                    parent[maxi(root_i, root_j)] = mini(root_i, root_j)
    var by_root: Dictionary[int, Group] = {}
    for i in count:
        var root := _root_of(parent, i)
        if not by_root.has(root):
            var made := Group.new()
            by_root[root] = made
            _groups.append(made)
        by_root[root].add(i, _boxes[i], _identity[i])
    var kept: Dictionary[String, Drawn] = {}
    var tail := "|%s|%s" % [size, origin]
    for group in _groups:
        group.key = "%s%s" % [",".join(group.identity), tail]
        if _drawn.has(group.key):
            kept[group.key] = _drawn[group.key]
    _drawn = kept


static func _root_of(parent: PackedInt32Array, i: int) -> int:
    var at := i
    while parent[at] != at:
        parent[at] = parent[parent[at]]
        at = parent[at]
    return at


## Every glyph's box with a pixel of edge round it, which is all the block
## covers. An empty text covers nothing.
func bounds() -> Rect2i:
    if _boxes.is_empty():
        return Rect2i()
    var all := _boxes[0]
    for box in _boxes:
        all = all.merge(box)
    return _edged(all)


## The groups of glyphs whose boxes reach *region*, each as one path, drawn in
## one dispatch so letters that overlap, a script face's joins, are covered once
## and not twice. A group's path and its resolved outline are kept while its
## letters stand as they are, so a redraw over a chunk, or over the letter
## beside one just typed, resolves nothing again.
func draw(region: Rect2i, chunk: SaChunk) -> void:
    var reach := Rect2(region).grow(1.0)
    var scale := size / Glyphs.UNITS
    for group in _groups:
        if not group.box.intersects(reach):
            continue
        var drawn: Drawn = _drawn.get(group.key, null)
        if drawn == null:
            if _kernel == null:
                _kernel = SaVectorFill.make_kernel()
            drawn = Drawn.new(_kernel)
            for i in group.runs:
                var run: Array = runs[i]
                Glyphs.add_to(drawn.path, outlines.get(String(run[0]), ""), _place(run), scale)
            _drawn[group.key] = drawn
        if not drawn.path.is_empty():
            drawn.fill.draw_region(chunk, region, drawn.path, paint)


## Where *run*'s glyph stands, in document pixels.
func _place(run: Array) -> Vector2:
    return origin + Vector2(float(run[1]), float(run[2])) / PLACE_STEPS


## Takes a move and a uniform scale of the whole document, *map*, into the
## block: its first baseline goes where the map sends it, and its size and every
## glyph's place scale by the map's scale, so the letters stay sharp outlines
## at the new size. Says nothing on [signal SaDrawnRecipe.changed], because the
## caller draws the layer again over its new chunks.
##
## A scale counts as uniform when its two axes differ by less than a pixel over
## the block, which is what Image Size with the ratio locked gives once it has
## rounded the second side. A turn, a flip, a skew or a scale that is not uniform
## answers false and leaves the block as it was.
func take_map(map: Transform2D) -> bool:
    if map.x.y != 0.0 or map.y.x != 0.0 or map.x.x <= 0.0 or map.y.y <= 0.0:
        return false
    var reach := float(maxi(bounds().size.x, bounds().size.y))
    if absf(map.x.x - map.y.y) * reach >= 1.0:
        return false
    var scale := (map.x.x + map.y.y) / 2.0
    origin = map * origin
    if scale != 1.0:
        size = maxf(size * scale, 0.01)
        for run: Array in runs:
            run[1] = roundf(float(run[1]) * scale)
            run[2] = roundf(float(run[2]) * scale)
    _layout = null
    _box_runs()
    return true


## The block as the state dump and the door say it: its text, its lines and
## where each starts, its family and whether that is missing here, the glyphs
## drawn and their box, and each font they came from with how many glyphs it
## gave, a fallback font among them. Point text breaks only where the text
## says, so it never overflows.
func report() -> Dictionary:
    var given: Array[int] = []
    given.resize(fonts.size())
    for run: Array in runs:
        var place := int(String(run[0]).get_slice(".", 0))
        if place >= 0 and place < given.size():
            given[place] += 1
    var used: Array = []
    for i in fonts.size():
        used.append({"family": String(fonts[i].get("family", "")), "glyphs": given[i], "fallback": i > 0})
    var breaks: Array[int] = []
    var at := 0
    for line in text.split("\n"):
        breaks.append(at)
        at += line.length() + 1
    var box := bounds()
    return {
        "text": text,
        "lines": breaks.size(),
        "breaks": breaks,
        "family": family,
        "size": size,
        "missing": missing,
        "glyphs": runs.size(),
        "fonts": used,
        "bounds": [box.position.x, box.position.y, box.size.x, box.size.y],
        "overflow": false,
    }


## The words the Layers docker names a fresh text layer by, the first line cut
## to a few words, as Photoshop names one.
func title() -> String:
    var first := text.strip_edges().split("\n")[0] if not text.strip_edges().is_empty() else ""
    return first.left(32).strip_edges()


func to_json() -> Dictionary:
    return {
        "text": text,
        "family": family,
        "size": size,
        "paint": [paint.r, paint.g, paint.b, paint.a],
        "at": [origin.x, origin.y],
        "fonts": fonts.duplicate(true),
        "runs": runs.duplicate(true),
        "outlines": outlines.duplicate(),
    }


func from_json(saved: Dictionary) -> void:
    text = String(saved.get("text", ""))
    family = String(saved.get("family", Fonts.DEFAULT_FAMILY))
    size = float(saved.get("size", DEFAULT_SIZE))
    var p: Array = saved.get("paint", [])
    if p.size() == 4:
        paint = Color(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
    var a: Array = saved.get("at", [])
    if a.size() == 2:
        origin = Vector2(float(a[0]), float(a[1]))
    fonts.clear()
    for named: Variant in saved.get("fonts", []):
        if named is Dictionary:
            fonts.append(named)
    runs = (saved.get("runs", []) as Array).duplicate(true)
    outlines.clear()
    var kept: Variant = saved.get("outlines", {})
    if kept is Dictionary:
        for key: Variant in kept:
            outlines[String(key)] = String(kept[key])
    missing = not Fonts.has_family(family)
    _layout = null
    _box_runs()


## Runs whose boxes overlap, drawn as one path.
class Group:
    extends RefCounted

    ## The runs, by their place in [member runs].
    var runs: PackedInt32Array = PackedInt32Array()
    ## Each run's glyph and place, and the group's own name from them, the
    ## block's size and its origin: what its path is made of.
    var identity: Array[String] = []
    var key: String = ""
    ## The box round every run.
    var box: Rect2 = Rect2()

    func add(run: int, run_box: Rect2, run_identity: String) -> void:
        box = run_box if runs.is_empty() else box.merge(run_box)
        runs.append(run)
        identity.append(run_identity)


## A group's path with the renderer that kept its resolved outline.
class Drawn:
    extends RefCounted

    var path := SaVectorPath.new()
    var fill: SaVectorFill = null

    func _init(kernel: SaCompute) -> void:
        fill = SaVectorFill.new(kernel)
