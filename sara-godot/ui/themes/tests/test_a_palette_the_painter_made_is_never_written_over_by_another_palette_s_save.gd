## A palette the painter made is never written over by another palette's save.
##
## A swatch edit on a shipped palette forks it as "<name> (custom)", and picking
## the shipped one again and touching a swatch forked a second time under the
## same name, so the second fork's file was the first's and a palette built
## swatch by swatch was gone with no copy in `themes/deleted/`. Names that fold
## to one file did the same, and a name holding a character Windows refuses
## failed the save. Each case is driven as the Colour Themes page drives it,
## through `SaTheme.fork` and `SaTheme.set_color`.
extends "res://tests/test_framework.gd"

const FIRST := Color(0.9, 0.1, 0.2, 1.0)
const SECOND := Color(0.1, 0.8, 0.3, 1.0)
const KEY := "accent_primary"

var _saved_theme: String = "default"
var _before: Array[String] = []


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _before = SaTheme.custom_ids()
    SaTheme.use_named("default")


## The files this suite wrote are removed outright rather than deleted, so the
## deleted folder holds nothing a run of the suites made.
func after_each() -> void:
    for id: String in SaTheme.custom_ids():
        if not _before.has(id):
            DirAccess.remove_absolute(SaTheme.custom_path(id))
    SaTheme.use_named(_saved_theme)


func _read(id: String) -> SaPalette:
    return ResourceLoader.load(SaTheme.custom_path(id), "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette


func _names() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in SaTheme.available():
        out.append(String(entry["name"]))
    return out


## The page's own path: the first swatch edit on a shipped palette forks it
## under "<name> (custom)".
func _fork_and_set(color: Color) -> String:
    SaTheme.use_named("default")
    var id := SaTheme.fork(SaTheme.palette.display_name + SaTheme.CUSTOM_SUFFIX)
    assert_true(SaTheme.set_color(KEY, color), "The swatch is set on the fork")
    return id


func test_a_second_fork_of_the_same_shipped_palette_leaves_the_first_alone() -> void:
    var first := _fork_and_set(FIRST)
    var second := _fork_and_set(SECOND)

    assert_true(first != second, "The second fork has an id of its own, %s beside %s" % [second, first])
    var ids := SaTheme.custom_ids()
    assert_true(ids.has(first) and ids.has(second), "and both files are in the settings folder")
    var kept := _read(first)
    assert_not_null(kept, "The first palette's file still reads")
    assert_true(kept.get(KEY).is_equal_approx(FIRST), "and still holds the swatch it was given")
    assert_true(_read(second).get(KEY).is_equal_approx(SECOND), "while the second holds its own")
    assert_true(kept.display_name != _read(second).display_name, "and the dropdown tells the two apart")


func test_two_names_that_fold_to_one_file_make_two_palettes() -> void:
    var slash := SaTheme.fork("Ink/Night")
    var space := SaTheme.fork("ink night")

    assert_true(slash != space, "Two ids, %s and %s" % [slash, space])
    assert_true(FileAccess.file_exists(SaTheme.custom_path(slash)), "the first file is there")
    assert_true(FileAccess.file_exists(SaTheme.custom_path(space)), "and so is the second")
    var names := _names()
    assert_true(names.has("Ink/Night"), "The dropdown offers 'Ink/Night'")
    assert_true(names.has(SaTheme.palette.display_name), "and '%s' beside it" % SaTheme.palette.display_name)


func test_a_name_windows_refuses_still_writes_a_palette() -> void:
    var refused := 'Mist ? * " < > | Dawn'
    var id := SaTheme.fork(refused)

    assert_eq(SaTheme.palette_id, id, "The fork is the palette in hand, not the one before it")
    for character: String in ["?", "*", '"', "<", ">", "|"]:
        assert_false(id.contains(character), "The file name holds no %s" % character)
    assert_true(FileAccess.file_exists(SaTheme.custom_path(id)), "A file is written")
    assert_not_null(_read(id), "which loads back as a palette")
    assert_true(_names().has(refused), "and is on offer under the name as typed")


func test_a_name_that_leaves_nothing_still_gets_a_file_of_its_own() -> void:
    var first := SaTheme.fork("???")
    SaTheme.use_named("default")
    var second := SaTheme.fork("***")

    assert_true(first != second, "Two names of refused characters alone make two files, %s and %s" % [first, second])
    assert_true(FileAccess.file_exists(SaTheme.custom_path(first)), "the first is there")
    assert_true(FileAccess.file_exists(SaTheme.custom_path(second)), "and so is the second")


func test_save_as_under_the_name_in_hand_still_writes_its_own_file() -> void:
    var first := _fork_and_set(FIRST)
    var name := SaTheme.palette.display_name
    var before := SaTheme.custom_ids().size()
    SaTheme.set_color(KEY, SECOND)

    var again := SaTheme.fork(name)
    assert_eq(again, first, "Save As under the palette's own name writes its own file")
    assert_eq(SaTheme.custom_ids().size(), before, "and adds no second entry")
    assert_true(_read(first).get(KEY).is_equal_approx(SECOND), "carrying what was on screen")
