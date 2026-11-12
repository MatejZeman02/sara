## One of the four axes a colour space is made of: which three lights the numbers
## are amounts of.
##
## A gamut is its three primary chromaticities and nothing else. It deliberately
## does **not** carry a white point: the same primaries at a different white are
## still the same three lights, and pretending otherwise is what makes every pair
## of spaces a special case instead of a composition. White points bridge
## separately, through Bradford adaptation, in `SaColorSpace`.
##
## The matrices are derived rather than tabulated. Published sRGB matrices differ
## in the last digit depending on which white point rounding their source used, so
## a table would encode somebody else's rounding as though it were the standard.
## Deriving from the chromaticities makes the rounding visible and one decision:
## see `SaColorSpace.WHITE_D65`.
@tool
class_name SaGamut
extends RefCounted

## Stable ids. These reach `.sad` through the space id, so they are part of the
## serialisation contract.
const ID_SRGB: StringName = &"srgb"
const ID_DISPLAY_P3: StringName = &"display_p3"
const ID_AP1: StringName = &"ap1"
const ID_REC2020: StringName = &"rec2020"

var id: StringName = ID_SRGB

var display_name: String = "sRGB / Rec. 709"

## Red, green and blue chromaticities in CIE xy.
var primaries: PackedVector2Array = PackedVector2Array()


static func create(gamut_id: StringName, name: String, xy: PackedVector2Array) -> SaGamut:
    var gamut := SaGamut.new()
    gamut.id = gamut_id
    gamut.display_name = name
    gamut.primaries = xy
    return gamut


## The primaries sRGB and Rec. 709 share. One gamut, two standards, which is
## exactly why the gamut is separable from the curve.
static func srgb() -> SaGamut:
    return create(
        ID_SRGB, "sRGB / Rec. 709", PackedVector2Array([Vector2(0.640, 0.330), Vector2(0.300, 0.600), Vector2(0.150, 0.060)])
    )


static func display_p3() -> SaGamut:
    return create(
        ID_DISPLAY_P3, "Display P3", PackedVector2Array([Vector2(0.680, 0.320), Vector2(0.265, 0.690), Vector2(0.150, 0.060)])
    )


## ACES AP1, the primaries ACEScg uses.
static func ap1() -> SaGamut:
    return create(ID_AP1, "ACES AP1", PackedVector2Array([Vector2(0.713, 0.293), Vector2(0.165, 0.830), Vector2(0.128, 0.044)]))


static func rec2020() -> SaGamut:
    return create(
        ID_REC2020, "Rec. 2020", PackedVector2Array([Vector2(0.708, 0.292), Vector2(0.170, 0.797), Vector2(0.131, 0.046)])
    )


## Every gamut a document may declare, in the order a chooser should offer them.
static func presets() -> Array[SaGamut]:
    var all: Array[SaGamut] = [srgb(), display_p3(), ap1(), rec2020()]
    return all


## The gamut *gamut_id* names, or null when nothing does.
static func from_id(gamut_id: StringName) -> SaGamut:
    for gamut in presets():
        if gamut.id == gamut_id:
            return gamut
    return null


## The named gamut whose primaries these are, or null for a custom set. Used to
## give a loaded document's chromaticities a name again, so the browser and the
## info docker can say "Display P3" rather than three pairs of numbers.
static func from_primaries(xy: PackedVector2Array) -> SaGamut:
    for gamut in presets():
        if gamut.matches_primaries(xy):
            return gamut
    return null


## The white point this gamut is conventionally normalised to.
##
## A gamut does not require a white, which is why one is not stored here, but
## every one of these has a conventional partner and a chooser offering the three
## lights without one would be asking a question nobody wants. ACES AP1 is D60 and
## everything else here is D65.
func default_white() -> Vector2:
    return SaColorSpace.WHITE_D60 if id == ID_AP1 else SaColorSpace.WHITE_D65


func matches_primaries(xy: PackedVector2Array) -> bool:
    if xy.size() != primaries.size():
        return false
    for i in primaries.size():
        if not primaries[i].is_equal_approx(xy[i]):
            return false
    return true


func matches(other: SaGamut) -> bool:
    return other != null and matches_primaries(other.primaries)


## How far outside an edge a primary may sit and still count as on it, in xy.
## The published chromaticities have three decimals, so a shared primary such
## as the blue sRGB and Display P3 both use lands on the edge to within float
## rounding and nothing a real gamut differs by comes near this.
const CONTAINS_TOLERANCE := 1e-6


