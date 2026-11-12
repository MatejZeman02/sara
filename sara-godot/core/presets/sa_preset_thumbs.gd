## A preset's thumbnail, which is a stroke rendered now rather than a picture
## stored once.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own work. What `_point_at` and `_pressure_at` draw is a sine over the
## width with the pressure at zero at both ends and full in the middle, which is
## a taper, and not a two-point ramp from no pressure to full.
##
## **What a thumbnail has to say is what the brush does, not what somebody
## drew.** So the stroke is generated rather than recorded, it sweeps the whole
## pressure range once so a painter sees both ends of it, and it curves rather
## than running straight so the tip is seen turning.
##
## **Why a read-back is not a breach of hard rule 1.** That rule is about the
## canvas during a stroke: the document never leaves VRAM while a painter is
## painting. This is a throwaway document with no canvas attached and no painter
## in front of it, composited once and read back once, when a chooser or an
## editor opens. The rule's own text names export and the eyedropper as the two
## readers, and this is the third of the same kind.
##
## **It knows nothing about brushes.** The caller hands over the tool's own
## script and the settings resource, and the stroke is driven through
## `ToolState.handle_input` with the same events the app pushes at it, so a
## third-party tool with a settings resource gets a thumbnail for free. Nothing
## here names the stamp brush.
class_name SaPresetThumbs
extends RefCounted

## The thumbnail a chooser shows, from the spec.
const SIZE := Vector2i(128, 64)

## The strip the brush editor's dashboard holds, from the spec's own drawing.
const PREVIEW_SIZE := Vector2i(320, 60)

## The tip thumbnail's size, square because a dab is. The chooser's cell
## follows it, so the two-to-one strip is the stroke's shape alone.
const TIP_SIZE := Vector2i(64, 64)

## What a tip's file name carries before `.png`, so one preset has two cached
## pictures rather than one that is redrawn every time the choice is flipped. A
## suffix rather than a second directory, because `forget` then has one place
## to look and `DIR_NAME`'s "never offered as a brush" argument still holds: a
## `.tip.png` is not a `.tres`.
const TIP_SUFFIX: String = ".tip"

## The radius a cached tip is drawn at, as the fraction of the square that
## `radius` is of a document's smaller dimension.
##
## Fixed rather than the preset's own, and the same number the brush editor's
## `TipPreview` fixes for the same reason: a tip is a shape, a hardness, a mirror
## and a rotation, and a preset at half a percent draws a dab a third of a texel
## across which says nothing about any of them, and a cell of an invisible dot
## is a chooser nobody can pick in.
##
## Size is what the stroke picture says, and it is on the tool options row and on
## the Size page besides, so nothing is lost by the tip not repeating it.
##
## It is the radius of the first dab, and `render_tip` frames what that dab
## painted rather than trusting it to fill the cell.
const TIP_RADIUS: float = 0.36

## How much of a tip cell the painted tip spans, its longer side against the
## cell's, which leaves a sixteenth of the cell as margin on each side.
##
## A tip fills its cell in the Brush Editor's grid. A fixed radius fixes the
## dab's box, and two things put the paint well inside that box. An image tip
## whose picture leaves a margin paints only where its picture is, and a Size
## option below full strength scales every dab at full pressure, so either can
## draw a dot in a corner of the cell. So the cell is framed by what was painted
## rather than by what was asked for.
const TIP_FILL: float = 0.875

## Below this share of `TIP_FILL` the tip is painted a second time, larger,
## rather than only framed.
##
## Framing a small dab enlarges the texels it has, and under half the fill the
## supersampled render has fewer than two of them for each texel of the cell. The
## second dab is drawn at the radius the first says would fill, so the picture
## stays sharp and the extra render is spent only on the presets that need it.
const TIP_REDRAW_BELOW: float = 0.5

## The most the second dab's radius is multiplied by. A picture that is a speck
## in a wide margin would otherwise ask for a dab many times the easel, and past
## this a slightly soft enlargement is the cheaper picture.
const TIP_MAX_GROWTH: float = 8.0

## How far a channel has to be from the corner's, in levels of 255, to count as
## paint when a tip is framed. Five is the two percent `TipPreview` measures
## its ink at, so the two agree on where a dab ends.
const INK_LEVELS: int = 5

## How far a texel of a finished picture has to be from its corner, in levels of
## 255, before it is a stroke a chooser cell shows rather than the card.
##
## The chooser's own suite counts a picture's ink at a twentieth of full scale,
## which is 12.75 levels, so a picture carrying a texel at 13 is one that suite
## calls painted. The two lines have to agree: a stroke drawn again because it is
## empty at this one has to be the stroke that suite would otherwise take for a
## blank cell.
const VISIBLE_LEVELS: int = 13

## The line a picture drawn again has to reach before the drawing stops.
##
## Twice `VISIBLE_LEVELS`, because the picture is 128 by 64 and the chooser draws
## it in a cell of at most 80 by 40, where four picture texels make one of the
## cell's: a stroke that only just carries ink in the picture is under four
## levels in the cell, which is nothing. Measured on the shipped Spatter, its
## picture peaks at 23 levels of 255 at four times its radius and 45 at eight,
## and in an 80 by 40 cell the first is a faint hairline like the Pencil's and
## the second is a scatter of dots.
const SHOWN_LEVELS: int = 26

