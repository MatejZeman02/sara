## What a document's pixels are a picture of: a flat canvas, or a panorama whose
## left edge meets its right. The second descriptor beside the colour space, held
## at `SaDocument.projection`, written to the `.sad` header and assigned under
## Image > Projection....
##
## **A kind** is what a module registers through
## `SaContext.register_projection`, an open list and not two: the skeleton
## registers flat, equirectangular and polar through that call the way a module
## would. Each kind brings four things, the map from a document pixel to a view
## position or direction and back, its
## wrap, its fold at a singular point and the stretch a round dab needs at a
## pixel, and a kind whose view is a disc says where the disc lies on the flat
## canvas. What reads a projection calls those and names no kind.
##
## **The descriptor** is a kind, an orientation and the wrap, which is the
## kind's and never chosen. It is written by its constructor alone, so a
## document changes projection by being handed a new one, which is what makes
## [method assign] one history step.
##
## **Directions** are in Godot's frame: y up, minus z ahead, x to the right. A
## sphere kind's longitude runs the way the picture reads from inside, turning
## right as x grows.
class_name SaProjection
extends RefCounted

## What a kind joins at its edges. Derived from the kind, except on a flat
## document, whose wrap the painter chooses on the top bar.
enum Wrap { NONE, X, XY }

## A flat document's wrap as the `.sad` header's `wrap` key spells it. NONE
## is never written, so a file from before the key opens with no wrap.
const WRAP_WORDS := {Wrap.NONE: "none", Wrap.X: "x", Wrap.XY: "xy"}

## What a kind's view position is: the document pixel itself for a canvas, a
## unit direction for a sphere, a point of the unit disc, z nought, for a disc.
enum View { CANVAS, SPHERE, DISC }

## The kind every document is until told otherwise, and what a file without
## the header key reads as.
const FLAT := &"flat"
const EQUIRECTANGULAR := &"equirectangular"
const POLAR := &"polar"

## The `.sad` header's key, additive to v4 the way the colour space's is.
const HEADER_KEY := "projection"
## The tip a stretched dab is shaped from, `Stretched`.
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The kind, never null. One a file names and no module registered is kept by
## its id and maps as flat, so saving the file again loses nothing.
var kind: Kind
## Where the kind's angle nought points, never null.
var orientation: Heading
## The kind's wrap, read off it when this was made, or on a flat document the
## wrap it was made with. Every reader of a wrap reads it here, so a flat
## document that wraps is painted, filtered and selected across its edges by
## the same code a panorama is.
var wrapping: Wrap


## *projection_kind* null is flat, and *projection_orientation* null is
## Blender's with no yaw. *flat_wrap* is a flat document's wrap and is ignored
## for any other kind, whose wrap is its own.
func _init(projection_kind: Kind = null, projection_orientation: Heading = null, flat_wrap: Wrap = Wrap.NONE) -> void:
    kind = projection_kind if projection_kind != null else Kind.new(FLAT, "Flat")
    orientation = projection_orientation if projection_orientation != null else Heading.new()
    wrapping = flat_wrap if kind.id == FLAT else kind.wrapping


## Whether *other* is the same kind in the same orientation. A flat
## document's wrap is not part of it, since a wrap moves no pixel and the
## Projection dialog's Flat is the same picture wrapped or not.
func matches(other: SaProjection) -> bool:
    return other != null and other.kind.id == kind.id and orientation.matches(other.orientation)


## Flat in Blender's orientation with no yaw, which a header leaves out.
## A flat document that wraps is not, so its header keeps the wrap.
func is_default() -> bool:
    return kind.id == FLAT and orientation.matches(Heading.new()) and wrapping == Wrap.NONE


## The position *pixel* of a document of *size* stands for in this kind's view.
func to_view(pixel: Vector2, size: Vector2) -> Vector3:
    return kind.to_view(pixel, size, orientation)


