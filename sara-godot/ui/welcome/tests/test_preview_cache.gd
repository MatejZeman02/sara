## The card pictures for files that carry none of their own: a
## document read back once while it is live, kept under `user://` and named from
## the path and the file's time, and drawn by the recent grid when the file has
## no preview of its own.
##
## What a card looks like on the running app, and what the state dump says about
## where its picture came from, is
## `scenarios/a-file-with-no-preview-still-has-a-card-picture.json`.
extends "res://tests/test_framework.gd"

## A file with no preview of its own, which is every older `.sad` and every
## picture opened as a document.
static var scratch_plain: String = SaDataRoot.path("d5-plain.sad")

## A file that carries one, hand-written the way `test_recent_grid.gd`
## writes it.
static var scratch_with_preview: String = SaDataRoot.path("d5-with-preview.sad")

static var scratch_missing: String = SaDataRoot.path("d5-this-file-is-not-there.sad")

var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _write_plain(scratch_plain)
    _write_preview_sad(scratch_with_preview)
    DirAccess.remove_absolute(scratch_missing)
    # Oldest first, so the list reads newest first as the picture, the plain
    # file and the missing one, the order `test_recent_grid.gd` uses.
    SaSettings.add_recent_file(scratch_missing)
    SaSettings.add_recent_file(scratch_plain)
    SaSettings.add_recent_file(scratch_with_preview)
    # A picture left by an earlier run carries a time this run's file no longer
    # has, and one for a path this suite does not use is nobody's. Both go.
    WelcomePreviewCache.prune()


func after_each() -> void:
    for path: String in [scratch_plain, scratch_with_preview]:
        DirAccess.remove_absolute(_cache_name(path))
    WelcomePreviewCache.prune()
    for path: String in [scratch_with_preview, scratch_plain, scratch_missing]:
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(path)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func test_the_name_carries_the_path_and_the_file_s_time() -> void:
    var where := WelcomePreviewCache.cache_path(scratch_plain)
    assert_true(where.begins_with(WelcomePreviewCache.folder() + "/"), "under the cache folder: %s" % where)
    assert_true(where.ends_with("." + SaNoteImage.EXTENSION), "written as a WebP, the file's own preview format")
    assert_true(where.contains(scratch_plain.md5_text()), "keyed by the path's own digest, so two paths never share one")
    assert_true(
        where.ends_with("-%d.%s" % [FileAccess.get_modified_time(scratch_plain), SaNoteImage.EXTENSION]),
        "and by the second the file was written at: %s" % where
    )
    assert_eq(WelcomePreviewCache.cache_path(scratch_missing), "", "a path with no file behind it has no name")
    assert_eq(WelcomePreviewCache.cache_path(""), "", "and neither has an empty one")


func test_a_picture_written_for_a_file_is_read_back_at_the_preview_s_size() -> void:
    assert_null(WelcomePreviewCache.read(scratch_plain), "no picture before one is taken")
    assert_true(WelcomePreviewCache.write(scratch_plain, _picture(300, 200)), "a picture for a file that is there")
    var read_back := WelcomePreviewCache.read(scratch_plain)
    assert_not_null(read_back, "and it reads back")
    assert_eq(read_back.get_width(), WelcomePreviewCache.LONG_SIDE, "shrunk to the long side a file's preview uses")
    assert_eq(read_back.get_height(), 171, "keeping its shape, 200 of 300 at 256 across")


func test_a_picture_from_before_the_last_save_is_not_read() -> void:
    var when := FileAccess.get_modified_time(scratch_plain)
    var stale := "%s/%s-%d.%s" % [WelcomePreviewCache.folder(), scratch_plain.md5_text(), when - 1, SaNoteImage.EXTENSION]
    DirAccess.make_dir_recursive_absolute(WelcomePreviewCache.folder())
    assert_eq(SaNoteImage.save(_picture(8, 8), stale), OK, "a picture from before the last save reaches the disk")
    assert_false(FileAccess.file_exists(WelcomePreviewCache.cache_path(scratch_plain)), "and nothing is under the current name")
    assert_null(WelcomePreviewCache.read(scratch_plain), "so a file saved since its picture was taken draws its placeholder")


