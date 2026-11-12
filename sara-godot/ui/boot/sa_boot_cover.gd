## The picture over the main window while it builds, with a line that says
## what is loading.
##
## Dockers popping in one by one read to a painter as an error, as though Sara
## would not load at all. So a quit keeps a picture of the window,
## `keep_the_session`, and the next boot covers the main window with it, blurred and fogged by `boot_cover.gdshader`, under a thin
## progress line that names each stage in a painter's words. On
## `boot_finished` the cover waits for the layout's first fit, fades and frees
## itself, and says so with `gone`, which is what a command line's document and
## a recovery offer wait for.
##
## A `CanvasLayer` above the one the engine draws embedded windows on, so a
## docker built under it stays under it, and it takes no input: a click during
## the boot goes where it would have gone without it.
##
## **The welcome window stands above it.** `SaBoot` puts it up first so a
## painter can pick a document while Sara loads, and embedded it is drawn on
## that same layer 1024, so it stood under the blur for the whole of an 11.6 s
## boot. The engine draws every embedded window on the one canvas and hands a
## press to the topmost window under it, so no layer puts one window above the
## cover and leaves the dockers below. The cover draws the welcome window's own
## picture over the blur instead, with every window under it in the tree, a list
## it dropped or a tip, and brings it in front of the dockers the boot shows
## after it, which is where a press goes. A window of its own, with subwindows
## not embedded, is above the main window and this already.
##
## **That picture is not faded with the blur.** Drawn inside the faded control
## it would go down to the fade's alpha over the same window the engine draws
## under the blur, a veil for as long as the fade lasts. It
## is a child of the layer beside the faded control, whole until the cover
## leaves, when the engine's own picture of the window takes its place
## unchanged.
##
## **A window of its own cannot be covered by a layer**, so the cover holds it
## back instead: `hold_back` keeps a let-out docker out of the layout store's
## show until `gone`, and the dockers come up after the blur rather than blank
## over it.
##
## With no saved picture, with the Preferences switch off, or with a picture
## from a window of another shape, the stock picture stands in, a quarter size
## shot of the default layout the harness took, through the same shader.
class_name SaBootCover
extends CanvasLayer

## Emitted once, as the cover leaves the tree after its fade.
signal gone

## The picture's file under the data root, `SaDataRoot`, in the user folder.
const PICTURE_FILE := "last-session.webp"

## The picture for a first run, a switch that is off, or a window of another shape.
const STOCK_PATH := "res://assets/boot_cover_stock.webp"

## The engine draws embedded windows on a canvas at layer 1024
## (`SUBWINDOW_CANVAS_LAYER` in `viewport.h`), so the cover sits above it.
const LAYER := 1100

## The boot's marks, in the order `Main._boot_in_stages` reaches them, and what
## the line says while the stage after each one runs.
const STAGES: Array = [
    [&"bootstrap_begin", "Building the window and the canvas"],
    [&"ui_built", "Loading brushes and modules"],
    [&"modules_bootstrapped", "Sorting the blend modes"],
    [&"blend_favourites_canonical", "Laying out the dockers"],
    [&"boot_finished", "Ready"],
]

## A stage longer than this adds its seconds to its name, so a stall says where
## it is and that it is still counting.
const STALL_SEC := 3.0

## How long the fade takes.
const FADE_SEC := 0.35

## How long the cover waits before it fades, a few frames, so `SaBootFit` has
## fitted the layout at the end of the first and the next one drew it.
const FIT_WAIT_SEC := 0.05

## How far the saved picture's aspect may be from the window's, as a fraction,
## before it counts as a window of another shape.
const SHAPE_TOLERANCE := 0.02

## A quit keeps a picture this many times smaller than the window on each side.
const SCALE_DOWN := 4

## The scenario flag that stops the boot at a stage, for a shot of the cover.
const HOLD_ARG := "--hold-boot-at="

