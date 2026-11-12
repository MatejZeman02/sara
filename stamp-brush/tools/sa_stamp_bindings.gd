## The stamp kernel's bindings past the tip's own two: the paper, the masking
## brush's block, the smudge stage's carry and the gradient-map tip's ramp.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaBrushTipMask` in the door binds what any kernel that draws a tip reads, the
## soft generator's table and the picture. `dab.gmacs` declares six bindings
## more, and a uniform set has to cover every binding a kernel declares, so
## whoever dispatches it binds all of them. [method bind] is that one call on
## the stamp's side, and it is what `SaBrushTipMask.bind` was until the tip
## moved into the door and left what only the stamp reads here.
##
## **It is the masking brush's block and the ramp's holder as well**, because
## those are the two things it holds. It hangs on the tip's mask as the mask's
## companion, so it lives exactly as long as the tip does and carries over a
## change of picture the way it did when it was a field on the mask. [method of]
## answers it.
class_name SaStampBindings
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Where `dab.gmacs` declares the two things it binds past the tip's own pair,
## the paper and the masking brush. Named here rather than written as numbers
## at the call site, because the kernel and this have to agree, and named
## *here* because this is what binds them. `StateBrush` re-exports the paper's
## under the name the suites use, and the masking brush's is reached through
## this class alone. The tip's two, the softness table at 2 and the picture at
## 3, are `SaBrushTipMask`'s in the door.
const PATTERN_BINDING: int = 4
const MASKING_BINDING: int = 5
## The paint's height the eraser lowers, `StateBrush`'s
## `HEIGHT_BINDING`.
const HEIGHT_BINDING: int = 7
## The preset's ramp a gradient-map tip paints through, after the smudge
## stage's exchange at 8, which is why `SaWalkBatch`'s records moved to 10.
const RAMP_BINDING: int = 9

## Where each of the masking brush's numbers sits in the buffer bound at
## [constant MASKING_BINDING], and where its softness table starts.
## `shaders/dab_texel.gmacs` declares the same names against the same numbers,
## because the two ends of a storage buffer have to agree and a bare index at
## either end is the one thing a reader cannot check.
const MASK_ACTIVE: int = 0
const MASK_STRENGTH: int = 1
const MASK_HALF_X: int = 2
const MASK_HALF_Y: int = 3
const MASK_COS: int = 4
const MASK_SIN: int = 5
const MASK_FADE_X: int = 6
const MASK_FADE_Y: int = 7
const MASK_SPIKES: int = 8
const MASK_GENERATOR: int = 9
const MASK_SHAPE: int = 10
const MASK_ANTIALIAS: int = 11
const MASK_MIRROR: int = 12
## How far the painted tip's own lightness moves the dab's colour.
##
## It rides in the masking brush's buffer rather than in the push constant
## because the block has no room left: `dab.gmacs`'s params are at their 128
## bytes. A buffer declares its header length itself, so a slot here costs
## nothing structurally: this is the second number the buffer carries for
## something that is not the mask, and the file's own sentence about the block
## being written whole either way is why it is safe to put it here rather than
## in one of its own.
const MASK_TIP_LIGHTNESS: int = 13
## Which of the two ways the kernel moves the colour its row asks for, because
## what a lightness shift means depends on what the document stores.
##
## **The kernel cannot ask, so the CPU tells it.** A document whose chunks hold
## Oklab coordinates holds a lightness already, and the shift is an add to the
## first number. One that holds encoded RGB needs the document's own transfer
## curve under an Oklab round trip, which is the four numbers beside this one.
## Neither can be worked out from the dab's own push constant, whose colour slot
## says what the values are and not what curve put them there.
const MASK_TIP_LIGHTNESS_MODE: int = 14
## The document's transfer curve, as the four numbers `sa_transfer_decode` and
## `sa_transfer_encode` take. Read only in RGB mode.
const MASK_TRANSFER_SLOPE: int = 15
const MASK_TRANSFER_THRESHOLD: int = 16
const MASK_TRANSFER_GAIN: int = 17
const MASK_TRANSFER_EXPONENT: int = 18
## How the mask's coverage meets the dab's, `SaMaskingBrush.Op` as a float.
## Nought is multiply, which is what the slot reads for a
## block that predates the field.
const MASK_OP: int = 19
## Where the mask's own scatter puts its centre, in document pixels from the
## dab's. Behind the op rather than beside the mask's own
## numbers, so no slot any caller already reads moves: the buffer's header is
## as long as it says it is, and the softness table moves with it.
const MASK_OFFSET_X: int = 20
const MASK_OFFSET_Y: int = 21
## The document's two gamut matrices, its linear RGB into linear sRGB and back,
## which the RGB mode's Oklab round trip goes through so that a wide gamut
## document's shift lands on the number dialled. Nine floats each, column by
## column, the first [constant GAMUT_FLOATS] of
## `SaColorSpacePushConstant.to_push_constant`, so the kernel reads them the
## way every composite kernel reads that block.
const MASK_TO_LINEAR_SRGB: int = 22
const MASK_FROM_LINEAR_SRGB: int = 31
const GAMUT_FLOATS: int = 18
## The stroke's seed, folded to 24 bits so a float holds it exactly, which the
## kernel's rounding of a store into a half canvas draws from. Behind the
## matrices, so no slot ahead of it shifts.
const MASK_STROKE_SEED: int = 40
const MASK_HEADER: int = 41

