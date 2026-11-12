## How the canvas fills a display wider than the document.
##
## A painter who likes a wide panel's saturated colours may want the document's
## primaries shown as the panel's own, as a program that takes the display for
## sRGB does, and a panel such as Display P3 reaches much further in green and
## red than in blue, so a second choice stretches all three evenly.
##
## Three matrices from linear sRGB, which is where the view shader holds a
## colour once the document, the proof and the roll-off are done with it, into
## the display's linear RGB. *Correct* converts into the display profile's
## primaries. *Native* hands the panel the document's own linear RGB
## unconverted, so the panel reads the document's red as its own red. *Even*
## does what Native does over primaries stretched from the document's: each one
## moved outward in Oklab by the same chroma ratio, at its own lightness and
## hue, the ratio being the largest all three can take and still sit on the
## panel, so nothing clips and a mix leans no way the primaries do not. The
## matrix keeps white, so it sets each primary's intensity rather than keeping
## it, and the ratio holds for chroma over lightness, which scaling a linear
## colour leaves alone because Oklab takes one cube root of all three.
##
## A view transform on the display side, never a stored pixel, and the title bar
## says when it is not Correct, so a colour judged under Native is not mistaken
## for one that survives export.
class_name SaDisplayFill
extends RefCounted

const CORRECT := "correct"
const NATIVE := "native"
const EVEN := "even"

## The widest stretch the search tries, and how many halvings it makes. Forty
## halvings of four is far past any number a float matrix can tell apart.
const MAX_RATIO := 4.0
const RATIO_STEPS := 40

## How far below zero a display channel may read and still count as on the
## panel, relative to the largest channel, so a primary the panel shares with the
## document is not refused over rounding.
const ON_PANEL_TOLERANCE := 0.00001

const PRIMARY_NAMES: Array[String] = ["red", "green", "blue"]


## The name of *fill* in the window title and on Canvas and colour.
static func display_name(fill: String) -> String:
    match fill:
        NATIVE:
            return "Unconverted"
        EVEN:
            return "Even stretch"
    return "Converted"


## Linear sRGB into the display's linear RGB, for *fill* over a document in
## *document* on a display in *display*.
static func matrix(fill: String, document: SaColorSpace, display: SaColorSpace) -> Basis:
    var shown := display if display != null else SaColorSpace.srgb()
    var source := _gamut_of(document)
    match fill:
        NATIVE:
            return source.from_linear_srgb_matrix()
        EVEN:
            var stretched := SaColorSpace.create(
                SaColorSpace.ID_CUSTOM, stretched_primaries(source, shown), SaColorSpace.WHITE_D65, SaTransferFunction.linear()
            )
            var into_display: Basis = shown.xyz_to_rgb() * SaColorSpace.adaptation(SaColorSpace.WHITE_D65, shown.white)
            return into_display * stretched.rgb_to_xyz() * source.from_linear_srgb_matrix()
    # The expression the canvas has always used, so Correct is today's matrix to
    # the last bit and an sRGB display keeps its exact passthrough.
    if shown.is_display_ready():
        return Basis.IDENTITY
    return shown.to_linear_srgb_matrix().inverse()


## How far each of the document's primaries can stretch in Oklab chroma and stay
## on the panel, red, green and blue. Below one where the document is wider than
## the panel, in which case Even shrinks rather than clips.
static func stretch_ratios(document: SaColorSpace, display: SaColorSpace) -> PackedFloat32Array:
    var source := _gamut_of(document)
    var shown := display if display != null else SaColorSpace.srgb()
    var ratios := PackedFloat32Array()
    for channel in 3:
        var low := 0.0
        var high := MAX_RATIO
        for step in RATIO_STEPS:
            var middle := (low + high) * 0.5
            if _on_panel(stretched_primary(source, channel, middle), shown):
                low = middle
            else:
                high = middle
        ratios.append(low)
    return ratios


## The one ratio Even stretches by: the smallest of [method stretch_ratios].
static func even_ratio(document: SaColorSpace, display: SaColorSpace) -> float:
    var ratios := stretch_ratios(document, display)
    return minf(ratios[0], minf(ratios[1], ratios[2]))


## Which primary sets [method even_ratio], 0 for red, 1 for green, 2 for blue.
static func limiting_primary(document: SaColorSpace, display: SaColorSpace) -> int:
    var ratios := stretch_ratios(document, display)
    var at := 0
    for channel in 3:
        if ratios[channel] < ratios[at]:
            at = channel
    return at


## The document's primary *channel* moved outward by *ratio* in Oklab chroma, at
## its own lightness and hue, in linear sRGB.
static func stretched_primary(document: SaColorSpace, channel: int, ratio: float) -> Vector3:
    var unit := Vector3.ZERO
    unit[channel] = 1.0
    var lab := SaOklab.from_linear_srgb(_gamut_of(document).to_linear_srgb_matrix() * unit)
    return SaOklab.to_linear_srgb(Vector3(lab.x, lab.y * ratio, lab.z * ratio))


## The chromaticities Even treats the document's numbers as, one ratio for all
## three primaries.
static func stretched_primaries(document: SaColorSpace, display: SaColorSpace) -> PackedVector2Array:
    var ratio := even_ratio(document, display)
    var out := PackedVector2Array()
    var to_xyz := SaColorSpace.linear_srgb().rgb_to_xyz()
    for channel in 3:
        var xyz: Vector3 = to_xyz * stretched_primary(document, channel, ratio)
        var sum := maxf(xyz.x + xyz.y + xyz.z, 0.000001)
        out.append(Vector2(xyz.x / sum, xyz.y / sum))
    return out


## The three matrices and the stretch for a dump, so a scenario reads numbers
## where a shot of a stretched picture is only a picture.
static func report(fill: String, document: SaColorSpace, display: SaColorSpace) -> Dictionary:
    var ratios := stretch_ratios(document, display)
    return {
        "fill": fill,
        "name": display_name(fill),
        "correct": _rows(matrix(CORRECT, document, display)),
        "native": _rows(matrix(NATIVE, document, display)),
        "even": _rows(matrix(EVEN, document, display)),
        "stretch_ratios": Array(ratios),
        "even_ratio": even_ratio(document, display),
        "even_set_by": PRIMARY_NAMES[limiting_primary(document, display)],
    }


## A document's primaries and white, linear: the gamut without its curve or its
## coordinates, which is all a display matrix asks about. sRGB for no document.
static func _gamut_of(document: SaColorSpace) -> SaColorSpace:
    if document == null:
        return SaColorSpace.linear_srgb()
    return SaColorSpace.create(SaColorSpace.ID_CUSTOM, document.primaries, document.white, SaTransferFunction.linear())


static func _on_panel(linear_srgb: Vector3, shown: SaColorSpace) -> bool:
    var channels: Vector3 = shown.from_linear_srgb_matrix() * linear_srgb
    var largest := maxf(channels.x, maxf(channels.y, channels.z))
    return minf(channels.x, minf(channels.y, channels.z)) >= -ON_PANEL_TOLERANCE * maxf(largest, 0.000001)


static func _rows(basis: Basis) -> Array:
    return [
        [basis.x.x, basis.y.x, basis.z.x],
        [basis.x.y, basis.y.y, basis.z.y],
        [basis.x.z, basis.y.z, basis.z.z],
    ]
