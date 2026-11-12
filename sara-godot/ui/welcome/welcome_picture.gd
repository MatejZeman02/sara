## The picture across the top of the Welcome window, the version and under it a
## credit line right aligned in its lower right corner, as Blender's splash has.
##
## The band is as wide as the window and a third of that tall, so it takes its
## height from the window's width (`band_height`) and the picture is scaled to
## cover it. The files and the sidecar JSON a picture is made of are described in
## `pictures/README.md`.
##
## The place, the season and the hour are read once, when the window opens.
## `WelcomeSun` guesses the place from the time zone, the season picks the
## lights (`PictureLights`), and the two either side of the hour on the 24 hour
## circle are shown, the second over the first at the fraction of the way
## between them, a cross fade of two textures with no shader and nothing per
## frame. `PictureParts` composes a light's parts once per opening and
## `PictureOverlays` lays the sidecar's overlays by chance. A light with no
## parts is shown as its file.
##
## Reading parts is the renderer's work on the main thread and costly, so
## `ReadAhead` reads the parts the next opening may show, one a frame, once Sara
## has started and again after each opening. An opening then only blends them on
## the pool, and the band shows the picture a frame or two later. An hour that
## moved past what was read ahead reads what it lacks and blends it before the
## frame ends.
##
## Nothing here reads the canvas or the renderer, because `SaBoot` builds the
## window this stands in before either exists.
@tool
class_name WelcomePicture
extends Control

const FOLDER := "res://ui/welcome/pictures/"

## The window's opening width, which the picture is made at twice of.
const OPENING_WIDTH: int = 720

## How many times the band is as wide as it is tall.
const WIDTHS_PER_HEIGHT: int = 3

## The tallest the band grows, in logical units, so a window made larger gives the
## rest of its height to the panes. Without it Ctrl+Space would grow the band
## and shrink the News scroll rather than give the change log room. Above the
## opening width's 240, so the band opens at that height.
const BAND_CEILING: int = 280

## The room the words keep from the band's edges, in logical units.
const WORDS_PAD: int = 12

const FOLDER_VARIABLE := "SARA_WELCOME_PICTURES"
const VERSION_VARIABLE := "SARA_WELCOME_VERSION"

## The key (`"0.18"`) of the picture this shows, and the words that go with it.
var key: String = ""
var title: String = ""
var credit: String = ""

## The lights the picture comes in, by hour, empty for a picture that is one, and
## the ones of them the season shows, which `fade` indexes.
var lights: Array[PictureLights.Light] = []
var shown: Array[PictureLights.Light] = []

## The local hour, the season and the sun this was last shown at, and the fade
## it came to.
var hour: float = 0.0
var season: String = ""
var sky: WelcomeSun.SunNow = null
var fade: PictureLights.Fade = PictureLights.Fade.new(-1, -1, 0.0)

## The roll that keeps one light of a moment that holds several, drawn again
## at each opening (`PictureLights.one_each`).
var mood_roll: float = 0.0

## The roll the clouds drift by, 0 to 1 of the strip's width, drawn again at
## each opening.
var drift: float = 0.0

## The parts of each light that comes in them, by its file name (`PictureParts`).
var parts: Dictionary = {}

## The first light, or the one picture, the second over it, the overlays laid
## over both, and those laid under the clouds, which `PictureParts.compose` draws and
## which this node only rolls.
var picture: TextureRect
var over: TextureRect
var overlays: PictureOverlays
var beneath: PictureOverlays
var version_line: Label
var credit_line: Label

var _running: String = ""
var _plain: String = ""
## The group task composing the picture on the pool, -1 when none is, and the
## lights and jobs it shows once made.
var _task: int = -1
var _task_showing: Array[PictureLights.Light] = []
var _task_jobs: Array[PictureParts.Composing] = []

## The reading ahead under way, held here because a signal holds no reference
## to the object whose method it calls. One at a time for every band.
static var _reading: ReadAhead = null


