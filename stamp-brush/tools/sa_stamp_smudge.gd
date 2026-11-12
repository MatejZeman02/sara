## The smudge stage of one stamp stroke: the carry its smudge dabs pick paint
## up into and lay from, made by the first dab that asks for it.
##
## The carry starts empty with each stroke, because its snapshot is taken under
## the box of the dab that first asks, and is dropped at the lift. It reads no
## tool: the stamp brush hands it the dab, where the dab was placed and what it
## lands on, and [SaSmudgeReservoir] does the work on the card.
class_name SaStampSmudge
extends RefCounted

## The carry of the stroke under way, or null while no dab has asked for one.
var carry: SaSmudgeReservoir = null


## Sends the smudge dabs this frame or this tick queued, as one list, and
## commits the dirty rectangles of every dab sent since the last commit.
func submit() -> void:
    if carry != null:
        carry.submit()


## Lets the stroke's carry go, at the press and at the lift, after committing
## what it still held, so no dab of the stroke goes uncomposited.
func drop() -> void:
    submit()
    carry = null


## The pickup of *dab*, placed at *placed* with *settings*, before the dab reads
## what it carried. The first one makes the carry over the easel of *surface*,
## asked through the door rather than named, and the layer of
## *doc* the stroke paints on, the layer as well as the easel because the brush
## may have asked for the pickup to read that rather than the composite. The
## carry holds the field of colours under the tip rather than one mean, because
## a stamp brush smears pictures and the mean of a wide tip is grey. *moves_height*
## says whether the stroke drags the layer's height with its colour. *mask* is
## the tip mask the dab binds, whose picture and ramp a gradient map's meeting
## reads.
func pick_up(
    dab: SaDabParams,
    placed: SaStampPlacement,
    settings: Resource,
    surface: SaSurface,
    doc: SaDocument,
    moves_height: bool,
    mask: SaBrushTipMask = null
) -> void:
    if carry == null:
        var heights := SaSmudgeReservoir.moving(doc, moves_height)
        var easel_of := surface.easel if surface != null else null
        carry = SaSmudgeReservoir.new(
            easel_of, doc.active_layer, settings.smudge_sample_merged, placed.region, heights, true, settings.blend_mode
        )
    # The reach is the dab's own radius times the brush's own multiple, so
    # a pickup wider than the dab reads the paint past it, and the mode is
    # the brush's own rate, dragging or averaging.
    carry.pick_up(
        placed.region,
        placed.position,
        placed.half_extent.x * settings.smudge_radius,
        dab.smudge_pickup,
        dab.smudge_length,
        dab.smudge_color_rate,
        settings.smudge_mode,
        _own_colour(dab, settings),
        _ramp(dab, placed, settings, mask)
    )


## The colour the carry meets in the brush's own blend mode: the dab's, already
## in the document's values, or nought in alpha for a gradient map, whose colour
## is the ramp's at each texel and is met through [method _ramp] instead.
static func _own_colour(dab: SaDabParams, settings: Resource) -> Color:
    if _maps(settings):
        return Color(0.0, 0.0, 0.0, 0.0)
    return Color(dab.color.r, dab.color.g, dab.color.b, 1.0)


## A gradient map's ramp, for the carry to meet cell by cell: the picture and
## the ramp *mask* binds on the dab, and the dab's angle, radii and mirror as
## *placed* gives them to its block. Null for any other tip mode, and with no
## mask.
static func _ramp(dab: SaDabParams, placed: SaStampPlacement, settings: Resource, mask: SaBrushTipMask) -> SaSmudgeMix.Ramp:
    if mask == null or not _maps(settings):
        return null
    var tip: Resource = settings.get("tip")
    var generator: int = tip.effective_generator() if tip != null else SaDabGeometry.Generator.DEFAULT
    return SaSmudgeMix.Ramp.new(
        mask.sampler_rid(),
        SaStampBindings.of(mask).ramp.rid(),
        placed.radians,
        placed.half_extent,
        placed.mirror_bits,
        generator,
        dab.color
    )


static func _maps(settings: Resource) -> bool:
    var mode := int(settings.get("tip_mode")) if "tip_mode" in settings else -1
    return mode == SaStampBrushSettings.TipMode.GRADIENT_MAP


## Binds the carry onto *compute* for a smudge dab, or the stand-in for any
## other, and answers the carry whose heights the dab's targets bind, which is
## the carry of a smudge dab that is not erasing and null otherwise.
func bind(compute: SaCompute, dab: SaDabParams, erasing: bool, paint: SaPaintContext) -> SaSmudgeReservoir:
    SaSmudgeReservoir.bind(compute, carry if dab.smudge else null)
    var smudged: SaSmudgeReservoir = carry if dab.smudge and not erasing else null
    if smudged != null:
        smudged.reach_heights(paint.targets)
    return smudged


## Lays a smudge dab through *dispatcher*: it joins the queue the carry sends as
## one list at the end of the event, after its pickup, unless *at_once*, which a
## stroke painting straight into the layer its snapshot copies asks for, because
## the next dab's growth has to copy what this one painted. Such a dab's dirty
## rectangles wait for [method submit], once a frame, because committing them a
## dab at a time cost a deep painting a millisecond a dab.
func lay(paint: SaPaintContext, compute: SaCompute, dispatcher: Callable, at_once: bool) -> void:
    carry.lay(paint, compute, "dab", dispatcher)
    if at_once:
        carry.submit(false)