## The multipliers a stroke the picture cannot show is drawn again at, in
## order. Two doublings and then the ceiling `render_tip` grows a tip by, so
## the worst case is the tip's own and the ladder stops on the first picture
## that reaches `SHOWN_LEVELS` rather than at the ceiling.
const STROKE_GROWTHS: Array[float] = [2.0, 4.0, TIP_MAX_GROWTH]

## Beside the presets rather than in a second directory, and hidden, so
## `SaPresetStore.list_names` never offers a painter a PNG as a brush: that walk
## takes files ending in `.tres` and a dot-directory is not a file at all.
const DIR_NAME: String = ".thumbs"

## The colour every thumbnail is drawn in. Dark rather than black so a hard round
## brush and a soft one are told apart by their edges rather than by a silhouette.
const INK := Color(0.08, 0.08, 0.1, 1.0)

## The seed every thumbnail's stroke starts its random streams from, handed to
## the tool as `ToolState.stroke_seed`.
##
## Fixed rather than the wall clock's, because the chooser renders a thumbnail
## once per launch where the cache is empty and a capture run always empties
## it. The Grainy Pencil jumps its paper by a phase drawn per stroke, and drawn
## off the clock that phase moved the grain under a 48 by 24 cell by a level or
## two on every launch. A fixed phase is also the
## honest picture: the grain a cell shows is a grain the brush lays, and a jump
## the painter never sees would say nothing more about it. Any number but zero,
## which is the tool's word for the clock.
const STROKE_SEED: int = 1

## How much larger the throwaway document is than the thumbnail, before the image
## is scaled down.
##
## Not decoration. A radius is a fraction of the canvas's smaller dimension, so on
## a 64-tall strip the Sketch preset's 0.00463 is a third of a pixel and Paint's
## 0.023 is one and a half: both come out as the same hairline and the two
## thumbnails are indistinguishable. Rendered four times as large and scaled down,
## the same two are a faint line and a solid one, which is the difference a
## painter is choosing between. It also costs the antialiasing a 128 by 64 stroke
## has nowhere else to get.
const SUPERSAMPLE: int = 4

## Dabs along the S. Enough that the stroke reads as a stroke at 128 wide and
## few enough that a library of two hundred is two hundred cheap renders rather
## than two hundred expensive ones.
const STEPS: int = 40

## What the run has done, for a dump. A second open of the same chooser must read
## the cache and render nothing, and only a counter says which of the two
## happened.
static var renders: int = 0
static var cache_hits: int = 0
## The composites, the asks of the card, and the reads by the way each came,
## for a dump and for the suite that holds no step does two of them. A read
## waited for is one whose bytes the card handed back, and a read at once one
## that waited on the card in the call.
static var composites: int = 0
static var asks: int = 0
static var reads_waited: int = 0
static var reads_at_once: int = 0

## The one compositor every throwaway easel here composites through.
##
## **Shared, because a fresh compositor costs a pipeline load.**
## `SaEasel.create_default` builds a fresh `SaCompositor` when it is handed none,
## and a fresh one loads its blend pipelines on the first composite, which here
## is the stroke's commit on the release. A private compositor would make every
## preview pay that load, many times the dab itself, to draw one dab.
##
## Shared through the door `create_default` already has, whose own comment says it
## lets several easels share one blend-mode registry. What is shared is that
## registry, the kernels it loaded and the scratch textures a composite reuses,
## all of which one synchronous render at a time is safe to reuse. The easel, the
## document, the layers and the tool are still built fresh for every render, so no
## picture reads anything of the last one, and the dab is still the real tool's
## dab through the real kernel.
static var _compositor: SaCompositor = null

## The compositor the last render's easel composited through, for a dump and for
## the suite that pins the fix. Written only by `Paint`, which is the one place
## that decides it.
static var last_compositor: SaCompositor = null


## A view that answers wherever the renderer says the pointer is.
##
## The stroke is driven through the tool's own `handle_input`, which reads the
## position off the view rather than off the event, so a renderer with no window
## needs one of these. Nothing else on `SaView` is asked, and the defaults answer
## the rest.
class ThumbView:
    extends SaView

    var at: Vector2 = Vector2.ZERO

    func get_document_mouse_position() -> Vector2:
        return at


