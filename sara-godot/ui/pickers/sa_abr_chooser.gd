## Load Tip on an `.abr` opens this chooser, and the tip picked loads as a
## `.png` would.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A cell per tip, drawn the way the Tip Image grid draws one.** The mask is
## fitted into a square, kept in its proportions, and shown white with the
## coverage as its alpha, so a tip reads as the shape it paints on any shade of
## the theme. The tip's name is under it, which the grid leaves to a tooltip,
## because a collection's tips are told apart by name in Photoshop too. A brush
## Sara cannot load, a computed one, is listed rather than left out: its cell is
## dimmed and marked, its tooltip says why, and a press on it says so where
## refusals go and keeps the chooser up for another pick.
##
## **The tip picked is written as a `.png` into the saved tips folder**, the one
## `SaBrushTipMask.save` writes, and loaded from there by the path the picker
## would have given. The other way, the collection's path and the tip's index,
## would have every reader of a tip path, the cache, the grid and the preset,
## learn a second kind of address, and `core/api/tip` has no room in its budget
## for that. A file in the tips folder is what a preset already carries for a
## tip of the painter's own, so a preset saved with it reopens wherever that
## folder is, and says the file is not on disk where it is not.
##
## The PNG is grey and alpha, the coverage in the alpha and the grey nought, so
## `SaTipImage` reads the mask back texel for texel. Its `brush_spacing` and
## `brush_name` text keys carry the spacing and the name the collection gave,
## the keys a tip exported from Krita carries. A name outside ASCII is left to
## the file name, which the loader falls back to, rather than written as
## question marks. A tip stored at 16 bits keeps its upper byte, since Godot
## decodes a PNG at 8 bits whatever it was written at.
##
## In `ui/pickers`, because a window a painter clicks in is
## interface and `core` never names `ui`, rather than in `core/api/abr` beside
## the reader. `SaBrushTipMask.choose_file` is the one door both brushes load a
## tip through, and that door asks for it through `SaDialogsInHand`, which
## `SaPickers` attaches [method open] to when the interface starts.
class_name SaAbrChooser
extends AcceptDialog

## The side of the square a tip's picture is fitted into.
const PICTURE: int = 64

## The widest a row of cells grows before it wraps.
const COLUMNS: int = 4

## The rows shown before the list scrolls.
const ROWS_SHOWN: int = 3

## What a cell whose tip cannot be loaded shows in place of a picture, the Tip
## Image grid's mark.
const UNREADABLE_MARK: String = "?"

## How much a refused cell is dimmed, the alpha `SaOptionSpec` dims a row by.
const DIMMED_ALPHA: float = SaOptionSpec.DIMMED_ALPHA

## A cell's width, wider than the picture so a name of two words fits under
## it. Its height is the picture's and a line's, as the button measures them.
const CELL_WIDTH: int = 108

## Where the IHDR chunk ends in every PNG: an 8-byte signature and a 25-byte
## chunk. The text keys are written right after it.
const IHDR_END: int = 33

## The collection the cells are made of.
var collection: SaAbrCollection = null

## One button per tip, in the collection's order.
var cells: GridContainer = null

## What a pick calls with the path the tip was written to.
var _on_chosen: Callable = Callable()

## The cells' frame, sized to them once the theme has measured one.
var _scroll: ScrollContainer = null


func _init(read: SaAbrCollection, on_chosen: Callable) -> void:
    collection = read
    _on_chosen = on_chosen
    name = "AbrChooser"
    title = tr("Choose a Tip from %s") % read.file_name
    get_ok_button().visible = false
    add_cancel_button(tr("Cancel"))
    visibility_changed.connect(_on_visibility_changed)
    _scroll = ScrollContainer.new()
    _scroll.name = "AbrTipScroll"
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    cells = GridContainer.new()
    cells.name = "AbrTips"
    cells.columns = clampi(read.tips.size(), 1, COLUMNS)
    _scroll.add_child(cells)
    add_child(_scroll)
    for place in read.tips.size():
        cells.add_child(_cell(place))


## Sizes the frame to the cells as the theme draws them: every column, and
## the rows up to [constant ROWS_SHOWN], with room for the bar a longer list
## scrolls by.
func _ready() -> void:
    if cells.get_child_count() == 0:
        return
    var cell := (cells.get_child(0) as Control).get_combined_minimum_size()
    var rows := ceili(cells.get_child_count() / float(cells.columns))
    var shown := mini(rows, ROWS_SHOWN)
    var gap := cells.get_theme_constant("v_separation")
    var across := cells.get_combined_minimum_size().x
    if rows > shown:
        across += _scroll.get_v_scroll_bar().get_combined_minimum_size().x
    _scroll.custom_minimum_size = Vector2(across, shown * cell.y + (shown - 1) * gap)


## Opens the chooser on the collection at *path* over the main window. A file
## that is not read is refused with the reader's sentence and opens nothing.
static func open(path: String, on_chosen: Callable) -> SaAbrChooser:
    var read := SaAbrCollection.load_from(path)
    if not read.ok():
        EventBus.paint_refused.emit(read.error)
        return null
    var loop := Engine.get_main_loop() as SceneTree
    if loop == null or loop.root == null:
        return null
    var chooser := SaAbrChooser.new(read, on_chosen)
    loop.root.add_child(chooser)
    chooser.popup_centered()
    return chooser


