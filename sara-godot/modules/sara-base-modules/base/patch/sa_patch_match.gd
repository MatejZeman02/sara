## The patch tool's Texture method: the hole drawn again out of patches of the
## picture around it, by PatchMatch on the GPU.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The two papers it follows, named here because the patent read of the patch
## tool asks what the method is. Barnes, Shechtman, Finkelstein and Goldman,
## "PatchMatch: A Randomized Correspondence Algorithm for Structural Image
## Editing", SIGGRAPH 2009, for the nearest-neighbour field and the search that
## finds it. Wexler, Shechtman and Irani, "Space-Time Completion of Video",
## IEEE PAMI 2007, for the pyramid and the vote the field is used in. Krita's
## Smart Patch tool, `kis_inpaint.cpp`, is the same pair on the CPU, and its
## patch radius, its pyramid's stopping rule, its iteration counts per level,
## its similarity curve and its floor under a vote are this file's and the
## kernel's. No line of it is copied, since its loops walk scanlines and these
## are kernels. Krita's lines for those numbers are on `PROVENANCE.md` beside
## this file.
##
## Where this departs from Krita, and why:
##
## - The field covers the hole's rectangle grown by a patch, not the whole
##   level, because only a patch that overlaps the hole votes for anything
##   (hard rule 2). The source is still the whole level.
## - A pass of Krita's search walks every scanline forwards and back, so a good
##   match crosses the image in one pass. A GPU pass has no order, so a match
##   travels [constant STEP] texels a pass here and the random search carries
##   the rest. A step that halves over several passes, jump flooding, draws
##   visibly worse seams, so it is not what this does.
## - Krita's coarsest level starts from the hole zeroed. Here it starts from
##   the Smooth method's fill, which is cheap at that size and gives the first
##   search a hole that looks like its surround rather than like black.
## - The seed lays the coarser level's colour into the hole under the vote, so
##   a texel whose votes fall under the floor keeps that answer, which is what
##   Krita's upscaled target holds in the same place.
## - The finest level's vote takes the patch of highest weight rather than the
##   mean of them all, which is what keeps the picture's grain, and the header
##   of `patch_match.gmacs` says why.
##
## The pyramid, the fields and the coarsest start are scratch over the work
## rectangle, allocated for one patch and released with it. Nothing is read
## back.
extends RefCounted

## Krita's default patch radius, so a patch is 9 by 9 texels.
const RADIUS: int = 4

## Krita's floor under a vote: a hole texel whose votes weigh less than this in
## all keeps the coarser level's answer rather than trusting a few poor matches.
const VOTE_FLOOR: float = 1.0

## How far a pass looks for a neighbour's match, in texels.
##
## One, as in the paper. Jump flooding, a pass at each of 4, 2 and 1 for each
## of Krita's, draws a seam across a hole wide enough to tell it, at three
## times the passes. A long
## step offers a texel the match of a patch that does not overlap its own,
## which is no evidence that the match suits it, so a coherent region grows
## across a seam it should have stopped at.
const STEP: int = 1

## The smallest side a level of the pyramid may have. Krita stops at the patch
## radius, where a patch is mostly off the level, and a level a patch wide is
## the least that still has a patch inside it.
const MIN_LEVEL_SIDE: int = 2 * RADIUS + 1

## The bindings `patch_match.gmacs` declares, in its own order.
const BINDING_COLOUR: int = 0
const BINDING_WEIGHT: int = 1
const BINDING_COARSE: int = 2
const BINDING_COARSE_WEIGHT: int = 3
const BINDING_FIELD: int = 4
const BINDING_FIELD_OUT: int = 5

## A field holds texel positions, which a half float stops counting exactly at
## 2048.
const FIELD_FORMAT: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

var _compute: SaCompute = null

## A 1 by 1 texel per format met, bound where a kernel declares a binding this
## dispatch has nothing for.
var _blank: Dictionary = {}

## Counts the dispatches of one fill, so each search pass and each seed draws
## random numbers of its own and a rerun draws the same ones.
var _stream: int = 0


## One level of the pyramid: its colour and weight, where the hole lies in it,
## and the two fields a search ping-pongs between.
class Level:
    extends RefCounted

    var colour: SaTexture
    var weight: SaTexture

    ## The hole's rectangle at this level, which the vote covers.
    var hole: Rect2i

    ## The hole grown by a patch, which the seed and the search cover and the
    ## fields are the size of.
    var search: Rect2i

    var _fields: Array[SaTexture] = []
    var _current: int = 0

    func _init(level_colour: SaTexture, level_weight: SaTexture, level_hole: Rect2i, radius: int) -> void:
        colour = level_colour
        weight = level_weight
        var whole := Rect2i(Vector2i.ZERO, colour.size)
        hole = level_hole.intersection(whole)
        search = hole.grow(radius).intersection(whole)
        var side := search.size.max(Vector2i.ONE)
        _fields = [SaTexture.new(side, FIELD_FORMAT), SaTexture.new(side, FIELD_FORMAT)]

    ## The field the last pass wrote.
    func field() -> SaTexture:
        return _fields[_current]

    ## The field the next pass writes.
    func spare() -> SaTexture:
        return _fields[1 - _current]

    ## Makes the field the last pass wrote the current one.
    func flip() -> void:
        _current = 1 - _current


