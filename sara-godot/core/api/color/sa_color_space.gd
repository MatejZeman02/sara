## What a document's numbers mean: gamut, white point, transfer curve and depth.
##
## `.sad` records it, so a file means the same to every build that reads it
## and not only to the one that wrote it. This is data rather than an enum,
## because a colour space is four independent choices and the useful ones are
## combinations: ACEScg is AP1 primaries at D60 with a linear
## transfer, and "linear sRGB" is the sRGB gamut with the curve taken off.
@tool
class_name SaColorSpace
extends RefCounted

## Storage depth. F32 and F16 only: integer formats clamp to 0-1 by
## construction, which would make the no-clamp guarantee hold only sometimes.
enum Depth { F32, F16 }

## What the stored triple *is*, before gamut, white point and transfer say what
## it means. RGB is the default. OKLAB stores perceptual coordinates directly, so
## painting and the Normal blend mix along the perceptual axis rather than an
## RGB one, and the four non-separable modes stop converting at all.
##
## The other three axes keep their meaning under a non-RGB choice: gamut and
## white point say what the document is for on export, and the transfer curve
## is the document's RGB *view*, which every separable blend mode is
## arithmetic on.
enum Coordinates { RGB, OKLAB }

## Bradford cone response, the standard basis for chromatic adaptation. Rows are
## written as the maths states them and transposed on construction, because a
## Godot Basis takes columns.
const BRADFORD_ROWS := [
    Vector3(0.8951, 0.2664, -0.1614),
    Vector3(-0.7502, 1.7135, 0.0367),
    Vector3(0.0389, -0.0685, 1.0296),
]

## Stable string ids. These reach `.sad`, so they are the serialisation contract
## and must not change meaning.
const ID_SRGB: StringName = &"srgb"
const ID_LINEAR_SRGB: StringName = &"linear_srgb"
const ID_DISPLAY_P3: StringName = &"display_p3"
const ID_ACESCG: StringName = &"acescg"
const ID_REC2020: StringName = &"rec2020"
const ID_OKLAB: StringName = &"oklab"
const ID_OKLAB_P3: StringName = &"oklab_p3"
const ID_OKLAB_SRGB_GAMMA30: StringName = &"oklab_srgb_gamma30"
const ID_CUSTOM: StringName = &"custom"
const ID_UNSPECIFIED: StringName = &"unspecified"

## D65 to six places, not the four the sRGB spec tabulates: the rounded
## (0.3127, 0.3290) yields a blue column of 0.95053 where every published sRGB
## matrix says 0.95030, derived from the ASTM E308 white. Matching what other
## colour software actually uses avoids a small neutral shift on conversion.
const WHITE_D65 := Vector2(0.312727, 0.329023)
const WHITE_D60 := Vector2(0.32168, 0.33767)

## Identifies a preset, or `custom` when the values were set by hand. Not itself
## authoritative: the primaries, white point and transfer are.
var id: StringName = ID_SRGB

## Red, green and blue chromaticities in CIE xy.
var primaries: PackedVector2Array = PackedVector2Array([Vector2(0.640, 0.330), Vector2(0.300, 0.600), Vector2(0.150, 0.060)])

## White point in CIE xy.
var white: Vector2 = WHITE_D65

## The curve between stored values and light-linear ones, as a value rather than
## an enum member, so a document can declare one this file never heard of. See
## [SaTransferFunction].
var transfer: SaTransferFunction = SaTransferFunction.srgb()

var depth: Depth = Depth.F32

## The coordinate system the stored triple is written in. See [enum Coordinates].
##
## Additive to the v4 header: a file that does not name it holds RGB, the only
## coordinates a header without the field can have been written in.
var coordinates: Coordinates = Coordinates.RGB

## False when the document was loaded from a file that recorded no colour space.
##
## A v4 header can carry no colour space at all, and such files must keep
## opening. They are treated as gamma sRGB for rendering, which is
## what they were painted as, but the distinction is kept rather than papered
## over: "the file did not say" and "the file said sRGB" differ the moment
## anything offers to convert the document, and a converter that cannot tell them
## apart will silently transform pixels nobody described.
var is_specified: bool = true

