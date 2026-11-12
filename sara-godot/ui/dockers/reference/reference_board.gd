## One reference board: the pictures on it, each with a rectangle in board space
## and a place in the z order, and the board's own zoom and offset.
##
## The model the Reference docker draws and the docker's input moves. Nothing
## here is a Node: a board is data plus the operations the spec names, a move,
## a raise, a fit, a normalise, and the two conversions between board space and
## the docker's picture Control. The docker holds several of these, one per
## tab, and asks the one under the tab that is showing.
##
## **The pictures are kept on the CPU as well as in a texture**, because a
## sample reads a texel, and a readback for one pixel is what hard rule 1 (no CPU-GPU ping-pong)
## exists to avoid. The reference
## is not the canvas and never enters the paint path.
##
## **A path that does not resolve is a placeholder, never a dropped slot.** A
## painting reopened on another machine keeps every rectangle where it was and
## draws the file's name in the empty one, so the painter knows what to put
## back and where.
##
## **Saved as paths and rectangles**, by `to_header` into the `.sad` header or
## the settings file, and back by `from_header`. Additive to the v4 container,
## an older Sara ignores the key. The pictures' own bytes beside them, and a read
## from those when a path does not resolve, are `SaSadReferencePictures`'s.
class_name SaReferenceBoard
extends RefCounted

## The floor and ceiling of the board's zoom. The floor is where a board of
## large photographs still fits a small docker and the ceiling is where one
## texel is a readable square.
const MIN_ZOOM: float = 0.02
const MAX_ZOOM: float = 32.0

## The height every picture is brought to by a normalise, in board units, and
## the gap between two normalised pictures.
const NORMAL_HEIGHT: float = 512.0
const NORMAL_GAP: float = 24.0

## The three readings of "the same size" the Preferences row offers.
const NORMALISE_MODES: Array[String] = ["height", "width", "area"]

## The size a placeholder is drawn at when nothing says how large the picture
## was, which is a fresh open of a path that is already gone.
const PLACEHOLDER_SIZE := Vector2(512.0, 512.0)