## The document pixel *point* of this kind's view stands on.
func from_view(point: Vector3, size: Vector2) -> Vector2:
    return kind.from_view(point, size, orientation)


## Where *pixel*, which may lie past an edge, lands inside the document.
func fold(pixel: Vector2, size: Vector2) -> Vector2:
    return kind.fold(pixel, size)


## How much wider than tall a round dab is in document pixels at *pixel*.
func stretch(pixel: Vector2, size: Vector2) -> float:
    return kind.stretch(pixel, size)


## The map from the flat canvas of a document of *size*, in document pixels as
## the flat view lays them out, to this kind's view position on a plane.
func plane(size: Vector2) -> Transform2D:
    return kind.plane(size)


## The maps that take the part of *region*, in document pixels, past a pole
## over it to the far side, read downward, one for each pole it reaches past.
## None for a kind with no pole, whose edge clips.
func pole_folds(region: Rect2, size: Vector2) -> Array[Transform2D]:
    return kind.pole_folds(region, size)


## The kind and orientation in words, for the dialog's Current line.
func describe() -> String:
    var words := String(TranslationServer.translate(kind.label))
    if kind.view == View.CANVAS:
        return words
    return "%s, %s" % [words, orientation.describe()]


func to_header() -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {
        "kind": String(kind.id), "orientation": String(orientation.preset), "yaw": orientation.yaw
    }
    if kind.id == FLAT and wrapping != Wrap.NONE:
        out["wrap"] = WRAP_WORDS[wrapping]
    return out


## The projection *raw*, a header's value, names, its kind looked up in *kinds*.
## Absent is flat, which every file written before the key was. A kind *kinds*
## does not hold, or any kind when there is no *kinds*, is kept by its id.
static func from_header(raw: Variant, kinds: Kinds) -> SaProjection:
    var entry := SaTyped.strings(raw)
    var kind_id := SaTyped.name_at(entry, "kind", FLAT)
    var found: Kind = kinds.find(kind_id) if kinds != null else null
    if found == null:
        if kinds != null and kind_id != FLAT:
            push_warning("SaProjection: the file's projection '%s' is registered by no module, and maps as flat." % kind_id)
        found = Kind.new(kind_id, String(kind_id).capitalize())
    var turned := Heading.new(SaTyped.name_at(entry, "orientation", Heading.BLENDER), SaTyped.float_at(entry, "yaw", 0.0))
    # A file written before projections could wrap has no `wrap`, and a word this build does not
    # know reads as no wrap too.
    var word := String(SaTyped.name_at(entry, "wrap", &"none"))
    var edges: Wrap = WRAP_WORDS.find_key(word) if WRAP_WORDS.values().has(word) else Wrap.NONE
    return SaProjection.new(found, turned, edges)


## Makes *document*, a flat one, wrap as *edges* says, and turns its infinite
## canvas off when it wraps, because a wrap needs a fixed page. True when that
## turned the infinite canvas off, for the caller to say so. Not a history
## step, as the infinite canvas's switch is not, and it marks the document
## changed, since the `.sad` keeps it. A panorama's wrap is its kind's, so
## nothing happens to one. The argument is not called *wrap*, which is a
## built-in function of Godot's and warns when a name shadows it.
static func wrap_flat(document: SaDocument, edges: Wrap) -> bool:
    if document == null or document.projection.kind.id != FLAT:
        return false
    var stopped := false
    if edges != Wrap.NONE and document.infinite_canvas != null and document.infinite_canvas.on:
        document.infinite_canvas.on = false
        stopped = true
    if document.projection.wrapping != edges:
        document.projection = SaProjection.new(document.projection.kind, document.projection.orientation, edges)
        document.modified = true
    return stopped


