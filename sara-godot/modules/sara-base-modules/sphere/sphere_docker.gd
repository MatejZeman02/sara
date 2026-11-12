## The Sphere docker: the panorama on a small ball seen from outside, for
## judging it as a light source, turned by a drag inside it.
##
## **A second shader of the Environment view's maths**, and no 3D scene. The
## ball is one polygon drawn through the material
## `SaEnvironmentView.Composer` composes over the canvas's own shader, with
## `sa_sphere.gdshaderinc` in place of the view's include: the same camera
## basis, the same kind's map read from the same lookup table, and the
## roll-off, the soft proof and False Colour after it as the canvas has them.
## It reads the easel's output through a Texture2DRD and asks for no
## composite of its own, so it costs the pixels it covers and no dispatch.
##
## **It follows the document as it is painted**: a stroke is composited where
## the canvas shows it, into the one output this ball reads, so the ball has
## it with the frame the canvas asks for.
##
## **Mirror-like.** A globe painted on its outside reads backwards, its
## longitude running right to left. This ball shows at each point the direction
## the view from inside shows at the same place, so the picture reads the way
## the document does, a word left to right, longitude nought facing the viewer
## at turn nought in Godot's orientation.
##
## **Its words ask for their room in a longer language.** In English the
## docker ships at 150 by 240 and its title and sentence stand whole in it, so
## nothing there moves. A translation longer than English would break the
## one-word title inside itself and cut the sentence, so where the words are not
## English the title keeps its one line and the sentence asks for every line it
## has, and the window, which wraps its controls, grows to hold them.
##
## **Hidden until asked**, as the pop-up palette is: a fresh profile leaves it
## closed, `DockerLayoutStore.HIDDEN_UNTIL_ASKED`, and the Window menu's row
## opens it. On a document that is not a sphere it says so in a sentence in
## place of the ball.
##
## Registered by `module.gd` beside it through `SaContext.register_docker`, the
## call every module's docker makes (hard rule 6). No script of the skeleton
## names this file, and the shipped layouts and a painter's saved one find the
## docker by the id below.
@tool
extends DockerWindow

## The docker's id, the section `docker_layout.cfg` files its window under. A
## stored layout names its window by this id, so it stays the one the shipped
## layouts were written with and an older profile's layout opens the docker.
const DOCKER_ID := &"SphereDocker"

## What the docker opens at under a layout with no section for it, and the
## place the shipped default gives it, the free strip right of the pop-up
## palette and under Info.
const DEFAULT_SIZE := Vector2i(150, 240)
const DEFAULT_POSITION := Vector2i(750, 600)

## The include the ball's material is composed with, the view's own and the
## ball's ray beside it, found beside this file so a copy of the folder
## composes with its own. Named and never preloaded: the boot compiles this
## script on the loader's worker, and a resource that is not a script
## preloaded there is a nested load whose token Godot 4.7 leaves alive at exit,
## two leaked objects in every run's log.
const INCLUDE_NAME := "sa_sphere.gdshaderinc"

## The ball, with its camera, its material and its drag.
var ball: Ball = null

## The path of `INCLUDE_NAME` beside this script, the one the composer reads.
var include_path: String = ""

## The sentence shown in place of the ball on a document that is not a sphere.
var sentence: Label = null

## The surface the ball shows. Null means the document the painter is working
## on, which is what the Window menu's docker shows, and a suite hands in one
## of its own.
var _surface: SaSurface = null