## *version* is the running version, `SARA_WELCOME_VERSION` in a debug build that
## sets it and `application/config/version` otherwise when empty, and
## *folder* is where the pictures are, which a suite points elsewhere. The hour
## and season are the clock's, which `show_at` replaces.
func _init(version: String = "", folder: String = FOLDER) -> void:
    name = "WelcomePicture"
    _running = version
    if _running.is_empty() and OS.is_debug_build():
        _running = OS.get_environment(VERSION_VARIABLE)
    if _running.is_empty():
        _running = SaBuildInfo.version()
    custom_minimum_size = Vector2(0.0, float(band_height(OPENING_WIDTH)))
    size_flags_horizontal = Control.SIZE_FILL
    # A press on the band is a press on the window it is in, which leaves the
    # window up, so the band takes it rather than letting it fall through to
    # whatever stands under the window.
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true
    tree_entered.connect(_follow_the_window)
    tree_exiting.connect(_let_go_of_the_window)

    picture = _cover("Picture")
    over = _cover("Over")

    var words := VBoxContainer.new()
    words.name = "Words"
    words.mouse_filter = Control.MOUSE_FILTER_IGNORE
    words.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    words.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    words.grow_vertical = Control.GROW_DIRECTION_BEGIN
    words.offset_right = -float(WORDS_PAD)
    words.offset_bottom = -float(WORDS_PAD)
    words.add_theme_constant_override("separation", 0)
    add_child(words)
    version_line = _line(words, "VersionLine")
    credit_line = _line(words, "CreditLine")
    version_line.text = _running

    var from := folder_of(folder)
    key = pick(keys_in(from), _running)
    var sidecar := {}
    if not key.is_empty():
        sidecar = _read_words("%s%s.json" % [from, key])
        title = str(sidecar.get("title", ""))
        credit = str(sidecar.get("credit", ""))
        lights = PictureLights.lights_in(sidecar, from)
        parts = PictureParts.listed_in(sidecar, from)
        _plain = "%s%s.png" % [from, key]
    overlays = PictureOverlays.new(_overlays_of(sidecar, false), from)
    over.add_sibling(overlays)
    beneath = PictureOverlays.new(_overlays_of(sidecar, true), from)
    beneath.name = "Beneath"
    beneath.visible = false
    overlays.add_sibling(beneath)
    credit_line.text = credit_text(title, credit)
    _show_now()


## Shows the picture as it is at *at_hour*, the local hour with minutes as a
## fraction, in *at_season*, which is none for a painter with no season, under
## *at_sky*, the sun then, which a sidecar of sun lights fades by and one of
## hours leaves alone. A picture that is one, or that its season leaves no light
## of, has nothing to change. One in lights puts the second over the first at
## the fade's fraction. When every part it needs is kept, it is composed on the
## pool and `_process` shows it once made, so the frame that asked waits for
## none of it, and `settle` waits for it.
func show_at(at_hour: float, at_season: String = "", at_sky: WelcomeSun.SunNow = null) -> void:
    _drop_composing()
    hour = fposmod(at_hour, PictureLights.DAY_HOURS)
    season = at_season
    sky = at_sky
    var chosen := chosen_at(lights, mood_roll, hour, season, sky)
    shown = chosen[0]
    fade = chosen[1]
    over.texture = null
    over.modulate = Color(1.0, 1.0, 1.0, fade.fraction)
    overlays.show_over(shown, fade, hour)
    if shown.is_empty():
        picture.texture = load(_plain) as Texture2D if not _plain.is_empty() else null
        return
    var showing: Array[PictureLights.Light] = [shown[fade.first]]
    if fade.faded() and fade.fraction > 0.0:
        showing.append(shown[fade.second])
    var jobs := _jobs_of(showing, fade.fraction)
    _task = PictureParts.Composing.in_background(jobs)
    _task_showing = showing
    _task_jobs = jobs
    if _task >= 0:
        picture.texture = null
        return
    PictureParts.Composing.all(jobs)
    _lay(showing, jobs)