## The value of `HOLD_ARG` that lets the boot finish and stops the fade halfway,
## for a shot of whatever the fade shows. A capture run fades in no time at all,
## so this one fades for `FADE_SEC` whatever the run.
const HALFWAY := &"halfway"

## The group a cover stands in while it is in the tree, `in_tree`'s.
const GROUP := &"sa_boot_cover"

## The group of the windows the cover holds back, `hold_back`'s.
const HELD_BACK := &"sa_boot_cover_held_back"

## The progress line's height and the gap under its words, in logical pixels.
const LINE_HEIGHT := 3.0
const WORDS_GAP := 8.0

## "last session" or "stock", which picture the cover drew.
var _source := ""
## The stage the line shows, and the words it shows for it.
var _stage: StringName = &""
var _words := ""
## When the shown stage began, in msec, for the stall's seconds.
var _stage_began := 0
var _fading := false
## How long this cover's fade takes, nothing when a harness drives the run.
var _fade_sec := FADE_SEC
## Whether the fade stops halfway and the cover stays, `HALFWAY`'s.
var _halfway := false
## The fade once it has begun, which a suite steps by hand.
var _tween: Tween = null

var _root := Control.new()
var _picture := ColorRect.new()
var _track := ColorRect.new()
var _fill := ColorRect.new()
var _label := Label.new()
var _lifted := Control.new()


## *window_size* is the main window's in pixels, *path* where the last
## session's picture is, *show_last* the Preferences switch, and *fade_sec*
## how long the fade takes, zero for a run a scenario or the door drives, whose
## first step would otherwise meet a cover half faded. *halfway* stops the fade
## halfway for a scenario that asks for exactly that.
func _init(
    window_size: Vector2i,
    path: String = picture_path(),
    show_last: bool = true,
    fade_sec: float = FADE_SEC,
    halfway: bool = held_at(OS.get_cmdline_user_args()) == HALFWAY
) -> void:
    name = "BootCover"
    layer = LAYER
    add_to_group(GROUP)
    _halfway = halfway
    _fade_sec = FADE_SEC if halfway else fade_sec
    var image := _last_session(path, window_size) if show_last else null
    _source = "last session" if image != null else "stock"
    if image == null:
        image = _stock()
    _build(image)
    reach(STAGES[0][0])


## The stage *stage* has been reached: the line moves on and names what runs
## next. `boot_finished` starts the fade.
func reach(stage: StringName) -> void:
    var index := _index_of(stage)
    if index < 0:
        return
    _stage = stage
    _words = tr(STAGES[index][1])
    _label.text = _words
    _stage_began = Time.get_ticks_msec()
    _fill.anchor_right = float(index) / float(STAGES.size() - 1)
    _fill.offset_right = 0.0
    var parent := get_parent()
    if parent != null:
        parent.move_child(self, -1)
    if stage == STAGES[-1][0]:
        _fade_out()


func _process(_delta: float) -> void:
    var held := (Time.get_ticks_msec() - _stage_began) / 1000.0
    if held >= STALL_SEC and not _fading:
        _label.text = tr_n("%s, %d s", "%s, %d s", int(held)) % [_words, int(held)]
    lift()


## The cover standing in *node*'s tree, or null outside a tree and once the
## cover is leaving, so a show heard on `gone` is not held back again.
static func in_tree(node: Node) -> SaBootCover:
    if node == null or not node.is_inside_tree():
        return null
    return node.get_tree().get_first_node_in_group(GROUP) as SaBootCover


## Keeps *window* hidden until this cover is gone, when it is a window of its
## own: the layout store places it and leaves it hidden, `holds_back`, and the
## dockers show it on `gone`. An embedded window is under the cover already and
## is left alone. True when the window is held.
func hold_back(window: Window) -> bool:
    if window == null or not is_in_group(GROUP) or not is_inside_tree() or not window.is_inside_tree():
        return false
    if window.is_embedded():
        return false
    window.add_to_group(HELD_BACK)
    return true


## Whether a cover holds *window* back, so a show of it waits for `gone`.
static func holds_back(window: Window) -> bool:
    return window != null and window.is_in_group(HELD_BACK)