## Says *target* is what *document*'s pixels are, as one history step that
## moves no pixel. False, and no step, when it already is.
static func assign(document: SaDocument, target: SaProjection) -> bool:
    if document == null or target == null or target.matches(document.projection):
        return false
    var before := document.projection
    var apply := Callable(document, &"set")
    if document.history != null:
        document.history.commit_pair("Assign Projection", apply.bind(&"projection", target), apply.bind(&"projection", before))
    document.projection = target
    return true


## Redraws every layer of *document* from its projection into *target*, so the
## picture stays where it is in the view and its pixels move, at the canvas
## size the pair of kinds asks for, as one history step. False, and no step,
## when it already is *target* or there is no GPU to draw with. Image >
## Projection's Convert, and `sa_projection_conversion.gd` says how.
static func reproject(document: SaDocument, target: SaProjection) -> bool:
    return SaProjectionConversion.new(document, target).run()


## What [method reproject] would do to *document* in one sentence for the
## dialog: the size the canvas takes, and the layers that hold no pixels and
## keep their record.
static func reproject_note(document: SaDocument, target: SaProjection) -> String:
    return SaProjectionConversion.note(document, target)


## The canvas a document of *size* in *from* takes when converted to *to*.
static func reprojected_size(from: SaProjection, to: SaProjection, size: Vector2i) -> Vector2i:
    return SaProjectionConversion.size_for(from, to, size)


## Flat, equirectangular and polar, which the skeleton registers through
## `SaContext.register_projection` as a module would.
static func builtins() -> Array[Kind]:
    var out: Array[Kind] = [Kind.new(FLAT, "Flat"), Equirectangular.new(), Polar.new()]
    return out


## Where a kind's angle nought points and which way the angle runs, as a preset
## of a program the picture is made for and a free yaw on top of it.
##
## Measured against both programs' own code. Godot's sky reads a direction at
## `atan(x, -z) / TAU` across, so its nought is straight ahead. Blender's Cycles
## reads it at `0.5 - atan(y, x) / TAU` with z up, which with Blender's z taken
## to Godot's y the way a glTF is is a quarter turn round from Godot's, running
## the same way.
##
## Called a heading because an inner class named `Orientation` loses to the
## global enum of that name, and every typed use of it fails to parse.
class Heading:
    extends RefCounted

    const BLENDER := &"blender"
    const GODOT := &"godot"

    ## The azimuth of angle nought under each preset, in turns from straight
    ## ahead towards the right.
    const ZEROS: Dictionary[StringName, float] = {BLENDER: -0.25, GODOT: 0.0}
    const LABELS: Dictionary[StringName, String] = {BLENDER: "Blender's orientation", GODOT: "Godot's orientation"}

    var preset: StringName = BLENDER
    ## Degrees added to the preset's nought, in (-180, 180].
    var yaw: float = 0.0

    ## A preset neither program has is Blender's, the default.
    func _init(orientation_preset: StringName = BLENDER, orientation_yaw: float = 0.0) -> void:
        preset = orientation_preset if ZEROS.has(orientation_preset) else BLENDER
        yaw = -wrapf(-orientation_yaw, -180.0, 180.0)

    func matches(other: Heading) -> bool:
        return other != null and other.preset == preset and is_equal_approx(other.yaw, yaw)

    ## The azimuth in radians of the angle *turned*, which runs from nought to
    ## TAU across the document.
    func azimuth(turned: float) -> float:
        return (ZEROS[preset] * TAU) + deg_to_rad(yaw) + turned

    ## The angle across the document, in [0, TAU), of *at*, an azimuth.
    func angle(at: float) -> float:
        return fposmod(at - (ZEROS[preset] * TAU) - deg_to_rad(yaw), TAU)

    func describe() -> String:
        var words := String(TranslationServer.translate(LABELS[preset]))
        if is_zero_approx(yaw):
            return words
        return String(TranslationServer.translate("%s turned %s degrees")) % [words, String.num(yaw, 1).trim_suffix(".0")]

    static func presets() -> Array[StringName]:
        var out: Array[StringName] = []
        out.assign(ZEROS.keys())
        return out