## The two modes `MASK_TIP_LIGHTNESS_MODE` carries, named for the reason every
## other number in this block is: `dab_texel.gmacs` declares the same two.
##
## **A mode rather than a branch on the document, because the kernel has no
## document.** A dab dispatch reads a push constant and three bindings, and the
## composite's colour-space tail is not one of them. What the chunks hold is a
## question only the CPU can answer, so it answers it here, once per dab, in the
## same buffer the rest of the row travels in.
const LIGHTNESS_RGB: float = 0.0
const LIGHTNESS_OKLAB: float = 1.0

## The strength a mask arrives at until the Masking Brush page gives it a row:
## the whole mask, which is what switching one on means.
const FULL_STRENGTH: float = 1.0

## The masking brush's numbers and its own falloff table, as one buffer.
##
## **Held and updated in place rather than rebuilt per dab.** Its length never
## moves, the header being fixed and the table being
## [constant SaBrushTip.SOFTNESS_SAMPLES] floats, and every number in it does
## move: the mask's half-extents follow the dab's diameter, so a pressure ramp
## rewrites them on every dab of a stroke. A fresh `SaCompute.Buffer` per dab
## would be an allocation and a new uniform set per dab for a payload of a few
## hundred bytes.
var masking_buffer: SaCompute.Buffer = null
var masking_values: PackedFloat32Array = PackedFloat32Array()

## The gamut [method gamut_for] built its matrices for last, and the matrices.
static var _gamut_primaries: PackedVector2Array = PackedVector2Array()
static var _gamut_white: Vector2 = Vector2.ZERO
static var _gamut: PackedFloat32Array = PackedFloat32Array()

## The tip's mode the last press settled and the ramp it paints through, which
## every dispatch of the stroke reads and none of them uploads.
var ramp: Ramp = Ramp.new()