## Shows the picture composing on the pool once it is made, a frame or two
## after the opening that asked for it.
func _process(_delta: float) -> void:
    if _task >= 0 and WorkerThreadPool.is_group_task_completed(_task):
        settle()


## Waits for a picture composing on the pool and shows it, for a caller that
## reads the band's textures at once. Does nothing when none is.
func settle() -> void:
    if _task < 0:
        return
    WorkerThreadPool.wait_for_group_task_completion(_task)
    _task = -1
    _lay(_task_showing, _task_jobs)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _drop_composing()


## Waits for a picture composing on the pool without showing it, because a
## task is waited for once and a newer picture replaces it.
func _drop_composing() -> void:
    if _task >= 0:
        WorkerThreadPool.wait_for_group_task_completion(_task)
    _task = -1
    _task_jobs = []


## The lights of *of_lights* a band shows at *roll*, *at_hour*, *at_season* and
## under *at_sky*, and the fade between them, as `[shown, fade]`.
static func chosen_at(
    of_lights: Array[PictureLights.Light], roll: float, at_hour: float, at_season: String, at_sky: WelcomeSun.SunNow
) -> Array:
    var chosen := PictureLights.one_each(PictureLights.in_season(of_lights, at_season), roll)
    if at_sky != null and PictureLights.by_sun(chosen):
        chosen = PictureLights.reached(chosen, at_sky)
        return [chosen, PictureLights.fade_by_sun(chosen, at_sky)]
    return [chosen, PictureLights.fade_at(chosen, at_hour)]


## The files an opening at *at_hour*, *at_season* and under *at_sky* may read
## out of *of_parts*, at any roll of the mood: the parts of each light it may
## show and the overlays under their clouds of *under*. The mood is walked in
## twentieths, which lands on every light but one of a weight under a
## twentieth, and that one is read at its opening as before.
static func parts_at(
    of_lights: Array[PictureLights.Light],
    of_parts: Dictionary,
    under: Array[PictureOverlays.Overlay],
    at_hour: float,
    at_season: String,
    at_sky: WelcomeSun.SunNow
) -> PackedStringArray:
    var found := PackedStringArray()
    for step in 21:
        var chosen := chosen_at(of_lights, step / 20.0, at_hour, at_season, at_sky)
        var lit: Array[PictureLights.Light] = chosen[0]
        var at_fade: PictureLights.Fade = chosen[1]
        if lit.is_empty():
            continue
        var showing: Array[PictureLights.Light] = [lit[at_fade.first]]
        if at_fade.faded() and at_fade.fraction > 0.0:
            showing.append(lit[at_fade.second])
        for light in showing:
            var in_parts: PictureParts = of_parts.get(light.path.get_file())
            if in_parts == null:
                continue
            var files: Array[String] = [in_parts.back, in_parts.clouds, in_parts.land]
            if in_parts.body != null:
                files.append(in_parts.body.path)
                if not in_parts.body.reflection.is_empty():
                    files.append(in_parts.body.reflection)
            for overlay in under:
                if overlay.belongs_to(light):
                    files.append(overlay.path)
            for file in files:
                if not found.has(file):
                    found.append(file)
    return found


## Reads ahead the parts an opening of the window may show, from a few frames
## on, for a window not built yet. `SaWelcomeWindow.read_ahead` is the door.
static func read_ahead(folder: String = FOLDER) -> void:
    var from := folder_of(folder)
    var running := SaBuildInfo.version()
    if OS.is_debug_build() and OS.has_environment(VERSION_VARIABLE):
        running = OS.get_environment(VERSION_VARIABLE)
    var found := pick(keys_in(from), running)
    if found.is_empty():
        return
    _start_reading(_parts_of_sidecar.bind("%s%s.json" % [from, found], from), ReadAhead.SETTLE_FRAMES)


