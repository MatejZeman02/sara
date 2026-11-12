## Filter > Distort > Lens Correction, a photograph's barrel or pincushion
## straightened.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Lens correction, a lens and sensor effect, for a photograph that
## arrived already developed. One neighbourhood pass over `lens_correction.gmacs`
## under the radial model of Brown and Conrady with its first term alone: a
## texel at the distance r from the document's centre, r counted in half
## diagonals, reads the picture at (1 - k r²) times that distance along the same
## radius, where k is Amount over a hundred. Above nought a corner reads from
## nearer the middle, so the picture spreads outwards towards its corners and the
## bulge of a barrel straightens. Below nought a corner reads from further out,
## the picture draws in and a pincushion's pinch straightens. Lines that were
## straight bow the other way, which is how a painter sees the amount on a grid.
##
## One term because one slider sets it by eye against a line that should be
## straight. The second term bends the corners against the middles of the edges,
## the moustache of a few wide zooms, and asks for a second slider that no single
## straight line could set apart from the first.
##
## The centre is the document's, handed to the kernel as the document's size,
## and never the layer's or the dirty rectangle's, so a layer painted in one
## corner chunk alone moves by where its paint sits on the canvas and an attached
## filter agrees with a bake.
##
## Crop to fill scales the corrected picture up about the same centre, by the
## least factor at which every texel of the document reads from inside it, so a
## picture drawn in shows no streaked or empty edge. A texel at r reads at
## (r / s)(1 - k r² / s²), which rises with r, so the texel that reads furthest
## out against its own edge is a corner's, and the factor is the root of
## s²(s - 1) = -k r² at the corner texel's middle. Above nought every read
## already falls inside and the factor is one. A record saved before the switch
## reads it as off and paints the pixels it did.
##
## The furthest any texel reads from its own place decides how the pass reads.
## Within a chunk it is a halo round each chunk, the pass a saved record has
## always laid. Past it, a correction of 30 percent on a photograph 4000 pixels
## wide moves a corner 750, the pass reads the whole node, and its
## [member SaNeighbourhoodPass.carries] answers the band of the canvas whose
## reads land in a changed rectangle, so a stroke under an attached correction
## redraws that band and not the picture. Nothing holds the amount, and the
## slider reaches what it says on a canvas of any size.
##
## The parameters are kept in the store, which the compositor reads with no
## dialog built.
class_name SaLensCorrectionFilter
extends SaFilter

const SHADER := "sara-base-modules/lens_correction"
const KERNEL := "lens_correction"
## The kernel with the crop, run when its factor is past one.
const CROPPED := "lens_correction_cropped"
## The widest bend a typed value may ask for, in percent. Past a third of the
## half diagonal the read r (1 - k r²) turns back on itself before the corner and
## the picture would fold over, so 30 keeps every radius reading one of its own.
const HARD_AMOUNT := 30.0
## The soft ends of the Amount slider's drag, in percent.
const SOFT_AMOUNT := 20.0
## The furthest a texel may read from its own place, in document pixels, and
## still be read through a halo: a halo is one chunk at most and the bilinear
## read takes the texel after the place it falls on. Past it the pass reads the
## whole node.
const HALO_MOVE := SaChunk.SIZE - 1
## The kernel file a pass that reads the whole node runs.
const WHOLE_SHADER := "sara-base-modules/lens_correction_whole"
const WHOLE_KERNEL := "lens_correction_whole"
## The switch's key, the slug of its label.
const CROP := &"crop_to_fill"
## On for a new filter. A record saved before the switch reads it as off.
const DEFAULTS := {"amount": 0.0, CROP: true}
## Newton steps for the crop's factor, more than its cubic ever needs.
const ROOT_STEPS := 30
## Halvings of the search for the radius a read came from.
const SEARCH_STEPS := 40
## How far past the read's own texel a change is taken to reach, in document
## pixels: the bilinear read takes the texel after the place it falls on.
const READ_SPREAD := 2


func title() -> String:
    return "Lens Correction"


## Listed under Distort in the Filter menu and the browser, beside the chromatic
## aberration.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Straighten the lines a wide lens bowed: above nought a barrel's bulge, below it a pincushion's pinch."


func build(ui: SaDialog) -> void:
    ui.title(title())
    var bend := {"hard_min": -HARD_AMOUNT, "hard_max": HARD_AMOUNT, "step": 0.1, "decimals": 1, "suffix": " %"}
    ui.slider("Amount", -SOFT_AMOUNT, SOFT_AMOUNT, DEFAULTS["amount"], bend)
    ui.checkbox("Crop to fill", DEFAULTS[CROP])
    ui.parameter_value(CROP, DEFAULTS[CROP], false)


