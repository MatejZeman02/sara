## The names behind a colour space's numbers: which illuminant a white point is,
## and which gamut a set of primaries is.
##
## `SaGamut` and `SaColorSpace` carry the chromaticities because the maths needs
## them. Nothing there carries a name for a *measured* pair, because nothing
## there has to read one out to a person. This file is the lookup that does, and
## it is separate for two reasons. The tolerance is a presentation decision
## rather than a colour one: `SaGamut.matches_primaries` compares with
## `is_equal_approx`, which is about a millionth and refuses a white written to
## four decimals in a file header, and a panel that says nothing whenever a
## number was rounded on the way in is a panel that says nothing. And the table
## here is wider than the one a document may declare: Adobe RGB is a gamut a
## file can arrive tagged with and Sara does not offer, D50 is the print
## illuminant every ICC profile normalises to, and both have to be nameable
## without becoming things a document can be created as.
##
## The five gamuts and the three illuminants are what a painter meets. Anything
## else reads as its numbers.
@tool
class_name SaColorNames
extends RefCounted

## How far a chromaticity may sit from a table entry and still be that entry.
##
## Four decimals is what a `.sad` header, an ICC profile and a printed table all
## write, so 0.0005 is exactly "the fourth decimal agrees". Sara's own D65 is
## (0.312727, 0.329023) and the four-decimal form of it is (0.3127, 0.3290),
## 0.000027 away, so a document opened from a file that rounded is still D65.
## Tighter than this and the row goes quiet on real files. Looser and the three
## illuminants start to overlap what sits between them.
const TOLERANCE: float = 0.0005

## The name for primaries that match nothing in the table.
##
## Lower case, and no numbers after it, because the three primary rows under it
## are already the numbers. A row reading `custom` beside them says the only
## thing the rows cannot: that Sara looked and did not recognise them.
const CUSTOM_NAME: String = "custom"

## CIE D50, the ICC profile connection space's white. Not a `SaColorSpace`
## constant, because no preset there is normalised to it.
const WHITE_D50 := Vector2(0.34567, 0.35850)


## Adobe RGB (1998). Not a `SaGamut` preset, because a document cannot be
## created in it, but a file can arrive tagged with it and then this row is the
## only thing that says so.
##
## A function rather than a `const`, because a `PackedVector2Array` literal is
## not a constant expression in GDScript and a `const` holding one fails the
## whole script to parse, which takes every suite that depends on it with it.
static func adobe_rgb_primaries() -> PackedVector2Array:
    return PackedVector2Array([Vector2(0.6400, 0.3300), Vector2(0.2100, 0.7100), Vector2(0.1500, 0.0600)])


## Every illuminant this file can name, as name and chromaticity, in the order a
## reader meets them: the one Sara paints under first, then print, then ACES.
##
## D65 and D60 come from `SaColorSpace` rather than being written again here, so
## a change to Sara's white cannot leave the row naming the old one.
static func illuminants() -> Array:
    return [
        ["D65", SaColorSpace.WHITE_D65],
        ["D50", WHITE_D50],
        ["D60", SaColorSpace.WHITE_D60],
    ]


## Every gamut this file can name, as name and primaries.
##
## The four Sara offers come from `SaGamut.presets()` with their own display
## names, so the Info docker and a gamut chooser cannot disagree about what
## AP1 is called. Adobe RGB is appended because it is readable and not
## offerable.
static func gamuts() -> Array:
    var named: Array = []
    for gamut in SaGamut.presets():
        named.append([gamut.display_name, gamut.primaries])
    named.append(["Adobe RGB", adobe_rgb_primaries()])
    return named


## The illuminant *white* is, or an empty string when it is none of them.
##
## Empty rather than `custom`, because a white point that is not a standard
## light is a legitimate thing for a document to declare and the two decimals
## are then the whole answer. The gamut lookup says `custom` instead, and the
## difference is that unrecognised primaries are nearly always a tagging
## mistake while an unrecognised white is nearly always deliberate.
static func illuminant_name(white: Vector2) -> String:
    for entry: Array in illuminants():
        var known: Vector2 = entry[1]
        if _near(white, known):
            var name: String = entry[0]
            return name
    return ""


## *white* as a painter reads it: the illuminant's name in front and the pair
## behind it, "D65 (0.3127, 0.3290)", or the pair alone when it is no illuminant.
##
## The name alone cannot be checked against a file header and the numbers alone
## tell a painter nothing they can name, so both. One function rather than one format string in each
## place that prints a white: the Info docker's row and the Colour Spaces page's
## readout are the same answer to the same question, and a painter who reads D50
## in the docker finds D50 where the spaces are described.
static func white_point_text(white: Vector2) -> String:
    var numbers := "%.4f, %.4f" % [white.x, white.y]
    var illuminant := illuminant_name(white)
    return numbers if illuminant.is_empty() else "%s (%s)" % [illuminant, numbers]


## The gamut *primaries* are, or `custom`.
##
## Order matters and the table's does: Adobe RGB shares sRGB's red and blue and
## differs only in green, so a comparison that stopped at two primaries would
## call one the other. All three are compared, always.
static func gamut_name(primaries: PackedVector2Array) -> String:
    if primaries.size() < 3:
        return CUSTOM_NAME
    for entry: Array in gamuts():
        var known: PackedVector2Array = entry[1]
        if known.size() < 3:
            continue
        if _near(primaries[0], known[0]) and _near(primaries[1], known[1]) and _near(primaries[2], known[2]):
            var name: String = entry[0]
            return name
    return CUSTOM_NAME


static func _near(a: Vector2, b: Vector2) -> bool:
    return absf(a.x - b.x) <= TOLERANCE and absf(a.y - b.y) <= TOLERANCE