## Whether a save the painter asks for rounds the full precision colour to
## [constant SaSadSnapshot.KEPT_BITS] significant bits, the painter's choice for
## each document, made beside the depth in the Image menu. On unless the painter
## turned it off, so a file that does not record the choice opens with it on.
## Not compared by
## [method matches], since it says how a file is written and not what a colour
## means, and carried by every copy below so a conversion keeps it.
var rounds_at_save: bool = true

## The description of the ICC profile file the space was read from, or empty
## for a space no file named. Saved with the document so its space reads back
## under the name the painter chose it by, and not as Custom. Not compared by
## [method matches], since it names the colours and does not change them.
var profile_name: String = ""


static func create(
    space_id: StringName,
    space_primaries: PackedVector2Array,
    space_white: Vector2,
    space_transfer: SaTransferFunction,
    space_depth: Depth = Depth.F32,
    space_coordinates: Coordinates = Coordinates.RGB
) -> SaColorSpace:
    var space := SaColorSpace.new()
    space.id = space_id
    space.primaries = space_primaries
    space.white = space_white
    space.transfer = space_transfer
    space.depth = space_depth
    space.coordinates = space_coordinates
    return space


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------


## Gamma-encoded sRGB, and what a file that records no colour space is read as.
static func srgb() -> SaColorSpace:
    return create(
        ID_SRGB,
        PackedVector2Array([Vector2(0.640, 0.330), Vector2(0.300, 0.600), Vector2(0.150, 0.060)]),
        WHITE_D65,
        SaTransferFunction.srgb()
    )


## The sRGB gamut with the curve taken off. The simplest scene-referred document.
static func linear_srgb() -> SaColorSpace:
    var space := srgb()
    space.id = ID_LINEAR_SRGB
    space.transfer = SaTransferFunction.linear()
    return space


static func display_p3() -> SaColorSpace:
    return create(
        ID_DISPLAY_P3,
        PackedVector2Array([Vector2(0.680, 0.320), Vector2(0.265, 0.690), Vector2(0.150, 0.060)]),
        WHITE_D65,
        SaTransferFunction.srgb()
    )


## ACEScg (AP1 primaries at D60), linear. The case the whole no-clamp invariant
## exists for: a Blender render opened here keeps its out-of-range values.
static func acescg() -> SaColorSpace:
    return create(
        ID_ACESCG,
        PackedVector2Array([Vector2(0.713, 0.293), Vector2(0.165, 0.830), Vector2(0.128, 0.044)]),
        WHITE_D60,
        SaTransferFunction.linear()
    )


static func rec2020() -> SaColorSpace:
    return create(
        ID_REC2020,
        PackedVector2Array([Vector2(0.708, 0.292), Vector2(0.170, 0.797), Vector2(0.131, 0.046)]),
        WHITE_D65,
        SaTransferFunction.linear()
    )


## What a document gets when a file recorded no colour space. Renders exactly as
## sRGB, and says it was never told.
static func unspecified() -> SaColorSpace:
    var space := srgb()
    space.id = ID_UNSPECIFIED
    space.is_specified = false
    return space


## Perceptual coordinates over the sRGB gamut: chunks hold Oklab (L, a, b)
## rather than red, green and blue.
##
## The gamut and the curve are not decoration here. Oklab itself is
## gamut-independent, so the primaries say what the document is for on export,
## and the sRGB curve is the RGB view every separable blend mode works in.
static func oklab() -> SaColorSpace:
    var space := srgb()
    space.id = ID_OKLAB
    space.coordinates = Coordinates.OKLAB
    return space