func run(ctx: SaFilterContext) -> void:
    var canvas := ctx.canvas_size()
    var params := pass_params(parameters(), canvas)
    var bend := float(params["amount"])
    var scale := float(params["zoom"])
    var move := largest_move(bend, scale, canvas)
    if reads_whole(move):
        ctx.neighbourhood_pass(WHOLE_SHADER, WHOLE_KERNEL, params, SaFilterContext.WHOLE_NODE, {}, SaFilterContext.WRITES_CANVAS)
        var recorded := ctx.point as SaNeighbourhoodPass
        if recorded != null:
            recorded.carries = reading.bind(bend, scale)
        return
    var kernel := KERNEL if scale == 1.0 else CROPPED
    ctx.neighbourhood_pass(SHADER, kernel, params, reach(move))


## *values*, the record's own units, as the kernel's params over a document of
## *canvas* pixels: the amount as the fraction k, the crop's factor and the
## canvas. A record that does not name the switch is one saved before it, and
## reads it as off.
static func pass_params(values: Dictionary, canvas: Vector2i) -> Dictionary:
    var crop := SaTyped.flag(values.get(String(CROP), false))
    var bend := clampf(float(values.get("amount", DEFAULTS["amount"])), -HARD_AMOUNT, HARD_AMOUNT) / 100.0
    return {"amount": bend, "zoom": zoom(bend, canvas, crop), "canvas": Vector2(canvas)}


## Whether a pass whose furthest read moves *move* document pixels reads the
## whole node rather than a halo round each chunk.
static func reads_whole(move: float) -> bool:
    return move > float(HALO_MOVE)


## Half the diagonal of a document of *canvas* pixels, the length a radius is
## counted in, and never under a pixel.
static func half_diagonal(canvas: Vector2i) -> float:
    return maxf(Vector2(canvas).length() * 0.5, 1.0)


## How far the middle of a corner texel of *canvas* stands from the centre, in
## half diagonals: the furthest out a texel's own place is.
static func corner_texel(canvas: Vector2i) -> float:
    var middle := Vector2(canvas) * 0.5
    return (middle - Vector2(0.5, 0.5)).abs().length() / half_diagonal(canvas)


## The factor Crop to fill scales the corrected picture up by, under the
## fraction *bend* on *canvas*, and one when *crop* is off or nothing reads
## outside. The root of s²(s - 1) = -k c², c the corner texel's distance, by
## Newton's steps from 1 - k c², where the cubic is already above nought and
## every step falls towards the root without passing it.
static func zoom(bend: float, canvas: Vector2i, crop: bool) -> float:
    if not crop or bend >= 0.0:
        return 1.0
    var reach_out := corner_texel(canvas)
    var pull := -bend * reach_out * reach_out
    var s := 1.0 + pull
    for _step in ROOT_STEPS:
        var gap := s * s * (s - 1.0) - pull
        var slope := 3.0 * s * s - 2.0 * s
        if gap <= 0.0 or slope <= 0.0:
            break
        s -= gap / slope
    return maxf(s, 1.0)


## How far a texel at *r* half diagonals reads from its own place, in half
## diagonals, under the fraction *bend* and the crop's factor *scale*. Signed,
## outwards above nought.
static func move_at(r: float, bend: float, scale: float) -> float:
    var seen := r / scale
    return seen * (1.0 - bend * seen * seen) - r


## The furthest any texel of *canvas* reads from its own place under *bend* and
## *scale*, in document pixels. With no crop the move k r³ grows to the corner.
## With the crop it is nought at the middle and near nought at the corner, so
## its peak stands where its slope is nought, at r² = s²(s - 1) / (-3 k), and
## both are weighed.
static func largest_move(bend: float, scale: float, canvas: Vector2i) -> float:
    var most := absf(move_at(1.0, bend, scale))
    if bend < 0.0 and scale > 1.0:
        var peak := sqrt(scale * scale * (scale - 1.0) / (-3.0 * bend))
        if peak < 1.0:
            most = maxf(most, absf(move_at(peak, bend, scale)))
    return most * half_diagonal(canvas)


## How far a corner of *canvas* reads from its own place under the fraction
## *bend* with no crop, in document pixels. A corner sits at r one, so its move
## is the whole of k half diagonals.
static func corner_move(bend: float, canvas: Vector2i) -> float:
    return largest_move(bend, 1.0, canvas)


## The halo of a move of *move* pixels: a bilinear read takes the texel the
## place falls on and the one after it, so the floor and one more. A move of
## exactly [const HALO_MOVE] is a chunk, with no rounding of the float to push
## it over.
static func reach(move: float) -> int:
    return floori(move) + 1


