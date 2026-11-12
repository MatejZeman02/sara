## The picture beside a note: what is cut out of the readback, how far it is
## scaled down, and the format it is written in.
##
## A class of its own because what a picture is cut and shrunk to is not what
## the mode does, and static throughout so a headless test can crop and shrink
## an `Image` without a window to read back from.
##
## A whole window is shrunk to LONG_SIDE and written as WebP, because a whole
## window in PNG is large and nothing in a note about a control is read at
## pixel level. A region the painter drew is the exception
## and is written whole, since drawing one is what "the pixels are the point"
## looks like.
class_name SaNoteImage
extends RefCounted

## The longest side a whole-window shot is allowed, in pixels.
const LONG_SIDE: int = 1600

## WebP quality for both shots. Lossy: 90 is where the text in Sara's own UI
## still reads and the file is under a tenth of the PNG.
const QUALITY: float = 0.9

const EXTENSION := "webp"

## A shift-drag shorter than this in either direction is a slip, not a region.
const MIN_REGION: float = 8.0


## The image a note saves: the region when one was drawn, the whole window
## shrunk otherwise. Null in, null out, which is what a failed readback gives.
static func for_note(shot: Image, region: Rect2, logical: Vector2) -> Image:
    if shot == null:
        return null
    if is_region(region):
        return crop(shot, region, logical)
    return shrink(shot, LONG_SIDE)


## The part of `shot` the region covers, at the readback's own resolution.
## Falls back to the whole window when the region lands outside the picture.
static func crop(shot: Image, region: Rect2, logical: Vector2) -> Image:
    var box := in_pixels(region, logical, Vector2(shot.get_size()))
    if box.size.x < 1 or box.size.y < 1:
        return shrink(shot, LONG_SIDE)
    return shot.get_region(box)


## A rectangle in the root viewport's logical units as whole pixels of a
## readback `size` across, clipped to it.
##
## The two differ whenever the window has a content scale: the pointer is read
## in logical units and the readback is physical pixels, so a region drawn at
## 2x would otherwise crop the top-left quarter of what was framed.
static func in_pixels(region: Rect2, logical: Vector2, size: Vector2) -> Rect2i:
    var ratio := Vector2.ONE
    if logical.x > 0.0 and logical.y > 0.0:
        ratio = size / logical
    var at := (region.position * ratio).floor()
    var span := (region.size * ratio).ceil()
    var box := Rect2i(Vector2i(at), Vector2i(span))
    return box.intersection(Rect2i(Vector2i.ZERO, Vector2i(size)))


## The root's readback *shot* with every visible window of its own drawn in at
## the place it stands, so a shot or a note shows what the desktop showed.
##
## The root's texture holds the root and what is embedded in it. With embedded
## subwindows on a docker or a list is embedded and already there, and this
## finds nothing to add. With them off each is a window of the operating system
## and the readback had the root behind it: a note on a menu row showed no menu,
## and a shot of a docker let out over the canvas showed the canvas.
static func with_windows(shot: Image, root: Window) -> Image:
    if shot == null or root == null or not root.is_inside_tree():
        return shot
    return paste_windows(shot, root, windows_over(root))


## Every window of its own *host* holds, and every one each of those holds in
## turn, in tree order. A list opened from a let-out docker is a child of the
## docker's window, which `windows_of_their_own` stops at because what is under a
## window is measured in its own space. A window of its own stands where the
## desktop put it whatever it hangs from, so it is drawn in all the same.
static func windows_over(host: Node) -> Array[Window]:
    var found: Array[Window] = []
    for window in SaCursorPolicy.windows_of_their_own(host):
        found.append(window)
        if not (window is Popup):
            found.append_array(windows_over(window))
    return found


