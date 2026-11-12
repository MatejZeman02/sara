## Frames at rest, the two the review found.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An audit read every `_process`, `Timer` and per-frame `queue_redraw` in
## the tree for what it costs while nothing changes, behind the frame pacer: Sara idle drew
## every frame. The five-second rests measured zero frames, and the two rows
## below are what a frame at rest still owes.
##
## **A row's method is `pending_` until its fix lands.** A reviewer never fixes,
## so each asserts the behaviour the fix has to produce and fails against the
## tree it was written on. The runner calls `test_` methods only, and the fixer
## of a row renames its method in the same commit as the fix. Both are renamed:
##
## | Method | Row | What it reads |
## |---|---|---|
## | `test_every_refresh_that_rewrites_a_texture_asks_for_a_frame` | f9 | a `queue_redraw` in each of three refreshes, fixed |
## | `test_a_hidden_info_docker_stops_its_ticker` | f10 | a stopped `Timer` while the docker is hidden, fixed |
##
## f9 is read off the source, the way `test_f95` reads the visibility overrides:
## the ask is a deferred callback the engine flushes between iterations, and a
## suite that awaits drops every assertion after the await. What
## has to hold is that each refresh asks at all.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

## Each refresh that dispatches into the texture its `TextureRect` already
## shows, and the ask it has to carry, as it reads in the file.
const REFRESHES: Array = [
    {"path": "res://ui/dockers/layers/list/thumbnail/layer_thumbnail.gd", "asks": "queue_redraw()"},
    {"path": "res://ui/dockers/graph/graph_docker.gd", "asks": "_picture.queue_redraw()"},
    # The Levels histogram, the base module's.
    {"path": "res://modules/sara-base-modules/base/filters/sa_adjust_graph.gd", "asks": "queue_redraw()"},
]


## The body of `refresh`, from its signature to the next top-level definition.
static func _refresh_body(source: String) -> String:
    var start := source.find("\nfunc refresh() -> void:")
    if start < 0:
        return ""
    var after := source.find("\nfunc ", start + 1)
    var until := source.find("\nstatic func ", start + 1)
    if until >= 0 and (after < 0 or until < after):
        after = until
    return source.substr(start, -1 if after < 0 else after - start)


## The measurement's own instrument: the pacer's capture line carries the
## engine's drawn-frame count, which is the one number the audit is about and which no
## dump carried before.
func test_the_pacer_reports_the_frames_drawn() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree to ask the pacer in")
    if tree == null:
        return
    var line := SaFramePacer.capture_state(tree)
    var report: Variant = JSON.parse_string(line.trim_prefix("SaCapture: pacer "))
    assert_true(report is Dictionary, "the pacer line is JSON after its prefix")
    if report is Dictionary:
        assert_true(report.has("frames_drawn"), "and it carries frames_drawn")
        assert_eq(int(report["frames_drawn"]), Engine.get_frames_drawn(), "which is the engine's own count")


## f9. The layer thumbnail, the Graph docker and the adjustment dialog's graph
## refresh by dispatching a kernel into the texture their `TextureRect` already
## shows, then hand the same `Texture2DRD` back to a setter that returns early
## on an unchanged object. The refresh moves VRAM and marks nothing, and the
## engine draws a frame only when something marked, so the row shows
## the old picture until something unrelated draws one.
func test_every_refresh_that_rewrites_a_texture_asks_for_a_frame() -> void:
    for entry: Dictionary in REFRESHES:
        var path := String(entry["path"])
        var source := FileAccess.get_file_as_string(path)
        assert_false(source.is_empty(), "%s is readable" % path)
        var body := _refresh_body(source)
        assert_false(body.is_empty(), "%s has a refresh() to read" % path)
        assert_true(
            body.contains(String(entry["asks"])),
            "%s's refresh asks for a frame with %s after it rewrote its picture" % [path, entry["asks"]]
        )


## f10, fixed. The docker wrote its rows ten times a second from a `Timer` that
## autostarted and was never stopped, whether or not the docker was shown. A
## closed docker is still in the tree, so at rest it formatted twenty strings a
## tick for nobody, and the moment a counter moved its labels changed text and
## the engine drew a frame of a window nobody sees. `info_docker.gd` follows
## `visibility_changed` now.
##
## The docker goes into the tree the way `test_windows_open` puts every window
## there: under an autoload's child, with subwindows embedded, or the run maps
## a real OS window and blocks.
func test_a_hidden_info_docker_stops_its_ticker() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree to put a docker in")
    if tree == null:
        return
    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "InfoDockerRestHost"
    EventBus.add_child(host)

    var docker: InfoDocker = DOCKER.new()
    docker.name = "InfoDockerUnderTest"
    host.add_child(docker)
    docker.show()
    assert_true(docker.is_embedded(), "the docker must embed here, or this test maps a real OS window")
    assert_false(docker._update_timer.is_stopped(), "a shown docker ticks")

    docker.hide()
    assert_true(docker._update_timer.is_stopped(), "a hidden docker stops ticking, its rows have nobody to read them")

    docker.show()
    assert_false(docker._update_timer.is_stopped(), "and starts again when it is shown")

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding
