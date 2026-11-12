## The chord that summons a docker under the pointer, and the
## leave that sends it back once the pointer has been away long enough.
##
## The cases: the docker appears where
## the pointer is, takes no focus and writes nothing to the layout, goes back
## when the pointer has been out for the dwell and past the distance, and the
## chord twice within a second closes it. The summon chords ship bound in Sara's
## own map and unbound in Krita's and Photoshop's.
##
## The windows are never added to a tree, for the capture pitfall page's reason,
## so the summon is driven through its own `step` with the clock handed in, and
## the focus rule through `DockerFocus.follow`, which is free of node state for
## exactly this. The running app's proof is the scenario named for the unit.
extends "res://tests/test_framework.gd"

## The command registry builds the InputMap actions, so the profile case needs
## the fixture `core/registry/tests/test_krita_profile.gd` uses, and that one needs a device.
const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_layout_path: String = SaDataRoot.path("test_u2_summon_layout.cfg")
const SECTION: String = "LayersDocker"
const HOME := Vector2i(1500, 120)
const SIZE := Vector2i(300, 400)
const POINT := Vector2i(700, 500)
## Far enough from any rectangle this suite draws to be past every reach.
const AWAY := Vector2(100, 100)
const REACH: float = 57.6

var _dwell_before: Variant = null


func before_each() -> void:
    _dwell_before = SaSettings.module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY)
    SaDockerBorrow.new().dwell_ms = 1000


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


func _docker(visible: bool) -> Window:
    var win := Window.new()
    win.name = SECTION
    win.position = HOME
    win.size = SIZE
    win.visible = visible
    return win


## A store with the one docker and the file written once from it, which is the
## layout a painter's session left behind.
func _store_with(win: Window) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": SECTION, "name": "Layers"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store


func test_a_summoned_docker_sits_under_the_pointer_and_leaves_after_the_dwell() -> void:
    var win := _docker(true)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)

    assert_true(summon.summon(win, SECTION, POINT, 10000), "the chord summons the docker")
    assert_true(Rect2i(win.position, win.size).has_point(POINT), "under the pointer")
    assert_true(summon.is_summoned(win), "and the summon says it is out")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "the layout file is byte for byte what it was")
    assert_eq(store.stored_positions().get(SECTION), HOME, "and the layout still holds the painter's position")

    var inside := Vector2(POINT)
    assert_false(summon.step(SECTION, inside, REACH, 10100), "the pointer inside keeps it")
    assert_false(summon.step(SECTION, inside, REACH, 20000), "however long it stays")
    var near := Vector2(win.position.x - REACH * 0.5, POINT.y)
    assert_false(summon.step(SECTION, near, REACH, 20100), "just outside, within the reach, starts nothing")
    assert_false(summon.step(SECTION, near, REACH, 30000), "and keeps nothing running")

    assert_false(summon.step(SECTION, AWAY, REACH, 30100), "past the reach starts the dwell")
    assert_false(summon.step(SECTION, AWAY, REACH, 30900), "and the docker waits it out")
    assert_false(summon.step(SECTION, inside, REACH, 31000), "coming back inside stops the dwell")
    assert_false(summon.step(SECTION, AWAY, REACH, 31100), "leaving again starts it afresh")
    assert_false(summon.step(SECTION, AWAY, REACH, 32000), "so the first leave's time is not counted")
    assert_true(summon.step(SECTION, AWAY, REACH, 32100), "a full dwell away sends it back")

    assert_false(store.is_borrowed(SECTION), "nothing is borrowed after the leave")
    assert_eq(win.position, HOME, "the docker is where the painter left it")
    assert_eq(win.size, SIZE, "at its own size")
    assert_true(win.visible, "and a docker that was open stays open, having jumped and come back")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "and the leave wrote nothing either")

    summon.free()
    win.free()
    store.free()


func test_the_chord_twice_within_a_second_closes_the_docker() -> void:
    var win := _docker(false)
    var store := _store_with(win)
    var summon := DockerSummon.new(store)

    assert_true(summon.summon(win, SECTION, POINT, 5000), "the first press summons")
    assert_true(win.visible, "a shut docker is shown")
    assert_true(summon.summon(win, SECTION, POINT, 5600), "the second press answers")
    assert_false(store.is_borrowed(SECTION), "and closes it within the second")
    assert_false(win.visible, "back to shut, which is where it was")
    assert_eq(win.position, HOME, "at the painter's position")

    summon.summon(win, SECTION, POINT, 8000)
    var moved_to := Vector2i(300, 300)
    summon.summon(win, SECTION, moved_to, 9500)
    assert_true(store.is_borrowed(SECTION), "a second press after the second moves rather than closes")
    assert_true(Rect2i(win.position, win.size).has_point(moved_to), "to where the pointer is now")
    summon.send_back(SECTION)
    assert_eq(win.position, HOME, "and the return still goes to the painter's rectangle")
    assert_false(win.visible, "shut, as the first summon found it")

    summon.free()
    win.free()
    store.free()


