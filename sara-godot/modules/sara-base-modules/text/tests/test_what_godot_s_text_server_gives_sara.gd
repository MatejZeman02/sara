## What Godot's text server gives Sara's text layers, measured.
##
## Every text layer leans on TextServerAdvanced: HarfBuzz shapes, ICU breaks
## lines and words, FreeType reads the outlines. Each test pins one behaviour
## the text page's plan depends on, with the numbers it was read from, so an
## engine update that changes any of them fails here before a text layer
## draws differently.
##
## The fixtures are OFL fonts small enough to keep: Inter from the interface's
## own fonts, the variable Inter as a Latin WOFF2, and a subset of Noto Sans
## CJK JP holding the few characters the vertical test sets. System fallback
## is off on every font, so a machine's installed fonts never change a glyph.
extends "res://tests/test_framework.gd"

const INTER := "res://ui/themes/fonts/inter/Inter-Regular.ttf"
const INTER_VARIABLE := "res://modules/sara-base-modules/text/tests/fixtures/inter-variable-latin.woff2"
const CJK := "res://modules/sara-base-modules/text/tests/fixtures/noto-sans-cjk-jp-subset.otf"

## Inter's units per em. Both Inters have 2048.
const UPEM := 2048.0

## The first four points of Inter Regular's "g" in font units with y down,
## as fontTools reads the static file, and of the variable Inter's "g" at its
## Bold instance, wght 700, as fontTools' instancer computes them.
const G_REGULAR := [Vector2(611, 442), Vector2(425, 442), Vector2(203, 306), Vector2(151, 214)]
const G_BOLD := [Vector2(624.50, 442), Vector2(484.84, 442), Vector2(277.38, 371.44), Vector2(147.12, 247.46)]

var _ts: TextServer = null

## Every font a test loads, held until the test ends, since a font freed
## takes its RID with it and a shaped text over a dead RID has no glyphs.
var _fonts: Array[Font] = []


func before_each() -> void:
    _ts = TextServerManager.get_primary_interface()


func after_each() -> void:
    _fonts.clear()


func _font(path: String) -> FontFile:
    var font := FontFile.new()
    assert_eq(font.load_dynamic_font(path), OK, "%s loads" % path)
    font.allow_system_fallback = false
    _fonts.append(font)
    return font


func _points(rid: RID, size: int, character: String) -> PackedVector3Array:
    var glyph := _ts.font_get_glyph_index(rid, size, character.unicode_at(0), 0)
    return _ts.font_get_glyph_contours(rid, size, glyph).points


## The largest distance between two outlines' points, each scaled to font
## units, or -1 when they differ in the number of points.
func _apart(a: PackedVector3Array, size_a: float, b: PackedVector3Array, size_b: float) -> float:
    if a.size() != b.size():
        return -1.0
    var most := 0.0
    for i in a.size():
        var pa := Vector2(a[i].x, a[i].y) * UPEM / size_a
        var pb := Vector2(b[i].x, b[i].y) * UPEM / size_b
        most = maxf(most, pa.distance_to(pb))
    return most


func _shaped(spans: Array, orientation := TextServer.ORIENTATION_HORIZONTAL) -> RID:
    var shaped := _ts.create_shaped_text(TextServer.DIRECTION_AUTO, orientation)
    for span: Array in spans:
        _ts.shaped_text_add_string(shaped, span[0], [span[1]], span[2], span[3], span[4])
    _ts.shaped_text_shape(shaped)
    return shaped


## The outline call ignores the font's `hinting` property and loads with
## FreeType's defaults, so Inter's own TrueType instructions move points in y
## below 200 px, while x stays put. At a size equal to the units per em the
## points are the font's units exactly. The text layer therefore reads its
## outlines at a large size and scales them, never at the size it draws.
func test_an_outline_carries_the_font_s_hinting_below_its_units_per_em() -> void:
    var hinted := {}
    for hinting: TextServer.Hinting in [TextServer.HINTING_NONE, TextServer.HINTING_NORMAL]:
        var font := _font(INTER)
        font.hinting = hinting
        var rid: RID = font.get_rids()[0]
        var at_em := _points(rid, int(UPEM), "g")
        for i in G_REGULAR.size():
            assert_eq(Vector2(at_em[i].x, at_em[i].y), G_REGULAR[i], "at 2048 px point %d is the font's own" % i)
        var small := _points(rid, 100, "g")
        hinted[hinting] = small
        var most_x := 0.0
        var most_y := 0.0
        for i in small.size():
            most_x = maxf(most_x, absf(small[i].x * UPEM / 100.0 - at_em[i].x))
            most_y = maxf(most_y, absf(small[i].y * UPEM / 100.0 - at_em[i].y))
        assert_true(most_x < 1.0, "x is not hinted at 100 px, %.2f units off" % most_x)
        assert_true(most_y > 20.0, "y is hinted at 100 px, %.2f units off" % most_y)
        assert_eq(_apart(_points(rid, 256, "g"), 256.0, at_em, UPEM), 0.0, "the hinting stops by 256 px")
    assert_eq(hinted[TextServer.HINTING_NONE], hinted[TextServer.HINTING_NORMAL], "the hinting property changes nothing")


