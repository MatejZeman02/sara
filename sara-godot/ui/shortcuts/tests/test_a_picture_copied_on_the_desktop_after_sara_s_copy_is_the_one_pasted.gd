## Ctrl+V and File > New from Clipboard take the desktop's picture when the
## painter copied it after copying in Sara, and Sara's copy when nothing was
## copied on the desktop between.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Cut or a Copy leaves a text of its own on the desktop clipboard, and a Paste that finds
## it gone reads the desktop first, so a PNG put on the desktop clipboard with
## `wl-copy` after a stroke was copied is the one Ctrl+V lays. The desktop is two seams here, the text
## clipboard `SaClipboard.desktop` and the picture reader `desktop_picture` of
## `SaShortcutCommands` and of `SaNewFromClipboard`, because a run on a desktop
## would take whatever was copied there last. What `wl-copy` and the engine
## answer on a real compositor is for a door session to measure.
extends "res://tests/test_framework.gd"

## Real chunks copied and pasted on the GPU.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(512, 256)

## The picture the desktop is given, a PNG of a modest size.
const DESKTOP_SIZE := Vector2i(300, 200)


## A desktop clipboard held in the suite, which hands back what was last put on
## it, or nothing at all when it is not *readable*, as a headless run's.
class FakeDesktop:
    extends SaClipboard.DesktopClipboard

    var held_text: String = ""
    var can_read: bool = true

    func readable() -> bool:
        return can_read

    func write(content: String) -> void:
        if can_read:
            held_text = content

    func text() -> String:
        return held_text


var _surface: SaSurface = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _commands: SaCommandRegistry = null
var _shortcuts: SaShortcutCommands = null
var _desktop: FakeDesktop = null
var _kept_paste_reader: Callable = Callable()
var _kept_new_reader: Callable = Callable()
var _kept_fit: String = ""

## Every read of the desktop's picture, by either seam.
var _reads: Array = []

## What the desktop's picture reader hands over, or null for none.
var _desktop_picture: SaDesktopPicture = null


func before_each() -> void:
    _held().clear()
    _desktop = FakeDesktop.new()
    SaClipboard.desktop = _desktop
    _reads = []
    _desktop_picture = null
    _kept_paste_reader = SaShortcutCommands.desktop_picture
    _kept_new_reader = SaNewFromClipboard.desktop_picture
    SaShortcutCommands.desktop_picture = _read_desktop
    SaNewFromClipboard.desktop_picture = _read_desktop
    _kept_fit = SaSettings.import_fit
    SaSettings.import_fit = "ask"
    _surface = Fixtures.make_surface(CANVAS)
    _doc = _surface.easel.document
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _commands = Fixtures.make_registries(_surface).commands
    _shortcuts = SaShortcutCommands.new(Callable(), func() -> SaCanvas: return _canvas, Callable(), null)
    _shortcuts.register_into(_commands)


func after_each() -> void:
    _held().clear()
    SaClipboard.desktop = SaClipboard.DesktopClipboard.new()
    SaShortcutCommands.desktop_picture = _kept_paste_reader
    SaNewFromClipboard.desktop_picture = _kept_new_reader
    SaSettings.import_fit = _kept_fit
    _canvas.free()
    _canvas = null
    _shortcuts = null
    _commands = null
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    _desktop = null


func _held() -> SaClipboard:
    return SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard


func _read_desktop() -> SaDesktopPicture:
    _reads.append(true)
    return _desktop_picture


## The painter copies a picture in a browser: the desktop's text is gone and its
## picture is a solid red one.
func _desktop_given_a_picture() -> void:
    _desktop.held_text = ""
    var image := Image.create_empty(DESKTOP_SIZE.x, DESKTOP_SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    _desktop_picture = SaDesktopPicture.new(image, "the engine")


## A new active layer painted green over the whole canvas.
func _painted(named: String = "") -> SaLayer:
    var layer := SaLayerOps.new(_doc).add()
    if not named.is_empty():
        layer.name = named
    layer.fill(Color(0.0, 1.0, 0.0, 1.0))
    _doc.set_active_layer(layer)
    return layer


func _names() -> Array[String]:
    var names: Array[String] = []
    for child in _doc.get_children():
        if child is SaLayer:
            names.append(str(child.name))
    return names


func _layer_named(named: String) -> SaLayer:
    for child in _doc.get_children():
        if child is SaLayer and str(child.name) == named:
            return child as SaLayer
    return null


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


## Both orders: Copy, a desktop picture, Ctrl+V lays the
## picture at its own size, then Copy again and Ctrl+V lays Sara's copy.
func test_a_desktop_picture_copied_after_sara_s_copy_is_pasted_and_a_copy_after_it_wins_again() -> void:
    _painted()
    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    assert_false(_desktop.held_text.is_empty(), "and left its mark on the desktop clipboard")
    _desktop_given_a_picture()
    assert_true(_commands.execute(&"edit_paste"), "Edit > Paste ran")
    var picture := _layer_named("Pasted Picture")
    assert_not_null(picture, "The desktop's picture was pasted, named as a desktop picture is")
    assert_null(_layer_named("Pasted Layer"), "and not Sara's old copy")
    if picture == null:
        return
    @warning_ignore("integer_division")
    var corner := (CANVAS - DESKTOP_SIZE) / 2
    assert_almost_eq(_texel(picture, corner.x + 2, corner.y + 2).r, 1.0, 1e-3, "red inside the picture's own size")
    assert_almost_eq(_texel(picture, corner.x - 2, corner.y + 2).a, 0.0, 1e-3, "and clear just outside it")

    _painted("Again")
    assert_true(_commands.execute(&"edit_copy"), "a Copy in Sara after the desktop's")
    var reads := _reads.size()
    assert_true(_commands.execute(&"edit_paste"), "and Paste again")
    assert_not_null(_layer_named("Pasted Layer"), "lays Sara's copy")
    assert_almost_eq(_texel(_layer_named("Pasted Layer"), 4, 4).g, 1.0, 1e-3, "holding what Copy took")
    assert_eq(_reads.size(), reads, "and the desktop is not read while it holds the copy's mark")


## Copy and Paste with nothing copied on the desktop between: Sara's copy, and
## the desktop is never read.
func test_copy_and_paste_inside_sara_with_nothing_between_pastes_sara_s_copy() -> void:
    _painted()
    _desktop_picture = SaDesktopPicture.new(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8), "the engine")
    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    assert_true(_commands.execute(&"edit_paste"), "Edit > Paste ran")
    assert_not_null(_layer_named("Pasted Layer"), "Sara's copy is pasted")
    assert_null(_layer_named("Pasted Picture"), "not the desktop's")
    assert_true(_reads.is_empty(), "and the desktop was not read")