## The preset's ramp on the card, as the document's own values, and the tip's
## mode it was settled under.
##
## **Settled before a stroke opens, uploaded only when it moved.** The brush
## calls [method settle] at the press, ahead of `begin_stroke`, and the texels
## go to the card only when the stops, the painter's pair an empty gradient
## follows, or the document's space differ from what they were built from. Every
## dispatch inside the stroke binds what is held, so a stroke uploads nothing,
## and a mode or a ramp changed under a stroke is the next stroke's.
##
## **The document's encoding is made here and not in the kernel**, unlike
## Gradient Map, whose kernel converts each texel it maps: the dab's push
## constant has no room for a space's matrix and curve, and once per change on
## the CPU is cheaper than once per texel per dab. Oklab to linear sRGB, the
## space's gamut and then its curve, or the Lab triple as it is for a document
## that stores Oklab, and nothing is clamped on the way.
##
## **Never settled is the tip's lightness row applying and no ramp**, which is
## every suite and every caller that binds a dab without a press.
class Ramp:
    extends RefCounted

    ## `SaStampBrushSettings.TipMode` as the last press read it, or -1 before
    ## any press.
    var mode: int = -1
    ## The texels, made on the first gradient-map press and kept after, so the
    ## mode going back and forth costs no allocation.
    var texture: SaTexture = null
    ## What [member texture] was built from: the stops and the space.
    var _key: Array = []

    ## Reads *settings*' mode, and in gradient map mode its ramp in *space*'s
    ## encoding, and uploads the ramp when it differs from what is held. Answers
    ## whether it uploaded, which a suite counts.
    func settle(settings: Resource, space: SaColorSpace) -> bool:
        mode = int(settings.get("tip_mode")) if settings != null and "tip_mode" in settings else -1
        if mode != SaStampBrushSettings.TipMode.GRADIENT_MAP or GlobalShaderCompiler.get_rd() == null:
            return false
        var source: SaColorRamp = settings.gradient_ramp()
        var key: Array = [source.to_array(), null]
        if space != null:
            key[1] = [int(space.coordinates), space.from_linear_srgb_matrix(), space.transfer.to_params()]
        if texture != null and texture.rid.is_valid() and key == _key:
            return false
        if texture == null or not texture.rid.is_valid():
            texture = SaTexture.new(Vector2i(SaColorRamp.TEXELS, 1))
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels(source, space).to_byte_array())
        _key = key
        return true

    ## Whether the tip's lightness row moves the dab's colour: in lightness map
    ## mode, and before any press, where the row is all there was.
    func lightness_applies() -> bool:
        return mode == -1 or mode == SaStampBrushSettings.TipMode.LIGHTNESS_MAP

    ## The texture [constant RAMP_BINDING] takes, the ramp in gradient map mode
    ## and the one texel stand-in that says off in every other.
    func rid() -> RID:
        if mode == SaStampBrushSettings.TipMode.GRADIENT_MAP and texture != null and texture.rid.is_valid():
            return texture.rid
        return SaBrushTipMask.stand_in().rid

    ## *source* as [constant SaColorRamp.TEXELS] RGBA floats in *space*'s own
    ## values, each at its texel's centre. Null is sRGB, the skeleton's default.
    static func texels(source: SaColorRamp, space: SaColorSpace) -> PackedFloat32Array:
        var data := source.to_oklab_texels(SaColorRamp.TEXELS, space)
        if space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB:
            return data
        var transfer: SaTransferFunction = space.transfer if space != null else SaTransferFunction.srgb()
        # Once for the whole ramp, since a gamut's matrix is a solve and the
        # ramp is a thousand texels.
        var gamut: Basis = space.from_linear_srgb_matrix() if space != null else Basis.IDENTITY
        for at in range(0, data.size(), 4):
            var linear: Vector3 = gamut * SaOklab.to_linear_srgb(Vector3(data[at], data[at + 1], data[at + 2]))
            data[at] = transfer.encode(linear.x)
            data[at + 1] = transfer.encode(linear.y)
            data[at + 2] = transfer.encode(linear.z)
        return data


## The block *mask* carries, made and hung on it the first time it is asked
## for, so a suite that loads a mask by hand reaches the same buffer the brush
## binds and holds it as long as it holds the mask.
static func of(mask: SaBrushTipMask) -> SaStampBindings:
    var block := mask.companion as SaStampBindings
    if block == null:
        block = SaStampBindings.new()
        mask.companion = block
    return block


