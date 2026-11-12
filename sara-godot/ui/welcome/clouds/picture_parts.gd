## A light of the Welcome picture in the parts its clouds drift in, which the
## sidecar's `parts` lists by the light's file. The sidecar's keys (the `back`,
## the `clouds` strip, the `land`, the `rows`, `origin` and `seam`, a `body` and
## its `reflection`) are described in `ui/welcome/pictures/README.md`.
##
## `compose` lays the back, the overlays an entry names `"beneath": "clouds"`
## (the stars), the strip moved round by `WelcomePicture.drift`, the body and the
## land, once, into the texture the band shows, and the reflection last. `Body`
## says where two fading lights lay their bodies, so two lights fading show one
## sun rather than one at each. One of these holds an entry's files with their
## folder and the numbers. The files are imported as images and read on the CPU,
## and `Composing` reads and blends them, one light to a thread.
##
## Reading a part asks the renderer for its image, which the main thread has to
## do, so `keep` reads one into `_kept` ahead of the opening, a frame at a time,
## and `fetch` takes it from there. `keep_only` lets go of what the next opening
## no longer needs, which holds the kept parts to the one or two lights on show.
class_name PictureParts
extends RefCounted

var back: String
var clouds: String
var land: String
var top: int
var origin: int
var seam: int
var body: Body

## The parts read ahead, by path, each as `fetch` would read it and in eight
## bits. Read and written on the main thread only.
static var _kept: Dictionary[String, Image] = {}


func _init(
    back_path: String,
    clouds_path: String,
    land_path: String,
    from_row: int,
    at_column: int = 0,
    seam_width: int = 0,
    with_body: Body = null
) -> void:
    back = back_path
    clouds = clouds_path
    land = land_path
    top = from_row
    origin = at_column
    seam = seam_width
    body = with_body


## The parts *sidecar* lists under `parts`, by light file name, with their
## files in *folder*. An entry short of a part, or naming a file that is not
## there, is left out, so its light is shown as its file.
static func listed_in(sidecar: Dictionary, folder: String) -> Dictionary:
    var found := {}
    var listed: Variant = sidecar.get("parts", {})
    if not listed is Dictionary:
        return found
    for file: Variant in listed:
        var entry: Variant = listed[file]
        if not entry is Dictionary:
            continue
        var paths: Array[String] = []
        for part: String in ["back", "clouds", "land"]:
            var named := str((entry as Dictionary).get(part, ""))
            if not named.is_empty() and named == named.get_file() and ResourceLoader.exists(folder + named):
                paths.append(folder + named)
        var rows: Variant = (entry as Dictionary).get("rows", [])
        if paths.size() == 3 and rows is Array and (rows as Array).size() == 2:
            var at := int(_number((entry as Dictionary).get("origin"), 0.0))
            var seam_width := int(_number((entry as Dictionary).get("seam"), 0.0))
            var with_body := Body.listed_in((entry as Dictionary).get("body"), folder)
            found[str(file)] = PictureParts.new(
                paths[0], paths[1], paths[2], int(_number(rows[0], 0.0)), at, seam_width, with_body
            )
    return found


## The light with its clouds moved *roll* of the strip's width to the right
## and round, the *under* overlays laid on the sky first at the opacity each
## rolled, and its body with the middle of its disc at *place*, its own when
## none is given, as one image with its mipmaps, read and blended on this
## thread.
func compose(roll: float, under: Array[PictureOverlays.Overlay] = [], place: Variant = null) -> Image:
    var job := composing(roll, under, place)
    for slot in job.images.size():
        job.fetch(slot)
        job.read(slot)
    job.compose()
    return job.made


## As `compose`, from the lossless PNGs in the repository rather than their
## lossy imports, which a suite comparing the blend with Sara's own
## export reads, since the loss of the import is no fault of the blend. A
## shipped build has no PNGs, only the imports.
func compose_from_sources(
    roll: float, under: Array[PictureOverlays.Overlay] = [], place: Variant = null, share: float = 1.0
) -> Image:
    var job := composing(roll, under, place, share)
    for slot in job.images.size():
        job.images[slot] = PictureParts.image_of(job.path_of(slot), true)
        job.read(slot)
    job.compose()
    return job.made


