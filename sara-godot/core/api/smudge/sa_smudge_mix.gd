## The smudge stage's mixes taken in the brush's own blend mode, so a brush in
## a mixing blend smears blue into yellow as green rather than as grey.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The mode's composite is the mix.** A mode's composite of *over* at coverage
## *t* onto *under* at alpha one is that mode's mix of the two, and Normal's is
## the straight line the stage always drew. So each mix the stage takes is
## staged by `smudge_mix.gmacs` into [member under] and [member over], the
## mode's own composite kernel runs on them through
## [method SaCompositor.record_mix], and the same kernel writes the result back
## to the carry. The kernel a mode registered is the only thing that knows its
## mix, so a mixing module's reaches the smudge through its descriptor and its
## `lut` and never by name, and no dab kernel binds anything new.
##
## **Three mixes.** The found paint entering the carry's one colour at the pickup,
## the found paint entering each cell of a carried picture, and the carry
## meeting the brush's colour where the dab lays it, texel 0 and each cell of a
## lattice the carry holds. Each is three records, a stage, the composite and a
## stage, and the reservoir puts them between the pickup and the dab in the
## one list it sends.
##
## **A gradient map meets the carry cell by cell.** Its colour is the ramp's at
## each texel, so its brush hands a [Ramp] in place of one colour, and the
## meeting puts under each cell of the carry's lattice the ramp's colour where
## that cell sits under the dab. A stroke with no lattice, a dulling one, has no
## cells to sample the ramp on and meets in the straight line.
##
## **Normal records nothing.** [method wanted] answers false for Normal and for
## Erase, which carves alpha and mixes no colour, so a brush in either paints as
## it did and costs what it did. So does a stroke with no easel, whose colour
## space and compositor are not known.
##
## **Its own class, held by the reservoir** for the stroke and dropped with it,
## its two images with it (hard rule 4). The work is at most the carry's
## sixty-five rows of sixty-four texels, never the canvas (hard rule 2), and
## nothing is read back (hard rule 1).
class_name SaSmudgeMix
extends RefCounted

## The kernel that stages the mixes and writes them back.
const KERNEL: String = "smudge_mix"

## The bindings of a gradient map's tip and ramp on [constant KERNEL], after
## its four images.
const TIP_BINDING: int = 4
const RAMP_BINDING: int = 5

## The stages of [constant KERNEL], in the order a dab runs them.
enum Stage { CARRY_IN, CARRY_OUT, CELLS_OUT, MEET_IN, MEET_OUT }

## The composite's destination: what each mix starts from, at the carry's own
## coordinates, and once the composite has run, the mix.
var under: SaTexture = null

## The composite's source: the colour each mix takes in, the share it takes in
## alpha.
var over: SaTexture = null

## The blend mode the brush paints in, whose composite every mix runs.
var mode: StringName = &""

var _compute: SaCompute = null
var _compositor: SaCompositor = null
var _space: SaColorSpace = null
var _white: float = 1.0


## Whether a brush in *mode* on *easel* mixes its smudge through the mode's
## composite: any mode the easel's compositor knows but Normal and Erase.
static func wanted(easel: SaEasel, blend: StringName) -> bool:
    if easel == null or easel.compositor == null or easel.document == null:
        return false
    if blend == SaLayer.BLEND_MODE.NORMAL or blend == SaLayer.BLEND_MODE.ERASE or blend.is_empty():
        return false
    return easel.compositor.has_blend_mode(blend)


## The mixes of a stroke in *blend* on *easel*, which [method wanted] has said
## yes to. The document's colour space and blend white go to every composite,
## because the carry holds the document's own values.
func _init(easel: SaEasel, blend: StringName) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    mode = blend
    _compositor = easel.compositor
    _space = easel.document.color_space
    _white = easel.document.blend_reference_white
    under = SaTexture.new(SaSmudgeField.CARRY)
    over = SaTexture.new(SaSmudgeField.CARRY)
    under.clear(Color(0.0, 0.0, 0.0, 0.0))
    over.clear(Color(0.0, 0.0, 0.0, 0.0))
    _compute = SaCompute.new(KERNEL)


## Compiles the kernel at the carry's depth, for the reason
## [method SaSmudgeReservoir.warm] gives. A mode's composite at that depth is
## the one every float document's own composite already built.
static func warm() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new(KERNEL).use_storage_format(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)


## Binds *carry*, the reservoir's, and *held*, a carried picture's memory or
## null, for the records that follow.
func bind(carry: SaTexture, held: SaTexture) -> void:
    if _compute == null:
        return
    _compute.set_texture(0, carry.rid)
    _compute.set_texture(1, under.rid)
    _compute.set_texture(2, over.rid)
    _compute.set_texture(3, (held if held != null else SaSmudgeReservoir.stand_in()).rid)
    _sample(null)