## One picture on the board. Written by the board that holds it, read by the
## docker that draws it.
##
## The four toggles, all of PureRef's but opacity: a flip, a greyscale, a crop
## and always on top. Each is a flag here, saved with
## the board, and the drawing reads them. The greyscale is a second texture made
## once from the image by the engine's own conversion, because the board draws
## every picture in one pass and a per-picture shader would be a Control per
## picture.
class Picture:
    extends RefCounted

    var path: String = ""
    ## Where it sits in board space, at the size it is drawn at. With a crop
    ## this is the rectangle the cropped region is drawn in.
    var rect: Rect2 = Rect2()
    ## The pixels, or null for a placeholder.
    var image: Image = null
    var texture: ImageTexture = null
    var source_space: SaColorSpace = null

    ## Mirrored left to right.
    var flip_h: bool = false
    ## Drawn without its colour.
    var greyscale: bool = false
    ## The part of the image shown, in texels. An empty rectangle is the whole.
    var crop: Rect2i = Rect2i()
    ## Drawn over every picture that is not, and found first under a click.
    var on_top: bool = false
    ## The bytes the `.sad` it came from stored for it, in memory only, which a save stores again.
    var held: PackedByteArray = PackedByteArray()
    ## The greyscale copy of `texture`, made on the first toggle.
    var grey_texture: ImageTexture = null

    ## Whether this element is the canvas rather than a file.
    ##
    ## A live element carries no `image` and no `texture`. What it shows is the
    ## easel's own output, drawn by [ReferenceCanvasElement] with the canvas's
    ## own display material, so the rolloff, the exposure and the profile are
    ## the ones the painter is looking at. Nothing is read back and nothing is
    ## composited twice, which is what keeps this inside hard rule 1 (no CPU-GPU ping-pong).
    var live: bool = false

    ## What a live element shows, in document texels, so the rectangle
    ## arithmetic below answers without reaching for a document.
    ##
    ## Written by the docker when the canvas is added and whenever it is
    ## resized. Zero is a live element with no document behind it, which draws
    ## as a placeholder the way a missing file does.
    var live_size: Vector2i = Vector2i.ZERO

    ## The size of what this element shows, in texels: the image's, or the
    ## canvas's for a live one.
    ##
    ## Every rectangle answer below is written against this rather than against
    ## `image`, which is what lets a live element crop, scale and place itself
    ## with no pixels on the CPU at all.
    func source_size() -> Vector2i:
        if live:
            return live_size
        return image.get_size() if image != null else Vector2i.ZERO

    ## Whether the path resolved to a picture. A placeholder keeps its slot and
    ## its rectangle and draws its name instead.
    func is_missing() -> bool:
        if live:
            return live_size.x <= 0 or live_size.y <= 0
        return texture == null

    ## The region of the image that is drawn: the crop, or all of it.
    func region() -> Rect2i:
        var whole := source_size()
        if whole.x <= 0 or whole.y <= 0:
            return Rect2i()
        if crop.size.x > 0 and crop.size.y > 0:
            return crop.intersection(Rect2i(Vector2i.ZERO, whole))
        return Rect2i(Vector2i.ZERO, whole)

    ## The texture the picture is drawn with, grey or in colour.
    ##
    ## Null for a live element, which is not drawn in the board's own pass at
    ## all: it has no CPU image to grey and no `ImageTexture` to hand over, so
    ## [ReferenceCanvasElement] draws it and this answers nothing rather than
    ## inventing a texture nobody can build.
    func shown_texture() -> Texture2D:
        if live:
            return null
        if greyscale and texture != null:
            if grey_texture == null:
                var grey := image.duplicate() as Image
                grey.convert(Image.FORMAT_LA8)
                grey_texture = ImageTexture.create_from_image(grey)
            return grey_texture
        return texture

    ## The texel *board_point* falls on, or (-1, -1) for a point off the picture.
    ## Through the crop and the flip, so the texel is the one under the pointer
    ## and not the one that would be there unflipped.
    func texel_at(board_point: Vector2) -> Vector2i:
        var whole := source_size()
        if whole.x <= 0 or whole.y <= 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
            return Vector2i(-1, -1)
        var shown := region()
        var unit := (board_point - rect.position) / rect.size
        if flip_h:
            unit.x = 1.0 - unit.x
        var local := Vector2(shown.position) + unit * Vector2(shown.size)
        var texel := Vector2i(floori(local.x), floori(local.y))
        if not shown.has_point(texel):
            return Vector2i(-1, -1)
        return texel

    ## Board units per texel, which a crop keeps so the picture does not jump.
    func scale() -> Vector2:
        var shown := region()
        if shown.size.x <= 0 or shown.size.y <= 0:
            return Vector2.ONE
        return rect.size / Vector2(shown.size)

    ## Shows only *texels* of the image, drawn where those texels were, so
    ## cropping is like cutting the paper rather than shrinking it. An empty
    ## or off-image rectangle clears the crop and the whole picture comes
    ## back where it was.
    func set_crop(texels: Rect2i) -> void:
        var size := source_size()
        if size.x <= 0 or size.y <= 0:
            return
        var whole := Rect2i(Vector2i.ZERO, size)
        var wanted := texels.intersection(whole)
        var per_texel := scale()
        var shown := region()
        if wanted.size.x <= 0 or wanted.size.y <= 0 or wanted == whole:
            crop = Rect2i()
            rect = Rect2(rect.position - Vector2(shown.position) * per_texel, Vector2(whole.size) * per_texel)
            return
        var offset := Vector2(wanted.position - shown.position) * per_texel
        if flip_h:
            offset.x = float(shown.end.x - wanted.end.x) * per_texel.x
        crop = wanted
        rect = Rect2(rect.position + offset, Vector2(wanted.size) * per_texel)