## A font with no instructions of its own is autohinted at every size, and
## its points reach the font's units only where a pixel is a unit or smaller.
func test_an_unhinted_font_is_autohinted_up_to_its_units_per_em() -> void:
    var rid: RID = _font(INTER_VARIABLE).get_rids()[0]
    var exact := _points(rid, 16384, "g")
    assert_true(_apart(_points(rid, 1000, "g"), 1000.0, exact, 16384.0) > 0.3, "1000 px is still hinted")
    assert_true(_apart(_points(rid, int(UPEM), "g"), UPEM, exact, 16384.0) < 0.001, "2048 px is the font's units")


## A FontVariation's coordinates reach the outline: the Bold instance's "g"
## is its own shape, within half a unit of the instancer's, because FreeType
## rounds the interpolated points to whole units.
func test_a_variable_font_s_instance_has_its_own_outline() -> void:
    var base := _font(INTER_VARIABLE)
    var bold := FontVariation.new()
    bold.base_font = base
    bold.variation_opentype = {_ts.name_to_tag("wght"): 700}
    var rid: RID = bold.get_rids()[0]
    assert_eq(_ts.font_get_variation_coordinates(rid), {_ts.name_to_tag("wght"): 700}, "the coordinates are set")
    var points := _points(rid, int(UPEM), "g")
    for i in G_BOLD.size():
        var point := Vector2(points[i].x, points[i].y)
        assert_true(point.distance_to(G_BOLD[i]) <= 0.71, "Bold point %d %s is the instancer's %s" % [i, point, G_BOLD[i]])
    var regular := _points(base.get_rids()[0], int(UPEM), "g")
    assert_true(_apart(points, UPEM, regular, UPEM) > 100.0, "Bold moves the outline")


func test_a_woff2_loads_with_its_axes() -> void:
    var font := _font(INTER_VARIABLE)
    assert_eq(font.get_font_name(), "Inter", "the family is read")
    var axes: Dictionary = _ts.font_supported_variation_list(font.get_rids()[0])
    assert_eq(axes.get(_ts.name_to_tag("wght")), Vector3i(100, 900, 400), "the weight axis runs 100 to 900 from 400")


## Features are set per span. Slashed zero and tabular figures on the first
## "01", none on the second, kerning off on the first "AV" and on, the
## default, on the second.
func test_opentype_features_apply_per_span() -> void:
    var rid: RID = _font(INTER).get_rids()[0]
    var figures := {_ts.name_to_tag("zero"): 1, _ts.name_to_tag("tnum"): 1}
    var shaped := _shaped(
        [
            ["01", rid, 100, figures, "en"],
            ["01", rid, 100, {}, "en"],
            ["AV", rid, 100, {_ts.name_to_tag("kern"): 0}, "en"],
            ["AV", rid, 100, {}, "en"],
        ]
    )
    var glyphs := _ts.shaped_text_get_glyphs(shaped)
    assert_true(glyphs[0].index != glyphs[2].index, "the first zero is slashed")
    assert_eq(glyphs[1].advance, glyphs[0].advance, "tabular one is as wide as zero")
    assert_true(glyphs[3].advance < glyphs[1].advance - 10.0, "proportional one is narrower")
    assert_true(glyphs[6].advance < glyphs[4].advance - 5.0, "kerning pulls V under A only where it is on")
    _ts.free_rid(shaped)


## Advances are whole pixels at the size shaped, whatever the subpixel mode,
## so a line set at 12 px is wider than the design by a pixel and more. The
## layout shapes at the units per em and scales, as it reads outlines.
func test_advances_are_whole_pixels_at_the_size_shaped() -> void:
    var rid: RID = _font(INTER).get_rids()[0]
    var widths := {}
    for size: int in [12, 100, int(UPEM)]:
        var shaped := _shaped([["Hamburgefonstiv AVATAR", rid, size, {}, "en"]])
        widths[size] = _ts.shaped_text_get_width(shaped) / size
        for glyph in _ts.shaped_text_get_glyphs(shaped):
            assert_eq(glyph.advance, roundf(glyph.advance), "an advance at %d px is whole" % size)
        _ts.free_rid(shaped)
    assert_true(
        absf(widths[12] - widths[int(UPEM)]) > 0.01, "12 px is %.4f em, the design %.4f" % [widths[12], widths[int(UPEM)]]
    )