## The rectangles of a canvas of *canvas* pixels whose texels read *area*, a
## changed rectangle in document pixels, under the fraction *bend* and the
## crop's factor *scale*, for [member SaNeighbourhoodPass.carries]. One
## rectangle, cut to the canvas by the caller.
##
## A texel's read moves it along its own radius, so the texel that reads a
## place stands at the place's offset from the centre times a factor that
## depends on the place's distance alone. Over the rectangle that distance runs
## between its nearest and its furthest point, the factor between what it is
## at those two and at the corner's radius, where the search caps it, and the
## offset between the rectangle's own sides. The products of the two ranges
## bound every texel that reads the rectangle, at three searches a call, as a
## stroke asks for one on every chunk it dirties. A change on the canvas's
## edge reaches every read that falls past it, since such a read takes the
## edge's texel, so a side on an edge is moved out by a canvas first.
static func reading(area: Rect2i, canvas: Vector2i, bend: float, scale: float) -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    if area.size.x <= 0 or area.size.y <= 0 or canvas.x <= 0 or canvas.y <= 0:
        return out
    var far := float(maxi(canvas.x, canvas.y))
    var read := Rect2(area.grow(READ_SPREAD))
    read = read.grow_individual(
        far if area.position.x <= 0 else 0.0,
        far if area.position.y <= 0 else 0.0,
        far if area.end.x >= canvas.x else 0.0,
        far if area.end.y >= canvas.y else 0.0
    )
    var centre := Vector2(canvas) * 0.5
    var half := half_diagonal(canvas)
    var low := read.position - centre
    var high := read.end - centre
    var nearest := Vector2(clampf(0.0, low.x, high.x), clampf(0.0, low.y, high.y)).length()
    var furthest := Vector2(maxf(absf(low.x), absf(high.x)), maxf(absf(low.y), absf(high.y))).length()
    var factors: Array[float] = [factor_at(nearest, half, bend, scale), factor_at(furthest, half, bend, scale)]
    if bend > 0.0:
        var cap := search_cap(bend, scale)
        var capped := cap * (1.0 - bend * cap * cap) * half
        if capped > nearest and capped < furthest:
            factors.append(factor_at(capped, half, bend, scale))
    var least: float = factors.min()
    var most: float = factors.max()
    var first := Vector2(minf(low.x * least, low.x * most), minf(low.y * least, low.y * most))
    var last := Vector2(maxf(high.x * least, high.x * most), maxf(high.y * least, high.y * most))
    var box := Rect2(centre + first, last - first).grow(READ_SPREAD)
    var corner := Vector2i(box.position.floor())
    out.append(Rect2i(corner, Vector2i(box.end.ceil()) - corner))
    return out


## What a place *distance* pixels from the centre is multiplied by to give the
## offset of the texel that reads it, a canvas's [param half] diagonal out
## being one. At the centre it is the crop's factor, the limit of the search.
static func factor_at(distance: float, half: float, bend: float, scale: float) -> float:
    if distance <= 0.0:
        return scale
    return read_by(Vector2(distance, 0.0), Vector2.ZERO, half, bend, scale).x / distance


## The furthest radius, in half diagonals, [method read_by] searches to: the
## canvas's corner above nought, where u (1 - k u²) stops rising first.
static func search_cap(bend: float, scale: float) -> float:
    return INF if bend <= 0.0 else minf(1.0 / scale, 1.0 / sqrt(3.0 * bend))


## The place, in document pixels, of the texel whose read falls at *place*,
## about *centre* on a canvas whose half diagonal is *half*, under the fraction
## *bend* and the crop's factor *scale*. A read seen u half diagonals out comes
## from u (1 - k u²), which rises with u up to the canvas's corner for every
## amount the slider takes, so the radius is found by halving. A place further
## out than any texel reads from is answered at the corner's radius.
static func read_by(place: Vector2, centre: Vector2, half: float, bend: float, scale: float) -> Vector2:
    var away := place - centre
    var out_by := away.length() / half
    if out_by <= 0.0:
        return centre
    var low := 0.0
    # Below nought u (1 - k u²) is at least u, so u is at most the place's own
    # distance. Above it the canvas's corner is the furthest a texel stands.
    var high := out_by if bend <= 0.0 else search_cap(bend, scale)
    for _step in SEARCH_STEPS:
        var middle := (low + high) * 0.5
        if middle * (1.0 - bend * middle * middle) < out_by:
            low = middle
        else:
            high = middle
    return centre + away * (high * scale / out_by)