## Picks the tip at *place*: written into the tips folder, the chooser closed,
## and its path handed on. A tip that cannot be loaded is refused with its
## sentence and the chooser stays. Answers the path, empty when nothing loaded.
func pick(place: int) -> String:
    if place < 0 or place >= collection.tips.size():
        return ""
    var tip: SaTipImage.Tip = collection.tips[place]
    if not tip.ok():
        EventBus.paint_refused.emit(tip.error)
        return ""
    var written := write(tip, collection.file_name, place + 1)
    if written.is_empty():
        EventBus.paint_refused.emit(tr("%s could not be written into the tips folder.") % tip.tip_name)
        return ""
    hide()
    _on_chosen.call(written)
    return written


## *tip* as a PNG file in the saved tips folder, by its name. A file of that
## name already holding the same bytes is answered as it is, so a tip picked
## twice is one file, and one holding another picture leaves the name to it and
## takes the next number. *place* names a tip the collection left unnamed.
static func write(tip: SaTipImage.Tip, collection_name: String, place: int) -> String:
    var bytes := png_of(tip)
    var stem := tip.tip_name.validate_filename().strip_edges()
    if stem.is_empty():
        stem = "%s %d" % [collection_name.get_basename(), place]
    var folder := SaBrushTipMask.saved_dir()
    var file := stem + ".png"
    var number := 1
    while FileAccess.file_exists(folder.path_join(file)):
        if FileAccess.get_file_as_bytes(folder.path_join(file)) == bytes:
            return folder.path_join(file)
        number += 1
        file = "%s %d.png" % [stem, number]
    return SaBrushTipMask.save(file, bytes)


## The PNG *tip* is written as, which `SaTipImage` reads back as the same mask,
## spacing and name.
static func png_of(tip: SaTipImage.Tip) -> PackedByteArray:
    var grey := PackedByteArray()
    grey.resize(tip.mask.size() * 2)
    for at in tip.mask.size():
        grey[2 * at + 1] = roundi(clampf(tip.mask[at], 0.0, 1.0) * 255.0)
    var image := Image.create_from_data(tip.size.x, tip.size.y, false, Image.FORMAT_LA8, grey)
    var png := image.save_png_to_buffer()
    var out := png.slice(0, IHDR_END)
    out.append_array(_text_chunk("brush_spacing", str(tip.spacing)))
    if _is_ascii(tip.tip_name):
        out.append_array(_text_chunk("brush_name", tip.tip_name))
    out.append_array(png.slice(IHDR_END))
    return out


## *tip*'s mask as the Tip Image grid draws it: fitted into a square of *side*,
## white, its coverage the alpha.
static func drawn(tip: SaTipImage.Tip, side: int) -> Image:
    var mask := Image.create_from_data(tip.size.x, tip.size.y, false, Image.FORMAT_RF, tip.mask.to_byte_array())
    var ratio := float(side) / float(maxi(1, maxi(tip.size.x, tip.size.y)))
    mask.resize(maxi(1, roundi(tip.size.x * ratio)), maxi(1, roundi(tip.size.y * ratio)), Image.INTERPOLATE_BILINEAR)
    mask.convert(Image.FORMAT_L8)
    var coverage := mask.get_data()
    var bytes := PackedByteArray()
    bytes.resize(coverage.size() * 2)
    for at in coverage.size():
        bytes[2 * at] = 255
        bytes[2 * at + 1] = coverage[at]
    return Image.create_from_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_LA8, bytes)


## The cell of the tip at *place*, named by its place counted from one, which is
## the name a scenario's `click` aims at.
func _cell(place: int) -> Button:
    var tip: SaTipImage.Tip = collection.tips[place]
    var cell := Button.new()
    cell.name = "AbrTip%d" % (place + 1)
    cell.focus_mode = Control.FOCUS_NONE
    cell.custom_minimum_size = Vector2(CELL_WIDTH, 0)
    cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cell.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
    # The theme caps a button's icon at the toolbar's, as the grid finds.
    cell.add_theme_constant_override("icon_max_width", PICTURE)
    cell.alignment = HORIZONTAL_ALIGNMENT_CENTER
    cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    cell.clip_text = true
    if tip.ok():
        cell.icon = ImageTexture.create_from_image(drawn(tip, PICTURE))
        cell.text = tip.tip_name
        cell.tooltip_text = "%s\n%s" % [tip.tip_name, collection.file_name]
    else:
        cell.text = "%s %s" % [UNREADABLE_MARK, tip.tip_name]
        cell.modulate = Color(1.0, 1.0, 1.0, DIMMED_ALPHA)
        cell.tooltip_text = "%s\n%s\n%s" % [tr("%s (unreadable)") % tip.tip_name, collection.file_name, tip.error]
    cell.pressed.connect(pick.bind(place))
    return cell


## A chooser taken off the screen, by a pick, Cancel or Escape, is gone.
func _on_visibility_changed() -> void:
    if not visible:
        queue_free()


## One `tEXt` chunk, *key* to *value*, its length and CRC as a PNG states them.
static func _text_chunk(key: String, value: String) -> PackedByteArray:
    var typed := "tEXt".to_ascii_buffer()
    typed.append_array(key.to_ascii_buffer())
    typed.append(0)
    typed.append_array(value.to_ascii_buffer())
    var out := _be32(typed.size() - 4)
    out.append_array(typed)
    out.append_array(_be32(SaExportGamut.crc32(typed)))
    return out


static func _be32(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


## Whether every character of *text* is printable ASCII, which is all a `tEXt`
## value is read as.
static func _is_ascii(text: String) -> bool:
    for at in text.length():
        var code := text.unicode_at(at)
        if code < 0x20 or code > 0x7E:
            return false
    return true
