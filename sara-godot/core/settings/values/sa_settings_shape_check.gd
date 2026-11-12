## The Shape Check's options, every one of them set on Preferences > Display:
## the method that throws the detail away, how far it reaches, how many blocks
## Blocks cuts the long side into, whether the lightness is posterised and to
## how many steps, and how many values a notan cuts it into and where.
##
## Blocks and Masses stand side by side, and every number of the shader that a
## painter would want to move is a preference here rather than a constant.
##
## **A link of the settings autoload's chain**, as `SaSettingsIdle` is:
## `SaSettings` extends `SaSettingsValues` extends `SaSettingsNewDocument`
## extends this extends
## `SaSettingsLocation`. Its own file because the Shape check is one subject,
## the count of levels with it.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsShapeCheck
extends SaSettingsLocation

## Blocks averages the canvas into flat squares, Masses keeps the edges between
## masses while it smooths inside them, and None leaves the picture whole for
## the posterise alone. Grey masses and Notan are the monochrome methods: Masses
## with the hue and chroma gone, and Masses with its lightness cut to two or
## three values. `SHAPE_METHODS` is the row's order on the Display page, and a
## method's place in it is the number the canvas shader branches on, so a method
## joins at the end and the stored names before it keep their places.
const SHAPE_BLOCKS: String = "blocks"
const SHAPE_MASSES: String = "masses"
const SHAPE_NONE: String = "none"
const SHAPE_GREY_MASSES: String = "grey_masses"
const SHAPE_NOTAN: String = "notan"
const SHAPE_METHODS: Array[String] = ["blocks", "masses", "none", "grey_masses", "notan"]

## The methods that smooth inside the masses at [member shape_check_reach],
## so the ones the Reach row belongs to.
const SHAPE_REACHING: Array[String] = ["masses", "grey_masses", "notan"]

## The methods that snap the lightness to [member shape_check_level_count]
## steps while the posterise is on. Notan cuts it at thresholds of its own.
const SHAPE_POSTERISING: Array[String] = ["blocks", "masses", "none", "grey_masses"]

## How many values a notan may cut the lightness into: light against dark, or
## a middle value between them.
const MIN_NOTAN_VALUES: int = 2
const MAX_NOTAN_VALUES: int = 3

## The shortest and the longest reach Masses may take, a share of the canvas's
## long side. Under half a per cent it keeps a painting's brush marks, and past
## five it melts a head into its shoulders.
const MIN_SHAPE_REACH: float = 0.005
const MAX_SHAPE_REACH: float = 0.05

## The fewest and the most blocks Blocks may cut the long side into. Eight is a
## thumbnail of a thumbnail, and past 128 a block is too small to lose anything.
const MIN_SHAPE_ACROSS: int = 8
const MAX_SHAPE_ACROSS: int = 128

## The fewest and the most steps of lightness the posterise may snap to. Two is
## a notan, light against dark, and one step would be a flat sheet with nothing
## left to read. Eleven is the Munsell value scale from black to white, past
## which neighbouring bands stop reading as steps.
const MIN_SHAPE_LEVELS: int = 2
const MAX_SHAPE_LEVELS: int = 11

## Which method throws the detail away. Blocks by default, the oldest method, so
## a profile that never named one shows the picture it was painted against. A
## profile that held the old Shape check row of Blocks, Levels or Both is read
## into this and [member shape_check_levels] by the version-21 step of
## `SaSettingsMigrations`.
var shape_check_method: String = SHAPE_BLOCKS:
    set(val):
        shape_check_method = val if SHAPE_METHODS.has(val) else SHAPE_BLOCKS
        changed.emit(&"shape_check_method")

## Whether the lightness is snapped to [member shape_check_level_count] steps
## after the method, with the hue and chroma riding along. On by default, so a
## fresh profile shows the method and the levels together.
var shape_check_levels: bool = true:
    set(val):
        shape_check_levels = val
        changed.emit(&"shape_check_levels")

## How many steps of lightness the posterise snaps to.
##
## The quantizer and the shape check's value half read this one count. Five by
## default, the shader's own five, so a painter who never moves it sees the
## picture a fixed five gives. The Info docker and the
## Display page write this one setting.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## reads the five a new one has.
var shape_check_level_count: int = 5:
    set(val):
        val = clampi(val, MIN_SHAPE_LEVELS, MAX_SHAPE_LEVELS)
        if shape_check_level_count == val:
            return
        shape_check_level_count = val
        changed.emit(&"shape_check_level_count")

## How far Masses looks for the side of an edge a texel belongs to, a share of
## the canvas's long side, so a picture and the same picture at twice the size
## read alike. A mass narrower than about this goes, and one wider keeps its
## outline. A per cent and a half by default, about the width of an eye in a
## head and shoulders portrait.
var shape_check_reach: float = 0.015:
    set(val):
        shape_check_reach = clampf(val, MIN_SHAPE_REACH, MAX_SHAPE_REACH)
        changed.emit(&"shape_check_reach")

## How many blocks Blocks cuts the long side into, whatever the document
## measures. Thirty-two by default, the constant the shader held.
var shape_check_across: int = 32:
    set(val):
        shape_check_across = clampi(val, MIN_SHAPE_ACROSS, MAX_SHAPE_ACROSS)
        changed.emit(&"shape_check_across")

## How many values Notan cuts the lightness into, two or three. Two by
## default, the black and white a notan study is drawn in.
var shape_check_notan_values: int = 2:
    set(val):
        shape_check_notan_values = clampi(val, MIN_NOTAN_VALUES, MAX_NOTAN_VALUES)
        changed.emit(&"shape_check_notan_values")

## Where a notan of two values turns from dark to light, on the Oklab lightness
## from nought to one. The middle by default.
var shape_check_notan_threshold: float = 0.5:
    set(val):
        shape_check_notan_threshold = clampf(val, 0.0, 1.0)
        changed.emit(&"shape_check_notan_threshold")

## Where a notan of three values turns from dark to the middle value, on the
## same lightness. A third by default, and [member shape_check_notan_light] two
## thirds, so the middle value sits on the middle of the scale. Crossed, the
## lower of the two is the dark one.
var shape_check_notan_dark: float = 1.0 / 3.0:
    set(val):
        shape_check_notan_dark = clampf(val, 0.0, 1.0)
        changed.emit(&"shape_check_notan_dark")

## Where a notan of three values turns from the middle value to light.
var shape_check_notan_light: float = 2.0 / 3.0:
    set(val):
        shape_check_notan_light = clampf(val, 0.0, 1.0)
        changed.emit(&"shape_check_notan_light")


## The options as the canvas shader's uniforms, by the names it declares, so
## the canvas writes them and its dump reads them back in one walk. The method
## goes as its place in `SHAPE_METHODS`, which is the number the shader
## branches on, and the count across as the float it divides by.
func shape_check_uniforms() -> Dictionary:
    return {
        "shape_check_method": SHAPE_METHODS.find(shape_check_method),
        "shape_check_levels": shape_check_levels,
        "shape_check_level_count": shape_check_level_count,
        "shape_check_reach": shape_check_reach,
        "shape_check_across": float(shape_check_across),
        "shape_check_notan_values": shape_check_notan_values,
        "shape_check_notan_threshold": shape_check_notan_threshold,
        "shape_check_notan_dark": shape_check_notan_dark,
        "shape_check_notan_light": shape_check_notan_light,
    }