var name: String = "Board"

## Bottom first, so the last is drawn on top and is the first a click finds.
var pictures: Array[Picture] = []

## The view over the board, in the picture Control's own coordinates: where the
## board's origin sits and how many screen pixels one board unit is drawn at.
var zoom: float = 1.0
var offset: Vector2 = Vector2.ZERO

## The picture shown alone, or null for the whole board. A view state and never saved: `to_header` writes the zoom
## and offset the board had before, so a board saved in solo opens whole.
## `soloed` validates it, so a picture taken off the board takes solo with it.
var _solo: Picture = null

## The view the board had when solo began, which leaving solo puts back.
var _before_zoom: float = 1.0
var _before_offset: Vector2 = Vector2.ZERO


func _init(board_name: String = "Board") -> void:
    name = board_name


# --- Loading ------------------------------------------------------------------


## Adds the picture at *path* to the right of everything on the board, at its
## own size, and answers it. A path that exists and cannot be read is refused
## with the loader's reason through `SaProblems`, and null comes back. A path
## that is not there at all is a placeholder, so a reference dragged in from a
## folder that has since been tidied is still a slot with a name.
func add_path(path: String) -> Picture:
    var exists := ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)
    var image: Image = _read(path) if exists else null
    if exists and image == null:
        return null
    return _place(path, image, Rect2(_next_free_x(), 0.0, 0.0, 0.0))


## Puts *path* back at *rect*, the way a board comes off the disk, read from *held*, the bytes a `.sad`
## stored for it, only when the path does not resolve, so an edit of the original shows. A path read
## neither way is a placeholder, because the painter opening a file cannot be asked to fix the file
## first. A rectangle with no size takes the picture's own, or the placeholder's.
func restore_path(path: String, rect: Rect2, held := PackedByteArray()) -> Picture:
    var exists := ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)
    var was := SaProblems.announce
    # A missing reference is drawn, not announced: one placeholder per picture
    # beats a stack of errors over a painting that opened fine.
    SaProblems.announce = false
    var image: Image = _read(path) if exists else null
    SaProblems.announce = was
    var stored := SaSadFile.reference_picture(held, path) if image == null else null
    var picture := _place(path, image if stored == null else stored.image, rect, stored.space if stored != null else null)
    picture.held = held
    return picture


## Adds the canvas to the right of everything on the board, at *canvas_size*
## texels, and answers it.
##
## A `Picture` like every other, so the canvas is compared against a reference
## with every toggle a picture has, in the same list, in the same z order, taking the same four
## toggles and the same resize handles. What is different is where its pixels
## come from, and that is one flag.
##
## **One per board.** A second canvas element would be the same texture twice
## with two rectangles, which is a thing PureRef would allow and which says
## nothing a painter wants said: the answer is to put the board's own zoom on
## it. The existing one is answered instead of a second being made, so the
## button is idempotent.
func add_canvas(canvas_size: Vector2i) -> Picture:
    var existing := canvas_picture()
    if existing != null:
        existing.live_size = canvas_size
        return existing
    var picture := Picture.new()
    picture.live = true
    picture.live_size = canvas_size
    var side := Vector2(canvas_size) if canvas_size.x > 0 and canvas_size.y > 0 else PLACEHOLDER_SIZE
    picture.rect = Rect2(Vector2(_next_free_x(), 0.0), side)
    pictures.append(picture)
    return picture


## The board's canvas element, or null for a board without one.
func canvas_picture() -> Picture:
    for picture in pictures:
        if picture.live:
            return picture
    return null


func _place(path: String, image: Image, rect: Rect2, space: SaColorSpace = null) -> Picture:
    var picture := Picture.new()
    picture.path = path
    if image != null:
        picture.image = image
        picture.texture = ImageTexture.create_from_image(image)
        picture.source_space = space if space != null else SaImageImport.space_for(path)
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        rect.size = Vector2(image.get_size()) if image != null else PLACEHOLDER_SIZE
    picture.rect = rect
    pictures.append(picture)
    return picture


