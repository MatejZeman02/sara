## The Environment view: the document seen from inside, as the sky, for a
## document whose projection is a sphere, and seen as its disc for one whose
## projection is a disc: a camera direction, yaw and pitch, and a field of view,
## dragged with the pan tool, and a CanvasItem shader that maps each screen
## pixel to a direction and samples the equirectangular output.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What it draws.** The easel's output, the texture the flat canvas shows,
## over the whole canvas area through a shader composed from the flat canvas's
## own: `Composer` puts `sa_environment.gdshaderinc` ahead of its `fragment` and
## the position the camera finds in place of UV, so the roll-off, the soft proof
## and False Colour, and a module's view mode, run after it as they are. It costs
## screen pixels and no dispatch. While it is on the easel composites the whole
## document, since any of it can be on screen, which `SaCanvas.shown_in_document`
## asks [method shows] about.
##
## **The kind's map.** The shader reads a small table of `SaProjection.from_view`
## over a grid of directions, built in [Lookup] when the projection or the size
## changes, so the view asks the kind and names none, as every reader of a
## projection does.
##
## **The camera.** Whatever moves the flat view moves the camera instead: a pan
## turns it and a zoom narrows or widens the field of view. The flat view's own
## pan and zoom are taken when the view goes on and put back when it goes off,
## so the painter comes back to the flat picture as it was. Nothing the document
## stores changes, because the view is an everyday button and not an edit.
##
## **The disc.** A kind whose view is a disc says where the disc lies on the
## flat canvas, `SaProjection.plane`, and the view draws it through the flat
## view's own pan, zoom, turn and mirror, so every gesture moves the disc the
## way it moves the flat picture. The view fits the whole disc in the frame
## when it goes on and puts the flat view back when it goes off. The shader is
## told the view is a plane and reads the same table, laid over the disc in
## angle and radius, and draws nothing past the rim. The pointer, the ring and
## the stretch below read the disc through the same map, so a stroke round the
## disc is a row of the document and a dab at its centre folds as at a pole.
##
## **Painting.** The pointer is the document pixel the camera's ray through it
## lands on, by the kind's own `from_view`, which [method pointer] answers to
## `SaCanvasView.get_document_mouse_position`, so every tool that asks the
## pointer paints, samples and fills on the sky with no code of its own. A
## painting tool's readings during a stroke are taken the short way round the
## seam by [Trail], so a stroke across the back of the sphere crosses the seam
## rather than the canvas, and the paint context lands each dab past an edge
## at the other. The ring is drawn round the dab under the pointer, by
## [method ring_scale]. The dab is round on the sphere: the brush stretches it
## in the document's x by the kind's stretch at its centre, which
## [method dab_stretch] answers, and lands a dab past a pole folded over it.
##
## **The seam.** The flat view of a wrapping document draws where it joins
## itself as a faint guide down both edges, [Seam], a child of the canvas the
## sky covers while this view is on.
class_name SaEnvironmentView
extends Control

## Emitted when the view goes on or off, for the buttons that show it.
signal switched(shown: bool)

## The node's name beside the canvas, which [method of_canvas] finds it by.
const NODE_NAME := "EnvironmentView"

## The flat zoom the view keeps the hidden canvas inside while it is on, so a
## zoom gesture always has room to change the field of view. `SaView.zoom_at`
## stops at `ZOOM_MIN` and `ZOOM_MAX`, and a view turned on at either end would
## zoom one way only.
const FLAT_ZOOM_ROOM := Vector2(0.05, 20.0)

## The command its key runs, on the Keyboard Shortcuts page with the others.
const COMMAND := &"view_environment"

## The camera this view looks through, written by its own methods.
var camera := Camera.new()

var _canvas: SaCanvas = null
## The canvas's flat view, the one every gesture moves, which this view reads
## its camera's moves off and puts back as it was.
var _flat_view: SaCanvasView = null
## Whether the sky is shown, written by `set_on` alone.
var on: bool = false
## The flat view as it stood when this view went on, put back when it goes off.
var _flat: Flat = null
## The flat view as it stood after the last move this view turned into a camera
## move, which the next move is measured from.
var _last: Flat = null
## The document this view went on over. Another one in the canvas turns it off.
var _document: SaDocument = null
var _settle_queued: bool = false
## True while this view moves the flat view itself, so it does not hear its own
## move as a gesture.
var _quiet: bool = false
var _trail := Trail.new()
var _sky: Dome = null
var _composer := Composer.new()
var _lookup := Lookup.new()


