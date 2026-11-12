## A `docker` step's placement outlives the layout store's settle loop.
##
## Filed by `s3-review-door` as `docker-step-inside-the-settle`. For sixty
## frames after a restore, `DockerLayoutStore._settle_against_compositor` puts
## every docker back where the stored layout says, which is right when the
## compositor moved it and wrong when a scenario did. `SaDockerDriver.docker`
## wrote `window.position` and printed it, the settle loop undid it on the next
## frame, and nothing said so: a scenario that placed a docker and then aimed at
## it aimed at the old rectangle, and `click-a-control-by-name`'s `control`
## step resolved correctly to the wrong place.
##
## **The fix is a note, not a save.** `note_placement` writes the store's own
## cache and its intended position, which is what the settle loop reads, and
## touches no file. `save(true)` would have done the same and written the
## painter's layout as well, which is the class `f59-scenario-layout` spent a
## unit on.
##
## The running-app half is `scenarios/docker-step-inside-the-settle.json`,
## whose first `docker` step has no wait in front of it and whose first dump
## reads the position it asked for. Before the fix it read (1584, 105), the
## stored one.
##
## The same fix applies on the other branch of the same function.
## `{"docker": "park"}` moved every window and noted none of them, so a park
## inside the settle window left `stored_positions` holding the layout the park
## had just undone. It surfaced as a scenario disagreeing with itself down the
## two paths rather than as a wrong shot, because a parked docker is off the
## edge either way and only the dump says where the layout thinks it is.
extends "res://tests/test_framework.gd"


func test_a_noted_placement_is_what_the_settle_loop_reads() -> void:
    var store := DockerLayoutStore.new()
    var win := Window.new()
    win.name = "ColorDocker"
    win.position = Vector2i(1584, 105)
    win.size = Vector2i(321, 480)
    # Not added to the tree: a `Window` in a headless suite hangs, which is the
    # capture pitfall page's own entry, and nothing here needs it drawn.
    var config := {"node": win, "id": "ColorDocker", "name": "Colour Picker"}
    store.dockers_provider = func() -> Array: return [config]

    assert_eq(
        store.value_for("ColorDocker", "position", Vector2i(-1, -1)),
        Vector2i(-1, -1),
        "the store has no opinion about a docker nothing has told it about"
    )

    win.position = Vector2i(400, 300)
    assert_true(store.note_placement(win), "the store knows this window")
    assert_eq(
        store.value_for("ColorDocker", "position", Vector2i(-1, -1)),
        Vector2i(400, 300),
        "and the settle loop now re-asserts where the step put it, not where the file says"
    )
    assert_eq(store.value_for("ColorDocker", "size", Vector2i()), Vector2i(321, 480), "the size goes with it")

    var stranger := Window.new()
    stranger.name = "NotADocker"
    assert_false(store.note_placement(stranger), "a window the store does not own is refused rather than cached")

    stranger.free()
    win.free()
    store.free()


## Park is the same note over every docker, and it is the note rather than
## the move that was missing: the windows went to `PARK_AT` all along.
func test_every_parked_docker_is_noted_the_way_one_placed_docker_is() -> void:
    var store := DockerLayoutStore.new()
    var windows: Array[Window] = []
    var configs: Array = []
    for name: String in ["ColorDocker", "LayersDocker", "ToolBoxDocker"]:
        var win := Window.new()
        win.name = name
        win.position = Vector2i(1584, 105)
        win.size = Vector2i(321, 480)
        windows.append(win)
        configs.append({"node": win, "id": name, "name": name})
    store.dockers_provider = func() -> Array: return configs

    for win in windows:
        assert_eq(
            store.value_for(String(win.name), "position", Vector2i(-1, -1)),
            Vector2i(-1, -1),
            "nothing is stored for %s before the park" % win.name
        )

    # What `SaDockerDriver._park_every_docker` does, per window: the move it
    # always did, and the note it went without.
    for win in windows:
        win.position = SaDockerDriver.PARK_AT
        assert_true(store.note_placement(win), "the store knows %s" % win.name)

    for win in windows:
        assert_eq(
            store.value_for(String(win.name), "position", Vector2i(-1, -1)),
            SaDockerDriver.PARK_AT,
            "%s is parked in the layout as well as on the screen" % win.name
        )

    for win in windows:
        win.free()
    store.free()