## Oklab coordinates over the Display P3 gamut with a cube-root curve.
##
## A preset is a label over primaries, a white, a curve and a coordinate
## system, and with none naming this combination File > New would read Custom
## for it. It is the shipped default a new document opens on.
##
## Gamma 3.0 rather than the sRGB curve because a cube root is what Oklab's own
## lightness is built on, so the RGB view the separable blend modes work in is
## nearly the perceptual axis the chunks already hold. Depth is not part of it:
## `with_depth` is applied before a match, so a preset carrying one would fail
## to name a document that is otherwise itself.
static func oklab_p3() -> SaColorSpace:
    var space := display_p3()
    space.id = ID_OKLAB_P3
    space.transfer = SaTransferFunction.gamma30()
    space.coordinates = Coordinates.OKLAB
    return space


## What Sara opens on when the display is an sRGB one: `oklab_p3`'s curve and
## coordinates over sRGB's primaries.
##
## The default takes its gamut from the display profile, so on an sRGB screen it
## is this combination, and no preset named it: New Document and the Colour
## Spaces page both read Custom for the space every fresh install paints in. It
## is its own preset rather than a change to `oklab`, because that one has the
## sRGB curve, an id reaches `.sad` files, and no old id may change meaning.
static func oklab_srgb_gamma30() -> SaColorSpace:
    var space := srgb()
    space.id = ID_OKLAB_SRGB_GAMMA30
    space.transfer = SaTransferFunction.gamma30()
    space.coordinates = Coordinates.OKLAB
    return space


## Every preset a chooser should offer, in the order it should offer them.
static func presets() -> Array[SaColorSpace]:
    var all: Array[SaColorSpace] = [
        srgb(), linear_srgb(), display_p3(), acescg(), rec2020(), oklab(), oklab_p3(), oklab_srgb_gamma30()
    ]
    return all


## The name a painter reads for a colour space, for a dropdown.
##
## Every Oklab entry says which gamut it carries, because Oklab has none: it is
## a coordinate system and is gamut independent, so the entry for sRGB's
## primaries and curve read in Oklab coordinates says "over sRGB" as "Oklab over
## Display P3" says its gamut, rather than a bare "Oklab". The third, over sRGB
## again, says "cube root" as well, because the two sRGB ones differ in the
## curve alone and a chooser showing both must tell them apart.
static func display_name(space_id: StringName) -> String:
    match space_id:
        ID_SRGB:
            return "sRGB"
        ID_LINEAR_SRGB:
            return "Linear sRGB"
        ID_DISPLAY_P3:
            return "Display P3"
        ID_ACESCG:
            return "ACEScg"
        ID_REC2020:
            return "Rec. 2020"
        ID_OKLAB:
            return "Oklab over sRGB"
        ID_OKLAB_P3:
            return "Oklab over Display P3"
        ID_OKLAB_SRGB_GAMMA30:
            return "Oklab over sRGB, cube root"
        ID_UNSPECIFIED:
            return "Unspecified"
        _:
            return "Custom"


# ---------------------------------------------------------------------------
# Derived matrices
# ---------------------------------------------------------------------------


## CIE xy plus an implied Y of 1 as an XYZ tristimulus. Kept here as well as on
## [SaGamut] because the white point is not a gamut's business and this is where
## callers reach for it.
static func xy_to_xyz(xy: Vector2) -> Vector3:
    return SaGamut.xy_to_xyz(xy)


## This document's three primaries as a gamut, named when they are a known one.
##
## The gamut is derived from the stored chromaticities rather than stored beside
## them, so a `.sad` that names no gamut still comes back with one, and a set of
## numbers that matches nothing is still a usable gamut rather than an error.
func gamut() -> SaGamut:
    var known := SaGamut.from_primaries(primaries)
    if known != null:
        return known
    return SaGamut.create(ID_CUSTOM, "Custom", primaries)


## The RGB to CIE XYZ matrix this space's primaries and white point imply.
func rgb_to_xyz() -> Basis:
    return gamut().rgb_to_xyz(white)


func xyz_to_rgb() -> Basis:
    return gamut().xyz_to_rgb(white)


static func _bradford() -> Basis:
    # The rows above become columns here, which is the transpose a Godot Basis
    # needs. Getting this backwards produces a matrix that still inverts and
    # still looks plausible, so it is asserted in test_sa_color_space.gd.
    return Basis(
        Vector3(BRADFORD_ROWS[0].x, BRADFORD_ROWS[1].x, BRADFORD_ROWS[2].x),
        Vector3(BRADFORD_ROWS[0].y, BRADFORD_ROWS[1].y, BRADFORD_ROWS[2].y),
        Vector3(BRADFORD_ROWS[0].z, BRADFORD_ROWS[1].z, BRADFORD_ROWS[2].z)
    )


## Bradford chromatic adaptation from white point *from_white* to *to_white*.
##
## Needed because converting between documents whose white points differ is not a
## plain matrix product: D65 white must come out as D60 white rather than as a
## colour cast, and only an adaptation step does that.
static func adaptation(from_white: Vector2, to_white: Vector2) -> Basis:
    var cone := _bradford()
    var source := cone * xy_to_xyz(from_white)
    var destination := cone * xy_to_xyz(to_white)
    if is_zero_approx(source.x) or is_zero_approx(source.y) or is_zero_approx(source.z):
        return Basis.IDENTITY
    var ratio := Basis(
        Vector3(destination.x / source.x, 0.0, 0.0),
        Vector3(0.0, destination.y / source.y, 0.0),
        Vector3(0.0, 0.0, destination.z / source.z)
    )
    return cone.inverse() * ratio * cone


## The matrix taking linear RGB in this space to linear RGB in *target*, white
## point adapted. Identity-ish when the two describe the same space.
func to_space_matrix(target: SaColorSpace) -> Basis:
    if target == null:
        return Basis.IDENTITY
    return target.xyz_to_rgb() * adaptation(white, target.white) * rgb_to_xyz()


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------


## The RenderingDevice format a colour field uses at this depth.
##
## What the descriptor *asks for*. Whether chunk storage can currently allocate
## it is a separate question, answered by [method storage_supports_depth].
func texel_format() -> int:
    return (
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT if depth == Depth.F16 else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    )


## Depths chunk storage can actually allocate: both, because kernels are
## compiled once per storage format and every dispatch site selects the
## variant matching the texture it binds. A list rather than "every depth the
## enum has", because a chooser must offer only what can be allocated, and the
## enum is the serialisation contract rather than a capability claim.
static func storage_depths() -> Array[int]:
    var supported: Array[int] = [Depth.F32, Depth.F16]
    return supported


## A copy of this descriptor at a different storage depth.
##
## Depth is orthogonal to what the colours mean: it is how many bits each channel
## gets, not which primaries or curve they are in. Keeping the two separable is
## what lets a conversion change the gamut of an F16 document without quietly
## reallocating it, and it keeps open splitting the descriptor further along
## the same line.
func with_depth(value: Depth) -> SaColorSpace:
    var copy := create(id, primaries, white, transfer, value, coordinates)
    copy.is_specified = is_specified
    copy.rounds_at_save = rounds_at_save
    copy.profile_name = profile_name
    return copy


## The same descriptor with [member rounds_at_save] set to *on*.
func with_rounding(on: bool) -> SaColorSpace:
    var copy := with_depth(depth)
    copy.rounds_at_save = on
    return copy


## The same descriptor storing *value* instead. Everything else is untouched,
## because the other three axes describe the document either way: what changes is
## only what the numbers in the chunks are.
func with_coordinates(value: Coordinates) -> SaColorSpace:
    var copy := create(id, primaries, white, transfer, depth, value)
    copy.is_specified = is_specified
    copy.rounds_at_save = rounds_at_save
    copy.profile_name = profile_name
    return copy


## The same descriptor over *target*'s primaries and its conventional white, named
## again when that makes a preset. What a document takes from the display profile
## and what Image, Gamut converts to: the curve, the coordinates and the depth are
## not the gamut's business.
func with_gamut(target: SaGamut) -> SaColorSpace:
    var copy := create(ID_CUSTOM, target.primaries, target.default_white(), transfer, depth, coordinates)
    copy.rounds_at_save = rounds_at_save
    for preset: SaColorSpace in presets():
        if preset.with_depth(depth).matches(copy):
            copy.id = preset.id
            break
    return copy


## Human-readable name for a coordinate system, for a chooser.
static func coordinates_name(value: int) -> String:
    return "Oklab" if value == Coordinates.OKLAB else "RGB"


## Every coordinate system a chooser should offer, in the order it should offer
## them. RGB first, because it is what almost every document should be.
static func storage_coordinates() -> Array[int]:
    return [Coordinates.RGB, Coordinates.OKLAB]


## Whether chunk storage can allocate colour fields at *value* today.
static func storage_supports_depth(value: int) -> bool:
    return storage_depths().has(value)


## Human-readable name for a depth, for a chooser.
static func depth_name(value: int) -> String:
    return "16-bit float" if value == Depth.F16 else "32-bit float"


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

const _DEPTH_NAMES := {Depth.F32: "F32", Depth.F16: "F16"}
const _COORDINATE_NAMES := {Coordinates.RGB: "RGB", Coordinates.OKLAB: "OKLAB"}


## The `.sad` v4 header representation. Enums are written as strings on purpose:
## an integer would silently change meaning the day somebody reorders the enum,
## and this is a file format. The rounding at save is written only when it is
## off, so a file with it on is byte for byte the file a build without the
## choice writes.
func to_header() -> Dictionary[String, Variant]:
    var xy: Array = []
    for point: Vector2 in primaries:
        xy.append([point.x, point.y])
    var header: Dictionary[String, Variant] = {
        "id": String(id),
        "primaries": xy,
        "white": [white.x, white.y],
        "transfer": String(transfer.id) if transfer != null else String(SaTransferFunction.ID_SRGB),
        # The numbers as well as the name, so a curve no build has a name for can
        # still be saved. A gamma chosen on a slider is exactly that: the id says
        # "some pure power curve" and only these four say which one.
        "transfer_params": Array(transfer.to_params()) if transfer != null else Array(SaTransferFunction.srgb().to_params()),
        "depth": _DEPTH_NAMES.get(depth, "F32"),
        "coordinates": _COORDINATE_NAMES.get(coordinates, "RGB"),
    }
    if not rounds_at_save:
        header["rounds_at_save"] = false
    if not profile_name.is_empty():
        header["profile_name"] = profile_name
    return header


## Reads the descriptor a header carries, or `unspecified()` when it carries none.
##
## Never assume sRGB for a missing key. Files written by the build that shipped
## v4 without a colour descriptor are real, and pretending they declared
## something is how a later conversion pass corrupts a document nobody described.
static func from_header(header: Dictionary[String, Variant]) -> SaColorSpace:
    if not header.has("color_space"):
        return unspecified()
    var raw := SaTyped.strings(header.get("color_space"))

    var space := SaColorSpace.new()
    space.id = StringName(str(raw.get("id", ID_CUSTOM)))

    var xy: Array = raw.get("primaries", [])
    if xy.size() >= 3:
        var parsed := PackedVector2Array()
        for point: Array in xy:
            parsed.append(Vector2(SaTyped.real(point[0]), SaTyped.real(point[1])))
        space.primaries = parsed

    var white_raw: Array = raw.get("white", [])
    if white_raw.size() >= 2:
        space.white = Vector2(SaTyped.real(white_raw[0]), SaTyped.real(white_raw[1]))

    # A curve this build does not have is a newer Sara or a module, and sRGB is
    # the fallback said out loud rather than assumed, since a document silently
    # rendered through the wrong curve looks plausible and is wrong everywhere.
    var transfer_id := StringName(str(raw.get("transfer", SaTransferFunction.ID_SRGB)))
    var curve := SaTransferFunction.from_id(transfer_id)
    # The numbers win over the name when a file carries both and disagrees, and
    # are the only thing that can describe a curve chosen on a slider.
    var raw_params: Variant = raw.get("transfer_params", [])
    var params: Array = raw_params if raw_params is Array else []
    var declared := SaTransferFunction.from_params(transfer_id, params)
    if declared != null and (curve == null or not curve.matches(declared)):
        curve = declared
    if curve == null:
        push_warning("SaColorSpace: unknown transfer curve '%s', reading the document as sRGB." % transfer_id)
        curve = SaTransferFunction.srgb()
    space.transfer = curve
    space.depth = Depth.F16 if str(raw.get("depth", "F32")) == "F16" else Depth.F32
    # A file naming no coordinate system holds RGB, a fact about the format
    # rather than an assumption, because the field is additive to the header. An unknown name is a
    # newer Sara or a module and is read as RGB anyway, warned rather than
    # refused, since refusing to open the file would be worse.
    var coordinate_name := str(raw.get("coordinates", "RGB"))
    if coordinate_name == "OKLAB":
        space.coordinates = Coordinates.OKLAB
    elif coordinate_name != "RGB":
        push_warning("SaColorSpace: unknown coordinate system '%s', reading the document as RGB." % coordinate_name)
    # A file that does not say is a file saved with the rounding on.
    space.rounds_at_save = raw.get("rounds_at_save", true) != false
    space.profile_name = str(raw.get("profile_name", ""))
    return space