## The ball: the output on a disc through the composed material, turned by a
## drag that starts on the disc. An inner class because it is the docker's
## drawing and nothing else draws one.
class Ball:
    extends Control

    ## A field of view of a right angle makes the ball's turn the view's own
    ## sum: a drag across the diameter turns it by the tangent of half of it
    ## times two, which is one radian per radius at the middle, so the point
    ## under the middle stays under the hand there.
    const FOV: float = PI * 0.5

    ## Sides of the polygon the disc is drawn as, enough that its rim reads
    ## as round at the sizes a docker gives it.
    const SIDES: int = 96

    ## Room left between the disc and the edge of the docker, in logical pixels.
    const INSET: float = 4.0

    ## Where the ball looks: yaw, the longitude at its middle in Godot's frame,
    ## and pitch, up from the horizon.
    var camera := SaEnvironmentView.Camera.new(0.0, 0.0, FOV)

    ## The canvas's shader with the ball's maths ahead of `fragment`.
    var composer: SaEnvironmentView.Composer = null

    var _lookup := SaEnvironmentView.Lookup.new()
    var _shown: Texture2DRD = null
    var _bound_rid := RID()
    var _turning: bool = false
    var _rim: Control = null

    func _init(include_path: String) -> void:
        name = "Ball"
        mouse_filter = MOUSE_FILTER_STOP
        # The lookup's position is folded back inside the document, but the
        # filter's taps beside the seam reach past it.
        texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
        composer = SaEnvironmentView.Composer.new(include_path, head())
        material = composer.material
        # A child, so the rim is drawn without the ball's material.
        _rim = Control.new()
        _rim.name = "Rim"
        _rim.mouse_filter = MOUSE_FILTER_IGNORE
        _rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _rim.draw.connect(_draw_rim)
        add_child(_rim)
        resized.connect(_rim.queue_redraw)

    ## The view's head with the ball's position read in place of the camera's
    ## through the screen, so the two can never differ in the rest.
    static func head() -> String:
        var head_of_view := SaEnvironmentView.Composer.HEAD
        assert(head_of_view.contains("sa_env_unwrapped(UV)"), "the Environment view's head no longer reads sa_env_unwrapped")
        return head_of_view.replace("sa_env_unwrapped(UV)", "sa_ball_unwrapped(UV)")

    ## The square the disc stands in, centred in the control.
    func disc() -> Rect2:
        var side := maxf(minf(size.x, size.y) - 2.0 * SaUI.pxf(INSET), 1.0)
        return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))

    ## Whether *point*, in the control's own pixels, is on the disc.
    func on_disc(point: Vector2) -> bool:
        var square := disc()
        return point.distance_to(square.get_center()) <= square.size.x * 0.5

    ## The direction the ball shows at *point*, the sum `sa_ball_ray` makes in
    ## the shader, or the rim's on a point off the disc.
    func ray_at(point: Vector2) -> Vector3:
        var square := disc()
        var across := (point - square.get_center()) / (square.size.x * 0.5)
        across.y = -across.y
        var depth := sqrt(maxf(1.0 - across.length_squared(), 0.0))
        var turned := camera.basis()
        return (-turned.z * depth + turned.x * across.x + turned.y * across.y).normalized()

    ## Turns the ball the way a hand dragging its middle by *drag* pixels would.
    func turn(drag: Vector2) -> void:
        camera.turn(drag, disc().size.x)
        _aim()

    ## Shows *surface*'s document: its canvas's shader composed again when it is
    ## another one, the easel's output bound again when it was replaced, the
    ## kind's map, and a filter for the texels a pixel covers at the middle of
    ## the ball.
    func follow(surface: SaSurface) -> void:
        var document := surface.get_document()
        composer.follow(SaInHand.Canvas.shader(surface))
        var output := SaInHand.Canvas.output_rid(surface)
        if output.is_valid() and output != _bound_rid:
            _shown = Texture2DRD.new()
            _shown.texture_rd_rid = output
            _bound_rid = output
            queue_redraw()
        var shape := Vector2(document.canvas_size)
        var wraps := document.projection.wrapping
        # A `bvec2` reaches the renderer as a whole number's low bits, as the
        # Environment view hands it. An Array reads as nought, so the lookup's
        # cell at the seam would blend across the whole document and draw a
        # band of the canvas's middle down the ball.
        var wanted := {
            &"sa_env_wraps": (1 if wraps != SaProjection.Wrap.NONE else 0) | (2 if wraps == SaProjection.Wrap.XY else 0),
            &"sa_env_lookup": _lookup.texture_for(document.projection, shape),
        }
        for key: StringName in wanted:
            if composer.material.get_shader_parameter(key) != wanted[key]:
                composer.material.set_shader_parameter(key, wanted[key])
        _aim()
        # Device pixels per radian at the middle of the ball against the
        # document's texels per radian down it, as the view itself asks.
        var window := get_window()
        var device := (window.content_scale_factor if window != null else 1.0) * disc().size.x * 0.5
        var wanted_filter := SaInHand.Canvas.texture_filter_for(device / maxf(shape.y / PI, 1e-6))
        if texture_filter != wanted_filter:
            texture_filter = wanted_filter

    ## Writes the camera's basis where the shader reads it, when it moved.
    func _aim() -> void:
        var turned := camera.basis()
        var wanted := {&"sa_env_right": turned.x, &"sa_env_up": turned.y, &"sa_env_forward": -turned.z}
        var moved := false
        for key: StringName in wanted:
            if composer.material.get_shader_parameter(key) != wanted[key]:
                composer.material.set_shader_parameter(key, wanted[key])
                moved = true
        if moved:
            queue_redraw()

    func _draw() -> void:
        if _shown == null:
            return
        var square := disc()
        var centre := square.get_center()
        var radius := square.size.x * 0.5
        var points := PackedVector2Array()
        var uvs := PackedVector2Array()
        for side in SIDES:
            var angle := TAU * float(side) / SIDES
            var point := centre + Vector2(cos(angle), sin(angle)) * radius
            points.append(point)
            uvs.append((point - square.position) / square.size)
        draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, _shown)

    func _draw_rim() -> void:
        if _shown == null:
            return
        var square := disc()
        _rim.draw_arc(square.get_center(), square.size.x * 0.5, 0.0, TAU, SIDES, SaTheme.palette.border_secondary, 1.5, true)

    func _gui_input(event: InputEvent) -> void:
        var button := event as InputEventMouseButton
        if button != null and button.button_index == MOUSE_BUTTON_LEFT:
            _turning = button.pressed and on_disc(button.position)
            accept_event()
            return
        var motion := event as InputEventMouseMotion
        if motion != null and _turning:
            turn(motion.relative)
            accept_event()