## The parts the picture of *sidecar_path* in *from* may show now, which
## `read_ahead` lists once its frames have settled rather than at the boot.
static func _parts_of_sidecar(sidecar_path: String, from: String) -> PackedStringArray:
    var sidecar := _read_words(sidecar_path)
    var under := PictureOverlays.overlays_in(_overlays_of(sidecar, true), from)
    var moment := WelcomeSun.now()
    var of_lights := PictureLights.lights_in(sidecar, from)
    var listed := PictureParts.listed_in(sidecar, from)
    return parts_at(of_lights, listed, under, moment.hour, moment.season, moment.sky)


## *folder*, or the debug build's `SARA_WELCOME_PICTURES` for the shipped one.
static func folder_of(folder: String) -> String:
    if folder == FOLDER and OS.is_debug_build() and OS.has_environment(FOLDER_VARIABLE):
        return OS.get_environment(FOLDER_VARIABLE)
    return folder


## Reads ahead what *listing* answers, from *frames* frames on, in place of a
## reading under way.
static func _start_reading(listing: Callable, frames: int) -> void:
    if _reading != null:
        _reading.stop()
    _reading = ReadAhead.new(listing, frames)
    if not _reading.start():
        _reading = null


## The jobs that compose each of *showing* in parts as the band shows it: at
## this opening's drift with the overlays under its clouds that won their roll
## and its sun or moon where `PictureParts.Body.places` lays it at *fraction*
## of the fade, as strong as `PictureParts.Body.shares` says. A light with no parts has none and is shown as its file.
func _jobs_of(showing: Array[PictureLights.Light], fraction: float) -> Array[PictureParts.Composing]:
    var bodies: Array[PictureParts.Body] = []
    for light in showing:
        var in_parts: PictureParts = parts.get(light.path.get_file())
        bodies.append(in_parts.body if in_parts != null else null)
    var places: Array[Vector2] = []
    var shares: Array[float] = [1.0, 1.0]
    if showing.size() > 1:
        places = PictureParts.Body.places(bodies[0], bodies[1], fraction)
        shares = PictureParts.Body.shares(bodies[0], bodies[1], fraction)
    var jobs: Array[PictureParts.Composing] = []
    for at in showing.size():
        var light := showing[at]
        var in_parts: PictureParts = parts.get(light.path.get_file())
        if in_parts == null:
            continue
        var under: Array[PictureOverlays.Overlay] = []
        for overlay in beneath.overlays:
            if overlay.drawn and overlay.belongs_to(light):
                under.append(overlay)
        var place: Variant = null
        if bodies[at] != null and at < places.size():
            place = places[at]
        jobs.append(in_parts.composing(drift, under, place, shares[mini(at, 1)]))
    return jobs


## Shows the lights of *showing*, those with parts as *jobs* made them, the
## first under and the second over it.
func _lay(showing: Array[PictureLights.Light], jobs: Array[PictureParts.Composing]) -> void:
    var textures: Array[Texture2D] = []
    var made := jobs.duplicate()
    for light in showing:
        if parts.has(light.path.get_file()):
            textures.append(ImageTexture.create_from_image((made.pop_front() as PictureParts.Composing).made))
        else:
            textures.append(load(light.path) as Texture2D)
    picture.texture = textures[0]
    if textures.size() > 1:
        over.texture = textures[1]


## *sidecar* with only the overlays it lays under the clouds when *under*, and
## only the rest otherwise.
static func _overlays_of(sidecar: Dictionary, under: bool) -> Dictionary:
    var kept := []
    var listed: Variant = sidecar.get("overlays", [])
    if listed is Array:
        for entry: Variant in listed:
            if entry is Dictionary and (str((entry as Dictionary).get("beneath", "")) == "clouds") == under:
                kept.append(entry)
    return {"overlays": kept}