## One stroke, or one dab, on a throwaway easel, sent an event at a time.
##
## `_paint` sends every event in one call and a `Drawing` a few a frame, so the
## easel, the events and the read-back are one path whatever pace they go at.
##
## **The composite and the read are two steps, and the read can wait for the
## card.** A read in the same call as the composite, through `texture_get_data`,
## waits until the card has run every dab the stroke sent, and that wait is what
## holds a slow frame. So the composite is one step and the read a later one,
## and a step that may wait asks through `texture_get_data_async` and takes the
## bytes two frames on, when the card hands them back, a small part of the wait.
## A step that may not wait reads at once, which is what `render`, `render_tip`,
## `ensure` and a capture's pinned clock ask for.
##
## **Each event is sent at its own time**, as `_send` says, so the pace the
## steps go at is never in the picture.
class Paint:
    extends RefCounted

    ## What a `step` did, which `Drawing.advance` reads to end a frame's share.
    enum Did { NOTHING, EVENT, COMPOSITE, ASK, WAIT, READ }

    ## What was painted, at the render size and 8 bits a channel, once `step` has
    ## answered true. Null when nothing could be drawn.
    var image: Image = null
    ## What the last `step` did.
    var did: Did = Did.NOTHING

    ## The easel, the view and the tool the events go to, all null once the
    ## picture is read or let go.
    var _easel: SaEasel = null
    var _view: ThumbView = null
    var _painter: ToolState = null
    var _events: Array[Array] = []
    ## How many of `_events` have been sent.
    var _sent: int = 0
    ## Whether the stroke is committed and composited, so the next step reads.
    var _composited: bool = false
    ## The engine's count of drawn frames when the card was asked for the
    ## picture, and -1 before it was.
    var _asked_at: int = -1
    ## What the card handed back, and whether it has.
    var _bytes := PackedByteArray()
    var _answered: bool = false

    ## Whether the tool lays a ground of its own, which it keeps.
    var own_ground: bool = false

    func _init(tool_script: Script, settings: Resource, render_size: Vector2i, one_dab: bool, grounded: bool = false) -> void:
        if tool_script == null or settings == null:
            return
        var easel := SaEasel.create_default(render_size, SaPresetThumbs.shared_compositor())
        SaPresetThumbs.last_compositor = easel.compositor
        SaResidency.spare(easel.document)
        var view := ThumbView.new()
        var surface := SaSurface.create(&"preset_thumb", easel, view)
        var source := tool_script as GDScript
        var built: Variant = source.new() if source != null else null
        var painter: ToolState = built if built is ToolState else null
        if painter == null:
            easel.free()
            return
        painter.surface = surface
        painter.stroke_seed = STROKE_SEED
        # Onto the tool's own settings object rather than swapping the resource
        # in, because a tool may hold a reference to the one it was born with,
        # which is the whole of `eraser-paints`.
        var held: Variant = painter.get("settings")
        if held is Resource:
            var target: Resource = held
            SaPresetStore.copy_settings(settings, target)
            # The ink, after the copy, because `copy_settings` excludes the colour
            # on purpose: a preset carries a brush and not a palette, and one
            # loaded from the chooser must not repaint what the painter has in
            # hand. A thumbnail needs an ink all the same, and a fixed dark one
            # over the default document's mid grey reads for every brush rather
            # than for whichever colour happened to be current. An eraser preset
            # draws nothing here, which is what an eraser does and is worth seeing.
            if "color" in target:
                target.set("color", INK)
        # A tool that lays no paint shows its work on a ground of its own,
        # liquify's grid.
        own_ground = painter.has_method(&"begin_picture")
        if own_ground:
            painter.call(&"begin_picture")
        elif grounded:
            SaThumbGround.lay(easel.document)
            easel.request_full_composite()
            easel.process_pending_composite()
        # A brush that picks up reads the composite, which an easel nobody has
        # drawn yet holds as nothing, and a smear over nothing thins to
        # nothing. Composited once, the ground is under it as a document's is
        # in the app.
        elif _picks_up(settings):
            easel.request_full_composite()
            easel.process_pending_composite()
        _easel = easel
        _view = view
        _painter = painter
        _events = SaPresetThumbs._events(render_size, one_dab)

    ## Whether *settings* switch the smudge stage's pickup on.
    static func _picks_up(settings: Resource) -> bool:
        var held: Object = settings.get("smudge_pickup_option") if "smudge_pickup_option" in settings else null
        var pickup := held as SaCurveOption
        return pickup != null and pickup.enabled

    ## Sends the next event, or once every one is sent composites the easel, and
    ## on a later call reads it back into `image`. Answers whether the picture is
    ## finished, and `did` says what the call did.
    ##
    ## *at_once* reads in the call after the composite. Otherwise that call asks
    ## the card, and the calls after it wait until the bytes come back. A call
    ## that finds no frame drawn since it asked reads at once all the same,
    ## because the card hands an answer back only as a frame is drawn: that is a
    ## suite's loop, or a window that draws nothing while it rests.
    func step(at_once: bool = true) -> bool:
        if _easel == null:
            did = Did.NOTHING
            return true
        if _sent < _events.size():
            _sent += 1
            SaPresetThumbs._send(_painter, _view, _events[_sent - 1], _sent - 1)
            did = Did.EVENT
            return false
        if not _composited:
            _composite()
            return false
        if _answered:
            var answered := SaExport.texture_image_from_bytes(_easel.output, _bytes)
            if answered != null:
                SaPresetThumbs.reads_waited += 1
                _finish(answered)
                return true
        elif not at_once and _asked_at < 0 and _ask():
            did = Did.ASK
            return false
        elif not at_once and _asked_at >= 0 and Engine.get_frames_drawn() != _asked_at:
            did = Did.WAIT
            return false
        SaPresetThumbs.reads_at_once += 1
        _finish(SaExport.get_texture_image_float(_easel.output))
        return true

    ## The card's answer to `_ask`, handed over as this method, which holds the
    ## picture by its id alone, so a picture let go meanwhile is not kept for
    ## bytes nobody will read (`SaExport.ask_texture_bytes` says why never a lambda).
    func heard(bytes: PackedByteArray) -> void:
        _bytes = bytes
        _answered = true

    ## Commits the stroke and composites the easel, which leaves the picture in
    ## its output for the next step to read.
    func _composite() -> void:
        var document := _easel.document
        if document != null:
            document.commit_stroke()
        _easel.request_full_composite()
        _easel.process_pending_composite()
        # What `SaExport.get_easel_image_float` does before its read, here so the
        # read is a read and nothing else.
        _easel.flush()
        _composited = true
        SaPresetThumbs.composites += 1
        did = Did.COMPOSITE

    ## Asks the card for the output's bytes, and answers whether it was asked.
    ## Only the main device hands an answer back as a frame is drawn, so a local
    ## one is read at once.
    func _ask() -> bool:
        if not SaExport.ask_texture_bytes(_easel.output, heard):
            return false
        _asked_at = Engine.get_frames_drawn()
        SaPresetThumbs.asks += 1
        return true

    ## Lets go of the easel and keeps *float_image* as `image`, at 8 bits.
    func _finish(float_image: Image) -> void:
        _let_go()
        if float_image != null:
            float_image.convert(Image.FORMAT_RGBA8)
        image = float_image
        did = Did.READ

    ## Lets go of a picture nobody will finish. A stroke under way is lifted
    ## first, so the brush sends what it held while its easel is still there.
    func abandon() -> void:
        if _easel == null:
            return
        if _sent > 0 and _sent < _events.size():
            SaPresetThumbs._send(_painter, _view, _events[-1], _events.size() - 1)
            if _easel.document != null:
                _easel.document.commit_stroke()
        _let_go()

    func _let_go() -> void:
        if _easel.document != null:
            _easel.document.free()
        _easel.free()
        _easel = null
        _view = null
        _painter = null