## The canvas is a constructor argument, the privates rule. Defaulted so that
## `.new()` still works the way Godot expects of a Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas
    _flat_view = canvas.view() if canvas != null else null
    name = NODE_NAME


## Puts the view beside *canvas* under *host*, the window-space control the main
## surface routes its input through, right above the canvas so whatever else is
## drawn over the canvas is drawn over the sky too. The surface overlay factory.
static func attach_to(host: Control, canvas: SaCanvas) -> SaEnvironmentView:
    var view := SaEnvironmentView.new(canvas)
    host.add_child(view)
    if canvas != null:
        canvas.add_child(Seam.new(canvas))
        if canvas.get_parent() == host:
            host.move_child(view, canvas.get_index() + 1)
    return view


## The view beside *canvas*, or null on a canvas that has none, a scratchpad's.
static func of_canvas(canvas: SaCanvas) -> SaEnvironmentView:
    if canvas == null or canvas.get_parent() == null:
        return null
    return canvas.get_parent().get_node_or_null(NODE_NAME) as SaEnvironmentView


## The view of the document the painter is working on, the one a button on the
## top bar drives, wherever the button sits. The front surface's canvas rather
## than the main window's, since every open document's tab will stand in that
## one window.
static func main() -> SaEnvironmentView:
    return of_canvas(SaCanvasView.front_canvas())


## The command that turns the main canvas's view on and off, on its key, P,
## in the View category of the Keyboard Shortcuts page. The top bar's button
## is the other door to the same switch.
static func register_command(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(COMMAND, "Switch between the flat view and the environment view", _toggle_main)
    command.label = "Environment View"
    var key := InputEventKey.new()
    key.keycode = KEY_P
    command.default_events = [key]
    command.category = &"view"
    command.sentence = "Look at a panorama from inside or a disc face on, the way it will be seen, and back to the flat picture."
    command.checked = func() -> bool: return _main_is_on()
    command.enabled = func() -> bool: return _main_can()
    ctx.register_command(command)


static func _toggle_main() -> bool:
    var view := main()
    return view != null and view.toggle()


static func _main_is_on() -> bool:
    var view := main()
    return view != null and view.on


static func _main_can() -> bool:
    var view := main()
    return view != null and view.refusal().is_empty()


## Whether *canvas* is shown as the sky right now.
static func shows(canvas: SaCanvas) -> bool:
    var view := of_canvas(canvas)
    return view != null and view.on


## Why *document* cannot be seen from inside or as its disc, in words for a
## tooltip, or empty when it can. A kind whose view is a sphere or a disc can,
## whatever it is called.
static func refusal_for(document: SaDocument) -> String:
    if document == null:
        return TranslationServer.translate("There is no document to look at.")
    if document.projection.kind.view != SaProjection.View.CANVAS:
        return ""
    return TranslationServer.translate(
        "The document is flat. Assign a panorama under Image > Projection... to look at it from inside."
    )


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_PASS
    _sky = Dome.new(_shown_texture)
    _sky.material = _composer.material
    add_child(_sky)
    visible = false
    set_process(false)


## Why the canvas's document cannot be seen from inside, or empty.
func refusal() -> String:
    return refusal_for(_canvas_document())


func _canvas_document() -> SaDocument:
    return _canvas.document if _canvas != null else null


## Turns the view on or off and answers whether that changed anything. Refused,
## and false, for a document [method refusal] names a reason for.
func set_on(wanted: bool) -> bool:
    if wanted == on or _canvas == null or (wanted and not refusal().is_empty()):
        return false
    var view := _flat_view
    on = wanted
    if wanted:
        _document = _canvas_document()
        _flat = Flat.of(view)
        if _shows_disc():
            _fit_disc(view)
        else:
            _keep_zoom_room(view)
        view.transform_changed.connect(_on_view_moved)
    else:
        view.transform_changed.disconnect(_on_view_moved)
        if _canvas_document() == _document:
            _quiet = true
            _flat.put_back(view)
            _quiet = false
        _document = null
    visible = wanted
    set_process(wanted)
    if wanted:
        _sync()
    _canvas.request_composite()
    switched.emit(wanted)
    return true


## Flat to Environment or back, the button's and the shortcut's one act.
func toggle() -> bool:
    return set_on(not on)


## The part of this view the dockers and the bar leave uncovered, in its own
## coordinates, whose middle the camera looks through and whose height the
## field of view spans: the room a flat fit centres the document in, so the
## middle of the sky is where the middle of the flat picture was. The whole
## view when nothing says otherwise.
func frame() -> Rect2:
    var whole := Rect2(Vector2.ZERO, size)
    if _canvas == null or not is_inside_tree():
        return whole
    var uncovered := _flat_view.get_free_rect()
    uncovered.position -= get_global_rect().position
    var shown := whole.intersection(uncovered)
    return shown if shown.size.x >= 1.0 and shown.size.y >= 1.0 else whole


func _process(_delta: float) -> void:
    if _canvas_document() != _document:
        # A document opened or made over this one: its own flat view is the one
        # it was fitted with, and the one taken here belongs to another picture,
        # so the switch goes off without putting it back.
        set_on(false)
        return
    if not refusal().is_empty():
        set_on(false)
        return
    _sync()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED and on:
        _follow_resize.call_deferred()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), RenderingServer.get_default_clear_color())