func _init(surface: SaSurface = null) -> void:
    _surface = surface
    include_path = (get_script() as Script).resource_path.get_base_dir().path_join(INCLUDE_NAME)
    _init_docker(DOCKER_ID, tr("Sphere"), DEFAULT_SIZE, Vector2i(120, 150))
    position = DEFAULT_POSITION

    var column := SaMake.column(_control_node, "VBoxContainer")
    column.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar(tr("Sphere"))
    column.add_child(drag_handle)

    var margin := SaMake.margin(column, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    ball = Ball.new(include_path)
    ball.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ball.size_flags_vertical = Control.SIZE_EXPAND_FILL
    margin.add_child(ball)

    sentence = Label.new()
    sentence.name = "Sentence"
    sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # Cut rather than asking for its whole height, which grows a docker 150
    # wide to past half again its height. The sentence stands whole at the size
    # the docker ships at, a smaller docker ends it with the mark, and the
    # tooltip has the whole of it and where to make the document one.
    # A translation asks for its whole height instead, in `fit_words`.
    sentence.text_overrun_behavior = SaTheme.TEXT_CUT
    sentence.mouse_filter = Control.MOUSE_FILTER_PASS
    sentence.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    sentence.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sentence.size_flags_vertical = Control.SIZE_EXPAND_FILL
    sentence.visible = false
    margin.add_child(sentence)


func _ready() -> void:
    _setup_docker_ready()
    if not SaInHand.Settings.profile_changed().is_connected(apply_layout_settings):
        SaInHand.Settings.profile_changed().connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(DOCKER_ID)


## The words read again in the locale set now, after `DockerWindow` has put the
## title in it and held it at its English width. Deferred so it comes after.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and drag_handle != null:
        fit_words.call_deferred()


## Gives the title and the sentence the room their words ask for when they are
## not English. A title of one word cannot wrap between words, so it keeps its
## one line, and a title of several is left to wrap between them as every
## docker's does. The sentence asks for its whole height. In English both are
## as they were, the title held and the sentence cut only in a docker made
## smaller than it ships at.
func fit_words() -> void:
    var words := drag_handle.find_child("TitleLabel", true, false) as Label
    if words != null and words.text != title and not words.text.contains(" "):
        words.autowrap_mode = TextServer.AUTOWRAP_OFF
        words.custom_minimum_size.x = 0.0
        # `DockerWindow` holds the English width again on a change of theme,
        # deferred, and this comes after it for the same reason.
        if not words.theme_changed.is_connected(fit_words):
            words.theme_changed.connect(fit_words, CONNECT_DEFERRED)
    var document := _shown_document()
    var english := refusal_for(document, _as_written)
    var translated := refusal_for(document) != english
    sentence.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if translated else SaTheme.TEXT_CUT
    # The window keeps the size it was given, so it is asked to take its
    # column's width and height once the labels have been measured again.
    if is_inside_tree() and (translated or words != null and words.autowrap_mode == TextServer.AUTOWRAP_OFF):
        _grow_to_words.call_deferred()


func _grow_to_words() -> void:
    enforce_column_minimum()
    grow_to_content()


## Why *document* has no ball to show, in a sentence short enough to stand
## whole in the docker at the size it ships at, or empty when it is a sphere.
## A flat one is told the Sphere shows panoramas, and so is a disc. *said*
## puts each message into words, the catalogue's by default, and `fit_words`
## hands in one that keeps the English to tell a translation by.
static func refusal_for(document: SaDocument, said: Callable = TranslationServer.translate) -> String:
    if document == null:
        return said.call("There is no document to show.")
    var kind := document.projection.kind
    if kind.view == SaProjection.View.SPHERE:
        return ""
    if kind.view == SaProjection.View.CANVAS:
        return said.call("The Sphere shows panoramas, and this one is flat.")
    return String(said.call("The Sphere shows panoramas, and this one is %s.")) % [String(said.call(kind.label)).to_lower()]


## A message as it is written in the source, the English.
static func _as_written(message: StringName) -> String:
    return String(message)


## Where a document the Sphere refuses is made one it shows, for the
## sentence's tooltip, or empty when there is no document to make one of.
static func hint_for(document: SaDocument) -> String:
    if document == null or document.projection.kind.view == SaProjection.View.SPHERE:
        return ""
    return TranslationServer.translate("Image > Projection... makes it equirectangular, and the Sphere shows it then.")


## The document the docker shows this frame, or null when there is none.
func _shown_document() -> SaDocument:
    var surface := shown_surface()
    return SaSurface.document_of(surface)


## The surface the ball shows this frame, the one handed in or the front one,
## so the ball follows the document brought forward.
func shown_surface() -> SaSurface:
    if _surface != null:
        return _surface
    return SaInHand.Canvas.front() if is_inside_tree() else null


## Shows the ball or the sentence for the document as it stands now. Polled
## while the docker is open, as the Minimap is, because the document, its kind
## and the easel's output are each replaced under the docker by a File New,
## an Image > Projection... or a resize, and none of them is told of it.
func sync() -> void:
    var surface := shown_surface()
    var document := SaSurface.document_of(surface)
    var refusal := refusal_for(document)
    if sentence.text != refusal:
        sentence.text = refusal
        fit_words()
        var hint := hint_for(document)
        sentence.tooltip_text = refusal if hint.is_empty() else "%s\n%s" % [refusal, hint]
    sentence.visible = not refusal.is_empty()
    ball.visible = refusal.is_empty()
    if ball.visible:
        ball.follow(surface)


func _process(_delta: float) -> void:
    if visible:
        sync()