## A preset's picture, drawn a few events at a time: the stroke and the ladder
## `render` describes, or the framed tip `render_tip` describes.
##
## **Steps, because a fresh profile has no picture cached.** A whole stroke of
## forty-one events on a 512 by 256 easel a frame, for every shipped preset,
## runs a cold start into slow frames with no hand on the pen. So the chooser
## sends a few events of a picture each frame, and `advance` with no budget is the old
## picture in one call, which `render`, `render_tip` and `ensure` still are.
## A frame's share composites in one frame and takes the read some frames
## later, when the card has run the stroke, as `Paint` says.
class Drawing:
    extends RefCounted

    ## Where a share left the picture: a stroke to begin, the picture's first or
    ## a rung's, part way through one, or waiting for the card to hand the one
    ## it sent back.
    enum Stage { START, STROKE, CARD }

    ## The finished picture, null until `done` and null after it when nothing
    ## could be drawn.
    var picture: Image = null
    var done: bool = false
    ## Whether this is a tip, framed as `render_tip` frames it, which is also the
    ## name its picture is cached under.
    var framed: bool = false
    ## Where the last `advance` with a budget stopped, which the presets chooser
    ## reads to give the rest of a frame to another picture while this one waits
    ## on the card, and to send one stroke at a time.
    var stage: Stage = Stage.START

    var _tool_script: Script = null
    ## The preset as it was handed over, which nothing here writes.
    var _settings: Resource = null
    var _size := Vector2i.ZERO
    var _one_dab: bool = false
    ## The paint under way, and the settings it was started from: the preset, or
    ## a copy of it at another radius.
    var _paint: Paint = null
    var _drawn: Resource = null
    ## The rung of `STROKE_GROWTHS` the paint under way is on, and -1 while it is
    ## the first paint at the preset's own radius.
    var _rung: int = -1
    var _radius: float = 0.0
    ## The picture so far, which a rung that draws nothing leaves standing.
    var _so_far: Image = null
    ## A tip's first dab and the box of paint in it, kept while a larger dab is
    ## drawn.
    var _first: Image = null
    var _box := Rect2i()
    ## Whether the picture is drawn over `SaThumbGround`, and then it is the last.
    var _grounded: bool = false

    func _init(tool_script: Script, settings: Resource, size: Vector2i, one_dab: bool, as_tip: bool) -> void:
        _tool_script = tool_script
        _settings = settings
        _size = size
        framed = as_tip
        _one_dab = one_dab or as_tip
        _drawn = SaPresetThumbs._drawn_from(settings, true) if as_tip else settings
        _paint = Paint.new(tool_script, _drawn, size * SUPERSAMPLE, _one_dab)

    ## The drawing `ensure` caches for a preset: its tip when *one_dab* is set,
    ## and its stroke otherwise.
    static func cached(tool_script: Script, settings: Resource, one_dab: bool) -> Drawing:
        if one_dab:
            return Drawing.new(tool_script, settings, TIP_SIZE, true, true)
        return Drawing.new(tool_script, settings, SIZE, false, false)

    ## Sends events until *budget_usec* is spent, or to the end when it is
    ## negative, and answers whether the picture is finished. An event is one
    ## step, so a frame runs over by at most the step it was in.
    ##
    ## With a budget the ask and each wait for the card end the frame's share,
    ## so no share both composites and reads, and the read is the bytes the card
    ## handed back rather than a wait for them. The ask goes in the composite's
    ## share when the budget lasts, since the card answers two frames after the
    ## frame that asked. With none the picture is read at once, in the call
    ## after the composite.
    ##
    ## A read ends the call too, when it leaves a stroke to begin, so a rung of
    ## the ladder or a larger tip starts only when the chooser gives it the
    ## share, never while another picture's stroke is part way.
    func advance(budget_usec: int) -> bool:
        var started := Time.get_ticks_usec()
        var at_once := budget_usec < 0
        while not done:
            if _paint.step(at_once):
                _took(_paint.image)
                stage = Stage.START
                if not at_once:
                    break
            elif not at_once and _paint.did != Paint.Did.EVENT and _paint.did != Paint.Did.COMPOSITE:
                stage = Stage.CARD
                break
            else:
                stage = Stage.STROKE
            if not at_once and Time.get_ticks_usec() - started >= budget_usec:
                break
        return done

    ## Lets go of the paint under way, and the drawing is done with no picture.
    func abandon() -> void:
        if _paint != null:
            _paint.abandon()
        _finish(null)

    func _took(image: Image) -> void:
        if framed:
            _took_tip(image)
        else:
            _took_stroke(image)

    ## The first paint is the picture unless the cell cannot show it. Then the
    ## stroke is drawn again at growing radii until the picture reaches
    ## `SHOWN_LEVELS`, or the last attempt is the picture when none does.
    ##
    ## The one number that grows is the preset's own `radius`, and it grows on a
    ## copy rather than on the preset, so a chooser never draws from a settings
    ## object that has been resized by having been looked at. A tool with no
    ## radius has nothing to grow and keeps the picture it already had.
    func _took_stroke(image: Image) -> void:
        if _rung < 0:
            if image == null:
                _finish(null)
                return
            SaPresetThumbs.renders += 1
            if _grounded:
                _finish(SaPresetThumbs._shown(image, _size))
                return
            _so_far = SaPresetThumbs._shown(image, _size)
            if not _paint.own_ground and not SaPresetThumbs._carries_ink(image, VISIBLE_LEVELS):
                _grounded = true
                _paint = Paint.new(_tool_script, _settings, _size * SUPERSAMPLE, _one_dab, true)
                return
            if SaPresetThumbs._carries_ink(_so_far, VISIBLE_LEVELS) or not SaPresetThumbs._carries_ink(image, VISIBLE_LEVELS):
                _finish(_so_far)
                return
            var grown := _settings.duplicate(true) as Resource
            if grown == null or not ("radius" in grown):
                _finish(_so_far)
                return
            _drawn = grown
            _radius = SaTyped.real(grown.get("radius"))
            _climb(0)
            return
        if image == null:
            _finish(_so_far)
            return
        _so_far = SaPresetThumbs._shown(image, _size)
        if SaPresetThumbs._carries_ink(_so_far, SHOWN_LEVELS) or _rung + 1 >= STROKE_GROWTHS.size():
            _finish(_so_far)
            return
        _climb(_rung + 1)

    func _climb(rung: int) -> void:
        _rung = rung
        _drawn.set("radius", _radius * STROKE_GROWTHS[rung])
        _paint = Paint.new(_tool_script, _drawn, _size * SUPERSAMPLE, _one_dab)

    ## The first dab, framed, or a larger one when the first painted too little
    ## to frame sharply. Only the copy `_drawn_from` made grows, which is the one
    ## that has a radius to grow and the one nobody else holds.
    func _took_tip(image: Image) -> void:
        if _grounded:
            _finish(SaPresetThumbs._shown(image, _size) if image != null else _framed_tip(_first, _box))
            return
        if _first == null:
            if image == null:
                _finish(null)
                return
            SaPresetThumbs.renders += 1
            _first = image
            _box = SaPresetThumbs._painted_box(image)
            # A dab that leaves nothing to frame changes what is under it, so its
            # tip is a stroke across the ground.
            if not _box.has_area() and not _paint.own_ground:
                _grounded = true
                _paint = Paint.new(_tool_script, _settings, _size * SUPERSAMPLE, false, true)
                return
            var growth := SaPresetThumbs._growth(_box, _size * SUPERSAMPLE)
            if growth > 1.0 and _drawn != _settings:
                _drawn.set("radius", SaTyped.real(_drawn.get("radius")) * growth)
                _paint = Paint.new(_tool_script, _drawn, _size * SUPERSAMPLE, true)
                return
            _finish_tip(_framed_tip(_first, _box))
            return
        var larger_box := SaPresetThumbs._painted_box(image) if image != null else Rect2i()
        if larger_box.has_area():
            _finish_tip(_framed_tip(image, larger_box))
        else:
            _finish_tip(_framed_tip(_first, _box))

    ## A framed tip with no ink a cell shows is drawn again over the ground.
    func _finish_tip(framed_tip: Image) -> void:
        if not _paint.own_ground and not SaPresetThumbs._carries_ink(framed_tip, VISIBLE_LEVELS):
            _grounded = true
            _paint = Paint.new(_tool_script, _settings, _size * SUPERSAMPLE, false, true)
            return
        _finish(framed_tip)

    func _framed_tip(image: Image, box: Rect2i) -> Image:
        var shown := SaPresetThumbs._framed(image, box, _size) if box.has_area() else image
        shown.resize(_size.x, _size.y, Image.INTERPOLATE_LANCZOS)
        return shown

    func _finish(finished: Image) -> void:
        picture = finished
        done = true
        _paint = null