## The left button's press and release, wherever they land, so [Trail] knows
## when a stroke starts and ends. Heard ahead of the surface, whose own `_input`
## carries a held stroke's release to the tool after this.
func _input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if not on or button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return
    if button.pressed:
        _trail.press()
    else:
        _trail.lift(Engine.get_process_frames())


## The document pixel the camera's ray through *point*, in this view's own
## coordinates, lands on: the kind's `from_view` of the direction the shader
## draws there, read exactly rather than through the shader's table. Inside the
## canvas, whatever the camera faces: a ray straight down the seam can come back
## a whole width across, the far edge rather than the near one, and is taken
## back to the near one.
func pixel_at(point: Vector2) -> Vector2:
    var document := _canvas_document()
    if document == null:
        return Vector2.ZERO
    var shape := Vector2(document.canvas_size)
    var at := document.projection.from_view(_view_position(point), shape)
    if document.projection.wrapping != SaProjection.Wrap.NONE and at.x >= shape.x:
        at.x -= shape.x
    return at


## The pointer in document pixels, what a tool reads in this view. A painting
## tool's reading during a stroke is the copy of [method pixel_at] one or more
## widths across that lies nearest the last, so a stroke drawn across the seam
## goes through it, and the paint context lands the part past the edge at the
## other. Every other reading is inside the canvas.
func pointer() -> Vector2:
    return _trail.follow(pixel_at(SaCursorPolicy.pointer_in(self)), _seam_width(), Engine.get_process_frames())


## Where a straight line from *from* to *to*, in document pixels, ends in this
## view: the copy of *to* the short way round the seam from *from*, for a
## painting tool on a document that wraps, which is how a Shift click's line
## crosses the seam.
func line_towards(from: Vector2, to: Vector2) -> Vector2:
    return Trail.nearest(to, from, _seam_width())


## How many times wider in the document's x a dab centred at *pixel* is drawn
## so it is round on the sky, the kind's stretch there, infinite at a pole and
## capped where the dab is shaped, `SaProjection.Stretched`.
func dab_stretch(pixel: Vector2) -> float:
    var document := _canvas_document()
    return document.projection.stretch(pixel, Vector2(document.canvas_size)) if document != null else 0.0


## Whether *at*, a point in the window's viewport, is on the sky.
func covers(at: Vector2) -> bool:
    var local := get_global_transform().affine_inverse() * at
    return on and Rect2(Vector2.ZERO, size).has_point(local)


## How many times the flat ring's radius the ring at *at*, a point in the
## window's viewport, is drawn on *canvas*: one while the canvas is shown flat,
## and over the sky or the disc enough to hold the dab the pointer lands there.
## That is the height a document pixel is drawn there, the dab's own axis,
## which the stretch leaves as it is while it makes the dab as wide on screen
## as it is tall. Where a document pixel is drawn wider than tall, near the rim
## of a disc shorter round than the document is wide, the dab is narrowed
## across and the height is still its size.
static func ring_scale(canvas: SaCanvas, at: Vector2) -> float:
    var view := of_canvas(canvas)
    var document := view._canvas_document() if view != null and view.on else null
    if document == null:
        return 1.0
    var turned := view.get_global_transform()
    var local := turned.affine_inverse() * at
    var here := view.pixel_at(local)
    var width := float(maxi(document.canvas_size.x, 1))
    var across := Trail.nearest(view.pixel_at(local + Vector2.RIGHT), here, width) - here
    var down := Trail.nearest(view.pixel_at(local + Vector2.DOWN), here, width) - here
    # The second column of the inverse of the map from screen to document,
    # whose columns are *across* and *down*: the screen pixels one document
    # row takes.
    var spread := absf(across.x * down.y - across.y * down.x)
    var tall := sqrt(across.x * across.x + down.x * down.x) / maxf(spread, 1e-12)
    var flat_zoom := maxf(view._flat_view.get_zoom(), 1e-6)
    return turned.get_scale().x * tall / flat_zoom