## Through "abc אבג 123 def" the caret splits where the direction changes,
## a selection across the boundary is two rectangles, and a click inside the
## Hebrew run lands inside it. The Hebrew glyphs are Inter's missing-glyph
## boxes, which carry advances as real ones do.
func test_carets_through_mixed_bidi_text() -> void:
    var rid: RID = _font(INTER).get_rids()[0]
    var shaped := _shaped([["abc אבג 123 def", rid, 100, {}, ""]])
    assert_eq(_ts.shaped_text_get_inferred_direction(shaped), TextServer.DIRECTION_LTR, "the paragraph is left to right")
    var inside: Dictionary = _ts.shaped_text_get_carets(shaped, 2)
    assert_eq(inside.leading_rect.position.x, inside.trailing_rect.position.x, "one caret inside a run")
    for boundary: int in [4, 8]:
        var split: Dictionary = _ts.shaped_text_get_carets(shaped, boundary)
        assert_true(split.leading_rect.position.x != split.trailing_rect.position.x, "two carets at %d" % boundary)
        assert_true(split.leading_direction != split.trailing_direction, "of two directions at %d" % boundary)
    assert_eq(_ts.shaped_text_get_selection(shaped, 2, 6).size(), 2, "a selection across the boundary is two rectangles")
    var middle: Dictionary = _ts.shaped_text_get_carets(shaped, 6)
    var hit := _ts.shaped_text_hit_test_position(shaped, middle.leading_rect.position.x)
    assert_true(hit >= 4 and hit <= 8, "a click in the Hebrew run lands in it, at %d" % hit)
    assert_eq(_ts.shaped_text_next_grapheme_pos(shaped, 4), 5, "the arrow steps one grapheme")
    _ts.free_rid(shaped)


## Vertical orientation applies the font's vertical forms to kana and
## punctuation, and sets every glyph upright with a full em's advance down
## the column. Latin stays upright too, with no rotation flag: UTR 50's
## sideways Latin is not done, so Sara rotates those runs itself.
func test_vertical_text_takes_vertical_forms_and_keeps_latin_upright() -> void:
    var rid: RID = _font(CJK).get_rids()[0]
    var text := "縦に書きます。「漢字」ABC"
    var across := _shaped([[text, rid, 100, {}, "ja"]])
    var down := _shaped([[text, rid, 100, {}, "ja"]], TextServer.ORIENTATION_VERTICAL)
    var flat := _ts.shaped_text_get_glyphs(across)
    var standing := _ts.shaped_text_get_glyphs(down)
    assert_eq(standing.size(), flat.size(), "one glyph each way")
    for i: int in [6, 7, 10]:
        assert_true(standing[i].index != flat[i].index, "%s takes its vertical form" % text[i])
    for i: int in [0, 8, 9]:
        assert_eq(standing[i].index, flat[i].index, "%s is the same glyph" % text[i])
    for i: int in [11, 12, 13]:
        assert_eq(standing[i].index, flat[i].index, "%s is not rotated" % text[i])
        assert_eq(standing[i].advance, 100.0, "%s advances a full em down" % text[i])
    assert_true(_ts.shaped_text_get_size(down).y > _ts.shaped_text_get_size(down).x, "the column is tall")
    _ts.free_rid(across)
    _ts.free_rid(down)


## In the editor and in the suites the ICU data is built into the engine,
## so Thai is broken into words by dictionary and Japanese between its
## characters. An exported build has the data only with the project setting
## `internationalization/locale/include_text_server_data`, and without it
## breaks neither, which the text page records from an export.
func test_thai_and_japanese_break_where_the_icu_data_is_present() -> void:
    assert_true(_ts.has_feature(TextServer.FEATURE_BREAK_ITERATORS), "the server breaks by ICU")
    var thai := "ภาษาไทยง่ายนิดเดียว"
    var breaks := _ts.string_get_word_breaks(thai, "th")
    var words := []
    for i in range(0, breaks.size(), 2):
        words.append(thai.substr(breaks[i], breaks[i + 1] - breaks[i]))
    assert_eq("|".join(words), "ภาษา|ไทย|ง่าย|นิด|เดียว", "Thai is five words")
    var rid: RID = _font(INTER).get_rids()[0]
    var japanese := "日本語の文章を改行します。"
    var shaped := _shaped([[japanese, rid, 20, {}, "ja"]])
    assert_true(_ts.shaped_text_get_line_breaks(shaped, 60.0).size() >= 6, "Japanese breaks inside a sentence")
    _ts.free_rid(shaped)


## On Linux the list is fontconfig's families, and each family's file is
## found. On Android it is nine aliases, which the text page records from the
## emulator. A machine with no fonts installed has nothing to list, which is
## not the engine's fault. Run on Windows, this is the check the text page
## still asks for there.
func test_the_system_s_fonts_are_listed_with_their_files() -> void:
    var families := OS.get_system_fonts()
    if families.is_empty():
        skip("no system fonts to list here")
        return
    if OS.get_name() == "Linux":
        assert_false(families.has("sans-serif"), "Linux lists families, not aliases")
    var path := OS.get_system_font_path(families[0])
    assert_true(FileAccess.file_exists(path), "%s is a file at %s" % [families[0], path])