static func thumbs_dir(preset_dir: String) -> String:
    return preset_dir.path_join(DIR_NAME)


## Where the picture of *preset_name* is cached, the tip's beside the stroke's
## when *one_dab* is set.
static func path_for(preset_dir: String, preset_name: String, one_dab: bool = false) -> String:
    var stem := SaPresetStore.sanitize_name(preset_name)
    return thumbs_dir(preset_dir).path_join(stem + (TIP_SUFFIX if one_dab else "") + ".png")


## Whether the thumbnail for *preset_name* has to be drawn again: there is none,
## or the `.tres` is newer than the `.png`.
##
## A modification time rather than a hash of the settings, because the file is
## what changed and the file system already answers this for nothing.
##
## A picture that cannot be read counts as stale too, so it is drawn again rather
## than handed to `Image.load_from_file` to fail with an error line.
static func is_stale(preset_dir: String, preset_name: String, one_dab: bool = false) -> bool:
    var png := path_for(preset_dir, preset_name, one_dab)
    if not FileAccess.file_exists(png) or not SaWholePng.reads(png):
        return true
    var tres := preset_dir.path_join(SaPresetStore.sanitize_name(preset_name) + SaPresetStore.EXTENSION)
    if not FileAccess.file_exists(tres):
        return false
    return FileAccess.get_modified_time(tres) > FileAccess.get_modified_time(png)


