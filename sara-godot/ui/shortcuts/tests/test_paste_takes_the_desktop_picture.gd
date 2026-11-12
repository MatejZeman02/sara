## Paste takes a picture from the desktop clipboard, and says so when there is
## none.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A picture put on the clipboard with `wl-copy` and Ctrl+V pressed gave no
## layer and no message. Under Wayland the engine answers that the
## clipboard holds a picture and hands over an empty one, measured by
## `scenarios/paste-takes-an-image-from-the-desktop-clipboard-and-copy-puts-one.json`,
## and the paste returned on that in silence. The desktop clipboard is the seam
## `SaShortcutCommands.desktop_picture` here, because a run on a desktop would
## paste whatever was copied there last, and each case sets it to a picture, an
## empty picture or nothing. What the engine and the clipboard programs answer
## on a real display is the scenario's to measure.
##
## The screen is a `SubViewport` with subwindows embedded in it, so the Fit
## dialog a paste opens is a window the case can find and answer.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks.
const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)

## A size that is not the canvas's, so the paste asks how to fit it.
const OTHER_SIZE := Vector2i(100, 50)

var _kept_reader: Callable = Callable()
var _kept_fit: String = ""
var _kept_embedding: bool = true
var _host: Node = null
var _screen: SubViewport = null
var _easel: SaEasel = null


func before_each() -> void:
    _shared().clear()
    _kept_reader = SaShortcutCommands.desktop_picture
    _kept_fit = SaSettings.import_fit
    SaSettings.import_fit = "ask"
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S14PasteHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    _screen = SubViewport.new()
    _screen.size = Vector2i(1280, 800)
    _screen.gui_embed_subwindows = true
    _host.add_child(_screen)
    _easel = SaEasel.create_default(CANVAS)


func after_each() -> void:
    SaShortcutCommands.desktop_picture = _kept_reader
    SaSettings.import_fit = _kept_fit
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _easel != null and is_instance_valid(_easel):
        _easel.free()
    if _host != null and is_instance_valid(_host):
        _host.free()
    _easel = null
    _host = null
    _screen = null


## A solid opaque red picture of *size*, so a texel says whether it landed.
func _picture(size: Vector2i) -> Image:
    var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    return image


## The seam answering *picture* on every call, each call counted in *calls*.
func _desktop_holds(picture: SaDesktopPicture, calls: Array = []) -> void:
    SaShortcutCommands.desktop_picture = func() -> SaDesktopPicture:
        calls.append(true)
        return picture


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


func _fit_dialog() -> SaImportFitDialog:
    return _screen.get_node_or_null(^"ImportFitDialog") as SaImportFitDialog


func _notice_says() -> String:
    var notice := SaMessage.notice_widget()
    return notice.label.text if notice != null and notice.showing() else ""


func _paste(placed: Array[SaLayer]) -> void:
    SaShortcutCommands.paste(_easel.document, _screen, func(layer: SaLayer) -> void: placed.append(layer))


## The plain case: a picture the canvas's size goes down at once as
## a layer of its own, under the name a paste gives, and the corner says
## nothing.
func test_a_picture_on_the_desktop_clipboard_becomes_a_layer() -> void:
    _desktop_holds(SaDesktopPicture.new(_picture(CANVAS), "the engine"))
    var before := _easel.document.get_child_count()
    var placed: Array[SaLayer] = []
    _paste(placed)
    assert_eq(_easel.document.get_child_count(), before + 1, "The paste added a layer")
    assert_eq(placed.size(), 1, "and handed it over")
    assert_eq(str(placed[0].name), "Pasted Picture", "named for a paste")
    assert_almost_eq(_texel(placed[0], 4, 4).r, 1.0, 1e-3, "holding the desktop's picture")
    assert_null(_fit_dialog(), "A picture the canvas's size is not asked about")
    assert_eq(_notice_says(), "", "and the corner says nothing")


## A picture of another size asks first, in the Fit dialog, when Paste Special
## pastes it, and Place puts it down. Ctrl+V no longer asks under the default
## which the suite beside this one reads.
func test_a_picture_of_another_size_opens_the_fit_dialog() -> void:
    _desktop_holds(SaDesktopPicture.new(_picture(OTHER_SIZE), "the engine"))
    var before := _easel.document.get_child_count()
    var placed: Array[SaLayer] = []
    SaShortcutCommands.paste(_easel.document, _screen, func(layer: SaLayer) -> void: placed.append(layer), true)
    var dialog := _fit_dialog()
    assert_not_null(dialog, "The paste opened the Fit dialog")
    if dialog == null:
        return
    assert_true(dialog.visible, "on screen")
    assert_eq(_easel.document.get_child_count(), before, "and nothing lands before it is answered")
    (dialog.find_child("PlaceButton", true, false) as Button).pressed.emit()
    assert_false(dialog.visible, "Place closes it")
    assert_eq(_easel.document.get_child_count(), before + 1, "and the picture is a layer")
    assert_eq(placed.size(), 1, "handed over once")
    assert_eq(str(placed[0].name), "Pasted Picture", "named for a paste")
    assert_eq(_notice_says(), "", "The corner says nothing")