## Where the next picture goes: just right of the rightmost edge, or at the
## origin on an empty board.
func _next_free_x() -> float:
    var right := 0.0
    for picture in pictures:
        right = maxf(right, picture.rect.end.x + NORMAL_GAP)
    return right


## `res://` is read through `ResourceLoader` rather than through `Image.load`,
## which does not resolve a resource path in an exported build. A scenario
## points at a file in the project and a painter points at one on disk, and
## both have to work.
static func _read(path: String) -> Image:
    if path.begins_with("res://"):
        var texture := ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null
        if texture == null:
            # A static function has no `self` to reach `tr` through.
            SaProblems.refuse(SaDockerIds.REFERENCE, TranslationServer.translate("Could not read '%s' as an image.") % path)
            return null
        return texture.get_image()
    return SaImageImport.read(path)


func remove(picture: Picture) -> void:
    if picture == _solo:
        leave_solo()
    pictures.erase(picture)


# --- Solo ----------------------------------------------------------------------


## The picture shown alone, or null while the whole board is.
func soloed() -> Picture:
    return _solo if _solo != null and pictures.has(_solo) else null


## Shows *picture* alone, fitted in *room* as `fit_one` fits it. The view the
## board had is kept only on the way in, so a second picture soloed from solo
## still leaves to the board as it was before either. False for a picture this
## board does not hold.
func solo(picture: Picture, room: Vector2) -> bool:
    if picture == null or not pictures.has(picture):
        return false
    if soloed() == null:
        _before_zoom = zoom
        _before_offset = offset
    _solo = picture
    fit_one(picture, room)
    return true


## The whole board again, at the zoom and offset it had before solo. False
## when nothing was soloed, so a caller knows whether the key did anything.
func leave_solo() -> bool:
    if _solo == null:
        return false
    _solo = null
    zoom = _before_zoom
    offset = _before_offset
    return true


# --- The z order and the moves -------------------------------------------------


## The pictures in the order they are drawn: the list's order, with every
## picture marked always on top after the rest. The list itself keeps the
## order a raise gives, so a picture taken off the top falls back to where
## it stood. In solo the soloed picture is the whole list, so the drawing, the
## hover and the colour pick all see that picture and no other.
func ordered() -> Array[Picture]:
    var out: Array[Picture] = []
    if soloed() != null:
        out.append(_solo)
        return out
    for picture in pictures:
        if not picture.on_top:
            out.append(picture)
    for picture in pictures:
        if picture.on_top:
            out.append(picture)
    return out


## The topmost picture under *board_point*, or null over the empty board.
func picture_at(board_point: Vector2) -> Picture:
    var drawn := ordered()
    for i in range(drawn.size() - 1, -1, -1):
        if drawn[i].rect.has_point(board_point):
            return drawn[i]
    return null


## Brings *picture* to the top of the z order, which a click on it does.
func raise(picture: Picture) -> void:
    if pictures.has(picture):
        pictures.erase(picture)
        pictures.append(picture)


## Moves *picture* by *delta*, in board units.
func move(picture: Picture, delta: Vector2) -> void:
    picture.rect.position += delta


## The smallest a picture can be dragged to, in board units on each side, so
## a corner pulled past its opposite leaves a picture rather than nothing.
const MIN_SIDE: float = 8.0

## The four corners a resize can take hold of, as the fraction of the
## rectangle each sits at: (0, 0) is the top left and (1, 1) the bottom right.
const CORNERS: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


## Where *corner* of *picture* sits, in board units.
func corner_point(picture: Picture, corner: Vector2) -> Vector2:
    return picture.rect.position + picture.rect.size * corner