func test_the_folder_holds_no_more_than_the_recent_list_names() -> void:
    assert_true(WelcomePreviewCache.write(scratch_plain, _picture(8, 8)), "the plain file is cached")
    assert_true(WelcomePreviewCache.write(scratch_with_preview, _picture(8, 8)), "and so is the one with its own preview")
    var plain_name := _cache_name(scratch_plain)
    var preview_name := _cache_name(scratch_with_preview)
    assert_true(FileAccess.file_exists(plain_name) and FileAccess.file_exists(preview_name), "both are on disk")

    SaSettings.remove_recent_file(scratch_plain)
    WelcomePreviewCache.prune()
    assert_false(FileAccess.file_exists(plain_name), "the path off the list loses its picture")
    assert_true(FileAccess.file_exists(preview_name), "and the one still on it keeps it")


func test_no_picture_is_written_for_a_path_with_nothing_behind_it() -> void:
    assert_false(WelcomePreviewCache.write(scratch_missing, _picture(8, 8)), "a missing file is refused")
    assert_false(WelcomePreviewCache.write(scratch_plain, null), "and so is no picture at all")
    assert_false(FileAccess.file_exists(_cache_name(scratch_missing)), "nothing appears on disk for either")


func test_a_card_draws_the_cache_where_the_file_carries_no_picture() -> void:
    assert_true(WelcomePreviewCache.write(scratch_plain, _picture(64, 64)), "the plain file has a cached picture")
    var grid := WelcomeRecentGrid.new()
    var report := grid.row_report()
    assert_eq(report.size(), 3, "three cards for three recent paths")
    assert_eq(_source(report, scratch_plain), "cache", "the file with no preview is drawn from the cache")
    assert_eq(_source(report, scratch_with_preview), "file", "a file with its own preview is drawn from the file")
    assert_eq(_source(report, scratch_missing), "", "and a card for a file that is gone is drawn from neither")
    assert_true(report[1]["preview"] as bool, "so the plain file's card reports a picture")
    assert_not_null(grid.cards[1].get_parent().find_child("Thumbnail", true, false), "and draws it rather than the placeholder")
    grid.free()


func test_only_a_path_that_arrives_is_read_as_the_open_that_moved_the_list() -> void:
    var grid := WelcomeRecentGrid.new()
    assert_eq(grid._arrived, "", "nothing has arrived before the list moves")
    # The plain file is already on the list, second, so this pushes it to the
    # head without changing the list's length: the shape `File > Open` makes
    # when the file is one a painter opened before.
    SaSettings.add_recent_file(scratch_plain)
    assert_eq(grid._arrived, scratch_plain, "a path pushed to the head is the one that arrived")
    SaSettings.add_recent_file(scratch_plain)
    assert_eq(grid._arrived, "", "and opening the same file again moves nothing, so nothing arrives")
    # A remove shortens the list, so its new head is a path that was already
    # there and no document was opened by it.
    SaSettings.remove_recent_file(str(SaSettings.recent_files()[0]))
    assert_eq(grid._arrived, "", "a remove opens nothing and nothing arrives")
    grid.free()


## The picture of a document read back at `width` by `height`, which is what
## `SaExport.get_preview_image` hands the cache on the running app.
func _picture(width: int, height: int) -> Image:
    var picture := Image.create(width, height, false, Image.FORMAT_RGBA8)
    picture.fill(Color(0.2, 0.4, 0.6))
    return picture


## Where the file at *path* has its picture, asked before the file is removed.
func _cache_name(path: String) -> String:
    return WelcomePreviewCache.cache_path(path)


func _source(report: Array, path: String) -> String:
    for row: Dictionary in report:
        if str(row["path"]) == path:
            return str(row["source"])
    return "<no card>"


## A `.sad` with no preview in it: a v4 header with nothing but a document name,
## written the way `SaCapture`'s own `save` step writes one, so this suite covers
## the shape the scenario meets rather than a hand-made one.
func _write_plain(path: String) -> void:
    var raw := JSON.stringify({"name": "d5-plain"}).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.close()
    assert_null(SaSadFile.read_preview(path), "the hand-written plain file carries no picture")


## A v4 `.sad` that carries a 64 by 36 preview and nothing else.
func _write_preview_sad(path: String) -> void:
    var picture := Image.create(64, 36, false, Image.FORMAT_RGBA8)
    picture.fill(Color(0.8, 0.3, 0.2))
    var blob := picture.save_webp_to_buffer(true, 0.9)
    var header := {"preview": {"offset": 0, "size": blob.size(), "format": "webp", "width": 64, "height": 36}}
    var raw := JSON.stringify(header).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.store_buffer(blob)
    file.close()
