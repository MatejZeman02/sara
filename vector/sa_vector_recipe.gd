## A vector layer's recipe: an ordered list of objects, drawn bottom to top,
## each a rectangle or an ellipse with its fill and its stroke.
##
## The layer is a drawn layer on the skeleton's door (`SaDrawnRecipe`), so
## its chunks are a cache every reader reads as paint, the history keeps the
## objects' JSON before and after an edit, and the `.sad` keeps the objects
## and no chunk. One recipe holds many objects, so a page of comic panels is
## one layer and one row in the Layers docker.
##
## **An edit says the object's bounds before and after it**, and the door
## redraws those two rectangles and nothing between them (hard rule 2). Each
## edit below is one call, which a tool or the door runs inside
## `SaDrawnLayer.edit` so the history records it as one step.
##
## Every object is drawn through `SaVectorFill.draw_region`, each part of it
## through a kernel of its own for as long as the layer lives, since a kernel
## keeps a chunk's buffers only until it draws that chunk again, and keeps the
## outline of the path it drew last, which the object hands it again until its
## shape changes.
@tool
extends SaDrawnRecipe

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")

## The objects, bottom first.
var objects: Array[VectorObject] = []
## Counts every change, an edit or a read, so a list on screen knows when
## to show the objects again without comparing them.
var edits: int = 0
## Every tile the kernel dispatched since a caller last cleared it, in the
## layer's texels, which is what tells a suite or a dump what a redraw touched.
var drawn_tiles: Array[Rect2i] = []

## Each object's kernel for each of its parts, by its id and the part's place.
## None is let go of while the layer lives, because a kernel freed with a
## draw still pending takes the buffers that dispatch reads.
var _kernels: Dictionary[String, SaVectorFill] = {}


func bounds() -> Rect2i:
    var out := Rect2i()
    for object in objects:
        if not object.visible:
            continue
        out = object.bounds() if out.size == Vector2i.ZERO else out.merge(object.bounds())
    return out


func draw(region: Rect2i, chunk: SaChunk) -> void:
    for object in objects:
        if not object.visible or not object.bounds().intersects(region):
            continue
        var parts := object.parts()
        for i in parts.size():
            var key := "%s/%d" % [object.id, i]
            if not _kernels.has(key):
                _kernels[key] = SaVectorFill.new()
            var kernel := _kernels[key]
            kernel.draw_region(chunk, region, parts[i][0] as SaVectorPath, parts[i][1] as Color, object.origin())
            drawn_tiles.append_array(kernel.drawn_tiles)


## The object named *object_id*, or null.
func find(object_id: String) -> VectorObject:
    for object in objects:
        if object.id == object_id:
            return object
    return null


## The topmost visible object that is not locked under *point*, in document
## pixels, within *reach* pixels of its edge, or null. Exact against the
## numbers, so nothing is read back (hard rule 1).
func hit(point: Vector2, reach: float = 0.0) -> VectorObject:
    for i in range(objects.size() - 1, -1, -1):
        var object := objects[i]
        if object.visible and not object.locked and object.has_point(point, reach):
            return object
    return null


## Puts *object* on top and draws it.
func add(object: VectorObject) -> void:
    objects.append(object)
    _touched([object.bounds()])


## Gives the object *object_id* the box *to*, a move or a resize.
func reshape(object_id: String, to: Rect2) -> void:
    var object := find(object_id)
    if object == null:
        return
    var before := object.bounds()
    object.box = to.abs()
    _touched([before, object.bounds()])


## Writes each value of *values* into the object *object_id* by its name in
## the object's JSON, a fill, a stroke, a width, a name, its eye or its lock.
func restyle(object_id: String, values: Dictionary) -> void:
    var object := find(object_id)
    if object == null:
        return
    var before := object.bounds()
    var saved := object.to_json()
    for key: String in values:
        saved[key] = values[key]
    object.read(saved)
    _touched([before, object.bounds()])


## Takes the object *object_id* off the layer.
func remove(object_id: String) -> void:
    var object := find(object_id)
    if object == null:
        return
    objects.erase(object)
    _touched([object.bounds()])


## Moves the object *object_id* by *places* in the drawing order, up for a
## positive count, as far as the top or the bottom.
func reorder(object_id: String, places: int) -> void:
    var object := find(object_id)
    if object == null:
        return
    var at := objects.find(object)
    var to := clampi(at + places, 0, objects.size() - 1)
    if to == at:
        return
    objects.remove_at(at)
    objects.insert(to, object)
    _touched([object.bounds()])


## A fresh id for an object of *kind*, `rect-3` or `ellipse-1`, taken by none
## of *taken*, the ids already in the document.
static func new_id(kind: VectorObject.Kind, taken: Dictionary) -> String:
    var stem := "ellipse" if kind == VectorObject.Kind.ELLIPSE else "rect"
    var n := 1
    while taken.has("%s-%d" % [stem, n]):
        n += 1
    return "%s-%d" % [stem, n]


## Every object id in *document*'s vector layers, as keys.
static func ids_in(document: SaDocument) -> Dictionary:
    var out := {}
    if document == null:
        return out
    for child in document.get_children():
        var layer := child as SaLayer
        var recipe: Variant = layer.recipe if layer != null else null
        if recipe == null or not recipe.has_method("hit"):
            continue
        for object: VectorObject in recipe.objects:
            out[object.id] = true
    return out


func to_json() -> Dictionary:
    var listed: Array = []
    for object in objects:
        listed.append(object.to_json())
    return {"objects": listed}


func from_json(saved: Dictionary) -> void:
    objects.clear()
    var listed: Variant = saved.get("objects", [])
    if listed is Array:
        for held: Variant in listed:
            var object := VectorObject.new()
            if held is Dictionary and object.read(held):
                objects.append(object)
    edits += 1


func _touched(rects: Array[Rect2i]) -> void:
    edits += 1
    changed.emit(rects)