## The thumbnail's path, rendering it first when it is stale. Empty when nothing
## could be drawn.
static func ensure(
    preset_dir: String, preset_name: String, tool_script: Script, settings: Resource, one_dab: bool = false
) -> String:
    var png := path_for(preset_dir, preset_name, one_dab)
    if not is_stale(preset_dir, preset_name, one_dab):
        cache_hits += 1
        return png
    var drawing := Drawing.cached(tool_script, settings, one_dab)
    drawing.advance(-1)
    return keep(preset_dir, preset_name, drawing)


## Saves what *drawing* drew as the cached picture of *preset_name*, and answers
## its path, or empty when nothing could be drawn. `ensure` hands over a drawing
## it finished at once, and the presets chooser one it advanced a few events a
## frame.
static func keep(preset_dir: String, preset_name: String, drawing: Drawing) -> String:
    if drawing.picture == null:
        return ""
    var png := path_for(preset_dir, preset_name, drawing.framed)
    DirAccess.make_dir_recursive_absolute(thumbs_dir(preset_dir))
    if not SaWholePng.write(png, drawing.picture):
        return ""
    return png


## What a cached picture is drawn from: the preset itself for a stroke, and a copy
## of it at `TIP_RADIUS` for a tip.
##
## The copy is deep, because a tip is a resource of its own and a shallow one
## would hand the renderer the preset's own tip to write on. A preset with no
## `radius` is drawn as it stands, which is what a tool that does not size its
## dab by a fraction wants.
static func _drawn_from(settings: Resource, one_dab: bool) -> Resource:
    if not one_dab or settings == null:
        return settings
    var shown := settings.duplicate(true) as Resource
    if shown == null or not ("radius" in shown):
        return settings
    shown.set("radius", TIP_RADIUS)
    return shown


## Removes the thumbnails of *preset_name*, so a deleted preset leaves no orphan.
##
## Both pictures, because a preset has a tip beside its stroke: forgetting the
## stroke alone would leave a `.tip.png` that the next preset saved under the
## same name would be shown by.
static func forget(preset_dir: String, preset_name: String) -> void:
    for one_dab: bool in [false, true]:
        var png := path_for(preset_dir, preset_name, one_dab)
        if FileAccess.file_exists(png):
            DirAccess.remove_absolute(png)


## Renders one stroke with *settings* on a throwaway document of *size*, and
## answers it as an 8-bit image.
##
## *tool_script* is the tool the preset belongs to, handed over rather than
## looked up: this file has no registry and no idea which tools exist.
##
## **A stroke the picture cannot show is drawn again, larger**. A radius is a
## fraction of the document's shorter side, so the share of a picture a dab
## covers does not move however large the render is: the Spatter's 0.28 percent
## is a third of a texel of a 128 by 64 picture at any supersample, and the ink
## it lays is spread too thin for the cell to show anything. Measured on the
## twenty-one presets the brush module ships, twenty of them peak at 20 levels of
## 255 or more in the finished picture and the Spatter at 6. So a picture that
## carries no ink at `VISIBLE_LEVELS` is drawn again at `STROKE_GROWTHS`'s radii
## and the first picture that shows is the one a chooser gets.
##
## Size is what the stroke picture says, which is why this only reaches a brush
## the picture cannot show at all: a preset that draws anything a cell can read
## is left at its own radius. Nothing is drawn again when the document itself
## carries no paint either, because no radius will show a brush that lays
## nothing, which is an eraser and is worth seeing empty.
##
## `Drawing` is where the ladder is climbed, so the presets chooser drawing a
## few events a frame climbs the same one.
static func render(tool_script: Script, settings: Resource, size: Vector2i = SIZE, one_dab: bool = false) -> Image:
    var drawing := Drawing.new(tool_script, settings, size, one_dab, false)
    drawing.advance(-1)
    return drawing.picture