# ---------------------------------------------------------------------------
# GLSL generation
# ---------------------------------------------------------------------------

## The name kernels `#include` to get this document's colour maths.
const GLSL_INCLUDE_NAME := "document_color_space"


## A Basis as the three column vectors a shader wants, in the `basis * v` sense.
## See sa_color_space_glsl.gd.
static func basis_columns(basis: Basis) -> Array[Vector3]:
    return SaColorSpaceGlsl.basis_columns(basis)


## This document's colour maths as a `.gmacs` include. See sa_color_space_glsl.gd.
func to_glsl() -> String:
    return SaColorSpaceGlsl.to_glsl(self)


## Two descriptors describe the same space when their values agree, whatever
## their ids say. `is_specified` is about provenance, not about colour, so it is
## deliberately not compared.
func matches(other: SaColorSpace) -> bool:
    if other == null:
        return false
    if depth != other.depth:
        return false
    if coordinates != other.coordinates:
        return false
    if transfer == null or not transfer.matches(other.transfer):
        return false
    if not white.is_equal_approx(other.white):
        return false
    if primaries.size() != other.primaries.size():
        return false
    for i in primaries.size():
        if not primaries[i].is_equal_approx(other.primaries[i]):
            return false
    return true


# ---------------------------------------------------------------------------
# Kernel transport
# ---------------------------------------------------------------------------


## The matrix taking this document's linear RGB into linear sRGB.
##
## Oklab is defined against linear sRGB, so a non-separable blend mode needs this
## to read a wide-gamut document's numbers as colours rather than as sRGB triples
## that happen to share their components.
func to_linear_srgb_matrix() -> Basis:
    var target := SaColorSpace.linear_srgb()
    if shares_gamut(target):
        return Basis.IDENTITY
    return to_space_matrix(target)


## The inverse of [method to_linear_srgb_matrix], taking linear sRGB back into
## this document's linear RGB.
func from_linear_srgb_matrix() -> Basis:
    var source := SaColorSpace.linear_srgb()
    if shares_gamut(source):
        return Basis.IDENTITY
    return source.to_space_matrix(self)


## Whether two descriptors span the same gamut, ignoring transfer and depth.
## The exact identity is worth insisting on rather than accepting whatever
## `M.inverse() * M` rounds to: the composite path is asserted bit-exact for
## values it is not supposed to disturb.
func shares_gamut(other: SaColorSpace) -> bool:
    if other == null:
        return false
    if not white.is_equal_approx(other.white):
        return false
    if primaries.size() != other.primaries.size():
        return false
    for i in primaries.size():
        if not primaries[i].is_equal_approx(other.primaries[i]):
            return false
    return true


## Short name for the space a mode with no space of its own would blend in,
## shown in brackets after "Normal". Names the encoding rather than the gamut,
## since that is what a Porter-Duff lerp actually travels through.
func blend_space_name() -> String:
    if coordinates == Coordinates.OKLAB:
        return "Oklab"
    if is_linear():
        return "linear"
    return transfer.display_name if transfer != null else "sRGB"