## Resizes *picture* so that *corner* lands on *board_point* while the opposite
## corner stays where it is. With *keep_aspect* the picture keeps its
## proportions and follows whichever axis the drag pulled further, so a corner
## dragged straight out grows the picture rather than pinning one side. Neither
## side goes under `MIN_SIDE`.
func resize(picture: Picture, corner: Vector2, board_point: Vector2, keep_aspect: bool = false) -> void:
    var before := picture.rect.size
    if before.x <= 0.0 or before.y <= 0.0:
        return
    var anchor := corner_point(picture, Vector2.ONE - corner)
    var pull := corner * 2.0 - Vector2.ONE
    var size := (board_point - anchor) * pull
    size = Vector2(maxf(size.x, MIN_SIDE), maxf(size.y, MIN_SIDE))
    if keep_aspect:
        var factor := maxf(size.x / before.x, size.y / before.y)
        size = before * factor
    picture.rect = Rect2(anchor - size * (Vector2.ONE - corner), size)


# --- The view ----------------------------------------------------------------


func to_view(board_point: Vector2) -> Vector2:
    return offset + board_point * zoom


func to_board(view_point: Vector2) -> Vector2:
    return (view_point - offset) / zoom


## The rectangle *picture* is drawn in, in the picture Control's coordinates.
func view_rect(picture: Picture) -> Rect2:
    return Rect2(to_view(picture.rect.position), picture.rect.size * zoom)


## Zooms about *at*, a point in the picture Control, so the board point under
## the pointer stays under it. The same rule the canvas's own wheel follows.
func zoom_about(at: Vector2, factor: float) -> bool:
    var wanted := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
    if is_equal_approx(wanted, zoom):
        return false
    offset = at - (at - offset) * (wanted / zoom)
    zoom = wanted
    return true


func pan_by(delta: Vector2) -> void:
    offset += delta


## The rectangle every picture fits in, in board units, or an empty one for an
## empty board. In solo it is the soloed picture's, so Fit stays on it.
func bounds() -> Rect2:
    if soloed() != null:
        return _solo.rect
    if pictures.is_empty():
        return Rect2()
    var out := pictures[0].rect
    for picture in pictures:
        out = out.merge(picture.rect)
    return out


## The whole board centred in *room*, at the largest zoom that shows all of
## it. Never above 1.0: a small reference blown up to fill the docker is a
## blurred one, and the wheel is there for a painter who wants that.
func fit_all(room: Vector2) -> void:
    fit_rect(bounds(), room)


## One picture centred in *room*, under the same rule.
func fit_one(picture: Picture, room: Vector2) -> void:
    fit_rect(picture.rect, room)


func fit_rect(rect: Rect2, room: Vector2) -> void:
    if room.x <= 0.0 or room.y <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return
    zoom = clampf(minf(room.x / rect.size.x, room.y / rect.size.y), MIN_ZOOM, 1.0)
    offset = (room - rect.size * zoom) * 0.5 - rect.position * zoom


# --- Normalise ---------------------------------------------------------------


## Every picture at one size, laid in a grid whose proportions come nearest
## those of *room*, so a fit after it fills the docker. The default is one
## height, rows of that height in reading order, left to right and then top to
## bottom. *mode* is the Preferences row's other two readings: one width, the
## pictures standing in columns of that width filled top to bottom, or one
## area, rows each as tall as its tallest picture. A placeholder keeps its
## rectangle's proportions, since nothing else is known about it. A *room* of
## zero asks for the old single row. Given *only*, a selection, those
## pictures alone are laid out, with the grid's top left where theirs was, and
## the rest stay put.
func normalise(mode: String = "height", room: Vector2 = Vector2.ZERO, only: Array[Picture] = []) -> void:
    if pictures.is_empty():
        return
    var by_columns := mode == "width"
    var in_order := (only if not only.is_empty() else pictures).duplicate()
    in_order.sort_custom(
        func(a: Picture, b: Picture) -> bool:
            var major_a := a.rect.position.x if by_columns else a.rect.position.y
            var major_b := b.rect.position.x if by_columns else b.rect.position.y
            if not is_equal_approx(major_a, major_b):
                return major_a < major_b
            var minor_a := a.rect.position.y if by_columns else a.rect.position.x
            return minor_a < (b.rect.position.y if by_columns else b.rect.position.x)
    )
    var sizes: Array[Vector2] = []
    for picture: Picture in in_order:
        sizes.append(ReferenceGrid.normal_size(picture.rect.size, mode, NORMAL_HEIGHT))
    var rects := ReferenceGrid.lay_out(sizes, room, by_columns, NORMAL_GAP)
    var shift := Vector2.ZERO
    if not only.is_empty():
        var was: Rect2 = in_order[0].rect
        var now := rects[0]
        for index in in_order.size():
            was = was.merge(in_order[index].rect)
            now = now.merge(rects[index])
        shift = was.position - now.position
    for index in in_order.size():
        in_order[index].rect = Rect2(rects[index].position + shift, rects[index].size)