## Draws the hole in *colour* again, and answers the colour and weight the
## result is in, which are *colour* and *weight* unless the pyramid was a single
## level and the Smooth start ended in its spare pair.
##
## *weight* is one over the picture and below one over the hole, the pair
## `patch_gather` writes, and *hole* is the hole's rectangle in their
## coordinates. *smooth* is the Smooth method's sweep, `(size, colours,
## weights) -> int` answering which of the two pairs it ended in, and it gives
## the coarsest level its start.
func fill(colour: SaTexture, weight: SaTexture, hole: Rect2i, smooth: Callable) -> Array[SaTexture]:
    if _compute == null:
        _compute = SaCompute.new("patch_match")
    _compute.use_storage_format(colour.format)
    _stream = 0
    var levels := _pyramid(colour, weight, hole, smooth)
    var top := levels.size() - 1
    for k in range(top, -1, -1):
        var level: Level = levels[k]
        var above: Level = levels[k + 1] if k < top else null
        _seed(level, above)
        if above != null:
            _vote(level, k == 0)
        for em in rounds_at(k, top):
            for _pass in passes_at(k):
                _search(level)
            # The last round's vote is the next level's, through the seed, the
            # way Krita's last round votes into the level below.
            if em < rounds_at(k, top) - 1 or k == 0:
                _vote(level, k == 0)
    var finest: Level = levels[0]
    return [finest.colour, finest.weight]


## Krita's rounds of search and vote at level *k*, `min(2k, 4)`, so the finest
## level has none and takes its answer from the level above. A pyramid of one
## level gets one round, since there is no level above to answer for it.
static func rounds_at(k: int, top: int) -> int:
    var rounds := mini(2 * k, 4)
    return maxi(rounds, 1) if k == top else rounds


## Krita's search passes per round at level *k*, `min(5, 1 + k)`.
static func passes_at(k: int) -> int:
    return mini(5, 1 + k)


## How many levels a work rectangle of *size* with a hole of *hole* is halved
## into, counting the work rectangle itself.
##
## A level is added while it stays [constant MIN_LEVEL_SIDE] wide and the
## hole's rectangle in it stays two texels across. Krita's own test is whether
## any texel is still hole, which needs the mask read back, and the rectangle is
## the answer the CPU already has. The hole shrinks a little faster than its
## rectangle, so the top level can find it gone, and the seed of the level under
## it then starts those texels at random.
static func levels_for(size: Vector2i, hole: Rect2i) -> int:
    var count := 1
    var next := _halve_size(size)
    var next_hole := _halve(hole)
    while mini(next.x, next.y) >= MIN_LEVEL_SIDE and mini(next_hole.size.x, next_hole.size.y) >= 2:
        count += 1
        next = _halve_size(next)
        next_hole = _halve(next_hole)
    return count


## Builds the pyramid over *colour* and *weight*, and starts its coarsest level
## with *smooth*.
func _pyramid(colour: SaTexture, weight: SaTexture, hole: Rect2i, smooth: Callable) -> Array[Level]:
    var colours: Array[SaTexture] = [colour]
    var weights: Array[SaTexture] = [weight]
    var holes: Array[Rect2i] = [hole]
    for _level in range(1, levels_for(colour.size, hole)):
        var size := _halve_size(colours.back().size)
        var coarse := SaTexture.new(size, colour.format)
        var coarse_weight := SaTexture.new(size, SaSelection.FORMAT)
        _down(colours.back(), weights.back(), coarse, coarse_weight)
        colours.append(coarse)
        weights.append(coarse_weight)
        holes.append(_halve(holes.back()))

    var top_size: Vector2i = colours.back().size
    var start_colours: Array[SaTexture] = [colours.back(), SaTexture.new(top_size, colour.format)]
    var start_weights: Array[SaTexture] = [weights.back(), SaTexture.new(top_size, SaSelection.FORMAT)]
    var settled: int = smooth.call(top_size, start_colours, start_weights)
    colours[-1] = start_colours[settled]
    weights[-1] = start_weights[settled]

    var levels: Array[Level] = []
    for k in colours.size():
        levels.append(Level.new(colours[k], weights[k], holes[k], RADIUS))
    return levels


## Halves *fine* into *coarse*.
func _down(fine: SaTexture, fine_weight: SaTexture, coarse: SaTexture, coarse_weight: SaTexture) -> void:
    _bind(fine, fine_weight, coarse, coarse_weight, _blank_at(FIELD_FORMAT), _blank_at(FIELD_FORMAT))
    var region := Rect2i(Vector2i.ZERO, coarse.size)
    _dispatch("patch_match_down", region, Vector4.ZERO, Vector4.ZERO)


## Starts *level*'s field from *above*'s, or at random when *above* is null.
func _seed(level: Level, above: Level) -> void:
    var coarse := above.colour if above != null else _blank_at(level.colour.format)
    var coarse_field := above.field() if above != null else _blank_at(FIELD_FORMAT)
    _bind(level.colour, level.weight, coarse, _blank_at(SaSelection.FORMAT), coarse_field, level.field())
    var origins := Vector4(level.search.position.x, level.search.position.y, 0.0, 0.0)
    if above != null:
        origins.z = above.search.position.x
        origins.w = above.search.position.y
    _dispatch("patch_match_seed", level.search, origins, Vector4(0.0, 0.0, 0.0, 1.0 if above == null else 0.0))


## One search pass over *level*.
func _search(level: Level) -> void:
    _bind(level.colour, level.weight, _blank_at(level.colour.format), _blank_at(SaSelection.FORMAT), level.field(), level.spare())
    var origins := Vector4(level.search.position.x, level.search.position.y, 0.0, 0.0)
    var reach := float(maxi(level.colour.size.x, level.colour.size.y))
    _dispatch("patch_match_search", level.search, origins, Vector4(0.0, float(STEP), reach, 0.0))
    level.flip()


## Redraws *level*'s hole from its field, by the best patch alone when
## *finest*, and by the mean of them all otherwise.
func _vote(level: Level, finest: bool) -> void:
    _bind(level.colour, level.weight, _blank_at(level.colour.format), _blank_at(SaSelection.FORMAT), level.field(), level.spare())
    var origins := Vector4(level.search.position.x, level.search.position.y, 0.0, 0.0)
    _dispatch("patch_match_vote", level.hole, origins, Vector4.ZERO, 1.0 if finest else 0.0)


## The six bindings, in the kernel's order.
func _bind(
    colour: SaTexture, weight: SaTexture, coarse: SaTexture, coarse_weight: SaTexture, field: SaTexture, field_out: SaTexture
) -> void:
    _compute.set_texture(BINDING_COLOUR, colour.rid)
    _compute.set_texture(BINDING_WEIGHT, weight.rid)
    _compute.set_texture(BINDING_COARSE, coarse.rid)
    _compute.set_texture(BINDING_COARSE_WEIGHT, coarse_weight.rid)
    _compute.set_texture(BINDING_FIELD, field.rid)
    _compute.set_texture(BINDING_FIELD_OUT, field_out.rid)


## One dispatch over *region*, with the push constant `patch_match.gmacs`
## declares. *tune*'s first float is replaced by this dispatch's stream, and
## *best* is one for a vote that takes the best patch alone.
func _dispatch(kernel: String, region: Rect2i, origins: Vector4, tune: Vector4, best: float = 0.0) -> void:
    if region.size.x <= 0 or region.size.y <= 0:
        return
    tune.x = float(_stream)
    _stream += 1
    var constants := PackedFloat32Array(
        [float(region.position.x), float(region.position.y), float(region.end.x), float(region.end.y)]
    )
    constants.append_array(PackedFloat32Array([origins.x, origins.y, origins.z, origins.w]))
    constants.append_array(PackedFloat32Array([tune.x, tune.y, tune.z, tune.w]))
    constants.append_array(PackedFloat32Array([float(RADIUS), VOTE_FLOOR, best, 0.0]))
    _compute.set_push_constant_float_array(constants)
    _compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)


## A 1 by 1 texel at *format*, kept per format met.
func _blank_at(format: int) -> SaTexture:
    var blank: SaTexture = _blank.get(format, null)
    if blank == null:
        blank = SaTexture.new(Vector2i(1, 1), format)
        blank.clear(Color(0.0, 0.0, 0.0, 0.0))
        _blank[format] = blank
    return blank


## The level above one of *size*, rounded up so no texel is dropped.
static func _halve_size(size: Vector2i) -> Vector2i:
    @warning_ignore("integer_division")
    return (size + Vector2i.ONE) / 2


## *rect* at the level above, grown to whole texels there.
static func _halve(rect: Rect2i) -> Rect2i:
    @warning_ignore("integer_division")
    var start := rect.position / 2
    @warning_ignore("integer_division")
    var end := (rect.end + Vector2i.ONE) / 2
    return Rect2i(start, end - start)
