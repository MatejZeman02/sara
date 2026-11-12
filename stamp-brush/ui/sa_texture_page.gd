## The brush editor's Texture page, as the rows it declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A curve option page with rows under its checkbox.** The page's checkbox and its strength, sensors and curve
## are `texture_option`, the tenth entry of `curve_option_pages` in `module.gd`, declared exactly the way Size
## and Scatter are. What this file adds is the sixteen rows the option has no room for, the chooser for the
## pattern, the scale, the offset, the three randomiser rows, the invert, the mode, the three tone rows with the
## pivot switch among them and the three cutoff rows, each a plain `SaOptionSpec` naming the page by title,
## which the editor joins to the curve page rather than opening a second page of the same name. So the page is
## declared and not drawn: no file under `ui/brush_editor/` names a pattern, a scale or a chooser, and the same
## rows reach the Tool Options docker behind its Advanced check the way every other row does.
##
## **The tone rows sit under the invert and not beside the scale**, because the
## first eight say which paper and where it lies and the three after them say what
## the paper is like. A painter reads the page top to bottom and picks before
## adjusting. The mode row sits between the two groups, on the same reading: it is
## the last thing said about the paper as a whole before the rows that describe
## its grain. The three cutoff rows go under those for the same reason and in
## Krita's own order, the band before the policy that says what happens outside
## it: a painter narrows the band while watching the paper and only then decides
## whether the outside is bare canvas or bare paint.
##
## **Its own file rather than lines in `module.gd`**, which stands at the
## length where a new page is a new class.
class_name SaTexturePage
extends RefCounted

## The page's title, which is the curve option's label and every row's `page`.
const PAGE: String = "Texture"

## The chooser's tile on the page, the window's default: three tiles beside
## a label fit a page 650 wide, and it is the narrowest side the name under
## a tile wraps into whole words at. At 48 "Canvas" ran into "Dot".
const CHOOSER_ICON: int = 64

## The offset's ceiling in document texels, two shipped tiles: anything past a
## tile wraps to inside it, and one extra tile is room for a painter thinking in
## a pattern scaled to two. The randomiser's two amounts share it, because a
## jump the fixed offset could not have reached by hand is a jump nobody can
## read back off the canvas.
const MAX_OFFSET: int = 512


## The eleven rows, in the order they sit under the heading. *store* is the
## module's one pattern store, bound into the chooser's factory so every
## chooser built from these rows lists from it, and null makes each chooser a
## store of its own, which is what a test asking for the rows alone gets.
static func rows(store: SaPatternStore = null) -> Array[SaOptionSpec]:
    var chooser := SaOptionSpec.make_custom(
        &"pattern_name",
        "Pattern",
        build_chooser.bind(store),
        bind_chooser,
        _on_the_page({"tooltip": "The pattern the dab is textured with, from Sara's patterns or your own."})
    )
    var scale := SaOptionSpec.make_float(
        &"texture_scale",
        "Scale",
        SaDabPattern.MIN_SCALE,
        SaDabPattern.MAX_SCALE,
        0.05,
        _on_the_page(
            {"decimals": 2, "suffix": "x", "tooltip": "How big the tile is drawn, as a multiple of the pattern's own size."}
        )
    )
    var offset_x := _offset(&"texture_offset_x", "Offset X")
    var offset_y := _offset(&"texture_offset_y", "Offset Y")
    var invert := SaOptionSpec.make(
        &"texture_invert",
        "Invert",
        SaOptionSpec.Kind.BOOL,
        _on_the_page({"tooltip": "Invert the texture, so the dab paints in full where it was taken away."})
    )
    # Krita's numbers rather than an index of the seven, for the reason
    # `SaDabPattern.Mode` gives: they have gaps, so the row's ids are not a run.
    # The list is `SaDabPattern`'s own, so a mode added there is offered here.
    var mode := SaOptionSpec.make_enum(
        &"texture_mode",
        "Mode",
        Array(SaDabPattern.MODES),
        Array(SaDabPattern.LABELS),
        _on_the_page(
            {
                "tooltip":
                (
                    "How the texture takes paint. Multiply thins the whole dab, Subtract lifts paint where the grain sits, "
                    + "Lightness moves the colour's lightness with the texture's, Height paints only where the texture is low, "
                    + "Colour Burn closes the dab over dark grain, Hard Mix Softer gives a flat fill with hard edges, "
                    + "and Linear Height paints whichever of Height and Multiply paints more."
                )
            }
        )
    )
    var random_switch := SaOptionSpec.make(
        &"texture_random_per_stroke",
        "Randomize per stroke",
        SaOptionSpec.Kind.BOOL,
        _on_the_page(
            {"tooltip": "Move the texture by a new random amount each time you press, so two strokes do not share a grain."}
        )
    )
    var jump := "How far the texture may jump along this axis when a stroke starts, in pixels."
    var random_x := _offset(&"texture_random_offset_x", "Random X", {"tooltip": jump})
    var random_y := _offset(&"texture_random_offset_y", "Random Y", {"tooltip": jump})
    var brightness := _tone(
        &"texture_brightness",
        "Brightness",
        SaPatternTone.MIN_BRIGHTNESS,
        SaPatternTone.MAX_BRIGHTNESS,
        {"tooltip": "Lighten or darken the whole texture, so the same grain takes more or less paint away."}
    )
    var contrast := _tone(
        &"texture_contrast",
        "Contrast",
        SaPatternTone.MIN_CONTRAST,
        SaPatternTone.MAX_CONTRAST,
        {"tooltip": "How deep the grain goes. Its light and dark parts move apart about the neutral point."}
    )
    var from_pattern := SaOptionSpec.make(
        &"texture_neutral_from_pattern",
        "Neutral from pattern",
        SaOptionSpec.Kind.BOOL,
        _on_the_page({"tooltip": "Turn the contrast about the texture's own average tone, so the grain widens on any pattern."})
    )
    var neutral := _tone(
        &"texture_neutral",
        "Neutral point",
        SaPatternTone.MIN_NEUTRAL,
        SaPatternTone.MAX_NEUTRAL,
        {
            "tooltip":
            # A number the tone does not read while the switch is on, so the row is
            "The texture value the contrast turns about, which stays as it is. Only used with Neutral from pattern off.",
            # dimmed rather than a slider that moves nothing.
            "enabled_when": &"texture_neutral_from_pattern",
            "enabled_when_values": [false]
        }
    )
    var cutoff_left := _tone(
        &"texture_cutoff_left",
        "Cutoff low",
        SaPatternTone.MIN_CUTOFF,
        SaPatternTone.MAX_CUTOFF,
        {"tooltip": "The darkest texture value kept. Darker values follow the Cutoff row."}
    )
    var cutoff_right := _tone(
        &"texture_cutoff_right",
        "Cutoff high",
        SaPatternTone.MIN_CUTOFF,
        SaPatternTone.MAX_CUTOFF,
        {"tooltip": "The lightest texture value kept. Lighter values follow the Cutoff row."}
    )
    var policy := SaOptionSpec.make_enum(
        &"texture_cutoff_policy",
        "Cutoff",
        [SaPatternTone.Policy.OFF, SaPatternTone.Policy.DAB, SaPatternTone.Policy.PAPER],
        ["Off", "Clip the dab", "Clip the texture"],
        _on_the_page(
            {
                "tooltip":
                (
                    "What happens outside the band between Cutoff low and Cutoff high. "
                    + "Clip the dab paints nothing there, Clip the texture paints as if there were no texture."
                )
            }
        )
    )
    var out: Array[SaOptionSpec] = [
        chooser,
        scale,
        offset_x,
        offset_y,
        random_switch,
        random_x,
        random_y,
        invert,
        mode,
        brightness,
        contrast,
        from_pattern,
        neutral,
        cutoff_left,
        cutoff_right,
        policy
    ]
    return out