## The picture at *path* as an image of its own, asked of the renderer,
## since every picture is imported as a lossy texture. Called on the
## main thread only, uncached, so the texture goes once its image is taken.
## With *from_source*, the PNG itself, lossless, which only a checkout has.
static func image_of(path: String, from_source := false) -> Image:
    if from_source:
        return Image.load_from_file(ProjectSettings.globalize_path(path))
    var texture := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
    return texture.get_image() if texture != null else null


## The part at *path* as an opening reads it, from `_kept` when it was read
## ahead and from the renderer otherwise. A kept image is shared, so a job
## copies it before it changes it.
static func kept_or_read(path: String) -> Image:
    var kept: Image = _kept.get(path)
    return kept if kept != null else PictureParts.image_of(path)


## Whether *path* is read ahead.
static func is_kept(path: String) -> bool:
    return _kept.has(path)


## Reads *path* ahead, on the main thread, for an opening to come.
static func keep(path: String) -> void:
    if _kept.has(path):
        return
    var image := PictureParts.image_of(path)
    if image == null:
        return
    image.clear_mipmaps()
    image.convert(Image.FORMAT_RGBA8)
    _kept[path] = image


## Lets go of every part read ahead but *paths*.
static func keep_only(paths: PackedStringArray) -> void:
    for path: String in _kept.keys():
        if not paths.has(path):
            _kept.erase(path)


## The light at *roll* with the *under* overlays and its body at *place*,
## shown at *share* of its strength as `Body.shares` gives it, to be read and
## composed, by `compose` here or with other lights by
## `Composing.all`.
func composing(roll: float, under: Array[PictureOverlays.Overlay] = [], place: Variant = null, share: float = 1.0) -> Composing:
    var paths: Array[String] = [back, clouds, land]
    var corner := Vector2i.ZERO
    var mirrored := Vector2i.ZERO
    var shown := 1.0
    if body != null:
        var at: Vector2 = place if place is Vector2 else body.at
        paths.append(body.path)
        corner = body.corner_at(at)
        shown = body.shown_at(at) * share
        if not body.reflection.is_empty():
            paths.append(body.reflection)
            mirrored = body.reflection_at(at)
    return Composing.new(paths, top, origin, roll, under, corner, body != null and body.over_clouds, mirrored, shown)


static func _number(given: Variant, otherwise: float) -> float:
    return float(given) if given is float or given is int else otherwise


## A light's sun or moon: its file, its kind, where its box's corner and the
## middle of its disc stand in the light, the row the middle goes down to
## before the ridge hides the disc, whether it is laid over the clouds, and
## its reflection's file and box's corner, none for a body with none.
class Body:
    ## How far into a fade from a sun to a moon, or a moon to a sun, the first
    ## has gone and the second begins to come. Before the half, so the light
    ## coming in already shows its own at the half, and the band shows one of
    ## them at any hour and never the two at once.
    const HANDOVER: float = 0.3

    ## The share of the way from its painted place down to where it sets over
    ## which a body fades out, all of it shown above. The ridge hides the disc
    ## as it goes down already, and a body faded the whole way would be too
    ## dim to see by the time its light is the one the band shows most.
    const FADES_OVER: float = 0.3

    var path: String
    var kind: String
    var box: Vector2i
    var at: Vector2
    var sets: float
    var over_clouds: bool
    var reflection: String
    var reflection_box: Vector2i

    func _init(
        file_path: String,
        of_kind: String,
        corner: Vector2i,
        disc: Vector2,
        set_row: float,
        over_the_clouds: bool = false,
        reflection_path: String = "",
        reflection_corner: Vector2i = Vector2i.ZERO
    ) -> void:
        path = file_path
        kind = of_kind
        box = corner
        at = disc
        sets = set_row
        over_clouds = over_the_clouds
        reflection = reflection_path
        reflection_box = reflection_corner

    ## The body an entry's `body` names in *folder*, or null for none or one
    ## whose file is not there.
    static func listed_in(entry: Variant, folder: String) -> Body:
        if not entry is Dictionary:
            return null
        var named := str((entry as Dictionary).get("file", ""))
        var corner: Variant = (entry as Dictionary).get("box", [])
        var disc: Variant = (entry as Dictionary).get("at", [])
        if named.is_empty() or named != named.get_file() or not ResourceLoader.exists(folder + named):
            return null
        if not (corner is Array and (corner as Array).size() == 2 and disc is Array and (disc as Array).size() == 2):
            return null
        var mirrored: Variant = (entry as Dictionary).get("reflection")
        var reflection_path := ""
        var reflection_corner := Vector2i.ZERO
        if mirrored is Dictionary:
            var file := str((mirrored as Dictionary).get("file", ""))
            var at_corner: Variant = (mirrored as Dictionary).get("box", [])
            var placed := at_corner is Array and (at_corner as Array).size() == 2
            if file == file.get_file() and ResourceLoader.exists(folder + file) and placed:
                reflection_path = folder + file
                reflection_corner = Vector2i(
                    int(PictureParts._number(at_corner[0], 0.0)), int(PictureParts._number(at_corner[1], 0.0))
                )
        return Body.new(
            folder + named,
            str((entry as Dictionary).get("kind", "sun")),
            Vector2i(int(PictureParts._number(corner[0], 0.0)), int(PictureParts._number(corner[1], 0.0))),
            Vector2(PictureParts._number(disc[0], 0.0), PictureParts._number(disc[1], 0.0)),
            PictureParts._number((entry as Dictionary).get("sets"), 0.0),
            (entry as Dictionary).get("over_clouds", false) == true,
            reflection_path,
            reflection_corner
        )

    ## Where the box's corner stands when the middle of the disc is at *place*.
    func corner_at(place: Vector2) -> Vector2i:
        return box + Vector2i((place - at).round())

    ## Where the reflection's corner stands when the middle of the disc is at
    ## *place*: moved sideways with it, and on the lake where it was cut.
    func reflection_at(place: Vector2) -> Vector2i:
        return reflection_box + Vector2i(roundi(place.x - at.x), 0)

    ## How much of the body, its glow and its reflection shows with the middle
    ## of the disc at *place*: all of it at its painted place and above, none
    ## once it has set, and fading over the last `FADES_OVER` of the way
    ## between, so a sun gone down leaves no glow in the sky over the light
    ## that follows.
    func shown_at(place: Vector2) -> float:
        if sets <= at.y:
            return 1.0
        return clampf((sets - place.y) / ((sets - at.y) * FADES_OVER), 0.0, 1.0)

    ## Where the bodies of two lights fading, *first* and *second*, either of
    ## them null for a light with none, lay the middles of their discs at
    ## *fraction* of the way from the first to the second. Two of one kind share
    ## a place, the fraction of the way along the straight line from the
    ## first's painted place to the second's, so one sun shows, its look
    ## crossing from one light's to the other's. A sun and a moon never share
    ## one: a sun going goes straight down from its place to where it sets by
    ## `HANDOVER` of the fade, and a sun coming comes straight up from where it
    ## sets to its place from there on. A moon stays where it is painted and
    ## fades there as `shares` says, since a summer night lays its twilight
    ## in front of the whole sky but round the moon, and a moon moved would
    ## be hidden. A body whose partner has none keeps its place.
    static func places(first: Body, second: Body, fraction: float) -> Array[Vector2]:
        var from := first.at if first != null else Vector2.ZERO
        var to := second.at if second != null else Vector2.ZERO
        if first != null and second != null:
            if first.kind == second.kind:
                from = first.at.lerp(second.at, fraction)
                to = from
            else:
                if first.kind != "moon":
                    from = first.at.lerp(Vector2(first.at.x, first.sets), _going(fraction))
                if second.kind != "moon":
                    to = Vector2(second.at.x, second.sets).lerp(second.at, _coming(fraction))
        return [from, to]

    ## How much of its strength each of the bodies of `places` shows at
    ## *fraction*: all of each, but for a moon handing over to a sun or taking
    ## over from one, which fades out by `HANDOVER` or in from there. A sun
    ## fades as it sets, by `shown_at`.
    static func shares(first: Body, second: Body, fraction: float) -> Array[float]:
        var going := 1.0
        var coming := 1.0
        if first != null and second != null and first.kind != second.kind:
            if first.kind == "moon":
                going = 1.0 - _going(fraction)
            if second.kind == "moon":
                coming = _coming(fraction)
        return [going, coming]

    static func _going(fraction: float) -> float:
        return clampf(fraction / HANDOVER, 0.0, 1.0)

    static func _coming(fraction: float) -> float:
        return clampf((fraction - HANDOVER) / (1.0 - HANDOVER), 0.0, 1.0)