## *image* scaled down to *size*, which is the picture a chooser cell is handed.
static func _shown(image: Image, size: Vector2i) -> Image:
    var shrunk := image.duplicate() as Image
    shrunk.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
    return shrunk


## Whether any texel of *image* is paint rather than the corner's card, at
## *levels* of 255 rather than at `INK_LEVELS`.
##
## **Each colour is read once rather than each texel.** The texels are taken as
## one integer each and sorted, which the engine does, and the walk jumps from
## one colour to the next. A picture that carries no ink at the cell's line is
## walked whole, which is a 512 by 256 render for a stroke the cell cannot show
## and for an eraser's, and walked a texel at a time in GDScript that took 18 to
## 24 ms of a frame on a slower machine. Sorted, the same answer took 1.3 to 1.7 ms over
## the shipped stamp presets, most of it the sort, because a picture of one
## stroke in one ink on the card holds at most 208 colours.
static func _carries_ink(image: Image, levels: int) -> bool:
    var data := image.get_data()
    var texels := data.to_int32_array()
    texels.sort()
    var at := 0
    while at < texels.size():
        # Red in the low byte, as the bytes lie in memory.
        var texel := texels[at]
        if (
            absi((texel & 0xFF) - data[0]) >= levels
            or absi(((texel >> 8) & 0xFF) - data[1]) >= levels
            or absi(((texel >> 16) & 0xFF) - data[2]) >= levels
        ):
            return true
        at = texels.bsearch(texel, false)
    return false


## A preset's tip for a chooser cell of *size*: one dab at `TIP_RADIUS`, framed
## so that what it painted spans `TIP_FILL` of the cell.
##
## The frame is taken from the paint rather than from the settings, so it holds
## whatever put the paint inside the dab's box, and this file still names no
## option of any tool. The shape, the hardness, the ratio, the rotation and the
## mirror are the preset's own and are what the cell shows. The size is not, and
## the stroke picture is where the size is judged, which `ensure` draws through
## `render` at the preset's own.
##
## The brush editor's `TipPreview` is not framed, and goes on calling `render`.
static func render_tip(tool_script: Script, settings: Resource, size: Vector2i = TIP_SIZE) -> Image:
    var drawing := Drawing.new(tool_script, settings, size, true, true)
    drawing.advance(-1)
    return drawing.picture


## How much larger the dab's radius has to be for *box* to reach the fill of a
## *render_size* square, or 1.0 when framing what is there is enough.
static func _growth(box: Rect2i, render_size: Vector2i) -> float:
    if not box.has_area():
        return 1.0
    var fill := TIP_FILL * float(mini(render_size.x, render_size.y))
    var longer := float(maxi(box.size.x, box.size.y))
    if longer >= fill * TIP_REDRAW_BELOW:
        return 1.0
    return minf(fill / longer, TIP_MAX_GROWTH)


## The smallest rectangle holding every texel of *image* that differs from the
## corner by more than `INK_LEVELS` on a channel, or an empty one when nothing was
## painted.
##
## The corner is the card, because a dab centred on the square does not reach it
## at the fill. Read from the bytes rather than through `get_pixel`, because this
## walks a 256 square once or twice per preset and a call per texel is most of
## what that would cost.
static func _painted_box(image: Image) -> Rect2i:
    var width := image.get_width()
    var height := image.get_height()
    var data := image.get_data()
    var low := Vector2i(width, height)
    var high := Vector2i(-1, -1)
    for y in height:
        var row := y * width * 4
        for x in width:
            var i := row + x * 4
            if (
                absi(data[i] - data[0]) > INK_LEVELS
                or absi(data[i + 1] - data[1]) > INK_LEVELS
                or absi(data[i + 2] - data[2]) > INK_LEVELS
            ):
                low = Vector2i(mini(low.x, x), mini(low.y, y))
                high = Vector2i(maxi(high.x, x), maxi(high.y, y))
    if high.x < 0:
        return Rect2i()
    return Rect2i(low, high - low + Vector2i.ONE)


## *image* cut to a frame of *size*'s shape centred on *box*, large enough that
## the box spans `TIP_FILL` of it. Where the frame runs past the image it is the
## corner's colour, the card the dab was painted on, so a dab scattered towards an
## edge is framed on what it left rather than on a black border.
static func _framed(image: Image, box: Rect2i, size: Vector2i) -> Image:
    var scale := maxf(float(box.size.x) / float(size.x), float(box.size.y) / float(size.y)) / TIP_FILL
    var frame := Vector2i(maxi(1, ceili(float(size.x) * scale)), maxi(1, ceili(float(size.y) * scale)))
    var framed := Image.create_empty(frame.x, frame.y, false, image.get_format())
    framed.fill(image.get_pixel(0, 0))
    var origin := box.get_center() - Vector2i(Vector2(frame) * 0.5)
    framed.blit_rect(image, Rect2i(origin, frame), Vector2i.ZERO)
    return framed


## The compositor `_paint` hands every easel, made the first time it is asked for.
##
## **It is let go when the tree exits, because a static outlives the rendering
## device**. A static var is dropped when the script class is, which is after
## the engine has torn the device down, so the compositor's computes and scratch
## textures would free their RIDs into a device that was gone, an "Attempted to
## free invalid ID" line each at the end of every run. The root leaving the tree
## is the last moment a node still has the device, so that is when
## `release_compositor` drops it, and the compositor's own RAII frees what it
## holds while the frees still mean something.
static func shared_compositor() -> SaCompositor:
    if _compositor == null:
        _compositor = SaCompositor.new()
        var tree := Engine.get_main_loop() as SceneTree
        if tree != null and not tree.root.tree_exiting.is_connected(release_compositor):
            tree.root.tree_exiting.connect(release_compositor)
    return _compositor