## What Wayland answers with nothing copied: a picture, and an empty one. It is
## nothing to paste, and the paste says so rather than returning in silence.
func test_an_empty_picture_is_nothing_to_paste_and_says_so() -> void:
    _desktop_holds(SaDesktopPicture.new(Image.new(), "the engine"))
    var before := _easel.document.get_child_count()
    var placed: Array[SaLayer] = []
    _paste(placed)
    assert_eq(_easel.document.get_child_count(), before, "No layer")
    assert_true(placed.is_empty(), "and nothing handed over")
    assert_null(_fit_dialog(), "No Fit dialog")
    assert_eq(_notice_says(), SaShortcutCommands.NOTHING_TO_PASTE, "The corner says there is nothing to paste")


## Nothing on either clipboard, the silent case.
func test_nothing_on_either_clipboard_says_so() -> void:
    _desktop_holds(null)
    var before := _easel.document.get_child_count()
    var placed: Array[SaLayer] = []
    _paste(placed)
    assert_eq(_easel.document.get_child_count(), before, "No layer")
    assert_null(_fit_dialog(), "No Fit dialog")
    assert_eq(
        _notice_says(),
        "Nothing to paste. Copy in Sara, or put a picture on the desktop clipboard.",
        "The corner says what to do, in the row's words"
    )


## Sara's own clipboard first, so a Copy inside Sara is never overruled by a
## picture a browser left on the desktop, and the desktop is not even asked.
func test_saras_own_clipboard_comes_before_the_desktop() -> void:
    var document := _easel.document
    var painted := SaLayerOps.new(document).add()
    painted.fill(Color(0.0, 1.0, 0.0, 1.0))
    document.set_active_layer(painted)
    assert_true(_shared().copy(document, painted) > 0, "Copy took something")
    var calls: Array = []
    _desktop_holds(SaDesktopPicture.new(_picture(CANVAS), "the engine"), calls)
    var before := document.get_child_count()
    var placed: Array[SaLayer] = []
    _paste(placed)
    assert_eq(document.get_child_count(), before + 1, "The paste added a layer")
    assert_almost_eq(_texel(document.active_layer, 4, 4).g, 1.0, 1e-3, "and it is what Copy took")
    assert_true(calls.is_empty(), "The desktop clipboard was not read")
    assert_eq(_notice_says(), "", "and the corner says nothing")


## A file manager's Copy leaves the file's address as text. The picture it names
## is read the way a dropped file is, and the layer takes the file's name.
func test_a_file_address_on_the_text_clipboard_names_a_picture() -> void:
    var folder := OS.get_temp_dir().path_join("sara-s14-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    var path := folder.path_join("a picture.png")
    assert_eq(_picture(OTHER_SIZE).save_png(path), OK, "The picture was written")
    var address := "file://" + ("/" if not path.begins_with("/") else "") + path.replace(" ", "%20")

    var picture := SaDesktopPicture._at_address(address + "\r\n")
    assert_not_null(picture, "The address names a picture")
    if picture != null:
        assert_eq(picture.image.get_size(), OTHER_SIZE, "read whole")
        assert_eq(picture.layer_name, "a picture", "its layer named for the file")
        assert_eq(picture.source, path, "and its source is the file")
    var at_localhost := SaDesktopPicture._at_address(address.replace("file://", "file://localhost"))
    assert_not_null(at_localhost, "The localhost form names the same picture")

    assert_null(SaDesktopPicture._at_address("a picture.png"), "Text that is not an address is no picture")
    assert_null(SaDesktopPicture._at_address(address.replace(".png", ".txt")), "nor an address of something else")
    assert_null(SaDesktopPicture._at_address(address.replace("a%20picture", "no%20picture")), "nor of nothing")
    DirAccess.remove_absolute(path)
    DirAccess.remove_absolute(folder)


## A clipboard program's bytes arrive as it wrote them, `$` and quotes and all,
## which `OS.execute` did not do: it ran the line through a shell that expanded
## them. A program that refuses gives nothing, and so does one there is no such
## display server for.
func test_a_clipboard_programs_bytes_arrive_as_written() -> void:
    if OS.get_name() == "Windows" or not SaRecorder.program_available("printf"):
        skip("no printf to stand in for a clipboard program")
        return
    var said := SaDesktopPicture._output_of("printf", PackedStringArray(["%s|", "a $HOME", 'b "c"']))
    assert_eq(said.get_string_from_utf8(), 'a $HOME|b "c"|', "Every byte as written")
    if SaRecorder.program_available("false"):
        assert_eq(SaDesktopPicture._output_of("false", PackedStringArray()).size(), 0, "A program that fails gives nothing")
    assert_null(SaDesktopPicture._from_program("Headless"), "No program reads a clipboard there is no server for")


## The clipboard the open documents share, the run's owner's, as main's is in
## the app. Asked for in `before_each`, which makes the owner when the run has
## none, so the commands find it.
func _shared() -> SaClipboard:
    return SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard


## Several files copied at once paste the first and say the rest were left
## out, in the row's words.
func test_several_files_copied_paste_the_first_and_say_so() -> void:
    _desktop_holds(SaDesktopPicture.new(_picture(CANVAS), "/a/red one.png", null, "red one", 2))
    var placed: Array[SaLayer] = []
    _paste(placed)
    assert_eq(placed.size(), 1, "One layer")
    assert_eq(str(placed[0].name), "red one", "named for the first file")
    assert_eq(_notice_says(), "Only the first of the 3 pictures copied was pasted.", "and the corner says so")