## The height of a band *width* wide, rounded up so the picture is never short
## of its band, and never over the ceiling.
static func band_height(width: int) -> int:
    return mini(ceili(float(width) / float(WIDTHS_PER_HEIGHT)), BAND_CEILING)


## The `major.minor` of *version*, which is what a picture is named for, or empty
## for a version that has no two numbers to it.
static func key_of(version: String) -> String:
    var numbers := version.split(".")
    if numbers.size() < 2 or not numbers[0].is_valid_int() or not numbers[1].substr(0, 1).is_valid_int():
        return ""
    return "%d.%d" % [numbers[0].to_int(), numbers[1].to_int()]


## The key of the picture a window of *version* shows out of *keys*: its own
## minor's when there is one, and the newest otherwise. Empty when there are none.
static func pick(keys: PackedStringArray, version: String) -> String:
    var own := key_of(version)
    if not own.is_empty() and keys.has(own):
        return own
    var newest := ""
    for candidate in keys:
        if newest.is_empty() or _is_newer(candidate, newest):
            newest = candidate
    return newest


## The keys of the pictures in *folder*, one for each `.json` in it that names a
## `major.minor`.
static func keys_in(folder: String) -> PackedStringArray:
    var found := PackedStringArray()
    if not DirAccess.dir_exists_absolute(folder):
        return found
    for file in DirAccess.get_files_at(folder):
        if file.get_extension() != "json":
            continue
        var stem := file.get_basename()
        if key_of(stem) == stem:
            found.append(stem)
    return found


## The line under the picture's corner: the credit and the title, or whichever of
## the two the sidecar has.
static func credit_text(picture_title: String, picture_credit: String) -> String:
    if picture_title.is_empty():
        return picture_credit
    if picture_credit.is_empty():
        return picture_title
    return "%s: %s" % [picture_credit, picture_title]


## A numeric order on two keys, since "0.9" is older than "0.18".
static func _is_newer(candidate: String, than: String) -> bool:
    var a := candidate.split(".")
    var b := than.split(".")
    if a[0].to_int() != b[0].to_int():
        return a[0].to_int() > b[0].to_int()
    return a[1].to_int() > b[1].to_int()