# --- To disk and back ----------------------------------------------------------


## The board as the `.sad` header and the settings file hold it: the name, the
## view, and one path and rectangle per picture. No pixels.
func to_header() -> Dictionary:
    var out: Array = []
    for picture in pictures:
        var entry := {
            "path": picture.path,
            "rect": [picture.rect.position.x, picture.rect.position.y, picture.rect.size.x, picture.rect.size.y],
        }
        # The canvas element, a flag and never pixels, written only when true: it shows whatever
        # document is open when the board is read, which is what "the canvas" means.
        if picture.live:
            entry["canvas"] = true
        # The four toggles, written only when set, so a board with none is the first boards' header.
        if picture.flip_h:
            entry["flip"] = true
        if picture.greyscale:
            entry["greyscale"] = true
        if picture.on_top:
            entry["on_top"] = true
        if picture.crop.size.x > 0 and picture.crop.size.y > 0:
            entry["crop"] = [picture.crop.position.x, picture.crop.position.y, picture.crop.size.x, picture.crop.size.y]
        if not picture.held.is_empty():
            entry[SaSadFile.REFERENCE_BYTES] = picture.held
        out.append(entry)
    var kept_zoom := _before_zoom if soloed() != null else zoom
    var kept_offset := _before_offset if soloed() != null else offset
    return {"name": name, "zoom": kept_zoom, "offset": [kept_offset.x, kept_offset.y], "pictures": out}


## A board back from what `to_header` wrote. Every picture is restored in its
## rectangle, present or not.
static func from_header(raw: Variant) -> SaReferenceBoard:
    var data: Dictionary = raw if raw is Dictionary else {}
    var board := SaReferenceBoard.new(String(data.get("name", "Board")))
    board.zoom = clampf(float(data.get("zoom", 1.0)), MIN_ZOOM, MAX_ZOOM)
    var at: Array = data.get("offset", [0.0, 0.0])
    if at.size() >= 2:
        board.offset = Vector2(float(at[0]), float(at[1]))
    for entry: Variant in data.get("pictures", []):
        if not (entry is Dictionary):
            continue
        var r: Array = entry.get("rect", [])
        var rect := Rect2()
        if r.size() >= 4:
            rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
        var picture: Picture = null
        if bool(entry.get("canvas", false)):
            # The size comes from the document the docker binds next, not from the file, as `to_header` says.
            picture = board.add_canvas(Vector2i.ZERO)
            picture.rect = rect if rect.size.x > 0.0 and rect.size.y > 0.0 else Rect2(rect.position, PLACEHOLDER_SIZE)
        else:
            picture = board.restore_path(String(entry.get("path", "")), rect, SaSadFile.reference_bytes(entry))
        picture.flip_h = bool(entry.get("flip", false))
        picture.greyscale = bool(entry.get("greyscale", false))
        picture.on_top = bool(entry.get("on_top", false))
        var c: Array = entry.get("crop", [])
        if c.size() >= 4:
            # Straight onto the flag: the saved rectangle is already cropped, and `set_crop` would crop it twice.
            picture.crop = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
    return board