## Whether stored values carry no curve at all, so a caller can skip a decode
## rather than compute one that should do nothing.
func is_linear() -> bool:
    return transfer == null or transfer.is_identity()


## How light a colour *stored* in this space is, 0 for black and 1 for white,
## read in the stored numbers themselves: Oklab's own L, and for an RGB space
## the luminance its primaries and white point give, over the values as they
## sit in the texture, so a grey stored as 0.5 reads 0.5 whatever the curve.
## A brush on a mask paints this number as coverage, which is Krita's rule.
## Nothing is clamped, so a colour past white reads past 1.
func lightness(stored: Color) -> float:
    if coordinates == Coordinates.OKLAB:
        return stored.r
    return (rgb_to_xyz() * Vector3(stored.r, stored.g, stored.b)).y


## Whether stored values are already what a screen and a colour picker want.
## True for any sRGB-gamut document with the sRGB curve, so callers take an
## exact passthrough rather than a round trip only approximately the identity.
func is_display_ready() -> bool:
    if coordinates != Coordinates.RGB:
        return false
    return transfer != null and transfer.id == SaTransferFunction.ID_SRGB and to_linear_srgb_matrix() == Basis.IDENTITY


## A colour as the picker holds it, in this document's own coordinates.
##
## **The picker speaks the document's gamut**. `1, 0, 0` is the red of the
## gamut the document declares, so a Display P3 document stores P3's red for it
## and an sRGB one stores sRGB's, and only the view maps either to the screen.
## Were every picked colour sRGB whatever the document said, no gesture would
## reach past sRGB and a P3 document proofed to sRGB would have nothing to
## move. The document is the source of truth, the way Photoshop and Krita have
## it.
##
## The curve stays the sRGB one whatever the document's is. The picker's numbers
## are what a screen shows, so mid grey from the wheel still lands in a linear
## document as 0.214 rather than 0.5. Alpha is coverage, never colour, and is carried through
## untouched.
func from_display(color: Color) -> Color:
    if _picks_stored():
        return color
    var display_curve := SaTransferFunction.srgb()
    var linear := Vector3(display_curve.decode(color.r), display_curve.decode(color.g), display_curve.decode(color.b))
    # Oklab is defined against linear sRGB and carries no gamut of its own, so
    # the document's gamut is carried there first. A wide gamut's red leaves 0 to
    # 1 on the way, P3's being sRGB red past one with green and blue below zero,
    # and nothing clamps it.
    if coordinates == Coordinates.OKLAB:
        var lab := SaOklab.from_linear_srgb(to_linear_srgb_matrix() * linear)
        return Color(lab.x, lab.y, lab.z, color.a)
    return Color(transfer.encode(linear.x), transfer.encode(linear.y), transfer.encode(linear.z), color.a)


## The inverse: a stored value as the picker's triple for it, in the gamut the
## document declares.
##
## What the eyedropper owes the colour wheel. Reading a texel and handing it over
## unconverted is the same bug as the brush's, in the other direction.
func to_display(color: Color) -> Color:
    if _picks_stored():
        return color
    var linear: Vector3
    if coordinates == Coordinates.OKLAB:
        linear = from_linear_srgb_matrix() * SaOklab.to_linear_srgb(Vector3(color.r, color.g, color.b))
    else:
        linear = Vector3(transfer.decode(color.r), transfer.decode(color.g), transfer.decode(color.b))
    var display_curve := SaTransferFunction.srgb()
    return Color(display_curve.encode(linear.x), display_curve.encode(linear.y), display_curve.encode(linear.z), color.a)


## Whether the picker's triple is already what the chunks hold: RGB through the
## sRGB curve, in any gamut. Wider than [method is_display_ready], which is the
## screen's question and asks for sRGB's primaries as well.
func _picks_stored() -> bool:
    return coordinates == Coordinates.RGB and transfer != null and transfer.id == SaTransferFunction.ID_SRGB