## The masking brush's buffer, rebuilt in place when any of its numbers has
## moved, and answered whether it moved or not.
##
## *masking* is `SaStampBrushSettings.masking`, and null or a block that is off
## is a header of nought at [constant MASK_ACTIVE], which is what the kernel
## answers on before it reads anything else. *dab_diameter* is the painted tip's
## own diameter in pixels, because the mask's size is a multiple of it: that is
## `SaMaskingBrush`'s one decision and its header says why.
##
## *info* is the stroke's own sample, read by the mask's size and strength
## options so the two slots below follow the sensors. Null is every caller that
## predates the options, and the options then answer their neutral values, which
## is the size the row set and the whole mask.
##
## *tip_lightness* is the painted tip's own lightness row, which is not the
## mask's and has no other way to the kernel. Nought is every caller that
## predates the row and every tip whose own picture carries no colour, and
## the kernel's shift is exactly nought there.
##
## *lightness_mode*, *transfer* and *gamut* say what the document stores,
## because the shift's meaning depends on it and the kernel cannot ask. The
## defaults are what a caller that predates the row painted under: encoded RGB
## through the sRGB curve in sRGB's primaries, which is `SaColorSpace.srgb()`
## and the skeleton's own default. *gamut* is [method gamut_for]'s answer.
##
## **The whole block is written even when the mask is off**, rather than only
## the flag. A buffer whose tail is last stroke's numbers is a buffer whose
## contents depend on what the painter did before, which is the kind of state
## that makes a bug reproduce for one person only.
func masking_for(
    masking: Resource,
    dab_diameter: float,
    info: SaStrokeInfo = null,
    tip_lightness: float = 0.0,
    lightness_mode: float = LIGHTNESS_RGB,
    transfer: PackedFloat32Array = PackedFloat32Array(),
    gamut: PackedFloat32Array = PackedFloat32Array()
) -> SaCompute.Buffer:
    var active: bool = masking != null and masking.has_method("active") and masking.active()
    var matrices := gamut if gamut.size() == GAMUT_FLOATS else gamut_for(null)
    # A block that is off and was off with the same numbers last dab is the
    # buffer already on the card, answered before the whole block is built and
    # compared again.
    var stroke_seed := stroke_seed_for(info)
    if not active and _holds_off(tip_lightness, lightness_mode, transfer, matrices, stroke_seed):
        return masking_buffer
    var values := PackedFloat32Array()
    values.resize(MASK_HEADER + SaBrushTipScript.SOFTNESS_SAMPLES)
    values[MASK_ACTIVE] = 1.0 if active else 0.0
    values[MASK_STROKE_SEED] = stroke_seed
    # The painted tip's lightness row, which is not the mask's and rides here
    # because the kernel's push constant is full. Written whether or not
    # there is a mask, for the reason the whole block is.
    values[MASK_TIP_LIGHTNESS] = clampf(tip_lightness, 0.0, 1.0)
    _write_lightness_space(values, lightness_mode, transfer, matrices)
    if active:
        # The mask's own two options read the sensors here, so a pressure ramp
        # moves the half-extents and the strength from dab to dab. A block
        # without the methods is a block that predates them, and answers the
        # neutral values.
        var tip: Resource = masking.shaped_tip(dab_diameter, info)
        var half: Vector2 = tip.half_extent()
        var fade: Vector2 = tip.effective_fade()
        values[MASK_STRENGTH] = FULL_STRENGTH
        if masking.has_method("evaluated_strength"):
            values[MASK_STRENGTH] = masking.evaluated_strength(info)
        if "op" in masking:
            values[MASK_OP] = float(masking.op)
        values[MASK_HALF_X] = half.x
        values[MASK_HALF_Y] = half.y
        # The mask's own dab, read after its size and strength so the draws
        # those two made from the per-dab stream come first, so an option read
        # after them moves no draw of theirs.
        var own: SaDabParams = masking.dab_for(dab_diameter, info) if masking.has_method("dab_for") else SaDabParams.new()
        # The second tip's own angle and its own rotation option, in document
        # space. It is deliberately not added to the dab's rotation, and
        # `sa_mask_coverage` says why. The mirror bits are its tip's turned over
        # by its own option, and one mirrored axis runs the angle the other way,
        # which is the painted tip's arithmetic in `state_brush.gd`.
        var mirror_bits: int = SaDabGeometry.mirror_bits(tip.mirror_bits(), own.mirror)
        var radians: float = tip.angle + own.rotation
        if SaDabGeometry.mirror_flips_handedness(mirror_bits):
            radians = -radians
        values[MASK_COS] = cos(radians)
        values[MASK_SIN] = sin(radians)
        values[MASK_OFFSET_X] = own.scatter.x
        values[MASK_OFFSET_Y] = own.scatter.y
        values[MASK_FADE_X] = fade.x
        values[MASK_FADE_Y] = fade.y
        values[MASK_SPIKES] = float(tip.spikes)
        # An image second tip is a seventh binding and a file load per dab, so
        # the kernel reads it as the default ramp and a mask carrying a picture
        # masks with a plain ellipse of its own size. The generator sent is
        # therefore the stored one rather than `effective_generator()`, which
        # would answer IMAGE for a tip that has a picture and leave the two ends
        # disagreeing about what was drawn.
        values[MASK_GENERATOR] = float(tip.generator)
        values[MASK_SHAPE] = float(tip.shape)
        values[MASK_ANTIALIAS] = 1.0 if tip.antialias_edges else 0.0
        values[MASK_MIRROR] = float(mirror_bits)
        var table: PackedFloat32Array = tip.softness_table()
        for i in mini(table.size(), SaBrushTipScript.SOFTNESS_SAMPLES):
            values[MASK_HEADER + i] = table[i]
    if masking_buffer == null:
        masking_values = values
        masking_buffer = SaCompute.Buffer.new(values.to_byte_array())
    elif values != masking_values:
        masking_values = values
        masking_buffer.update(values.to_byte_array())
    return masking_buffer


