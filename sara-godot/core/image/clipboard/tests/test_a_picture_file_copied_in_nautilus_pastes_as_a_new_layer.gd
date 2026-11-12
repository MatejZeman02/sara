## A file manager's Copy names the picture, so the paste reads it as the file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Nautilus 51.1 on a nested weston, copying one PNG and then two, offered
## `x-special/gnome-copied-files`, `text/plain;charset=utf-8`, `text/uri-list`
## and the portal's two tokens, and its plain text held the bare paths with no
## `file://`, which the old reader turned away. Each case here hands the reader
## the text one of those types holds, written as Nautilus wrote it.
extends "res://tests/test_framework.gd"

const SIZE := Vector2i(12, 8)

var _folder: String = ""
var _first: String = ""
var _second: String = ""


func before_each() -> void:
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _first = _folder.path_join("red one.png")
    _second = _folder.path_join("blue.png")
    assert_eq(_picture().save_png(_first), OK, "The first picture was written")
    assert_eq(_picture().save_png(_second), OK, "and the second")


func after_each() -> void:
    DirAccess.remove_absolute(_first)
    DirAccess.remove_absolute(_second)
    DirAccess.remove_absolute(_folder)


func _picture() -> Image:
    var image := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    return image


## The address a file manager writes for *path*, spaces escaped.
func _address(path: String) -> String:
    return "file://" + ("/" if not path.begins_with("/") else "") + path.replace(" ", "%20")


## Nautilus's plain text: the bare path, no `file://`, no line end.
func test_a_bare_path_names_the_picture() -> void:
    assert_eq(SaDesktopPicture.paths_in(_first), PackedStringArray([_first]), "The bare path is read as it is")
    var picture := SaDesktopPicture._at_address(_first)
    assert_not_null(picture, "and names a picture")
    if picture != null:
        assert_eq(picture.image.get_size(), SIZE, "read whole")
        assert_eq(picture.layer_name, "red one", "its layer named for the file")
        assert_eq(picture.left_out, 0, "with nothing left out")


## A `file://` line, as a browser or an older file manager leaves it.
func test_a_file_address_names_the_picture() -> void:
    assert_eq(SaDesktopPicture.paths_in(_address(_first) + "\r\n"), PackedStringArray([_first]), "The address decoded")
    assert_not_null(SaDesktopPicture._at_address(_address(_first)), "and it names a picture")


## `x-special/gnome-copied-files`: a `copy` line, then the addresses, and `cut`
## the same.
func test_a_copy_line_followed_by_addresses_names_the_pictures() -> void:
    for verb: String in ["copy", "cut"]:
        var text := "%s\n%s\n%s" % [verb, _address(_second), _address(_first)]
        assert_eq(SaDesktopPicture.paths_in(text), PackedStringArray([_second, _first]), "The %s line is skipped" % verb)
        var picture := SaDesktopPicture._at_address(text)
        assert_not_null(picture, "and the first address names a picture")
        if picture != null:
            assert_eq(picture.layer_name, "blue", "the first one copied")
            assert_eq(picture.left_out, 1, "and the second is counted as left out")


## `text/uri-list` with two files, each line ending in CRLF, and a comment.
func test_a_uri_list_with_two_files_names_both_in_order() -> void:
    var text := "# two files\r\n%s\r\n%s\r\n" % [_address(_first), _address(_second)]
    assert_eq(SaDesktopPicture.paths_in(text), PackedStringArray([_first, _second]), "Both, in the order copied")
    var picture := SaDesktopPicture._at_address(text)
    assert_not_null(picture, "The list names a picture")
    if picture != null:
        assert_eq(picture.source, _first, "the first")
        assert_eq(picture.left_out, 1, "one left out")
    assert_eq(SaDesktopPicture.left_out_line(1), "Only the first of the 2 pictures copied was pasted.", "and said so")


## Explorer's and Windows paths, which the reader takes on any system.
func test_a_drive_path_is_read_with_forward_slashes() -> void:
    assert_eq(SaDesktopPicture.paths_in("C:\\Users\\a\\b.png"), PackedStringArray(["C:/Users/a/b.png"]), "Backslashes")
    assert_eq(SaDesktopPicture.paths_in("file:///C:/Users/a%20b.png"), PackedStringArray(["C:/Users/a b.png"]), "an address")


## Text that is not a path stays no picture, so the paste says so as before.
func test_text_that_names_no_file_is_no_picture() -> void:
    for text: String in ["a picture.png", "Hello there", "//server/share/a.png", "", "copy"]:
        assert_null(SaDesktopPicture._at_address(text), "%s is no picture" % text)
    assert_null(SaDesktopPicture._at_address(_first.replace(".png", ".txt")), "nor a path to something else")
    assert_null(SaDesktopPicture._at_address(_folder.path_join("none.png")), "nor a path to nothing")
    assert_null(SaDesktopPicture._at_address("%s\n%s" % [_folder, _folder.path_join("none.png")]), "nor a list of those")


## A list where only the second file is a picture takes that one.
func test_a_list_skips_what_is_not_a_picture() -> void:
    var text := "%s\n%s" % [_folder, _second]
    var picture := SaDesktopPicture._at_address(text)
    assert_not_null(picture, "The picture in the list is found")
    if picture != null:
        assert_eq(picture.layer_name, "blue", "by its name")
        assert_eq(picture.left_out, 0, "and a folder is not counted")


## A list is asked of a clipboard program, and a display server that has none
## is asked for nothing. The Linux programs are named for the two types a file
## manager offers, and Explorer's file drop list is PowerShell's to print,
## since the engine's text clipboard never sees it.
func test_the_lists_are_asked_of_the_display_servers_own_program() -> void:
    assert_null(SaDesktopPicture._from_lists("Headless"), "No list is asked where there is no clipboard program")
    assert_null(SaDesktopPicture._from_lists("macOS"), "nor where the engine reads the clipboard itself")
    for server: String in ["Wayland", "X11", "Windows"]:
        var asked := SaTyped.list(SaDesktopPicture.FILE_LISTS.get(server))
        assert_true(not asked.is_empty(), "%s asks for a file list" % server)
        for entry: Variant in asked:
            var command := PackedStringArray(SaTyped.list(entry))
            assert_true(command.size() > 1, "%s's command names its program and its arguments" % server)
    assert_eq(
        str(SaTyped.list(SaDesktopPicture.FILE_LISTS["Wayland"])[0]).contains("text/uri-list"),
        true,
        "Wayland asks the uri list first"
    )
    assert_eq(
        str(SaTyped.list(SaDesktopPicture.FILE_LISTS["Windows"])[0]).contains("FileDropList"),
        true,
        "and Windows the file drop list"
    )