## One kind of projection. As it stands it is flat: the view is the canvas, no
## edge joins another, nothing folds and a round dab is round. A module's kind
## extends it and answers the four for its own geometry.
class Kind:
    extends RefCounted

    var id: StringName
    ## What the dialog lists it as.
    var label: String
    var wrapping: Wrap
    var view: View

    func _init(kind_id: StringName, kind_label: String, kind_wrap := Wrap.NONE, kind_view := View.CANVAS) -> void:
        id = kind_id
        label = kind_label
        wrapping = kind_wrap
        view = kind_view

    ## The view position of *pixel* in a document of *size*.
    func to_view(pixel: Vector2, _size: Vector2, _orientation: Heading) -> Vector3:
        return Vector3(pixel.x, pixel.y, 0.0)

    ## The pixel under *point*, a view position.
    func from_view(point: Vector3, _size: Vector2, _orientation: Heading) -> Vector2:
        return Vector2(point.x, point.y)

    ## Where *pixel*, which may lie past an edge, lands. A flat document keeps
    ## it where it is, for the caller to clamp.
    func fold(pixel: Vector2, _size: Vector2) -> Vector2:
        return pixel

    ## How much wider than tall, in document pixels, a dab that is round in the
    ## view is at *pixel*. INF at a singular point, for the caller to cap.
    func stretch(_pixel: Vector2, _size: Vector2) -> float:
        return 1.0

    ## Where this kind's view plane lies on the flat canvas of a document of
    ## *size*: the map from the canvas's own coordinates, document pixels as
    ## the flat view lays them out, to the view position. A canvas's view
    ## position is the pixel itself, and a disc kind says where its disc lies.
    func plane(_size: Vector2) -> Transform2D:
        return Transform2D.IDENTITY

    ## The maps that take a region's part past a pole over it. A flat
    ## document has no pole, and its edge clips.
    func pole_folds(_region: Rect2, _size: Vector2) -> Array[Transform2D]:
        return []

    ## *pixel* past the top row taken over the pole to the far side, read
    ## downward, the fold both built-in panoramas share.
    static func over_pole(pixel: Vector2, size: Vector2) -> Vector2:
        if pixel.y < 0.0:
            return Vector2(pixel.x + size.x * 0.5, -pixel.y)
        return pixel

    ## [method over_pole] as a map of the plane, for the top row, or for the
    ## bottom one when *row* is the canvas's height: half a turn across and
    ## the rows read back from the pole's row. It turns the plane over, so a
    ## dab drawn through it is the mirror of the one asked for.
    static func pole_map(size: Vector2, row: float = 0.0) -> Transform2D:
        return Transform2D(Vector2.RIGHT, Vector2.UP, Vector2(size.x * 0.5, 2.0 * row))


## Longitude across, latitude down, the top row the zenith and the bottom row
## the nadir. It wraps in x, and a position past the top row at longitude λ is
## the top row at λ plus half a turn, read downward.
class Equirectangular:
    extends Kind

    func _init() -> void:
        super(EQUIRECTANGULAR, "Equirectangular", Wrap.X, View.SPHERE)

    func to_view(pixel: Vector2, size: Vector2, orientation: Heading) -> Vector3:
        var latitude := PI * (0.5 - pixel.y / size.y)
        var at := orientation.azimuth(TAU * pixel.x / size.x)
        return Vector3(cos(latitude) * sin(at), sin(latitude), -cos(latitude) * cos(at))

    func from_view(point: Vector3, size: Vector2, orientation: Heading) -> Vector2:
        var ray := point.normalized()
        var latitude := asin(clampf(ray.y, -1.0, 1.0))
        var across := orientation.angle(atan2(ray.x, -ray.z))
        return Vector2(across / TAU * size.x, (0.5 - latitude / PI) * size.y)

    func fold(pixel: Vector2, size: Vector2) -> Vector2:
        var folded := over_pole(pixel, size)
        if folded.y > size.y:
            folded = Vector2(folded.x + size.x * 0.5, 2.0 * size.y - folded.y)
        return Vector2(fposmod(folded.x, size.x), clampf(folded.y, 0.0, size.y))

    ## The zenith above the top row and the nadir below the bottom one.
    func pole_folds(region: Rect2, size: Vector2) -> Array[Transform2D]:
        var out: Array[Transform2D] = []
        if region.position.y < 0.0:
            out.append(pole_map(size))
        if region.end.y > size.y:
            out.append(pole_map(size, size.y))
        return out

    ## One over the cosine of the latitude, in pixels of the document's own
    ## shape, which is one at the equator only when it is twice as wide as tall.
    func stretch(pixel: Vector2, size: Vector2) -> float:
        if pixel.y <= 0.0 or pixel.y >= size.y:
            return INF
        return size.x / (2.0 * size.y * cos(PI * (0.5 - pixel.y / size.y)))