## The stroke seed *info* was pressed with, folded to the 24 bits a float holds
## exactly, as the number [constant MASK_STROKE_SEED] carries. Nought for no
## stroke, which a suite dispatching a dab by hand sends.
static func stroke_seed_for(info: SaStrokeInfo) -> float:
    return 0.0 if info == null else float(SaStrokeInfo.folded_seed(info.stroke_seed))


## Whether [member masking_buffer] already holds the block of a mask that is
## off, painted under *tip_lightness*, *lightness_mode*, *transfer*, *gamut*
## and *stroke_seed*. The matrices are compared too, because a Display P3 document and
## an sRGB one share a curve and differ in nothing else the block carries.
func _holds_off(
    tip_lightness: float, lightness_mode: float, transfer: PackedFloat32Array, gamut: PackedFloat32Array, stroke_seed: float
) -> bool:
    if masking_buffer == null or masking_values.size() <= MASK_HEADER or transfer.size() != SaTransferFunction.PARAM_FLOATS:
        return false
    if masking_values[MASK_ACTIVE] != 0.0 or masking_values[MASK_STROKE_SEED] != stroke_seed:
        return false
    # Through a float array of their own, so each number is rounded to the
    # 32 bits the held block stores it at before the two are compared.
    var wanted := PackedFloat32Array([clampf(tip_lightness, 0.0, 1.0), lightness_mode])
    wanted.append_array(transfer)
    if wanted != masking_values.slice(MASK_TIP_LIGHTNESS, MASK_TRANSFER_EXPONENT + 1):
        return false
    return gamut == masking_values.slice(MASK_TO_LINEAR_SRGB, MASK_TO_LINEAR_SRGB + GAMUT_FLOATS)


## Which of the two ways *space*'s chunks hold a colour, as the number
## `dab_texel.gmacs` branches on.
##
## **Null is the sRGB answer**, which is the skeleton's own default and what
## every caller with no space to hand paints under: a tool with no document, a
## suite that dispatches a dab by hand, and the document itself until a file
## names a space.
static func lightness_mode_for(space: SaColorSpace) -> float:
    if space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return LIGHTNESS_OKLAB
    return LIGHTNESS_RGB


## The four numbers `sa_transfer_decode` and `sa_transfer_encode` take for
## *space*'s curve, which is what an RGB-storing document's values were encoded
## through.
##
## sRGB's when there is no space, for the reason [method lightness_mode_for]
## says. The curve is written even in OKLAB mode, where the kernel does not read
## it, because the block is written whole either way and a tail that held last
## document's curve would be exactly the state this file's own comment about
## writing the whole block exists to avoid.
static func transfer_for(space: SaColorSpace) -> PackedFloat32Array:
    if space == null:
        return SaTransferFunction.srgb().to_params()
    return space.transfer.to_params()


