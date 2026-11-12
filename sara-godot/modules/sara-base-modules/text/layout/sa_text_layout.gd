## Point text laid out: each line of a text shaped in one font, its glyphs
## placed, and the carets an editor walks through it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Shaped at the read size and scaled**, since Godot rounds advances to whole
## pixels at the size it shapes at, and a title set at 20 px would drift by up
## to half a pixel a letter. Every number this class answers is in document
## pixels from the block's origin, the first line's baseline at its start.
##
## **One shaped text a line**, broken only at the painter's newlines, which is
## point text. Godot's shaper does the rest: HarfBuzz's kerning, ligatures and
## contextual forms, ICU's BiDi with the glyphs given in the order they are
## seen, the carets and the grapheme steps through mixed directions.
##
## The shaped texts are `TextLine`s' own, freed with this.
extends RefCounted

const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")

## The text laid out.
var text: String = ""
## The size it is set at, in document pixels an em.
var size: float = 0.0
## Document pixels a pixel of the read size.
var scale: float = 0.0
## From the baseline up to the top of a line and down to its foot, and the
## step from one line's baseline to the next.
var ascent: float = 0.0
var descent: float = 0.0
var line_height: float = 0.0
## Each line's first character in [member text], its length, its shaped text
## and the y of its baseline.
var starts: PackedInt32Array = PackedInt32Array()
var lengths: PackedInt32Array = PackedInt32Array()
var baselines: PackedFloat64Array = PackedFloat64Array()
var _shaped: Array[RID] = []
## The lines that own the shaped texts, `TextLine`s, which free their RIDs as
## they go, so nothing here frees one by hand (hard rule 4).
var _lines: Array[TextLine] = []
var _server: TextServer = null


func _init(font: Font, laid: String, em: float) -> void:
    text = laid
    size = em
    scale = em / Fonts.READ_SIZE
    _server = TextServerManager.get_primary_interface()
    if font == null:
        return
    var rid: RID = font.get_rids()[0]
    ascent = _server.font_get_ascent(rid, Fonts.READ_SIZE) * scale
    descent = _server.font_get_descent(rid, Fonts.READ_SIZE) * scale
    line_height = ascent + descent
    var at := 0
    for line in laid.split("\n"):
        var held := TextLine.new()
        held.add_string(line, font, Fonts.READ_SIZE)
        _server.shaped_text_shape(held.get_rid())
        _lines.append(held)
        _shaped.append(held.get_rid())
        starts.append(at)
        lengths.append(line.length())
        baselines.append(line_height * (_shaped.size() - 1))
        at += line.length() + 1


## Every glyph with ink, each `[font_rid, glyph, at]` with *at* where its origin
## stands, in the order the shaper gives, which is the order they are seen.
func glyphs() -> Array:
    var out: Array = []
    for l in _shaped.size():
        var x := 0.0
        for glyph: Dictionary in _server.shaped_text_get_glyphs(_shaped[l]):
            var font_rid: RID = glyph.get("font_rid", RID())
            var offset: Vector2 = glyph.get("offset", Vector2.ZERO)
            var advance := float(glyph.get("advance", 0.0))
            for _r in int(glyph.get("repeat", 1)):
                if font_rid.is_valid() and int(glyph.get("index", 0)) != 0:
                    out.append([font_rid, int(glyph["index"]), Vector2((x + offset.x) * scale, baselines[l] + offset.y * scale)])
                x += advance
    return out


## Which line *index*, a caret's place in [member text], stands on.
func line_of(index: int) -> int:
    for l in range(starts.size() - 1, -1, -1):
        if index >= starts[l]:
            return l
    return 0


## The caret before character *index*, from the top of its line to the foot,
## at the x a character typed there would start.
func caret_at(index: int) -> Rect2:
    if _shaped.is_empty():
        return Rect2(0.0, -ascent, 0.0, line_height)
    var l := line_of(index)
    var x := 0.0
    var carets: Dictionary = _server.shaped_text_get_carets(_shaped[l], clampi(index - starts[l], 0, lengths[l]))
    var leading: Rect2 = carets.get("leading_rect", Rect2())
    if leading.size != Vector2.ZERO or leading.position != Vector2.ZERO:
        x = leading.position.x * scale
    elif index - starts[l] >= lengths[l]:
        x = _server.shaped_text_get_size(_shaped[l]).x * scale
    return Rect2(x, baselines[l] - ascent, 0.0, line_height)


## The caret nearest *local*, a point in the block's pixels.
func index_at(local: Vector2) -> int:
    if _shaped.is_empty():
        return 0
    var l := clampi(floori((local.y + ascent) / maxf(line_height, 0.001)), 0, _shaped.size() - 1)
    var inside := _server.shaped_text_hit_test_position(_shaped[l], local.x / scale)
    return starts[l] + clampi(inside, 0, lengths[l])


## The caret one grapheme after *index*, the next line's start at a line's end.
func next_index(index: int) -> int:
    var l := line_of(index)
    if index - starts[l] >= lengths[l]:
        return mini(index + 1, text.length())
    var inside := _server.shaped_text_next_grapheme_pos(_shaped[l], index - starts[l])
    return starts[l] + clampi(inside, index - starts[l] + 1, lengths[l])


## The caret one grapheme before *index*, the line above's end at a line's start.
func previous_index(index: int) -> int:
    var l := line_of(index)
    if index <= starts[l]:
        return maxi(index - 1, 0)
    var inside := _server.shaped_text_prev_grapheme_pos(_shaped[l], index - starts[l])
    return starts[l] + clampi(inside, 0, index - starts[l] - 1)


## The caret on the line *lines* away from *index*'s, at the x nearest its own,
## or the start or the end of the text past the first line or the last.
func index_across(index: int, lines: int) -> int:
    var l := line_of(index) + lines
    if l < 0:
        return 0
    if l >= _shaped.size():
        return text.length()
    var x := caret_at(index).position.x
    return index_at(Vector2(x, baselines[l]))


## The start and the end of *index*'s line.
func line_start(index: int) -> int:
    return starts[line_of(index)]


func line_end(index: int) -> int:
    var l := line_of(index)
    return starts[l] + lengths[l]