## Brings the welcome window in front of the embedded windows this hides and
## draws it over the blur, with every window under it in the tree. Every frame,
## because each docker the boot shows takes the front as it comes up, and a
## window that moves or closes has to be drawn where it is now. Once the fade
## has begun the boot is over and the welcome window came forward on its own
## at `boot_finished`, so a window shown after that is left where it opened.
func lift() -> void:
    if not _fading:
        bring_forward(_stack())
    _lifted.queue_redraw()


## The windows embedded in the viewport this is a layer of, bottom first, the
## order the engine draws them in and tests a press against, or none outside a
## tree and with subwindows not embedded.
func _stack() -> Array[Window]:
    var stack: Array[Window] = []
    if is_inside_tree():
        stack.assign(get_viewport().get_embedded_subwindows())
    return stack


## The windows of *stack*, bottom first, that are drawn over the cover: a shown
## welcome window and every shown window under one in the tree.
static func above(stack: Array[Window]) -> Array[Window]:
    var found: Array[Window] = []
    for window in stack:
        if window.visible and welcome_of(window) != null:
            found.append(window)
    return found


## Brings the topmost shown welcome window of *stack* in front, when the window
## a press would reach first is not the welcome window or one of its own. A
## window the pointer passes through, a docker's tip, is not one a press
## reaches. True when it moved one.
static func bring_forward(stack: Array[Window]) -> bool:
    var welcome: SaWelcomeWindow = null
    var top: Window = null
    for index in range(stack.size() - 1, -1, -1):
        var window := stack[index]
        if not window.visible:
            continue
        if top == null and not window.mouse_passthrough:
            top = window
        if welcome == null and window is SaWelcomeWindow:
            welcome = window as SaWelcomeWindow
    if welcome == null or top == null or welcome_of(top) != null:
        return false
    welcome.come_forward()
    return true


## The welcome window *node* is or is under in the tree, or null.
static func welcome_of(node: Node) -> SaWelcomeWindow:
    while node != null:
        if node is SaWelcomeWindow:
            return node as SaWelcomeWindow
        node = node.get_parent()
    return null


## Takes the window's picture at a quarter of its size and writes it to *path*,
## or, with *allowed* false, writes nothing and removes a picture an earlier
## quit kept. The one readback outside a stroke that the quit allows. True when a picture was written.
static func keep_the_session(viewport: Viewport, path: String = picture_path(), allowed: bool = true) -> bool:
    if not allowed:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
        return false
    if viewport == null or viewport.get_texture() == null:
        return false
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    var width := maxi(1, floori(image.get_width() / float(SCALE_DOWN)))
    var height := maxi(1, floori(image.get_height() / float(SCALE_DOWN)))
    image.resize(width, height, Image.INTERPOLATE_BILINEAR)
    return image.save_webp(path, true, 0.8) == OK


## Where a quit keeps the window's picture, under the data root.
static func picture_path() -> String:
    return SaDataRoot.path(PICTURE_FILE)


## The stage *args* asks the boot to stop at, or an empty name.
static func held_at(args: PackedStringArray) -> StringName:
    for arg in args:
        if arg.begins_with(HOLD_ARG):
            return StringName(arg.substr(HOLD_ARG.length()))
    return &""


static func _index_of(stage: StringName) -> int:
    for index in STAGES.size():
        if STAGES[index][0] == stage:
            return index
    return -1


## The saved picture, or null when there is none or it is from a window of
## another shape.
static func _last_session(path: String, window_size: Vector2i) -> Image:
    if not FileAccess.file_exists(path) or window_size.x <= 0 or window_size.y <= 0:
        return null
    var image := Image.load_from_file(path)
    if image == null or image.is_empty():
        return null
    var wanted := float(window_size.x) / float(window_size.y)
    var has := float(image.get_width()) / float(image.get_height())
    if absf(has - wanted) > wanted * SHAPE_TOLERANCE:
        return null
    return image