## A stored value of this space as the stored value of *target* that is the same
## colour, carried through linear sRGB.
##
## The colorimetric crossing, for a value that already names a colour: a pixel
## of a reference picture sampled into a document of another gamut. A picked
## triple is not one of those, it means whatever the document it lands in
## declares, and [method from_display] is its door.
func carried_to(target: SaColorSpace, color: Color) -> Color:
    if target == null or matches(target.with_depth(depth)):
        return color
    var linear: Vector3
    if coordinates == Coordinates.OKLAB:
        linear = SaOklab.to_linear_srgb(Vector3(color.r, color.g, color.b))
    else:
        linear = to_linear_srgb_matrix() * Vector3(transfer.decode(color.r), transfer.decode(color.g), transfer.decode(color.b))
    if target.coordinates == Coordinates.OKLAB:
        var lab := SaOklab.from_linear_srgb(linear)
        return Color(lab.x, lab.y, lab.z, color.a)
    var own: Vector3 = target.from_linear_srgb_matrix() * linear
    return Color(target.transfer.encode(own.x), target.transfer.encode(own.y), target.transfer.encode(own.z), color.a)


## A stored value of *source* as the picker's triple in *target*: a colour
## sampled off a picture that is not the document, named in the gamut the picker
## now speaks. A null *source* is a picture that never said and hands its
## numbers over as they are, and a null *target* is no document, where the
## picture's own gamut is the only one there is.
static func picked_across(source: SaColorSpace, target: SaColorSpace, stored: Color) -> Color:
    if source == null:
        return stored
    if target == null:
        return source.to_display(stored)
    return target.to_display(source.carried_to(target, stored))


## How many floats [method to_push_constant] writes. See sa_color_space_push_constant.gd.
const PUSH_CONSTANT_FLOATS: int = SaColorSpacePushConstant.PUSH_CONSTANT_FLOATS

## How many floats [method to_conversion_push_constant] writes.
const CONVERSION_PUSH_CONSTANT_FLOATS: int = SaColorSpacePushConstant.CONVERSION_PUSH_CONSTANT_FLOATS

## The tail [method to_push_constant] built last, and the fields it read to
## build it, so the next call hands it back unless one of those fields reads
## differently now.
var _tail := PackedFloat32Array()
var _tail_primaries := PackedVector2Array()
var _tail_white := Vector2.INF
var _tail_curve := PackedFloat32Array()
var _tail_coordinates: int = -1


## This descriptor as the tail of a composite kernel's push constant.
##
## Built once and kept, because a composite asks for it once per dispatch and a
## frame under adjustment layers runs thousands of them, each of which built the
## two matrices again, 61 ms of a 242 ms frame when it was measured. There is no setter
## to drop the kept tail on, so every call compares what the tail is built from
## with what it was built from: the primaries, the white, the curve's four
## numbers as the kernel reads them and the coordinates. A field written after
## the first read, as the suites do, gives the tail of its present value. The
## caller gets a copy, so one that writes into its tail never writes into ours.
func to_push_constant() -> PackedFloat32Array:
    var curve := transfer.to_params()
    var same := (
        _tail_coordinates == int(coordinates) and _tail_white == white and _tail_curve == curve and _tail_primaries == primaries
    )
    if not same:
        _tail = SaColorSpacePushConstant.to_push_constant(self)
        _tail_primaries = primaries.duplicate()
        _tail_white = white
        _tail_curve = curve
        _tail_coordinates = int(coordinates)
    return _tail.duplicate()


## The matrix taking this space's linear RGB into *target*'s, white point adapted.
func conversion_matrix(target: SaColorSpace) -> Basis:
    return SaColorSpacePushConstant.conversion_matrix(self, target)


## The push constant `convert_color_space.gmacs` reads: the matrix into *target*,
## then which transfer curve sits on each side.
func to_conversion_push_constant(target: SaColorSpace) -> PackedFloat32Array:
    return SaColorSpacePushConstant.to_conversion_push_constant(self, target)