## The chooser as a row: the pattern grid over the module's store,
## telling the skeleton's write door which name was pressed.
##
## *write* is the door `ToolOptionControls` hands a custom row, which writes
## the name onto the settings, marks the preset dirty and asks for a preview.
## The bare host hands an empty one, which is why it is checked. *store* is
## what [method rows] bound, after the two the door hands over because
## `Callable.bind` appends, and a fresh store stands in for null.
static func build_chooser(_spec: SaOptionSpec, write: Callable, store: SaPatternStore = null) -> Control:
    var chooser := SaPatternChooser.new(store if store != null else SaPatternStore.new(), CHOOSER_ICON)
    if write.is_valid():
        chooser.pattern_chosen.connect(write)
    return chooser


## Shows *value*, the settings' `pattern_name`, on the chooser without
## pressing anything, so a sync is not a pick.
static func bind_chooser(control: Control, value: Variant) -> void:
    var chooser := control as SaPatternChooser
    if chooser != null:
        chooser.show_choice(String(value))


## One of the three tone rows or the two cutoff bounds, which differ only in
## their band and their words.
##
## Two decimals and a step of a hundredth rather than the scale's twentieth: a
## grain's tooth is a shallow thing, and the difference between a contrast of
## 0.05 and one of 0.10 is a paper a painter can see. A cutoff bound is a
## pattern value read at the same resolution, so it takes the same row.
## What every row of the page shares: the page, and off the bar and behind
## Advanced for the reason the curve pages give. The bar is measured, and a
## painter who has not met the idea of a paper under the brush has no use for
## fifteen more rows in the docker. *fields* are the row's own, over these.
static func _on_the_page(fields: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var all_fields: Dictionary[String, Variant] = {"page": PAGE, "bar": false, "advanced": true}
    all_fields.merge(fields, true)
    return all_fields


static func _tone(key: StringName, label: String, low: float, high: float, fields: Dictionary[String, Variant]) -> SaOptionSpec:
    var own := _on_the_page({"decimals": 2})
    own.merge(fields, true)
    return SaOptionSpec.make_float(key, label, low, high, 0.01, own)


static func _offset(key: StringName, label: String, fields: Dictionary[String, Variant] = {}) -> SaOptionSpec:
    var own := _on_the_page(
        {
            "min_value": 0.0,
            "max_value": float(MAX_OFFSET),
            "step": 1.0,
            "decimals": 0,
            "suffix": " px",
            "tooltip": "Offset of the texture, in pixels."
        }
    )
    own.merge(fields, true)
    return SaOptionSpec.make(key, label, SaOptionSpec.Kind.INT, own)