## Whether the tool in hand paints, the tools the paint context lands past an
## edge, so the only ones whose readings may leave the canvas.
func _tool_paints() -> bool:
    var machine := _canvas.tool_machine() if _canvas != null else null
    if machine == null:
        return false
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    return descriptor != null and descriptor.is_painting


## The width a painting tool's readings are taken the short way round, or
## nought when they stay inside the canvas: for any other tool, and for a
## document that does not wrap across.
func _seam_width() -> float:
    var document := _canvas_document()
    if document == null or document.projection.wrapping == SaProjection.Wrap.NONE or not _tool_paints():
        return 0.0
    return float(document.canvas_size.x)


## The flat view moved, by a gesture, a tool or a menu. Read once the frame's
## moves are all in, because a zoom about a point is a zoom and then a pan, and
## only together do they say it was a zoom.
func _on_view_moved() -> void:
    if _quiet or not on or _settle_queued:
        return
    _settle_queued = true
    _settle.call_deferred()


## Turns the flat view's move into the camera's: a change of zoom changes the
## field of view, a pan with the zoom, the turn and the mirror as they were
## turns the camera, and a turn or a mirror of the flat view does nothing here.
## A disc is drawn through the flat view as it stands, so its moves are the
## disc's own and none is a camera's.
func _settle() -> void:
    _settle_queued = false
    if not on:
        return
    var view := _flat_view
    var now := Flat.of(view)
    if _shows_disc():
        _last = now
        _sync()
        return
    if not is_equal_approx(now.zoom, _last.zoom):
        camera.magnify(now.zoom / _last.zoom)
    elif is_equal_approx(now.rotation, _last.rotation) and now.flip == _last.flip:
        camera.turn(now.pan - _last.pan, frame().size.y)
    _last = now
    _keep_zoom_room(view)
    _sync()


## Whether the canvas's document is seen as a disc rather than as the sky.
func _shows_disc() -> bool:
    var document := _canvas_document()
    return document != null and document.projection.kind.view == SaProjection.View.DISC


## The map from this view's own coordinates to the kind's plane, through the
## flat canvas's pan, zoom, turn and mirror, which lay out the document pixels
## the kind's `plane` starts from.
func plane_map() -> Transform2D:
    var document := _canvas_document()
    if document == null:
        return Transform2D.IDENTITY
    var to_canvas := _canvas.get_global_transform().affine_inverse() * get_global_transform()
    return document.projection.plane(Vector2(document.canvas_size)) * to_canvas


## The kind's view position under *point*, in this view's coordinates: the
## camera's ray through it, or the point of a disc under it.
func _view_position(point: Vector2) -> Vector3:
    if _shows_disc():
        var on_disc := plane_map() * point
        return Vector3(on_disc.x, on_disc.y, 0.0)
    return camera.ray_at(point, frame())


## Zooms the flat view so the whole disc fits the frame and centres it there,
## the way Fit to View fits the flat picture. A disc is as wide at any turn.
func _fit_disc(view: SaView) -> void:
    var document := _canvas_document()
    var onto := document.projection.plane(Vector2(document.canvas_size)).affine_inverse()
    var middle := onto * Vector2.ZERO
    var reach := maxf(onto.basis_xform(Vector2.RIGHT).length(), 1e-6)
    var area := view.get_free_rect()
    _quiet = true
    view.set_zoom(minf(area.size.x, area.size.y) * 0.5 / reach)
    view.set_pan(area.get_center() - view.view_offset(middle))
    _quiet = false
    _last = Flat.of(view)


## Puts the hidden flat zoom back at one when it nears either end of the range,
## and takes the flat view as it then stands as the one the next move is
## measured from.
func _keep_zoom_room(view: SaView) -> void:
    var zoom := view.get_zoom()
    if zoom < FLAT_ZOOM_ROOM.x or zoom > FLAT_ZOOM_ROOM.y:
        _quiet = true
        view.set_zoom(1.0)
        _quiet = false
    _last = Flat.of(view)


## The window changed size, and the canvas moved its picture to keep the middle
## where it was without saying so. The flat view to come back to moves the same
## way, and the move is not a turn.
func _follow_resize() -> void:
    if not on:
        return
    var now := Flat.of(_flat_view)
    _flat.pan += now.pan - _last.pan
    _last = now
    _sync()