## The found paint entering the carry's one colour, after the pickup wrote what
## it found and where it started.
func record_carry() -> Array[SaCompute.Recorded]:
    return _three(Stage.CARRY_IN, Stage.CARRY_OUT, Rect2i(0, 0, 1, 1), Vector2i.ZERO, Color())


## The found paint entering each of *count* cells of a carried picture, after
## `smudge_field.gmacs` staged them.
func record_cells(count: Vector2i) -> Array[SaCompute.Recorded]:
    var out: Array[SaCompute.Recorded] = []
    var composite := _composite(Rect2i(Vector2i(0, 1), count))
    var settle := _stage(Stage.CELLS_OUT, count, Color(), _groups(Vector2i(count.x, count.y + 1)))
    if composite == null or settle == null:
        return out
    out.append(composite)
    out.append(settle)
    return out


## The carry meeting *brush*, the brush's colour in the document's values, in
## texel 0 and in each of *count* cells of a lattice the carry holds, nought
## for none.
## *ramp*, when given, is a gradient map's, met cell by cell, and *brush* is
## then the colour the dab lays where its tip has no picture.
func record_meet(brush: Color, count: Vector2i, ramp: Ramp = null) -> Array[SaCompute.Recorded]:
    var area := Vector2i(maxi(count.x, 1), count.y + 1)
    _sample(ramp)
    var out := _three(Stage.MEET_IN, Stage.MEET_OUT, Rect2i(Vector2i.ZERO, area), count, brush, ramp)
    _sample(null)
    return out


## Binds *ramp*'s tip and ramp for the records that follow, or the stand-ins,
## which a uniform set covering every binding needs on every other record.
func _sample(ramp: Ramp) -> void:
    if _compute == null:
        return
    var none := SaBrushTipMask.stand_in().rid
    _compute.set_sampled_texture(TIP_BINDING, ramp.tip if ramp != null else none)
    _compute.set_sampled_texture(RAMP_BINDING, ramp.ramp if ramp != null else none)


## A stage, the composite over *region* and a stage, or nothing when any of the
## three could not be recorded, because a stage written back with no composite
## between would lay the colour the mix started from.
func _three(
    first: Stage, last: Stage, region: Rect2i, count: Vector2i, brush: Color, ramp: Ramp = null
) -> Array[SaCompute.Recorded]:
    var out: Array[SaCompute.Recorded] = []
    var groups := _groups(region.end)
    var staged := _stage(first, count, brush, groups, ramp)
    var composite := _composite(region)
    var settle := _stage(last, count, brush, groups, ramp)
    if staged == null or composite == null or settle == null:
        return out
    out.append_array([staged, composite, settle])
    return out


func _stage(stage: Stage, count: Vector2i, brush: Color, groups: Vector2i, ramp: Ramp = null) -> SaCompute.Recorded:
    if _compute == null:
        return null
    var params := PackedFloat32Array([brush.r, brush.g, brush.b, 1.0, float(count.x), float(count.y), float(stage), 0.0])
    params.resize(16)
    if ramp != null:
        params[7] = 1.0
        params[8] = cos(ramp.radians)
        params[9] = sin(ramp.radians)
        params[10] = ramp.half_extent.x
        params[11] = ramp.half_extent.y
        params[12] = float(ramp.mirror)
        params[13] = float(ramp.generator)
    _compute.set_push_constant_float_array(params)
    return _compute.record(KERNEL, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, groups.x, groups.y, 1, true)


func _composite(region: Rect2i) -> SaCompute.Recorded:
    if _compositor == null or under == null:
        return null
    return _compositor.record_mix(under, over, mode, _space, _white, region)


## Groups to cover texels from the origin to *size*.
static func _groups(size: Vector2i) -> Vector2i:
    return Vector2i(SaCompute.groups_for(size.x), SaCompute.groups_for(size.y))


## A gradient map's colour for the meeting: the tip's picture whose green is
## the lightness the ramp is read at, the ramp, the dab's place on the tip,
## each as the dab's own block holds it, so a cell reads the ramp where the dab
## would at the same offset, and the dab's own colour in the document's
## values, which it lays where there is no picture or no ramp. The brush that paints the map makes one a dab,
## and the two textures are the ones its dab binds, held by its tip mask.
class Ramp:
    extends RefCounted

    var tip: RID
    var ramp: RID
    var radians: float
    var half_extent: Vector2
    var mirror: int
    var generator: int
    var colour: Color

    func _init(
        picture: RID, colours: RID, angle: float, extent: Vector2, mirror_bits: int, tip_generator: int, own: Color
    ) -> void:
        tip = picture
        ramp = colours
        radians = angle
        half_extent = extent
        mirror = mirror_bits
        generator = tip_generator
        colour = Color(own.r, own.g, own.b, 1.0)