## Whether every colour *other* holds lies inside this gamut, which is what a
## soft proof into this one would leave alone.
##
## A gamut's colours are the triangle its primaries span in CIE xy, and one
## triangle lies inside another when its three corners do, so the primaries are
## the whole test. A primary on an edge counts as inside, because sRGB and
## Display P3 share their blue and P3 still holds all of sRGB. Chromaticity
## alone, with no white point weighed, which is the separation the class
## comment makes: the proofs Preferences offers are all D65.
func contains(other: SaGamut) -> bool:
    if other == null or primaries.size() < 3 or other.primaries.size() < 3:
        return false
    for point in other.primaries:
        if not _encloses(point):
            return false
    return true


## What a soft proof into this gamut says over a document whose gamut is
## *shown*, under the mode's own name *mode_name*, for the canvas corner.
##
## Both gamuts, because the document's is what a picked colour means and which
## of the two is squeezed into which is the question. Then what the proof can
## do. A document whose gamut fits inside this one loses nothing to it, so the
## picture does not change, and the line says that is why, and where a narrower
## gamut is chosen when one of *offered* is narrower, rather than leaving the
## painter to decide the proof is broken. Inside the document's gamut, because
## paint brighter than its white lies outside every proof's cube and is clipped
## whichever is chosen.
##
## *offered* is the gamut ids a proof can be chosen from. The caller hands them
## in, the way `SaGamutMapping` is handed its setting, because a library here
## reads no preferences. Here rather than beside either caller because the
## canvas's Ctrl+Y and the Minimap's own proof say the same words, and the two
## sit in packages that cannot name each other's files.
func proof_line(mode_name: String, shown: SaGamut, offered: Array[String]) -> String:
    var head := TranslationServer.translate("%s: %s shown as %s") % [mode_name, shown.display_name, display_name]
    if not contains(shown):
        return TranslationServer.translate("%s, so colours outside %s are clipped.") % [head, display_name]
    var clips_nothing := TranslationServer.translate("%s, so nothing inside the document's gamut is clipped.") % head
    for gamut_id: String in offered:
        var other := from_id(StringName(gamut_id))
        if other != null and not other.contains(shown):
            return (
                clips_nothing
                + " "
                + TranslationServer.translate("Pick a narrower proof gamut in Preferences > Canvas and colour.")
            )
    return clips_nothing + " " + TranslationServer.translate("Preferences > Canvas and colour offers no narrower proof gamut.")


## Whether *point* lies inside this gamut's triangle or on its edge, whichever
## way round the three primaries are listed.
func _encloses(point: Vector2) -> bool:
    var winding := signf((primaries[1] - primaries[0]).cross(primaries[2] - primaries[0]))
    if winding == 0.0:
        return false
    for i in 3:
        var start := primaries[i]
        var side := (primaries[(i + 1) % 3] - start).cross(point - start) * winding
        if side < -CONTAINS_TOLERANCE:
            return false
    return true


## CIE xy plus an implied Y of 1 as an XYZ tristimulus.
static func xy_to_xyz(xy: Vector2) -> Vector3:
    if is_zero_approx(xy.y):
        return Vector3.ZERO
    return Vector3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y)


## This gamut's linear RGB to CIE XYZ, for a document whose white is *white*.
##
## Standard construction: build the matrix of primary tristimuli, solve it against
## the white point to get the per-primary scale that makes RGB 1,1,1 land exactly
## on the white point, then fold those scales in as columns.
##
## The white is a parameter rather than a member for the reason in the class
## comment: the same three lights normalised to a different white are the same
## gamut, and this matrix is where the two axes finally meet.
func rgb_to_xyz(white: Vector2) -> Basis:
    if primaries.size() < 3:
        return Basis.IDENTITY
    var r := xy_to_xyz(primaries[0])
    var g := xy_to_xyz(primaries[1])
    var b := xy_to_xyz(primaries[2])
    # A Godot Basis is built from its columns, and the primaries are exactly the
    # columns of this matrix, so no transpose is needed here.
    var primary_matrix := Basis(r, g, b)
    var scale := primary_matrix.inverse() * xy_to_xyz(white)
    return Basis(r * scale.x, g * scale.y, b * scale.z)


func xyz_to_rgb(white: Vector2) -> Basis:
    return rgb_to_xyz(white).inverse()