## Draws each of *windows* into *shot*, the picture of *root*, at its place,
## every other window first and the popups last, since an open list stands over
## every docker and dialog on the desktop. Among the rest the tree's order is
## the stacking, the one Godot knows. A hidden or minimised window is not on
## the desktop and is left out.
##
## A window's place is its own `position` against the root's, both in the
## desktop's pixels as Godot set them, scaled by the readback's size over the
## root's so a window with a content scale lands where it was seen. What falls
## outside the root's picture is cut there. Takes the windows rather than
## finding them so a suite can hand it embedded ones.
static func paste_windows(shot: Image, root: Window, windows: Array[Window]) -> Image:
    if shot == null or root == null:
        return shot
    var ratio := Vector2.ONE
    if root.size.x > 0 and root.size.y > 0:
        ratio = Vector2(shot.get_size()) / Vector2(root.size)
    var lists: Array[Window] = []
    var stacked: Array[Window] = []
    for window in windows:
        if not window.visible or window.mode == Window.MODE_MINIMIZED:
            continue
        if window is Popup:
            lists.append(window)
        else:
            stacked.append(window)
    stacked.append_array(lists)
    for window in stacked:
        var picture := window.get_texture().get_image() if window.get_texture() != null else null
        if picture == null:
            continue
        paste(shot, picture, Vector2(window.position - root.position) * ratio, ratio)
    return shot


## Whether *control*, in a window of its own, falls inside *root*'s picture
## once `with_windows` has drawn its window in. Its rectangle goes through its
## window's content scale to the desktop's pixels before it is laid on the root.
static func shows(control: Control, root: Window) -> bool:
    var window := control.get_window()
    if window == null or root == null:
        return false
    var rect := window.get_final_transform() * control.get_global_rect()
    rect.position += Vector2(window.position - root.position)
    return rect.intersects(Rect2(Vector2.ZERO, Vector2(root.size)))


## Draws *picture* into *shot* with its corner at *at*, in *shot*'s pixels, and
## scaled by *ratio* first. What falls outside *shot* is left out. Public and
## free of any window so a suite can paste one image into another.
static func paste(shot: Image, picture: Image, at: Vector2, ratio: Vector2 = Vector2.ONE) -> void:
    if shot == null or picture == null or picture.is_empty():
        return
    var piece := Image.new()
    piece.copy_from(picture)
    if piece.get_format() != shot.get_format():
        piece.convert(shot.get_format())
    if not ratio.is_equal_approx(Vector2.ONE):
        var scaled := (Vector2(piece.get_size()) * ratio).round()
        piece.resize(maxi(1, int(scaled.x)), maxi(1, int(scaled.y)), Image.INTERPOLATE_BILINEAR)
    shot.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(at.round()))


## `shot` with its longest side at `long_side`, or `shot` itself when it is
## already smaller. The arithmetic is the saved file's preview's, which sits
## under `core` where a note cannot be named, so it stands there and the note
## and the welcome window's cache ask for it here.
static func shrink(shot: Image, long_side: int) -> Image:
    return SaSadFile.shrink(shot, long_side)


## Writes the WebP. The readback comes back as RGBA8 today, and the conversion
## is here because `save_webp` refuses any other format outright rather than
## converting for itself.
static func save(shot: Image, path: String) -> Error:
    if shot == null:
        return ERR_INVALID_DATA
    var out := shot
    if out.get_format() != Image.FORMAT_RGBA8 and out.get_format() != Image.FORMAT_RGB8:
        out = Image.new()
        out.copy_from(shot)
        out.convert(Image.FORMAT_RGBA8)
    return out.save_webp(path, true, QUALITY)


## The rectangle a drag from `from` to `to` frames, whichever corner it started at.
static func region_between(from: Vector2, to: Vector2) -> Rect2:
    return Rect2(from, to - from).abs()


static func is_region(region: Rect2) -> bool:
    return region.size.x >= MIN_REGION and region.size.y >= MIN_REGION


## A point an overlay read in `window`, in the root viewport's coordinates.
##
## An embedded window's position is measured in the host's logical space, not
## in physical pixels, so the two differ by exactly that. A
## docker that is a real OS window has no offset the root can know, and a
## region drawn inside one is not in the readback anyway, which is what the
## entry's "outside the picture" line already says.
static func point_in_root(window: Window, root: Window, local: Vector2) -> Vector2:
    if window == null or root == null or window == root or not window.is_embedded():
        return local
    return local + Vector2(window.position)
