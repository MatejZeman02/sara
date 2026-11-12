## The brush preset History docker.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree: the docker is built, driven through the
## methods the bus and the buttons call, and freed.
extends "res://tests/test_framework.gd"

const HistoryDockerScript = preload("res://ui/dockers/presets/history_docker.gd")

static var scratch_dir: String = SaDataRoot.path("test_preset_history")
static var scratch_list: String = SaDataRoot.path("test_preset_history.cfg")


func _docker() -> HistoryDocker:
    var docker: HistoryDocker = HistoryDockerScript.new()
    docker.path = scratch_list
    docker.store.dir = scratch_dir
    return docker


## Three presets on disk for the list to be checked against, because a name
## whose preset is gone is dropped rather than shown as a button that fails.
##
## The files are written straight rather than through `save_preset`, which
## needs a settings resource carrying a script and would tie this suite to the
## module that provides one. `has_preset` asks the filesystem, so a file of the
## right name is the whole of what it wants.
func _presets(names: Array) -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    for preset_name: String in names:
        var file := FileAccess.open(scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION), FileAccess.WRITE)
        if file != null:
            file.store_string('[gd_resource type="Resource" format=3]\n')
            file.close()


func before_each() -> void:
    _clean()


func after_each() -> void:
    _clean()


func _clean() -> void:
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_list))
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


## The claim, in the half a test can hold: three loads, three rows,
## in the order they were loaded, newest first.
func test_three_loads_are_three_rows_newest_first() -> void:
    var docker := _docker()
    for preset_name: String in ["Sketch", "Paint", "Ink"]:
        docker.record(preset_name)

    assert_eq(Array(docker.entries), ["Ink", "Paint", "Sketch"], "the last loaded is the first row")
    assert_eq(docker.rows.get_child_count(), 4, "three buttons and the empty label")
    assert_false(docker.empty_label.visible, "which is hidden once there is a row")
    assert_eq(docker.rows.get_child(1).text, "Ink", "and the top button is the last preset loaded")
    docker.free()


## Loading one again moves it up rather than adding a second row, which is what
## makes the docker a history rather than a log.
func test_loading_one_again_moves_it_up() -> void:
    var docker := _docker()
    for preset_name: String in ["Sketch", "Paint", "Ink"]:
        docker.record(preset_name)
    docker.record("Paint")

    assert_eq(Array(docker.entries), ["Paint", "Ink", "Sketch"], "the repeat is at the top and only there")
    assert_eq(docker.rows.get_child_count(), 4, "and there are still three buttons")
    docker.free()


## The cap holds, and it drops the oldest rather than refusing the newest.
func test_the_list_stops_at_twenty() -> void:
    var docker := _docker()
    for i in 25:
        docker.record("Preset %d" % i)

    assert_eq(docker.entries.size(), HistoryDockerScript.MAX_ENTRIES, "twenty at most")
    assert_eq(docker.entries[0], "Preset 24", "the newest is kept")
    assert_false(Array(docker.entries).has("Preset 4"), "and the oldest is the one that went")
    docker.free()


## The other half of the claim: a restart keeps them. The list is a file,
## so a second docker reading it is what a restart looks like from here.
func test_a_restart_keeps_the_list() -> void:
    _presets(["Sketch", "Paint", "Ink"])
    var docker := _docker()
    for preset_name: String in ["Sketch", "Paint", "Ink"]:
        docker.record(preset_name)
    docker.free()

    var reopened := _docker()
    reopened.load_from(scratch_list)
    assert_eq(Array(reopened.entries), ["Ink", "Paint", "Sketch"], "the order survives the file")
    assert_eq(reopened.rows.get_child_count(), 4, "and the rows are rebuilt from it")
    reopened.free()


## A preset deleted between sessions leaves a name nothing can load, so the
## name goes rather than becoming a button that fails.
func test_a_name_whose_preset_is_gone_is_dropped_on_the_way_in() -> void:
    _presets(["Sketch", "Ink"])
    var docker := _docker()
    for preset_name: String in ["Sketch", "Paint", "Ink"]:
        docker.record(preset_name)
    docker.free()

    var reopened := _docker()
    reopened.load_from(scratch_list)
    assert_eq(Array(reopened.entries), ["Ink", "Sketch"], "Paint was never saved, so it does not come back")
    reopened.free()


## Nothing to load is a sentence rather than an empty box.
func test_an_empty_history_says_so() -> void:
    var docker := _docker()
    docker.load_from(scratch_list)
    assert_true(docker.entries.is_empty(), "nothing on disk is nothing in the list")
    assert_true(docker.empty_label.visible, "and the docker says so")
    docker.free()
