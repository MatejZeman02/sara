## A layer row's three locks read on the selected row.
##
## The three grayed lock buttons were not very visible when the layer is
## selected. An off lock was outlined in the muted text
## colour on every row, which measured 1.45 to 1 against the selection's ground
## in the pink palette and under 3 to 1 in four of the other five. The selected
## row now draws its off locks in the text colour, and what is held here is
## measured from the row itself in every shipped palette, so a palette that
## moves either colour fails here rather than on the painter's screen.
extends "res://tests/test_framework.gd"

## The rows bind their thumbnails, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## What the note's "not very visible" is held to, the WCAG floor for a control.
const MIN_CONTRAST := 3.0

## How far apart, as a distance in RGB, an on lock's ground has to be from the
## selected row's. Luminance alone cannot hold this half: Solarized Dark's
## orange and its selection's teal grey measure 1.17 to 1 and are as far apart
## as two colours on that palette get. The narrowest shipped pair, Photoshop
## Dark's blue on its grey, is 0.33 apart.
const MIN_ON_DISTANCE := 0.25


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## The WCAG relative luminance of an sRGB colour.
static func _luminance(color: Color) -> float:
    var lin := func(c: float) -> float: return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
    return 0.2126 * float(lin.call(color.r)) + 0.7152 * float(lin.call(color.g)) + 0.0722 * float(lin.call(color.b))


static func _contrast(a: Color, b: Color) -> float:
    var la := _luminance(a)
    var lb := _luminance(b)
    return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _distance(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## A row on a pick, styled selected or not.
func _row(easel: SaEasel, pick: SaLayerPick, selected: bool) -> SaLayerRowView:
    var row := SaLayerRowView.new("Layer 1", 0, false, 0, easel.document.active_layer, pick)
    pick.row_added(false)
    pick.select(0 if selected else -1)
    row.refresh(easel.document)
    row.style(SaLayerList.Drop.NONE)
    return row


func _ground(row: SaRowFrame) -> Color:
    return (row.get_theme_stylebox("panel") as StyleBoxFlat).bg_color


## Every shipped palette: the selected row's off locks measure 3 to 1 against
## its ground, outline and icon both, and an on lock is filled with a colour
## far enough from that ground to read as another state.
func test_an_off_lock_measures_three_to_one_on_the_selected_row_in_every_palette() -> void:
    var saved := SaTheme.palette_id
    var easel := _easel()
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var row := _row(easel, SaLayerPick.new(), true)
        assert_true(row.lit, "%s: the row is selected" % id)
        assert_eq(row.locks_ink, SaRowFrame.LOCK_INK_LIT, "%s: its locks take the selected row's ink" % id)
        var ground := _ground(row)
        for which: StringName in row.toggles:
            var btn: Button = row.toggles[which]
            var off := btn.get_theme_stylebox("normal") as StyleBoxFlat
            var on := btn.get_theme_stylebox("pressed") as StyleBoxFlat
            var rim := _contrast(off.border_color, ground)
            var icon := _contrast(btn.get_theme_color("icon_normal_color"), ground)
            assert_true(rim >= MIN_CONTRAST, "%s: %s off's outline measures %.2f to 1" % [id, which, rim])
            assert_true(icon >= MIN_CONTRAST, "%s: %s off's icon measures %.2f to 1" % [id, which, icon])
            assert_false(off.draw_center, "%s: %s off is still an outline" % [id, which])
            assert_true(on.draw_center, "%s: %s on is still filled" % [id, which])
            var apart := _distance(on.bg_color, ground)
            assert_true(apart >= MIN_ON_DISTANCE, "%s: %s on's ground is %.2f from the row's" % [id, which, apart])
        row.free()
    SaTheme.use_named(saved)
    easel.free()


## A row that is not selected keeps the muted off lock, and a row that is
## selected and then left goes back to it, so the quiet rows stay quiet.
func test_the_muted_lock_comes_back_when_the_row_is_left() -> void:
    var easel := _easel()
    var pick := SaLayerPick.new()
    var row := _row(easel, pick, false)
    var lock: Button = row.toggles[&"alpha"]
    assert_eq(row.locks_ink, SaRowFrame.LOCK_INK, "an unselected row draws its locks muted")
    assert_eq((lock.get_theme_stylebox("normal") as StyleBoxFlat).border_color, SaTheme.palette.text_muted, "outlined muted")

    pick.select(0)
    row.style(SaLayerList.Drop.NONE)
    assert_eq(
        (lock.get_theme_stylebox("normal") as StyleBoxFlat).border_color,
        SaTheme.palette.text_primary,
        "selected, in the text colour"
    )
    assert_eq(lock.get_theme_color("icon_normal_color"), SaTheme.palette.text_primary, "and its icon too")

    pick.select(-1)
    row.style(SaLayerList.Drop.NONE)
    assert_eq((lock.get_theme_stylebox("normal") as StyleBoxFlat).border_color, SaTheme.palette.text_muted, "left, muted again")
    assert_eq(lock.get_theme_color("icon_normal_color"), SaTheme.palette.text_muted, "and its icon too")
    row.free()
    easel.free()


## A palette switch while the row is selected moves its locks with it, and
## selecting the row back and forth binds no more icon colours than one pass,
## because a bind of the same colour on the same control replaces the last.
func test_a_switch_follows_the_ink_and_a_flip_binds_nothing_more() -> void:
    var saved := SaTheme.palette_id
    var easel := _easel()
    var pick := SaLayerPick.new()
    var row := _row(easel, pick, true)
    var lock: Button = row.toggles[&"paint"]

    SaTheme.use_named("paper")
    assert_eq(lock.get_theme_color("icon_normal_color"), SaTheme.palette.text_primary, "the switch kept the selected row's ink")
    assert_eq(
        (lock.get_theme_stylebox("normal") as StyleBoxFlat).border_color, SaTheme.palette.text_primary, "on the outline too"
    )

    var bound := SaTheme._bound_fonts.size()
    for i in 10:
        pick.select(-1 if i % 2 == 0 else 0)
        row.style(SaLayerList.Drop.NONE)
    assert_true(SaTheme._bound_fonts.size() <= bound, "ten flips leave no more bound colours than there were")

    row.free()
    SaTheme.use_named(saved)
    easel.free()
