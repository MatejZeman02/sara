## The welcome window's recent documents stand under their
## folders, a header per folder over its cards, the folders in the order of the
## newest document in each, the ten newest documents the limit.
##
## The grouping is handed paths and times alone, and then the grid is built
## over a recent list in three folders and its headers and cards are read.
extends "res://tests/test_framework.gd"

var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))


func after_each() -> void:
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _entry(path: String, time: float) -> Dictionary:
    return {"path": path, "time": time}


func test_the_folders_stand_in_the_order_of_their_newest_document() -> void:
    var groups := (
        WelcomeRecentFolders
        . group(
            [
                _entry("/art/old/a.sad", 100.0),
                _entry("/art/new/b.sad", 500.0),
                _entry("/art/mid/c.sad", 300.0),
                _entry("/art/old/d.sad", 400.0),
                _entry("/art/new/e.sad", 200.0),
            ]
        )
    )
    var folders: Array = groups.map(func(g: Dictionary) -> String: return g["folder"])
    assert_eq(folders, ["/art/new", "/art/old", "/art/mid"], "the folder of the newest document first, then by each one's newest")
    assert_eq(groups[0]["paths"], ["/art/new/b.sad", "/art/new/e.sad"], "a folder's cards newest first")
    assert_eq(groups[1]["paths"], ["/art/old/d.sad", "/art/old/a.sad"], "an older folder's too")
    assert_eq(groups[2]["paths"], ["/art/mid/c.sad"], "and a folder of one card")


func test_only_the_ten_newest_are_grouped() -> void:
    var entries: Array = []
    for i in 14:
        entries.append(_entry("/art/f%d/doc%d.sad" % [i % 3, i], float(i)))
    var groups := WelcomeRecentFolders.group(entries)
    var paths: Array = []
    for group: Dictionary in groups:
        paths.append_array(group["paths"])
    assert_eq(paths.size(), 10, "ten documents across the folders")
    for i in 4:
        assert_false(paths.has("/art/f%d/doc%d.sad" % [i % 3, i]), "the four oldest are left out, doc%d" % i)
    assert_eq(groups[0]["folder"], "/art/f1", "doc13 is the newest, so its folder leads")


func test_one_time_keeps_the_order_handed_in() -> void:
    var groups := WelcomeRecentFolders.group([_entry("/x/a.sad", 1.0), _entry("/y/b.sad", 1.0)])
    assert_eq(groups[0]["folder"], "/x", "a tie keeps the order of the list")


func test_the_recent_list_is_timed_by_its_order() -> void:
    var entries := WelcomeRecentFolders.of_recent_list(["/a/1.sad", "/b/2.sad", "/a/3.sad"])
    var groups := WelcomeRecentFolders.group(entries)
    assert_eq(groups.size(), 2, "two folders")
    assert_eq(groups[0]["paths"], ["/a/1.sad", "/a/3.sad"], "the head of the list is the newest")


func test_the_grid_draws_a_header_over_each_folders_cards() -> void:
    # Oldest first, so the list reads newest first: c/3, b/2, a/1, c/0.
    for path: String in ["/probe/c/0.sad", "/probe/a/1.sad", "/probe/b/2.sad", "/probe/c/3.sad"]:
        SaSettings.add_recent_file(path)
    var grid := WelcomeRecentGrid.new()
    assert_eq(grid.grids.size(), 3, "a grid per folder")
    var headers: Array = []
    for child: Node in grid.folders.get_children():
        if child is Label:
            headers.append((child as Label).text)
    assert_eq(headers, ["/probe/c", "/probe/b", "/probe/a"], "a header per folder, the newest document's first")
    assert_eq(grid.grids[0].get_child_count(), 2, "the newest folder holds its two cards")
    var rows: Array = grid.row_report().map(func(r: Dictionary) -> String: return r["path"])
    assert_eq(rows, ["/probe/c/3.sad", "/probe/c/0.sad", "/probe/b/2.sad", "/probe/a/1.sad"], "the cards stand folder by folder")
    var header_index := grid.folders.get_node("FolderHeader0").get_index()
    assert_eq(grid.folders.get_node("Cards0").get_index(), header_index + 1, "and each header stands over its cards")
    grid.free()