static func _stock() -> Image:
    var texture := load(STOCK_PATH) as Texture2D
    var image := texture.get_image() if texture != null else null
    if image == null or image.is_empty():
        image = Image.create(4, 3, false, Image.FORMAT_RGBA8)
        image.fill(Color(0.2, 0.2, 0.22))
    if image.is_compressed():
        image.decompress()
    return image


func _build(image: Image) -> void:
    image.convert(Image.FORMAT_RGBA8)
    image.generate_mipmaps()
    var material := ShaderMaterial.new()
    # Loaded here rather than preloaded: `SaBoot` compiles `main.gd` and what it
    # names on a worker, and a preloaded resource that is not a script leaks a
    # token at exit.
    material.shader = load("res://ui/boot/boot_cover.gdshader")
    material.set_shader_parameter(&"picture", ImageTexture.create_from_image(image))
    material.set_shader_parameter(&"fog_colour", SaTheme.palette.bg_primary)

    _root.name = "Cover"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)

    _picture.name = "Picture"
    _picture.material = material
    _picture.set_anchors_preset(Control.PRESET_FULL_RECT)
    _picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_picture)

    _track.name = "Track"
    _track.color = SaTheme.palette.border_secondary
    _track.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    _track.offset_top = -LINE_HEIGHT
    _track.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_track)

    _fill.name = "Fill"
    _fill.color = SaTheme.palette.accent_primary
    _fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
    _fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _track.add_child(_fill)

    _label.name = "Stage"
    _label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    _label.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _label.offset_left = WORDS_GAP * 2.0
    _label.offset_bottom = -(LINE_HEIGHT + WORDS_GAP)
    _label.add_theme_color_override(&"font_color", SaTheme.palette.text_primary)
    _label.add_theme_color_override(&"font_shadow_color", SaTheme.palette.shadow)
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_label)

    # Beside the faded control rather than in it, and after it, so the welcome
    # window is drawn over the line and its words, whole through the fade.
    _lifted.name = "Lifted"
    _lifted.set_anchors_preset(Control.PRESET_FULL_RECT)
    _lifted.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _lifted.draw.connect(_draw_above)
    add_child(_lifted)


## Each window `above` names where the engine draws it, from the picture its
## own viewport renders, which is what the engine draws on layer 1024 under
## this. The stack is read again here rather than kept from `lift`, so a window
## freed in between is not drawn. The windows are embedded in the viewport the
## cover is a layer of, so their positions are in the space this control draws in.
func _draw_above() -> void:
    for window in above(_stack()):
        var at := Rect2(Vector2(window.position), Vector2(window.size))
        _lifted.draw_texture_rect(window.get_texture(), at, false)


## Waits for the layout's first fit, fades, and leaves, all on one tween the
## cover owns, so a quit during the fade frees it with the cover rather than
## leaving a coroutine waiting. A cover outside any tree, which is a suite's,
## or one with no fade leaves at once. One held `HALFWAY` stops at half the
## fade and stays.
func _fade_out() -> void:
    if _fading:
        return
    _fading = true
    _label.text = _words
    if not is_inside_tree() or _fade_sec <= 0.0:
        _leave()
        return
    _tween = create_tween()
    _tween.tween_interval(FIT_WAIT_SEC)
    if _halfway:
        _tween.tween_property(_root, ^"modulate:a", 0.5, _fade_sec * 0.5)
        return
    _tween.tween_property(_root, ^"modulate:a", 0.0, _fade_sec)
    _tween.tween_callback(_leave)


## Says so, with every window it held back still marked for what hears it to
## show, then lets go of them, so the next show of one goes through, and leaves
## the tree.
func _leave() -> void:
    remove_from_group(GROUP)
    gone.emit()
    if is_inside_tree():
        for held in get_tree().get_nodes_in_group(HELD_BACK):
            held.remove_from_group(HELD_BACK)
    var parent := get_parent()
    if parent != null:
        parent.remove_child(self)
    queue_free()
