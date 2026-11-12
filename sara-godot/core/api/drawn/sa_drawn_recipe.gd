## What a drawn layer's pixels are drawn from: a vector layer's objects, a text
## layer's block, or a module's own shapes. A module extends this, names its
## script on `SaLayerTypeDescriptor.recipe`, and registers the type through
## `SaRegistries` as every built-in does.
##
## **Its chunks are a cache.** The layer holds ordinary `SaChunk`s at the
## document's depth, allocated only where the recipe covers something, so
## every reader of `SaLayer.chunks` reads a drawn layer as it reads paint: the
## compositor and its folds, masks, clipping, Merge Down, Select Opaque, the
## wand, Copy and the eyedropper. `SaDrawnLayer` writes them, and nothing else
## does, since a brush is refused on a drawn layer.
##
## **The face is narrow.** [method bounds] says where the recipe draws,
## [method draw] writes one region of one chunk, [signal changed] names the
## rectangles an edit touched, and the JSON pair is what the `.sad` and the
## history keep. The SVG pair and [method take_map] are the vector and text
## layers' to answer, and a recipe that has no such thing keeps the answers
## here, which say it has none.
@tool
class_name SaDrawnRecipe
extends RefCounted

## Said by an edit with the rectangles it touched in document pixels, an
## object's bounds before and after it, each grown by its stroke and a pixel of
## edge. `SaDrawnLayer` redraws those and nothing else (hard rule 2).
@warning_ignore("unused_signal")
signal changed(rects: Array[Rect2i])


## Where the recipe draws anything, in document pixels, an empty rectangle
## when it draws nothing. A chunk wholly outside it is let go.
func bounds() -> Rect2i:
    return Rect2i()


## Writes the part of the recipe inside *region* into *chunk*. *region* is in
## document pixels, lies inside the one chunk whose square holds its corner,
## is a whole number of 16 pixel tiles there, and has been cleared to
## transparent. Nothing outside it may change, since the chunk's other pixels
## are drawn already. A chunk at double resolution is twice as many texels
## across, `chunk.pixel_size()`, for the same region.
func draw(_region: Rect2i, _chunk: SaChunk) -> void:
    pass


## Everything the recipe is, as plain values a JSON file holds.
func to_json() -> Dictionary:
    return {}


## Becomes what *saved*, a dictionary [method to_json] wrote, describes. Says
## nothing on [signal changed]: whoever reads a recipe back redraws it.
func from_json(_saved: Dictionary) -> void:
    pass


## What the recipe says of itself to the state dump and the door, a few plain
## values a script checks a layer by without a picture, empty for one with
## nothing to say. The whole of it is [method to_json].
func report() -> Dictionary:
    return {}


## The recipe as SVG, empty for one with no SVG form.
func to_svg() -> String:
    return ""


## Becomes what the SVG *text* describes, and answers whether it could.
func from_svg(_text: String) -> bool:
    return false


## Takes the Transform tool's *map* into its own geometry, so a move, a scale
## or a turn leaves the recipe sharp rather than resampling its pixels, and
## answers whether it did. One that cannot answers false and stays as it was.
func take_map(_map: Transform2D) -> bool:
    return false
