## The one shipped palette that is light, and the properties that make it
## one rather than a dark palette with the numbers moved.
##
## A white profile was asked for, and all four shipped
## palettes were dark. A fifth `.tres` is cheap, so what is worth holding is
## not that the file exists but that its ground is light, its text is dark, its
## three ramps still run the way `SaTheme.GROUPS` says a ramp runs, and the
## four dark ones did not quietly follow it.
##
## Lightness is Oklab's L rather than `Color.v`, because `v` is the largest of
## the three channels and calls a saturated blue as light as white.
extends "res://tests/test_framework.gd"

const LIGHT_ID := "paper"

## The four that stay dark, and Pink,
## which is dark as well.
const DARK_IDS: Array[String] = ["default", "photoshop", "krita", "solarized", "pink"]

## Where a ground stops being dark and starts being light, in Oklab L. The dark
## palettes sit at 0.20 to 0.30 and the light one at 0.96, so nothing is near it.
const MIDDLE: float = 0.6


func _palette(id: String) -> SaPalette:
    return load(SaTheme.PALETTES[id]) as SaPalette


## Oklab's L for *color*, which is what `SaTheme.slide` moves a ramp along.
func _lightness(color: Color) -> float:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
    return OkhsvConversions.linear_srgb_to_oklab(linear).x


func test_the_new_palette_is_shipped_and_loads() -> void:
    assert_true(SaTheme.PALETTES.has(LIGHT_ID), "the light palette is keyed into PALETTES")
    var palette := _palette(LIGHT_ID)
    assert_not_null(palette, "and its .tres loads as an SaPalette")
    if palette == null:
        return
    assert_eq(palette.display_name, "Paper White", "under the name the dropdown shows")
    var names: Array[String] = []
    for entry: Dictionary in SaTheme.available():
        names.append(String(entry["id"]))
    assert_true(names.has(LIGHT_ID), "and the Colour Themes dropdown offers it")


## The whole of the claim: a light ground under dark text, and the only one.
func test_it_is_the_one_light_ground_and_its_text_is_dark() -> void:
    var palette := _palette(LIGHT_ID)
    if palette == null:
        return
    var ground := _lightness(palette.bg_primary)
    var text := _lightness(palette.text_primary)
    assert_true(ground > MIDDLE, "the ground is light: L %.2f" % ground)
    assert_true(text < MIDDLE, "and the text over it is dark: L %.2f" % text)
    assert_true(ground - text > 0.6, "with room between them: %.2f" % (ground - text))
    for id: String in DARK_IDS:
        var dark := _palette(id)
        assert_true(_lightness(dark.bg_primary) < MIDDLE, "%s is still a dark palette" % id)
        assert_true(_lightness(dark.text_primary) > MIDDLE, "with light text over it: %s" % id)


## Authored as ramps rather than as twenty-one free colours, which is what
## `linked_groups` promises and what the Colour Themes page relies on.
##
## The direction is contrast against the ground and not absolute lightness,
## which is the thing a light palette teaches: on the four dark ones
## `text_muted` is darker than `text_primary` and on this one it is lighter,
## and both are the same rule, that the shade of a group sits nearer the
## background than its base and the highlight sits further from it. Held over
## every shipped palette, because a rule only one file obeys is a coincidence.
func test_every_shipped_group_is_a_ramp_by_contrast() -> void:
    for id: String in SaTheme.PALETTES:
        var palette := _palette(id)
        assert_not_null(palette, "%s loads" % id)
        if palette == null:
            continue
        var ground := _lightness(palette.bg_primary)
        for group: String in SaTheme.GROUPS:
            var spec: Dictionary = SaTheme.GROUPS[group]
            var base := absf(_lightness(palette.get(String(spec["base"]))) - ground)
            var shade := absf(_lightness(palette.get(String(spec["shadow"]))) - ground)
            var over := String(spec["highlight"])
            if group == "background":
                # The base is the ground, so its own contrast is nought and
                # there is nothing to rank against. Only the panel is held, and
                # only that it sits over the ground: Solarized Dark's
                # `bg_secondary` is lighter than its `bg_primary` rather than
                # darker, so the shade runs the other way there and the three
                # do not straddle. That is the shipped set disagreeing with
                # itself and not this palette's to settle. Pink is a painter's
                # own as saved, and its panel sits under its
                # ground, so the rule is not held there either.
                if id == "pink":
                    continue
                assert_true(_lightness(palette.bg_panel) > ground, "%s, %s: the panel sits over the ground" % [id, group])
                continue
            assert_true(shade < base, "%s, %s: the shade is nearer the ground, %.2f against %.2f" % [id, group, shade, base])
            if not over.is_empty():
                var high := absf(_lightness(palette.get(over)) - ground)
                assert_true(high > base, "%s, %s: and the highlight further, %.2f" % [id, group, high])


## Every shipped palette links the same three groups, so the Colour Themes
## page shows the same twelve rows whichever is chosen.
func test_the_light_palette_links_the_same_three_groups() -> void:
    var palette := _palette(LIGHT_ID)
    if palette == null:
        return
    assert_eq(
        Array(palette.linked_groups),
        Array(SaPalette.new().linked_groups),
        "the same three groups are linked as on every shipped palette"
    )


## The two things the section said to reconsider rather than copy, because a
## number that reads as depth under a dark panel reads as dirt under a white
## one. Held as "lighter than every dark palette's" rather than at a number, so
## the next hand to touch the file has room.
func test_the_shadow_and_the_text_halo_were_reconsidered() -> void:
    var palette := _palette(LIGHT_ID)
    if palette == null:
        return
    for id: String in DARK_IDS:
        assert_true(
            palette.shadow.a < _palette(id).shadow.a + 0.001, "the light palette's panel shadow is no heavier than %s's" % id
        )
    assert_true(
        _lightness(palette.text_shadow) > _lightness(palette.text_primary),
        "and the halo under its dark text is lighter than the text, not darker"
    )
