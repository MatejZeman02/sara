## An F3 pressed in the first seconds after launch lists the
## settings.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An opening which finds the settings' catalogue stale
## asks for it to be built, and that nothing builds it while the list is up. Here
## the list opens on an index nothing has warmed, a query is typed, and the
## build is driven a page at a time with the list visible throughout. What a
## painter sees is
## `scenarios/an-f3-pressed-in-the-first-seconds-after-launch-lists-the-settings.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


## The opening lists no setting, each page leaves the list up, and once the last
## page is in the typed query finds Display profile, a setting.
func test_the_settings_join_an_open_list_page_by_page() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "U198SearchHost"
    EventBus.add_child(host)
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass, Callable())
    var window := SaSearchWindow.new(SaSearchIndex.new(registries.context))
    host.add_child(window)

    assert_true(window.index.settings_stale(), "Nothing has built the catalogue before the opening")
    window.open()
    assert_true(window.visible, "The list is up")
    assert_eq(_settings_in(window.entries), 0, "and the opening lists no setting")
    window.field.text = "display profile"
    window.field.text_changed.emit("display profile")
    assert_false(_lists_display_profile(window), "Display profile is not found before the build")

    var pages := 1
    while not window.warmer.step() and pages < 10000:
        assert_true(window.visible, "The list stays up while page %d is built" % pages)
        pages += 1
    assert_true(pages > 5, "The build ran a page a call, %d calls" % pages)
    assert_true(window.visible, "The list is still up after the last page")
    assert_false(window.index.settings_stale(), "The catalogue is built")
    assert_true(_settings_in(window.entries) > 100, "The open list's rows hold the settings")
    assert_eq(window.field.text, "display profile", "The typed query is kept")
    assert_true(_lists_display_profile(window), "and it finds Display profile: %s" % [window.report()])

    host.free()
    tree.root.gui_embed_subwindows = embedded


func _settings_in(rows: Array[SaSearchIndex.Entry]) -> int:
    var count := 0
    for entry: SaSearchIndex.Entry in rows:
        if entry.kind == SaSearchIndex.SETTING:
            count += 1
    return count


func _lists_display_profile(window: SaSearchWindow) -> bool:
    for entry: SaSearchIndex.Entry in window.shown:
        if entry.kind == SaSearchIndex.SETTING and entry.title == "Display profile":
            return true
    return false