## *space*'s two gamut matrices, into linear sRGB and back, as the
## [constant GAMUT_FLOATS] floats the kernel reads from
## [constant MASK_TO_LINEAR_SRGB].
##
## **The composite kernels' own packing**, the head of
## `SaColorSpacePushConstant.to_push_constant`, rather than a second writer of
## the same two matrices. sRGB's when there is no space, for the reason
## [method lightness_mode_for] says, and any sRGB-gamut space answers exactly
## the identity twice, since `to_linear_srgb_matrix` tests the gamut before it
## builds one, which is what keeps such a document's texels to the bit. Written
## in OKLAB mode too, where the kernel does not read them, for the reason
## [method transfer_for] writes its curve there.
##
## **Kept for the last gamut asked about**, because the brush asks once a dab
## and building the pair on a wide-gamut document costs over a hundred times
## what the curve does. Keyed on the primaries and the white rather than on the
## space, since those are what the matrices are made of and a space is a value
## whose fields can be set.
static func gamut_for(space: SaColorSpace) -> PackedFloat32Array:
    var document := space if space != null else SaColorSpace.srgb()
    if document.primaries != _gamut_primaries or document.white != _gamut_white or _gamut.size() != GAMUT_FLOATS:
        _gamut = SaColorSpacePushConstant.to_push_constant(document).slice(0, GAMUT_FLOATS)
        _gamut_primaries = document.primaries.duplicate()
        _gamut_white = document.white
    return _gamut


## Writes the slots that say what the document stores, which is the half of
## the lightness shift the CPU has to answer.
static func _write_lightness_space(
    values: PackedFloat32Array, lightness_mode: float, transfer: PackedFloat32Array, gamut: PackedFloat32Array
) -> void:
    values[MASK_TIP_LIGHTNESS_MODE] = lightness_mode
    var params := transfer if transfer.size() == SaTransferFunction.PARAM_FLOATS else SaTransferFunction.srgb().to_params()
    values[MASK_TRANSFER_SLOPE] = params[0]
    values[MASK_TRANSFER_THRESHOLD] = params[1]
    values[MASK_TRANSFER_GAIN] = params[2]
    values[MASK_TRANSFER_EXPONENT] = params[3]
    for i in GAMUT_FLOATS:
        values[MASK_TO_LINEAR_SRGB + i] = gamut[i]


## How far the painted tip's lightness moves the dab's colour: its row in
## lightness map mode and before any press, and nought in the other two, where
## the picture is a mask or picks from the ramp instead.
static func _lightness(mask: SaBrushTipMask, tip: Resource) -> float:
    return mask.lightness_strength_for(tip) if of(mask).ramp.lightness_applies() else 0.0


## Binds everything the stamp's kernel samples and answers the mask to hold on
## to.
##
## The tip's own two through the door first, *held* being what the tool bound
## last time, then the stamp's three. The stand-in goes on the paper's binding,
## which a uniform set covering every declared binding makes necessary rather
## than tidy, and the brush binds its paper over it when a stroke has one.
## *space* is `SaDocument.color_space`, the one thing about the document the dab
## kernel cannot read for itself and the thing the lightness shift's meaning
## turns on. Null is every caller with no document, which binds the sRGB answer
## [method lightness_mode_for] describes.
static func bind(
    compute: SaCompute,
    tip: Resource,
    held: SaBrushTipMask,
    masking: Resource = null,
    info: SaStrokeInfo = null,
    space: SaColorSpace = null
) -> SaBrushTipMask:
    var mask := SaBrushTipMask.bind(compute, tip, held, info)
    compute.set_sampled_texture(PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    # Bound on every dispatch whether or not there is a mask, because a uniform
    # set has to cover every binding the kernel declares. *masking* being null is
    # a block that is off, which is what every caller that predates the mask
    # sends. The stroke's own sample goes with it, so the mask's size and
    # strength options read the same sensors the painted tip did.
    compute.set_buffer(
        MASKING_BINDING,
        (
            of(mask)
            . masking_for(
                masking,
                tip.diameter,
                info,
                _lightness(mask, tip),
                lightness_mode_for(space),
                transfer_for(space),
                gamut_for(space)
            )
            . rid
        )
    )
    # The ramp the press settled, or the stand-in in every mode but gradient
    # map, for the reason the block above is bound whether or not there is one.
    compute.set_sampled_texture(RAMP_BINDING, of(mask).ramp.rid())
    # The smudge stage's carry, as its stand-in of nothing, for the same reason
    # as the block above. The brush binds its own carry over this when a stroke
    # has one, and every other caller of this door, which is every suite that
    # paints a real dab, gets a set that builds without knowing the stage exists.
    SaSmudgeReservoir.bind(compute, null)
    # The paint's height as its stand-in, which the kernel never writes, for
    # the same reason again. The brush binds a layer's own
    # height over it where a stroke erases straight into one.
    compute.set_texture(HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    return mask