func test_the_distance_is_to_the_rectangle_not_its_centre() -> void:
    var rect := Rect2(Vector2(100, 100), Vector2(300, 400))
    assert_eq(DockerSummon.distance_to(rect, Vector2(200, 200)), 0.0, "inside is no distance")
    assert_almost_eq(DockerSummon.distance_to(rect, Vector2(430, 300)), 30.0, 0.001, "beside the right edge")
    assert_almost_eq(DockerSummon.distance_to(rect, Vector2(430, 540)), 50.0, 0.001, "off the corner")


func test_a_summoned_docker_takes_no_focus_from_the_pointer() -> void:
    var docker := DockerWindow.new()
    docker.position = Vector2i(0, 0)
    docker.size = Vector2i(200, 200)
    docker.visible = true
    var stack: Array[Window] = [docker]
    var at := Vector2(50, 50)
    assert_eq(DockerFocus.follow(stack, null, at), docker, "an ordinary docker under the pointer takes the keyboard")
    var stands_off := func(win: Window) -> bool: return win == docker
    assert_null(DockerFocus.follow(stack, null, at, stands_off), "a summoned one leaves it with the canvas")
    assert_eq(DockerFocus.follow(stack, docker, at, stands_off), docker, "and one the painter clicked into keeps it")
    var canvas := Vector2(900, 900)
    assert_eq(DockerFocus.follow(stack, docker, canvas, stands_off), docker, "even with the pointer out over the canvas")
    assert_null(DockerFocus.follow(stack, docker, canvas), "where an ordinary docker gives it back")
    docker.free()


func test_the_summon_chords_are_bound_in_sara_and_empty_in_the_other_two() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var summons: Array[StringName] = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        summons.append(SaAppCommands.summon_id(entry[0]))
    assert_eq(summons.size(), 13, "one summon for each of the thirteen dockers, the pop-up palette among them")
    assert_true(summons.has(&"docker_summon_layers"), "named after the docker's word")
    assert_true(summons.has(&"docker_summon_info"), "the Info docker's included, whose toggle is info_docker")

    var seen: Array[String] = []
    for action: StringName in summons:
        var chords := SaShortcutStore.chords_for(action)
        assert_eq(chords.size(), 1, "%s has one chord in Sara's own map" % action)
        if chords.is_empty():
            continue
        assert_true(chords[0].begins_with("Alt+Shift+"), "%s is Alt+Shift with the docker's key, not %s" % [action, chords[0]])
        assert_false(seen.has(chords[0]), "%s is the only summon on %s" % [action, chords[0]])
        seen.append(chords[0])
        assert_eq(SaShortcutStore.conflicts(chords[0], action), [] as Array[String], "nothing else answers %s" % chords[0])

    for profile: String in SaShortcutStore.SHIPPED_PROFILES:
        var map := SaShortcutStore.load_profile(profile)
        for action: StringName in summons:
            # But the palette's under Krita, its one chord there, because Shift+W
            # belongs to the wrap.
            var palette := profile == "Krita" and action == &"docker_summon_palette"
            var kept: Array = ["Alt+Shift+W"] if palette else [""]
            assert_eq(map.get(String(action), []), kept, "%s leaves %s as it ships" % [profile, action])


func test_the_two_preferences_are_the_skeletons_own() -> void:
    var borrow := SaDockerBorrow.new()
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DISTANCE_KEY, null)
    assert_eq(borrow.distance, 0.03, "three percent of the width until the painter sets one")
    borrow.distance = 0.9
    assert_eq(borrow.distance, SaDockerBorrow.MAX_DISTANCE, "a distance past half the screen is held at half")
    assert_eq(
        SaSettings.module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DISTANCE_KEY),
        SaDockerBorrow.MAX_DISTANCE,
        "and it is written under the skeleton's own section"
    )
    assert_false(SaSettingsKeys.KEYS.has("docker_borrow_distance"), "not as a property of the skeleton's settings")
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DISTANCE_KEY, null)
    borrow.dwell_ms = -5
    assert_eq(borrow.dwell_ms, 0, "a negative wait is none")