## Everything the sky's shader reads, from the canvas's material, the document
## and the camera. Each write is skipped when it would change nothing. The wrap
## is a `bvec2`, which the renderer reads as a whole number's two low bits, one
## for across and two for down: handed an Array it reads nought, and the sky
## blended across the canvas within one cell of the seam.
func _sync() -> void:
    var document := _canvas_document()
    if document == null:
        return
    _composer.follow(_canvas.material as ShaderMaterial)
    var mat := _composer.material
    var shape := Vector2(document.canvas_size)
    var lookup := _lookup.texture_for(document.projection, shape)
    var shown := frame()
    var per_pixel := camera.per_pixel(shown.size.y)
    var whole := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
    var wraps := document.projection.wrapping
    var wanted := {
        &"sa_env_wraps": (1 if wraps != SaProjection.Wrap.NONE else 0) | (2 if wraps == SaProjection.Wrap.XY else 0),
        &"sa_env_lookup": lookup,
        &"sa_env_plane": _shows_disc(),
    }
    wanted.merge(_disc_basis(whole) if _shows_disc() else _camera_basis(shown, whole, per_pixel))
    for key: StringName in wanted:
        if mat.get_shader_parameter(key) != wanted[key]:
            mat.set_shader_parameter(key, wanted[key])
    # Texels of the document per radian down it against the screen's device
    # pixels per radian at the middle, which is where the flat canvas would ask
    # for nearest or linear. On a disc a row is one pixel of the flat canvas
    # outwards, and the flat canvas's own answer holds.
    var window := get_window()
    var device := (window.content_scale_factor if window != null else 1.0) / maxf(per_pixel, 1e-9)
    var texels := device / maxf(shape.y / PI, 1e-6)
    _sky.texture_filter = SaCanvas.filter_for(absf(_canvas.pixels_per_texel()) if _shows_disc() else texels)
    _sky.queue_redraw()


## The camera's basis, and the middle and reach of the frame it looks through,
## as the shader reads them.
func _camera_basis(shown: Rect2, whole: Vector2, per_pixel: float) -> Dictionary:
    var basis := camera.basis()
    return {
        &"sa_env_right": basis.x,
        &"sa_env_up": basis.y,
        &"sa_env_forward": -basis.z,
        &"sa_env_centre": shown.get_center() / whole,
        &"sa_env_reach": whole * per_pixel,
    }


## [method plane_map] in the shader's terms: the drawn rectangle's pixels from
## its top left corner, its columns the right and the negated up, its origin
## the forward vector.
func _disc_basis(whole: Vector2) -> Dictionary:
    var onto := plane_map()
    return {
        &"sa_env_right": Vector3(onto.x.x, onto.x.y, 0.0),
        &"sa_env_up": Vector3(-onto.y.x, -onto.y.y, 0.0),
        &"sa_env_forward": Vector3(onto.origin.x, onto.origin.y, 0.0),
        &"sa_env_centre": Vector2.ZERO,
        &"sa_env_reach": whole,
    }


func _shown_texture() -> Texture2D:
    return _canvas.texture if _canvas != null else null