## The angle across and the radius down, the top row the centre and the bottom
## row the rim. A horizontal stroke is a ring and a vertical one a spoke. It
## wraps in x, and the top row is one point that folds as a pole does.
class Polar:
    extends Kind

    func _init() -> void:
        super(POLAR, "Polar", Wrap.X, View.DISC)

    ## Angle nought points up the disc, as straight ahead points up a map.
    func to_view(pixel: Vector2, size: Vector2, orientation: Heading) -> Vector3:
        var radius := pixel.y / size.y
        var at := orientation.azimuth(TAU * pixel.x / size.x)
        return Vector3(radius * sin(at), radius * cos(at), 0.0)

    func from_view(point: Vector3, size: Vector2, orientation: Heading) -> Vector2:
        var across := orientation.angle(atan2(point.x, point.y))
        return Vector2(across / TAU * size.x, Vector2(point.x, point.y).length() * size.y)

    ## Past the rim is outside the disc, which nothing folds into it.
    func fold(pixel: Vector2, size: Vector2) -> Vector2:
        var folded := over_pole(pixel, size)
        return Vector2(fposmod(folded.x, size.x), folded.y)

    ## The centre, the top row, and never the rim.
    func pole_folds(region: Rect2, size: Vector2) -> Array[Transform2D]:
        var out: Array[Transform2D] = []
        if region.position.y < 0.0:
            out.append(pole_map(size))
        return out

    ## A ring at radius r pixels is TAU r long in the view and the width of the
    ## document across it.
    func stretch(pixel: Vector2, size: Vector2) -> float:
        if pixel.y <= 0.0:
            return INF
        return size.x / (TAU * pixel.y)

    ## The disc's centre at the canvas's middle and its rim the canvas's
    ## height out, so a row is one pixel of the canvas outwards, the scale
    ## [method stretch] assumes, and up the disc is up the screen.
    func plane(size: Vector2) -> Transform2D:
        var unit := 1.0 / maxf(size.y, 1.0)
        return Transform2D(Vector2(unit, 0.0), Vector2(0.0, -unit), Vector2(-0.5 * size.x * unit, 0.5 * size.y * unit))