## Copy Merged and Cut leave the mark too, so a picture copied after them wins.
func test_cut_and_copy_merged_leave_the_mark_as_copy_does() -> void:
    for operation: StringName in [&"edit_cut", &"edit_copy_merged"]:
        _painted()
        _surface.easel.request_composite()
        _commands.execute(operation)
        assert_false(_desktop.held_text.is_empty(), "%s left its mark" % operation)
        assert_false(_held().desktop_changed(), "which the desktop still holds")
        _desktop.held_text = "words"
        assert_true(_held().desktop_changed(), "and a later copy elsewhere is a change")


## Several picked layers copied and pasted with nothing between paste as
## layers, and a desktop picture copied after them is pasted instead.
func test_several_layers_held_paste_as_today_and_yield_to_a_later_desktop_picture() -> void:
    var first := _painted("First")
    var second := _painted("Second")
    _doc.picked.pick([first, second] as Array[SaLayer])
    assert_true(_commands.execute(&"edit_copy"), "Copy of two picked layers ran")
    assert_false(_held().layers.is_empty(), "and holds them as layers")
    var before := _names().size()
    assert_true(_commands.execute(&"edit_paste"), "Paste ran")
    assert_eq(_names().size(), before + 2, "and laid both layers")
    assert_true(_reads.is_empty(), "without reading the desktop")
    _desktop_given_a_picture()
    before = _names().size()
    assert_true(_commands.execute(&"edit_paste"), "Paste after a desktop copy ran")
    assert_eq(_names().size(), before + 1, "and laid one layer")
    assert_not_null(_layer_named("Pasted Picture"), "the desktop's picture")


## A mask copied and pasted with nothing between goes back into the mask, and
## the desktop is not read.
func test_a_mask_copied_and_pasted_inside_sara_pastes_into_the_mask() -> void:
    var layer := _painted()
    var ops := SaMaskOps.new(_doc)
    assert_true(ops.add(layer), "The layer has a mask")
    _doc.mask_target = SaMaskOps.mask_of(layer)
    assert_true(_commands.execute(&"edit_copy"), "Copy of the mask ran")
    assert_false(_desktop.held_text.is_empty(), "and left its mark")
    var before := _names().size()
    assert_true(_commands.execute(&"edit_paste"), "Paste into the mask ran")
    assert_eq(_names().size(), before, "and added no layer")
    assert_true(_reads.is_empty(), "nor read the desktop")


## Words copied on the desktop after Sara's copy are no picture, so Sara's
## copy is still what Paste lays.
func test_words_copied_on_the_desktop_leave_sara_s_copy_the_one_pasted() -> void:
    _painted()
    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    _desktop.held_text = "a sentence from a browser"
    assert_true(_commands.execute(&"edit_paste"), "Edit > Paste ran")
    assert_not_null(_layer_named("Pasted Layer"), "Sara's copy is pasted")
    assert_eq(_reads.size(), 1, "after the desktop was asked once")


## A desktop clipboard Sara cannot read back keeps today's order: no mark, and
## Sara's copy pasted without the desktop being asked.
func test_a_desktop_clipboard_sara_cannot_read_keeps_today_s_order() -> void:
    _desktop.can_read = false
    _painted()
    _desktop_given_a_picture()
    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    assert_false(_held().desktop_changed(), "No mark, so no change is seen")
    assert_true(_commands.execute(&"edit_paste"), "Edit > Paste ran")
    assert_not_null(_layer_named("Pasted Layer"), "Sara's copy is pasted")
    assert_true(_reads.is_empty(), "and the desktop was not read")


## File > New from Clipboard in both orders: the desktop's picture copied after
## Sara's copy, then Sara's copy made after the desktop's.
func test_new_from_clipboard_takes_the_later_of_the_two_copies() -> void:
    _painted()
    assert_true(_commands.execute(&"edit_copy"), "Edit > Copy ran")
    _desktop_given_a_picture()
    var source := SaNewFromClipboard.read(_doc, _held())
    assert_not_null(source, "New from Clipboard found a picture")
    if source == null:
        return
    assert_not_null(source._picture, "the desktop's")
    if source._picture != null:
        assert_eq(source._picture.image.get_size(), DESKTOP_SIZE, "of the PNG's size")
    assert_true(_commands.execute(&"edit_copy"), "a Copy in Sara after it")
    source = SaNewFromClipboard.read(_doc, _held())
    assert_not_null(source, "New from Clipboard found a picture again")
    if source == null:
        return
    assert_null(source._picture, "Sara's copy this time")
    assert_eq(source._held.bounds.size, CANVAS, "of the copy's size")