## Where the camera looks and how wide it sees. Yaw is the azimuth of the middle
## of the view in Godot's frame, from straight ahead, minus z, turning right
## towards x, the way a sphere kind's longitude runs. Pitch is up from the
## horizon, and the field of view is the angle from the top of the view to the
## bottom.
class Camera:
    extends RefCounted

    const FOV_DEFAULT: float = deg_to_rad(75.0)
    const FOV_MIN: float = deg_to_rad(10.0)
    const FOV_MAX: float = deg_to_rad(150.0)

    var yaw: float = 0.0
    var pitch: float = 0.0
    var fov: float = FOV_DEFAULT

    func _init(start_yaw: float = 0.0, start_pitch: float = 0.0, start_fov: float = FOV_DEFAULT) -> void:
        yaw = wrapf(start_yaw, -PI, PI)
        pitch = clampf(start_pitch, -PI * 0.5, PI * 0.5)
        fov = clampf(start_fov, FOV_MIN, FOV_MAX)

    ## Right, up and back, Godot's camera convention, so minus z is where the
    ## middle of the view looks.
    func basis() -> Basis:
        var ahead := Vector3(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
        var right := Vector3(cos(yaw), 0.0, sin(yaw))
        var up := Vector3(-sin(pitch) * sin(yaw), cos(pitch), sin(pitch) * cos(yaw))
        return Basis(right, up, -ahead)

    ## How far one unit ahead a screen pixel reaches, for a field of view
    ## *height* pixels tall.
    func per_pixel(height: float) -> float:
        return 2.0 * tan(fov * 0.5) / maxf(height, 1.0)

    ## The direction through *point* when the view looks through the middle of
    ## *shown* and the field of view spans its height, the same sum
    ## `sa_env_ray` makes in the shader.
    func ray_at(point: Vector2, shown: Rect2) -> Vector3:
        var off := (point - shown.get_center()) * per_pixel(shown.size.y)
        var turned := basis()
        return (-turned.z + turned.x * off.x - turned.y * off.y).normalized()

    ## Turns the way a hand dragging the sky by *drag* screen pixels of a field
    ## of view *height* pixels tall would: the point under the middle of the
    ## view stays under the hand.
    func turn(drag: Vector2, height: float) -> void:
        var step := per_pixel(height)
        yaw = wrapf(yaw - drag.x * step, -PI, PI)
        pitch = clampf(pitch + drag.y * step, -PI * 0.5, PI * 0.5)

    ## Magnifies the view by *factor*, more than one to narrow the field of view
    ## the way a zoom in enlarges the flat picture.
    func magnify(factor: float) -> void:
        if factor <= 0.0:
            return
        fov = clampf(2.0 * atan(tan(fov * 0.5) / factor), FOV_MIN, FOV_MAX)


## The flat view's pan, zoom, turn and mirror at one moment.
class Flat:
    extends RefCounted

    var pan: Vector2
    var zoom: float
    var rotation: float
    var flip: Vector2

    func _init(at_pan := Vector2.ZERO, at_zoom: float = 1.0, at_rotation: float = 0.0, at_flip := Vector2.ONE) -> void:
        pan = at_pan
        zoom = at_zoom
        rotation = at_rotation
        flip = at_flip

    static func of(view: SaView) -> Flat:
        return Flat.new(view.get_pan(), view.get_zoom(), view.get_rotation(), view.get_flip())

    ## Moves *view* back to this. The mirror and the turn first, the zoom, then
    ## the pan, which is where every other part leaves the picture.
    func put_back(view: SaView) -> void:
        view.set_flip(flip)
        view.set_rotation(rotation)
        view.set_zoom(zoom)
        view.set_pan(pan)


## The canvas's shader with the camera ahead of its `fragment`, built again only
## when the canvas's shader changes, and the material it draws with, whose
## parameters follow the canvas material's every frame.
class Composer:
    extends RefCounted

    const INCLUDE := "res://render/environment/sa_environment.gdshaderinc"
    ## What the composed `fragment` opens with: the position under the camera,
    ## the steps to the neighbouring pixels taken the short way round the seam,
    ## nothing past a disc's rim, and the colour there. The steps are taken
    ## before the rim's discard, since a derivative after it is undefined. The
    ## define makes every later UV the camera's.
    const HEAD := """void fragment() {
    vec2 sa_env_raw = sa_env_unwrapped(UV);
    vec2 sa_env_dx = sa_env_step(dFdx(sa_env_raw));
    vec2 sa_env_dy = sa_env_step(dFdy(sa_env_raw));
    if (sa_env_off(UV)) {
        discard;
    }
    vec2 sa_env_uv = sa_env_folded(sa_env_raw, TEXTURE_PIXEL_SIZE);
    COLOR = textureLod(TEXTURE, sa_env_uv, 0.0);
#define UV sa_env_uv
"""
    ## The shader composed over when the canvas has no material of its own yet.
    const BARE := "shader_type canvas_item;\n\nvoid fragment() {\n}\n"

    var material := ShaderMaterial.new()
    var _source: Shader = null
    var _built: bool = false
    var _names: Array[StringName] = []
    ## The include put ahead of `fragment` and the lines that open it, this
    ## view's unless a view of the same maths, the Sphere docker's ball, brings
    ## its own.
    var _include: String
    var _head: String

    func _init(include_path: String = INCLUDE, head: String = HEAD) -> void:
        _include = include_path
        _head = head

    ## Follows *canvas_material*: composes again when its shader is another one,
    ## and copies every parameter that differs.
    func follow(canvas_material: ShaderMaterial) -> void:
        var source := canvas_material.shader if canvas_material != null else null
        if source != _source or not _built:
            if _source != null and _source.changed.is_connected(_forget):
                _source.changed.disconnect(_forget)
            _source = source
            if source != null:
                source.changed.connect(_forget)
            material.shader = compose(source, _include, _head)
            _names = _uniforms(source)
            _built = true
        if canvas_material == null:
            return
        for key: StringName in _names:
            var value: Variant = canvas_material.get_shader_parameter(key)
            if material.get_shader_parameter(key) != value:
                material.set_shader_parameter(key, value)

    func _forget() -> void:
        _built = false

    ## *source*'s code with the include ahead of its `fragment`, the head opening
    ## it, and the derivatives of UV the head's own. A shader with no `fragment`
    ## to open is composed over [constant BARE], so the sky still shows.
    static func compose(source: Shader, include_path: String = INCLUDE, head: String = HEAD) -> Shader:
        var code := source.code if source != null else BARE
        var opening := RegEx.create_from_string("void\\s+fragment\\s*\\(\\s*\\)\\s*\\{")
        var found := opening.search(code)
        if found == null:
            code = BARE
            found = opening.search(code)
        var before := code.substr(0, found.get_start())
        var rest := code.substr(found.get_end())
        var closing := _closing_brace(rest)
        var body := rest.substr(0, closing).replace("dFdx(UV)", "sa_env_dx").replace("dFdy(UV)", "sa_env_dy")
        var after := rest.substr(closing)
        if source != null and not source.resource_path.is_empty():
            before = _absolute_includes(before, source.resource_path.get_base_dir())
        var composed := Shader.new()
        composed.code = '%s#include "%s"\n\n%s%s\n#undef UV\n%s' % [before, include_path, head, body, after]
        return composed

    ## Where the brace that closes `fragment` stands in *rest*, the code after
    ## its opening brace, so the camera's UV ends with it and a `light` after it
    ## reads its own.
    static func _closing_brace(rest: String) -> int:
        var depth := 1
        for at in rest.length():
            var character := rest[at]
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    return at
        return rest.length()

    ## A relative include made absolute, since the composed shader has no
    ## folder of its own to read one from.
    static func _absolute_includes(code: String, folder: String) -> String:
        var relative := RegEx.create_from_string('#include\\s+"(?!res://)([^"]+)"')
        var out := code
        for found: RegExMatch in relative.search_all(code):
            out = out.replace(found.get_string(), '#include "%s"' % folder.path_join(found.get_string(1)))
        return out

    static func _uniforms(source: Shader) -> Array[StringName]:
        var out: Array[StringName] = []
        if source == null:
            return out
        for entry: Dictionary in source.get_shader_uniform_list():
            var uniform: String = entry["name"]
            out.append(StringName(uniform))
        return out


## The kind's map as a table: for each direction of a grid in azimuth and angle
## from the zenith, or each point of a disc's grid in azimuth and radius, the
## document position `SaProjection.from_view` answers, as a fraction of the
## size. Built again when the projection or the size changes, and never while
## the camera moves.
##
## A table rather than the kind's own shader, so a module's kind needs none: an
## equirectangular map is a straight line in both of the grid's angles, and a
## disc's angle across and radius down in its angle and radius, so the shader's
## blend between neighbours gives it back exactly, and a kind that bends is
## followed to a fraction of a degree.
class Lookup:
    extends RefCounted

    const ACROSS: int = 256
    const DOWN: int = 128

    var _projection: SaProjection = null
    var _shape := Vector2.ZERO
    var _texture: ImageTexture = null

    func texture_for(projection: SaProjection, shape: Vector2) -> ImageTexture:
        if _texture == null or projection != _projection or shape != _shape:
            _projection = projection
            _shape = shape
            _texture = ImageTexture.create_from_image(table(projection, shape))
        return _texture

    ## The view position of the grid's cell *cell*, the same angles
    ## `sa_env_cell` reads in the shader: for a sphere the direction at its
    ## azimuth and angle from the zenith, and for a disc the point at its
    ## azimuth from up, turning right, and its fraction of the radius out.
    static func direction(cell: Vector2, view := SaProjection.View.SPHERE) -> Vector3:
        var azimuth := TAU * (cell.x + 0.5) / ACROSS
        var down := (cell.y + 0.5) / DOWN
        if view == SaProjection.View.DISC:
            return Vector3(down * sin(azimuth), down * cos(azimuth), 0.0)
        var zenith := PI * down
        return Vector3(sin(zenith) * sin(azimuth), cos(zenith), -sin(zenith) * cos(azimuth))

    static func table(projection: SaProjection, shape: Vector2) -> Image:
        var values := PackedFloat32Array()
        values.resize(ACROSS * DOWN * 2)
        var safe := Vector2(maxf(shape.x, 1.0), maxf(shape.y, 1.0))
        var view := projection.kind.view
        var at := 0
        for row in DOWN:
            for column in ACROSS:
                var fraction := projection.from_view(direction(Vector2(column, row), view), safe) / safe
                values[at] = fraction.x
                values[at + 1] = fraction.y
                at += 2
        return Image.create_from_data(ACROSS, DOWN, false, Image.FORMAT_RGF, values.to_byte_array())


## The easel's output drawn over the whole view through the composed material.
class Dome:
    extends Control

    var _texture: Callable

    func _init(source: Callable = Callable()) -> void:
        _texture = source
        name = "Dome"
        mouse_filter = MOUSE_FILTER_IGNORE
        texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    func _draw() -> void:
        var shown: Texture2D = _texture.call() if _texture.is_valid() else null
        if shown != null:
            draw_texture_rect(shown, Rect2(Vector2.ZERO, size), false)


## Where a painting tool last read the pointer during a stroke, so the next
## reading is taken the short way round the seam from it. A stroke runs from the
## left button's press to the end of the frame it is let go in, since the tool
## reads the pointer as it handles the release in that frame.
class Trail:
    extends RefCounted

    var _held: bool = false
    var _lifted: int = -1
    ## Whether the last reading was a stroke's, which the next one follows.
    var _going: bool = false
    var _last := Vector2.ZERO

    func press() -> void:
        _held = true
        _going = false

    func lift(frame: int) -> void:
        _held = false
        _lifted = frame

    ## *at*, read in process frame *frame*, as the stroke goes on: the copy of
    ## it [method nearest] the last reading while a stroke runs, and *at* itself
    ## for a stroke's first reading, between strokes, and for a width of nought.
    func follow(at: Vector2, width: float, frame: int) -> Vector2:
        var stroke := _held or frame == _lifted
        var out := nearest(at, _last, width) if stroke and _going else at
        _going = stroke
        _last = out
        return out

    ## The copy of *at* a whole number of *width* across that lies nearest
    ## *near*, or *at* itself for a width of nought.
    static func nearest(at: Vector2, near: Vector2, width: float) -> Vector2:
        if width <= 0.0:
            return at
        return Vector2(at.x + roundf((near.x - at.x) / width) * width, at.y)


## The flat view's guide to where a wrapping document joins itself: a faint
## dashed hairline down its left and right edges, and along its top and bottom
## too for a kind that wraps both ways. A child of the canvas, so it draws in
## document pixels and follows the zoom, the turn and the mirror the way the
## grid does, and the sky drawn over the canvas hides it.
class Seam:
    extends Control

    const NODE_NAME := "SeamGuide"
    ## One dash, and the gap after it, in screen pixels at any zoom.
    const DASH: float = 6.0
    const LIGHT := Color(1.0, 1.0, 1.0, 0.5)
    const DARK := Color(0.0, 0.0, 0.0, 0.3)

    var _host: SaCanvas = null
    ## The wrap, the document's size and the zoom the guide was last drawn for.
    var _drawn: Array = []

    func _init(host: SaCanvas = null) -> void:
        _host = host
        name = NODE_NAME
        mouse_filter = MOUSE_FILTER_IGNORE

    func _process(_delta: float) -> void:
        var wanted := _wanted()
        if wanted != _drawn:
            _drawn = wanted
            queue_redraw()

    func _wanted() -> Array:
        var document := _host.document if _host != null else null
        if document == null or document.projection.wrapping == SaProjection.Wrap.NONE:
            return []
        return [document.projection.wrapping, Vector2(document.canvas_size), maxf(absf(_host.scale.x), 1e-3)]

    ## The lines along the edges the document wraps across, in document pixels
    ## and half a screen pixel in, so each falls on the canvas's outer pixels.
    ## None for a document that does not wrap.
    func lines() -> Array[PackedVector2Array]:
        var out: Array[PackedVector2Array] = []
        var wanted := _wanted()
        if wanted.is_empty():
            return out
        var shape: Vector2 = wanted[1]
        var zoom: float = wanted[2]
        var inset: float = 0.5 / zoom
        for x: float in [inset, shape.x - inset]:
            out.append(PackedVector2Array([Vector2(x, 0.0), Vector2(x, shape.y)]))
        if wanted[0] == SaProjection.Wrap.XY:
            for y: float in [inset, shape.y - inset]:
                out.append(PackedVector2Array([Vector2(0.0, y), Vector2(shape.x, y)]))
        return out

    func _draw() -> void:
        var zoom: float = _drawn[2] if not _drawn.is_empty() else 1.0
        var dash: float = DASH / zoom
        for line: PackedVector2Array in lines():
            draw_line(line[0], line[1], DARK, -1.0)
            draw_dashed_line(line[0], line[1], LIGHT, -1.0, dash)
