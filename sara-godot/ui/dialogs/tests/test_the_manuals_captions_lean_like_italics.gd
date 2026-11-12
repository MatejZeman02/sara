## The Manual's captions lean like italics instead of tilting
## letter by letter.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A picture caption's text once wobbled weirdly. The italic faces held their slant where
## FreeType reads how far y moves with x, so each letter's right side rose and
## its stems stood upright. These read the faces the window gives its page, and
## then the glyphs the text server draws from them: an "l" whose top lies right
## of its foot by the slant, and an "n" whose two feet stand on one row, as the
## upright face's do.
extends "res://tests/test_framework.gd"

const PAGE := "res://manual/06-selections-and-the-transform-tool.md"
const FACES := ["italics_font", "bold_italics_font"]
## How far an italic letter's top leans right for each unit of its height.
const SLANT := 0.2
## Large enough that one texel of the bitmap is a small part of a letter.
const SIZE := 96

var _kept_theme: Theme = null
var _kept_embedding: bool = true
var _host: Node = null
var _window: SaManualWindow = null


func before_each() -> void:
    # The window reads Sara's theme, which a run of the suites has not built.
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U9TestHost"
    EventBus.add_child(_host)
    _window = SaManualWindow.new()
    _host.add_child(_window)
    _window.show_page(Array(_window.pages).find(PAGE))


func after_each() -> void:
    SaUI.shared_theme = _kept_theme
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _window = null


func test_the_page_shows_the_caption_in_italics() -> void:
    assert_true(_window.current >= 0, "The selections page is open")
    var caption := "[i]The same ellipse moved 160 pixels to the right and turned 20 degrees.[/i]"
    assert_true(_window.page_view.text.contains(caption), "and draws the ellipse's caption in the italic face")


func test_each_italic_face_moves_x_by_y_and_leaves_y_alone() -> void:
    for kind: String in FACES:
        var face := _window.page_view.get_theme_font(kind) as FontVariation
        assert_not_null(face, "The page's %s is a variation of Sara's face" % kind)
        if face == null:
            continue
        var lean := face.variation_transform
        # The text server hands FreeType {xx, xy, yx, yy} as these four.
        assert_eq(lean[0][0], 1.0, "%s keeps x's own scale" % kind)
        assert_almost_eq(lean[0][1], SLANT, 0.0001, "%s moves x by y, the slant" % kind)
        assert_eq(lean[1][0], 0.0, "%s moves y by nothing of x" % kind)
        assert_eq(lean[1][1], 1.0, "%s keeps y's own scale" % kind)
        assert_eq(lean.origin, Vector2.ZERO, "%s moves no letter off its origin" % kind)


func test_an_italic_l_leans_right_by_the_slant() -> void:
    for kind: String in FACES:
        var glyph := _drawn(_window.page_view.get_theme_font(kind), "l")
        var top := _top(glyph) + 2
        var foot := _lowest(glyph, 0, glyph["rect"].size.x) - 2
        var lean := (_centre(glyph, top) - _centre(glyph, foot)) / float(foot - top)
        assert_true(foot - top > 20, "The %s l stands %d texels tall" % [kind, foot - top])
        assert_almost_eq(lean, SLANT, 0.04, "The %s l's top lies right of its foot by the slant" % kind)


func test_an_italic_n_stands_both_feet_on_the_baseline() -> void:
    for kind: String in FACES:
        var face: Font = _window.page_view.get_theme_font(kind)
        var glyph := _drawn(face, "n")
        var half: int = glyph["rect"].size.x / 2
        var left := _lowest(glyph, 0, half)
        var right := _lowest(glyph, half, glyph["rect"].size.x)
        assert_true(absi(left - right) <= 1, "The %s n's feet stand on one row, %d and %d" % [kind, left, right])
        var upright := FontVariation.new()
        upright.base_font = (face as FontVariation).base_font
        var plain := _drawn(upright, "n")
        var depth: float = _lowest(glyph, 0, glyph["rect"].size.x) - glyph["baseline"]
        var plain_depth: float = _lowest(plain, 0, plain["rect"].size.x) - plain["baseline"]
        assert_almost_eq(depth, plain_depth, 1.0, "and on the row the upright n's feet stand on, %s" % kind)


## *letter* in *face* at SIZE as the text server draws it into its cache: the
## cache's picture, the glyph's rectangle in it, whether it holds a distance
## field, and the baseline's row counted from the rectangle's top, in texels.
func _drawn(face: Font, letter: String) -> Dictionary:
    var server := TextServerManager.get_primary_interface()
    var font: RID = face.get_rids()[0]
    var size := Vector2i(SIZE, 0)
    var index := server.font_get_glyph_index(font, SIZE, letter.unicode_at(0), 0)
    server.font_render_glyph(font, size, index)
    var rect := Rect2i(server.font_get_glyph_uv_rect(font, size, index))
    var drawn_size := server.font_get_glyph_size(font, size, index)
    var to_texels := rect.size.y / drawn_size.y
    return {
        "image": server.font_get_texture_image(font, size, server.font_get_glyph_texture_idx(font, size, index)),
        "rect": rect,
        "field": server.font_is_multichannel_signed_distance_field(font),
        "baseline": -server.font_get_glyph_offset(font, size, index).y * to_texels,
    }


## Whether the texel at *x* and *y* of the glyph's rectangle is inside the
## letter. A distance field is inside where the middle of its three channels is
## past one half, as its shader reads it.
func _ink(glyph: Dictionary, x: int, y: int) -> bool:
    var at: Vector2i = glyph["rect"].position + Vector2i(x, y)
    var texel: Color = glyph["image"].get_pixelv(at)
    if glyph["field"]:
        return maxf(minf(texel.r, texel.g), minf(maxf(texel.r, texel.g), texel.b)) > 0.5
    return texel.a > 0.5


## The first row of the glyph's rectangle holding any ink.
func _top(glyph: Dictionary) -> int:
    for y: int in glyph["rect"].size.y:
        for x: int in glyph["rect"].size.x:
            if _ink(glyph, x, y):
                return y
    return -1


## The last row of the glyph's rectangle holding ink between columns *from*
## and *to*.
func _lowest(glyph: Dictionary, from: int, to: int) -> int:
    for y: int in range(glyph["rect"].size.y - 1, -1, -1):
        for x: int in range(from, to):
            if _ink(glyph, x, y):
                return y
    return -1


## The middle of the ink across *row* of the glyph's rectangle.
func _centre(glyph: Dictionary, row: int) -> float:
    var first := -1
    var last := -1
    for x: int in glyph["rect"].size.x:
        if _ink(glyph, x, row):
            first = x if first < 0 else first
            last = x
    return (first + last) / 2.0