## A dab's half axes and turn in document pixels, stretched in x by the kind's
## stretch at its centre so that it is round where the view shows the document
## as a sphere. The kernel draws a shape turned in its own
## frame, so the stretched one is put back in that form. An ellipse takes the
## two axes of its stretched image, which is the same ellipse exactly. A
## picture or a rectangle is drawn along the stretched image of its own x
## axis, which keeps its turn as the stretch comes down to one and drops only
## the shear a stretch puts on a turned one. A spiked tip keeps its flat shape:
## its petals point every way in its own frame, and no pair of axes draws them
## stretched one way. The mirror is the flat dab's, since every shape the
## kernel draws but the picture is symmetric about its own axes and the
## picture keeps its x axis.
##
## **The cap.** The stretch runs to infinity at a pole, so it stops where the
## shape reaches half the canvas's width either side of its centre. There the
## dab already covers every longitude of the row through its centre, its copy
## folded over the pole the far half of them, and a wider one would paint over
## its own copy across the seam.
class Stretched:
    extends RefCounted

    ## The half axes, along the turned frame's x and y.
    var half_extent: Vector2
    ## The frame's turn, in radians.
    var radians: float
    ## The stretch the dab is drawn at, after the cap, and one for a flat dab.
    var stretch: float = 1.0

    ## *flat_extent* and *flat_radians* are the flat dab's, its mirror already
    ## taken into the turn, and *wanted* is `SaDabParams.stretch`, nought or
    ## below for the flat dab. *tip* is read for its spikes, generator and
    ## shape, as `SaDabPacking` reads it, and *width* is the canvas's.
    func _init(flat_extent: Vector2, flat_radians: float, wanted: float, tip: SaBrushTipScript, width: float) -> void:
        half_extent = flat_extent
        radians = flat_radians
        if wanted <= 0.0 or tip == null or tip.spikes > 2:
            return
        var c := cos(flat_radians)
        var s := sin(flat_radians)
        var a := flat_extent.x
        var b := flat_extent.y
        var picture := tip.effective_generator() == SaDabGeometry.Generator.IMAGE or tip.shape != SaBrushTipScript.Shape.CIRCLE
        # The flat shape's own half width, which the stretch multiplies.
        var reach := absf(a * c) + absf(b * s) if picture else sqrt(pow(a * c, 2.0) + pow(b * s, 2.0))
        # A dab already wider than half the canvas is not stretched further,
        # and one a kind narrows is narrowed whatever its size.
        stretch = minf(wanted, maxf(width * 0.5 / maxf(reach, 1e-6), 1.0))
        if picture:
            var along := sqrt(pow(stretch * c, 2.0) + s * s)
            half_extent = Vector2(a * along, b * stretch / along)
            radians = atan2(s, stretch * c)
            return
        # The ellipse's stretched image has the axes of the square root of
        # its matrix times its transpose, whose two eigenvalues are these.
        var p := stretch * stretch * (a * a * c * c + b * b * s * s)
        var r := a * a * s * s + b * b * c * c
        var q := stretch * (a * a - b * b) * c * s
        var major := sqrt(0.5 * (p + r) + sqrt(0.25 * (p - r) * (p - r) + q * q))
        half_extent = Vector2(major, stretch * a * b / maxf(major, 1e-12))
        radians = 0.5 * atan2(2.0 * q, p - r)


## The registered kinds by id, in the order they were registered.
class Kinds:
    extends RefCounted

    ## Registration and removal.
    signal changed

    var _kinds: Dictionary[StringName, Kind] = {}
    var _owners: Dictionary[StringName, StringName] = {}

    ## Refused for no kind, one with no id, or an id already registered.
    func register(added: Kind, module_id: StringName = &"") -> bool:
        if added == null or added.id == &"":
            push_error("SaProjection.Kinds: a kind needs an id.")
            return false
        if _kinds.has(added.id):
            push_error("SaProjection.Kinds: '%s' is registered already, by '%s'." % [added.id, _owners[added.id]])
            return false
        _kinds[added.id] = added
        _owners[added.id] = module_id
        changed.emit()
        return true

    func unregister_module(module_id: StringName) -> void:
        var gone := _owners.keys().filter(func(kind_id: StringName) -> bool: return _owners[kind_id] == module_id)
        for kind_id: StringName in gone:
            _kinds.erase(kind_id)
            _owners.erase(kind_id)
        if not gone.is_empty():
            changed.emit()

    func find(kind_id: StringName) -> Kind:
        return _kinds.get(kind_id, null)

    func ids() -> Array[StringName]:
        var out: Array[StringName] = []
        out.assign(_kinds.keys())
        return out