static func _read_words(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


## A texture that covers the band, with the mipmaps that keep it clean at scale 1.
func _cover(node_name: String) -> TextureRect:
    var made := TextureRect.new()
    made.name = node_name
    made.set_anchors_preset(Control.PRESET_FULL_RECT)
    made.mouse_filter = Control.MOUSE_FILTER_IGNORE
    made.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    made.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    made.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    add_child(made)
    return made


## A label of the band's words: the theme's light text over a soft dark shadow,
## so it reads on a pale sky as well as a dark ridge.
static func _line(parent: Node, node_name: String) -> Label:
    var made := SaMake.label(parent, node_name)
    made.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    made.mouse_filter = Control.MOUSE_FILTER_IGNORE
    made.add_theme_color_override("font_color", SaTheme.palette.text_primary)
    made.add_theme_color_override("font_shadow_color", SaTheme.palette.text_shadow)
    made.add_theme_constant_override("shadow_offset_x", 1)
    made.add_theme_constant_override("shadow_offset_y", 1)
    made.add_theme_constant_override("shadow_outline_size", 3)
    return made


## The band is a third as tall as the window is wide up to its ceiling, wherever it is dragged to.
## Read from the window's own viewport and not from this control's size, because
## the window's size is what changes first and this control follows a frame after.
## A window shown again takes the clock again, so one put away and brought back at
## dusk is not still the dawn it was built at. A hide changes nothing.
func _follow_the_window() -> void:
    var window := get_window()
    var seen := window.get_visible_rect().size
    var wanted := float(mini(band_height(roundi(seen.x)), _room_left(seen.y)))
    if not is_equal_approx(custom_minimum_size.y, wanted):
        custom_minimum_size.y = wanted
    if not window.size_changed.is_connected(_follow_the_window):
        window.size_changed.connect(_follow_the_window)
    if not window.visibility_changed.is_connected(_on_window_visibility):
        window.visibility_changed.connect(_on_window_visibility)
    var column := get_parent() as VBoxContainer
    if column != null and not column.minimum_size_changed.is_connected(_follow_the_window):
        column.minimum_size_changed.connect(_follow_the_window)


## The height a window *window_height* tall leaves the band, from the band's top
## down, once every row under it in its column has its minimum. A host too short
## for the band and the panes both makes the window shorter than they need, and
## the band is what gives way, so New and Open stay inside the window: at a
## scale of 2 on a 1280 by 800 screen the window is 335 tall and they stood at
## 337. A band in no column has the whole window. The column is heard as well
## as the window, because a wrapping label under the band takes its height on
## the frame after the window's size: in the running app the Recent pane's one
## sentence went to two lines then, and the band had already been measured.
func _room_left(window_height: float) -> int:
    var column := get_parent() as VBoxContainer
    if column == null:
        return floori(window_height)
    var under := 0.0
    for child: Node in column.get_children():
        var row := child as Control
        if row == null or row == self or not row.visible:
            continue
        under += row.get_combined_minimum_size().y + float(column.get_theme_constant("separation"))
    return maxi(0, floori(window_height - get_global_rect().position.y - under))


func _let_go_of_the_window() -> void:
    var window := get_window()
    if window == null:
        return
    if window.size_changed.is_connected(_follow_the_window):
        window.size_changed.disconnect(_follow_the_window)
    if window.visibility_changed.is_connected(_on_window_visibility):
        window.visibility_changed.disconnect(_on_window_visibility)
    var column := get_parent() as VBoxContainer
    if column != null and column.minimum_size_changed.is_connected(_follow_the_window):
        column.minimum_size_changed.disconnect(_follow_the_window)


func _on_window_visibility() -> void:
    if get_window().visible:
        _show_now()


func _show_now() -> void:
    overlays.roll_now()
    beneath.roll_now()
    mood_roll = PictureLights.roll_once()
    drift = PictureLights.roll_once()
    var moment := WelcomeSun.now()
    show_at(moment.hour, moment.season, moment.sky)
    # Listed on the next frame, as 2 ms of the opening's own was.
    _start_reading(parts_at.bind(lights, parts, beneath.overlays, moment.hour, moment.season, moment.sky), 0)


## Reads the parts an opening may show into `PictureParts`' kept ones, one a
## frame on the main thread, the only thread that may ask the renderer for an
## image, after *settle* frames. Its first frame after them asks *listing* for
## the files and lets go of every kept part not among them. It stops once it
## has read them or when another reading takes its place.
class ReadAhead:
    extends RefCounted

    ## The frames a reading for a window not built yet waits, so Sara's first
    ## frames, which build the rest of it, are not slowed by it.
    const SETTLE_FRAMES: int = 120

    var _listing: Callable
    var _files: PackedStringArray
    var _listed: bool = false
    var _settle: int
    var _tree: SceneTree = null

    func _init(listing: Callable, settle: int) -> void:
        _listing = listing
        _settle = settle

    ## Hears the frames, or does nothing and answers false when there is no tree.
    func start() -> bool:
        _tree = Engine.get_main_loop() as SceneTree
        if _tree == null:
            return false
        _tree.process_frame.connect(_on_frame)
        return true

    func stop() -> void:
        if _tree != null and _tree.process_frame.is_connected(_on_frame):
            _tree.process_frame.disconnect(_on_frame)

    func _on_frame() -> void:
        if _settle > 0:
            _settle -= 1
            return
        if not _listed:
            _listed = true
            var files: PackedStringArray = _listing.call()
            PictureParts.keep_only(files)
            for file in files:
                if not PictureParts.is_kept(file):
                    _files.append(file)
            return
        if _files.is_empty():
            stop()
            return
        PictureParts.keep(_files[0])
        _files.remove_at(0)