## One light being composed from its parts: the files it reads, the images read
## from them, and the picture made of them. The files of every light are read
## at once on the worker threads and then each light is blended on one, which
## is what keeps two lights fading within a few milliseconds of one.
class Composing:
    const HALF_LEVEL: float = 0.5 / 255.0
    const NUDGE: float = 0.0001
    ## How many bands of rows a light is blended in, each on a task of its own.
    const BANDS: int = 8

    ## The back, the strip and the land, the body and its reflection when
    ## there is one, and where the strip and the land start and the body's
    ## corner stands.
    var paths: Array[String]
    var top: int
    var origin: int
    var roll: float
    var under: Array[PictureOverlays.Overlay]
    var corner: Vector2i
    var over_clouds: bool
    ## Where the reflection's corner stands, when `paths` holds one after the
    ## body, and how much of the body and the reflection shows.
    var reflection_corner: Vector2i
    var shown: float
    ## The images of `paths`, then each overlay of *under*, in RGBA8, each
    ## written by the one task that reads its file.
    var images: Array[Image] = []
    var made: Image
    ## The blended bands of the rows, each written by the one task that blends it.
    var bands: Array[Image] = []

    func _init(
        of_paths: Array[String],
        from_row: int,
        at_column: int,
        at_roll: float,
        laid: Array[PictureOverlays.Overlay],
        body_corner: Vector2i = Vector2i.ZERO,
        body_over_clouds: bool = false,
        reflection_at: Vector2i = Vector2i.ZERO,
        body_shown: float = 1.0
    ) -> void:
        paths = of_paths
        top = from_row
        origin = at_column
        roll = at_roll
        under = laid
        corner = body_corner
        over_clouds = body_over_clouds
        reflection_corner = reflection_at
        shown = body_shown
        images.resize(paths.size() + under.size())

    ## Fetches every picture of *jobs* on this thread and converts them side
    ## by side, then lays each job's overlays,
    ## blends the bands of every job's rows side by side and finishes each job
    ## on a thread of its own, and returns once all are made.
    static func all(jobs: Array[Composing]) -> void:
        if jobs.is_empty():
            return
        var slots: Array[Vector2i] = []
        for at in jobs.size():
            for slot in jobs[at].images.size():
                slots.append(Vector2i(at, slot))
        for at in slots:
            jobs[at.x].fetch(at.y)
        var reading := WorkerThreadPool.add_group_task(func(at: int) -> void: jobs[slots[at].x].read(slots[at].y), slots.size())
        WorkerThreadPool.wait_for_group_task_completion(reading)
        var laying := WorkerThreadPool.add_group_task(func(at: int) -> void: jobs[at].lay_under(), jobs.size())
        WorkerThreadPool.wait_for_group_task_completion(laying)
        var blending := WorkerThreadPool.add_group_task(
            func(at: int) -> void: jobs[floori(at / float(BANDS))].blend_band(at % BANDS), jobs.size() * BANDS
        )
        WorkerThreadPool.wait_for_group_task_completion(blending)
        var finishing := WorkerThreadPool.add_group_task(func(at: int) -> void: jobs[at].finish(), jobs.size())
        WorkerThreadPool.wait_for_group_task_completion(finishing)

    ## Reads the picture of *slot* into `images`, on the thread that calls
    ## `all`, since the picture is a lossy texture and its image is
    ## asked of the renderer, which a worker waiting on that thread would
    ## deadlock. Uncached, so the texture goes once its image is taken, unless
    ## `keep` read it ahead, when it is the kept image, which `read` copies.
    func fetch(slot: int) -> void:
        images[slot] = PictureParts.kept_or_read(path_of(slot))

    ## The picture of *slot*, a part of `paths` or then an overlay of `under`.
    func path_of(slot: int) -> String:
        return paths[slot] if slot < paths.size() else under[slot - paths.size()].path

    ## Brings what `fetch` read for *slot* to the format it is blended in,
    ## a fresh image of its own, so this opening's blend never reaches the next.
    func read(slot: int) -> void:
        var image := images[slot].duplicate() as Image
        image.clear_mipmaps()
        image.convert(Image.FORMAT_RGBA8)
        if slot > 0 and slot < paths.size():
            image.convert(Image.FORMAT_RGBAF)
        if slot >= 3 and slot < paths.size() and shown < 1.0:
            image = _faded(image, shown)
        images[slot] = image

    ## Starts composing *jobs* on the pool, a task for each, when every picture
    ## they need is kept, and answers the group task, which the caller waits
    ## for. Answers -1 and starts nothing when one is not kept, because only
    ## this thread may read it, and then `all` composes them here.
    static func in_background(jobs: Array[Composing]) -> int:
        if jobs.is_empty():
            return -1
        for job in jobs:
            for slot in job.images.size():
                if not PictureParts.is_kept(job.path_of(slot)):
                    return -1
        for job in jobs:
            for slot in job.images.size():
                job.fetch(slot)
        return WorkerThreadPool.add_group_task(func(at: int) -> void: jobs[at].read_and_compose(), jobs.size())

    ## Reads every picture `fetch` fetched and composes them, on one thread.
    func read_and_compose() -> void:
        for slot in images.size():
            read(slot)
        compose()

    ## Blends what `read` read into `made`, the bands of its rows one after
    ## the other where `all` blends them side by side.
    func compose() -> void:
        lay_under()
        for at in BANDS:
            blend_band(at)
        finish()

    ## Lays the overlays *under* the clouds over the back, in eight bits, as
    ## the stars always were, before the rows are cut into bands.
    func lay_under() -> void:
        made = images[0]
        for at in under.size():
            _lay(made, images[paths.size() + at], under[at].opacity)
        bands.resize(BANDS)

    ## Blends band *at* of the strip's rows: the body, the strip moved round
    ## by the drift and the land over the back's rows, in float, because a
    ## blend into eight bits rounds down. The hazy day's sky, under its body,
    ## its clouds and its haze, came to 0.65 levels from Sara's export on the
    ## mean that way. The band then gains half a level so that its one
    ## conversion back to eight bits rounds to the nearest, and the rows are
    ## blended a band to a task because the light's own thread took twenty
    ## milliseconds over them.
    func blend_band(at: int) -> void:
        var strip := images[1]
        var width := strip.get_width()
        var rows := strip.get_height()
        var first := _band_starts(rows, at)
        var tall := _band_starts(rows, at + 1) - first
        var shift := posmod(origin + floori(roll * float(width)), width)
        var band := made.get_region(Rect2i(0, top + first, width, tall))
        band.convert(Image.FORMAT_RGBAF)
        var within := Rect2i(Vector2i.ZERO, band.get_size())
        var body_at := corner - Vector2i(0, top + first)
        if paths.size() > 3 and not over_clouds:
            _lay_within(band, images[3], body_at, within)
        band.blend_rect(strip, Rect2i(0, first, width - shift, tall), Vector2i(shift, 0))
        if shift > 0:
            band.blend_rect(strip, Rect2i(width - shift, first, shift, tall), Vector2i.ZERO)
        if paths.size() > 3 and over_clouds:
            _lay_within(band, images[3], body_at, within)
        band.blend_rect(images[2], Rect2i(0, first, width, tall), Vector2i.ZERO)
        _round_not_down(band)
        band.convert(Image.FORMAT_RGBA8)
        bands[at] = band

    ## Puts the blended bands back into `made`, lays the reflection over them
    ## and makes its mipmaps.
    func finish() -> void:
        var rows := images[1].get_height()
        for at in BANDS:
            made.blit_rect(bands[at], Rect2i(Vector2i.ZERO, bands[at].get_size()), Vector2i(0, top + _band_starts(rows, at)))
        bands.clear()
        if paths.size() > 4:
            _lay_reflection()
        made.generate_mipmaps()

    ## Lays the reflection over `made` at its corner and as much of it as
    ## shows, in float and rounded to the nearest as a band is, since it was
    ## solved to give back the light at its own place within half a level.
    func _lay_reflection() -> void:
        var reflection := images[4]
        var laid := Rect2i(reflection_corner, reflection.get_size()).intersection(Rect2i(Vector2i.ZERO, made.get_size()))
        if not laid.has_area():
            return
        var region := made.get_region(laid)
        region.convert(Image.FORMAT_RGBAF)
        region.blend_rect(reflection, Rect2i(laid.position - reflection_corner, laid.size), Vector2i.ZERO)
        _round_not_down(region)
        region.convert(Image.FORMAT_RGBA8)
        made.blit_rect(region, Rect2i(Vector2i.ZERO, laid.size), laid.position)

    ## *picture*, in float, with its alpha scaled by *share*.
    static func _faded(picture: Image, share: float) -> Image:
        var texels := picture.get_data().to_float32_array()
        for at in range(3, texels.size(), 4):
            texels[at] *= share
        return Image.create_from_data(
            picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBAF, texels.to_byte_array()
        )

    ## The row band *at* of a light's *rows* starts at, counted from the strip's top.
    static func _band_starts(rows: int, at: int) -> int:
        return floori(float(rows * at) / float(BANDS))

    ## Adds half a level of 255 to every texel of *rows*, so the conversion
    ## to eight bits, which rounds down, rounds to the nearest. Blended as a
    ## colour far over white at an alpha near naught, which adds the same to a
    ## texel of any colour within a fortieth of a level.
    static func _round_not_down(rows: Image) -> void:
        var half := Image.create_empty(rows.get_width(), rows.get_height(), false, Image.FORMAT_RGBAF)
        half.fill(Color(HALF_LEVEL / NUDGE, HALF_LEVEL / NUDGE, HALF_LEVEL / NUDGE, NUDGE))
        rows.blend_rect(half, Rect2i(Vector2i.ZERO, rows.get_size()), Vector2i.ZERO)

    ## Lays *body* over *onto*, the rows the strip and the land are laid
    ## over, with its corner at *at_corner* and cut to *within*, all of them,
    ## since under them the back is the whole light and a body moved down
    ## there would stand over the ground.
    static func _lay_within(onto: Image, body: Image, at_corner: Vector2i, within: Rect2i) -> void:
        var laid := Rect2i(at_corner, body.get_size()).intersection(within)
        if laid.has_area():
            onto.blend_rect(body, Rect2i(laid.position - at_corner, laid.size), laid.position)

    ## Lays *overlay* over *onto* at *opacity*, through the box it covers alone,
    ## since its alpha is scaled by hand there.
    static func _lay(onto: Image, overlay: Image, opacity: float) -> void:
        var box := overlay.get_used_rect()
        if box.has_area():
            var cut := overlay.get_region(box)
            var bytes := cut.get_data()
            for at in range(3, bytes.size(), 4):
                bytes[at] = roundi(float(bytes[at]) * opacity)
            cut.set_data(box.size.x, box.size.y, false, Image.FORMAT_RGBA8, bytes)
            onto.blend_rect(cut, Rect2i(Vector2i.ZERO, box.size), box.position)