## Lets go of the shared compositor and the last one a render used, so nothing
## static holds a GPU object once the tree has gone. The next render makes a fresh
## one, which is a pipeline load and nothing worse.
static func release_compositor() -> void:
    _compositor = null
    last_compositor = null


## One stroke, or one dab when *one_dab* is set, with *settings* on a throwaway
## document of *render_size*, answered at that size as an 8-bit image. Null when
## nothing could be drawn. Every event in one call, through the `Paint` a
## `Drawing` sends a few events a frame.
static func _paint(tool_script: Script, settings: Resource, render_size: Vector2i, one_dab: bool) -> Image:
    var paint := Paint.new(tool_script, settings, render_size, one_dab)
    while not paint.step():
        pass
    return paint.image


## Sends *painter* the whole stroke `_events` lists, moving *view* before each
## event.
static func _stroke(painter: ToolState, view: ThumbView, size: Vector2i, one_dab: bool = false) -> void:
    var events := _events(size, one_dab)
    for index in events.size():
        _send(painter, view, events[index], index)


## Moves *view* to where *sent* says the pointer is and hands *painter* the event,
## the *index*th of its stroke, with the pen clock held at that event's time.
##
## **The time is the event's place in the stroke, not the wall's.** A brush
## whose curves read speed, the Bristle Flat's Drift, reads it off the clock
## between events, and the wall clock between two events is however long the
## chooser took to come back to the picture, which would put the pace a picture
## is drawn at into the picture, two boots drawing one Bristle Flat apart. Held
## at one frame of [constant SaPenClock.FRAME_MS] an event, a picture is the
## stroke of a hand at sixty events a second, the rate the shipped speed curves
## were drawn at, drawn at once, by shares or in a capture. One time for every
## event, which is what a capture's pinned clock gave a picture drawn whole in a
## frame, reads as a pen at rest, the other end of every speed curve.
static func _send(painter: ToolState, view: ThumbView, sent: Array, index: int) -> void:
    var event: InputEvent = sent[1]
    view.at = sent[0]
    var handled := painter.handle_input.bind(event)
    SaPenClock.held(SaPenClock.after_frames(index), func() -> void: SaStrokeNote.aside(handled))


## The S, left to right, with the pressure up and back down, or one dab in the
## middle at full pressure when *one_dab* is set, as pairs of where the view says
## the pointer is and the event sent there.
##
## The single dab is the brush editor's tip preview, and it goes through this
## rather than through a second easel of its own: what a tip looks like is what
## the dab kernel draws, and a preview that painted its own idea of a mask would
## be a second authority on the tip's shape. The press is at the centre and the
## motion after it does not move, so the walk deposits exactly one.
##
## Two things per step and not one: the tool reads the position off the view and
## the pressure off the event, so the view is moved first and the event pushed
## after it, which is the order the app's own input path uses. The release
## carries no position, and the view stays where the last motion left it.
static func _events(size: Vector2i, one_dab: bool) -> Array[Array]:
    if one_dab:
        return _one_dab_events(size)
    var events: Array[Array] = []
    var at := Vector2.ZERO
    for i in STEPS + 1:
        var t := float(i) / float(STEPS)
        at = _point_at(t, size)
        if i == 0:
            events.append([at, _press(at)])
            continue
        var motion := InputEventMouseMotion.new()
        motion.pressure = _pressure_at(t)
        motion.position = at
        motion.global_position = at
        events.append([at, motion])
    events.append([at, _release()])
    return events


## One dab at the middle of a *size* square, at full pressure.
##
## A press and one motion that does not move: the press opens the stroke and the
## motion is what carries the pressure, which is the same pair the capture
## harness has to send for the same reason. The tilt is left at nothing, so a tip
## the sensors turn shows the turn the settings ask for rather than one this
## function chose.
static func _one_dab_events(size: Vector2i) -> Array[Array]:
    var centre := Vector2(float(size.x) * 0.5, float(size.y) * 0.5)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    motion.position = centre
    motion.global_position = centre
    return [[centre, _press(centre)], [centre, motion], [centre, _release()]]


static func _press(at: Vector2) -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    press.global_position = at
    return press


static func _release() -> InputEventMouseButton:
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    return release


## Where the stroke is at *t*, as document pixels of a *size* strip.
##
## A sine rather than a spline: one S over the width, inset by a fifth of the
## height at each end so a fat brush is not clipped by the strip's own edge.
static func _point_at(t: float, size: Vector2i) -> Vector2:
    var inset := float(size.y) * 0.28
    var x := inset + t * (float(size.x) - 2.0 * inset)
    var y := float(size.y) * 0.5 - sin(t * TAU) * (float(size.y) * 0.5 - inset)
    return Vector2(x, y)


## Zero at both ends and one in the middle, which is what makes a thumbnail show
## a taper rather than a bar.
static func _pressure_at(t: float) -> float:
    return sin(t * PI)
