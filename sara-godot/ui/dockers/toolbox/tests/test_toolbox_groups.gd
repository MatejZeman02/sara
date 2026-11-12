## The toolbox's groups are the painter's: a tool dragged out of one flyout
## lands in another or between two, the order is saved in the layout, and a
## fresh preset shows the registry's groups again.
##
## A group with multiple options inside should be reorderable, preferably by
## dragging a tool out by mouse and dropping it into another or in between. The gesture itself is the
## scenario's to show. What is graded here is the arithmetic under it, the
## docker's one door every drop goes through, and the two stores it writes.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _order: Array = []
var _groups_raw: Variant = null


func before_each() -> void:
    _order = SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    _groups_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)


## The profile is the run's own, and a move writes it, so every test puts the
## order and the groups back where it found them.
func after_each() -> void:
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, _groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


func _groups_of(docker: ToolBoxDocker) -> Array:
    return docker.toolbox_report()["groups"]


## The arithmetic of a move, on lists alone.
func test_moved_puts_a_tool_between_two_others_and_drops_an_emptied_group() -> void:
    var groups := [["brush", "eraser"], ["marquee", "lasso", "wand"], ["eyedropper"]]

    var between := SaToolBoxGroups.moved(groups, "lasso", 0, 1, false)
    assert_eq(
        between,
        [["brush", "lasso", "eraser"], ["marquee", "wand"], ["eyedropper"]],
        "the lasso lands between the brush and the eraser"
    )
    assert_eq(groups[1], ["marquee", "lasso", "wand"], "and the list handed in is not the one changed")

    var alone := SaToolBoxGroups.moved(groups, "lasso", 1, 0, true)
    assert_eq(
        alone, [["brush", "eraser"], ["lasso"], ["marquee", "wand"], ["eyedropper"]], "a new group opens where the index says"
    )

    var emptied := SaToolBoxGroups.moved(groups, "eyedropper", 0, 0, false)
    assert_eq(emptied, [["eyedropper", "brush", "eraser"], ["marquee", "lasso", "wand"]], "a group left empty leaves the list")

    var shifted := SaToolBoxGroups.moved([["a"], ["b", "c"]], "a", 2, 0, true)
    assert_eq(shifted, [["b", "c"], ["a"]], "and an index counted above an emptied group still lands after it")


## Which third of a button means what, and which half of a row.
func test_the_drop_targets_read_the_thirds_and_the_halves() -> void:
    var groups := [["brush", "eraser"], ["marquee", "lasso"]]
    assert_eq(SaToolBoxGroups.button_drop_target(groups, 1, 0.1), [1, 0, true], "the first third opens a group before the button")
    assert_eq(SaToolBoxGroups.button_drop_target(groups, 1, 0.5), [1, 2, false], "the middle joins the group at its end")
    assert_eq(SaToolBoxGroups.button_drop_target(groups, 1, 0.9), [2, 0, true], "and the last third opens one after it")
    assert_eq(SaToolBoxGroups.row_drop_target(groups, 0, "eraser", true), [0, 1, false], "the upper half of a row is before it")
    assert_eq(SaToolBoxGroups.row_drop_target(groups, 0, "eraser", false), [0, 2, false], "the lower half after it")
    assert_eq(
        SaToolBoxGroups.row_drop_target(groups, 0, "nowhere", true), [0, 2, false], "and a row the group does not hold is its end"
    )


## A group is named after its first member's category, and a second group out
## of one category takes a number, so two names never mean one button.
func test_groups_are_named_after_their_first_members_category() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptors := registry.list_descriptors()
    var groups := [["brush", "lasso"], ["marquee"], ["wand"], ["eyedropper"]]
    var names := SaToolBoxGroups.names_for(groups, descriptors)
    assert_eq(names[0], "paint", "the brush's group is paint")
    assert_eq(names[1], "select", "the marquee's is select")
    assert_eq(names[2], "wand", "and the wand's, split from it, is named by the group it names")
    assert_eq(names[3], "sample", "while the eyedropper keeps its own")


## The docker's door: the Done-when's move, read back from the report and from
## the layout order the settings hold. The fills are the group a tool joins,
## the brush and the eraser a button each.
func test_the_lasso_moves_between_the_fill_and_the_gradient() -> void:
    var docker := _toolbox()
    var fill := docker._group_names.find("fill")
    assert_true(fill >= 0, "there is a fill group to start with")
    assert_eq(_groups_of(docker)[fill], ["bucket_fill", "gradient"], "holding the fill and the gradient")

    assert_true(docker.move_tool("lasso", fill, 1, false), "the lasso moves")
    var groups := _groups_of(docker)
    assert_eq(groups[fill], ["bucket_fill", "lasso", "gradient"], "and sits between the fill and the gradient")
    assert_eq(docker.button_for_tool("lasso"), docker.button_for_tool("bucket_fill"), "on the fill's button")
    assert_eq(docker.tools_in_category_of("wand"), ["wand"], "and the wand is still alone")

    var registry := Fixtures.make_tool_registry()
    var order := SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    var fill_at := order.find(SaToolBoxGrid.layout_entry_for(registry.get_descriptor(&"bucket_fill")))
    assert_true(fill_at >= 0, "The layout order names the fill")
    assert_eq(order[fill_at + 1], "Lasso Tool", "and reads the lasso right after it")
    assert_eq(
        order[fill_at + 2], SaToolBoxGrid.layout_entry_for(registry.get_descriptor(&"gradient")), "and the gradient after that"
    )
    assert_eq(order[0], _order[0], "with the entries that are not tools where they stood")
    assert_eq(order.size(), _order.size(), "and nothing added or lost")
    docker.free()


## A fresh preset writes the order without the groups, and then the order wins:
## the registry's groups come back, in the order the preset states.
func test_a_fresh_preset_shows_the_registrys_order() -> void:
    var docker := _toolbox()
    var fill := docker._group_names.find("fill")
    docker.move_tool("lasso", fill, 1, false)
    assert_true(_groups_of(docker)[fill].has("lasso"), "the lasso is with the fills after the move")

    # What `SaDockerLayoutPresets.apply` does for the toolbox: the order alone.
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)
    docker.apply_layout_settings()

    var registry := Fixtures.make_tool_registry()
    var groups := _groups_of(docker)
    for group: Array in SaToolBoxGroups.from_registry(registry.list_tools()):
        assert_true(groups.has(group), "and the registry's group %s is drawn again" % str(group))
    assert_eq(
        docker.tools_in_category_of("lasso"),
        ["lasso", "polygonal_lasso", "magnetic_lasso"],
        "with the lasso back on the button of the lassos"
    )
    docker.free()


## A stored grouping outlives a rebuild while the order agrees, which is what
## makes the drag a setting rather than a session.
func test_a_moved_group_survives_a_rebuild() -> void:
    var docker := _toolbox()
    docker.move_tool("eyedropper", 0, 0, true)
    var groups := _groups_of(docker)
    assert_eq(groups[0], ["eyedropper"], "the eyedropper opens the toolbox on its own")

    var again := _toolbox()
    assert_eq(_groups_of(again), groups, "and a docker built from the same profile draws the same groups")
    assert_eq(again._group_names[0], "sample", "under the name of its category")
    docker.free()
    again.free()


## A tool the profile has never heard of, a module's registered after the
## groups were stored, joins the group holding a tool of its group id, and a
## tool with none opens a button of its own rather than vanishing.
func test_a_tool_missing_from_the_stored_groups_joins_its_group_id() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptors := registry.list_descriptors()
    var without: Array = []
    for group: Array in SaToolBoxGroups.from_registry(descriptors):
        var copy := group.duplicate()
        copy.erase("ellipse_select")
        copy.erase("wand")
        if not copy.is_empty():
            without.append(copy)
    # A move of the eyedropper to the front, so what is stored is a painter's.
    without = SaToolBoxGroups.moved(without, "eyedropper", 0, 0, true)
    SaToolBoxGroups.save(without, descriptors)

    var groups := SaToolBoxGroups.stored(descriptors)
    assert_eq(SaToolBoxGroups.flatten(groups).size(), descriptors.size(), "every registered tool is in a group")
    assert_eq(groups[0], ["eyedropper"], "the painter's grouping is the one read")
    assert_true(groups.has(["marquee", "ellipse_select"]), "the ellipse is with the marquee, which names its group id")
    assert_true(groups.has(["wand"]), "and the wand, which names none, is alone")


## The marquees, the fills and the lassos are the shared groups, otherwise no
## groups. Built from the registered descriptors with no stored layout. The
## object selection of the background-removal module is not in this registry.
func test_the_default_is_three_shared_groups_and_every_other_tool_alone() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptors := registry.list_tools()
    var groups := SaToolBoxGroups.from_registry(descriptors)
    var shared: Array = []
    for group: Array in groups:
        if group.size() > 1:
            shared.append(group)
    assert_eq(
        shared,
        [["bucket_fill", "gradient"], ["marquee", "ellipse_select"], ["lasso", "polygonal_lasso", "magnetic_lasso"]],
        "exactly three shared groups, the fills, the marquees and the lassos"
    )
    assert_eq(SaToolBoxGroups.flatten(groups).size(), descriptors.size(), "every tool is in one group")
    assert_eq(groups.size(), descriptors.size() - 4, "and every other tool is a group of one")
    var names := SaToolBoxGroups.names_for(groups, descriptors)
    assert_true(names.has("fill") and names.has("select"), "named after their group ids, %s" % [names])

    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, null)
    var docker := _toolbox()
    var marked := 0
    for button: Button in docker._buttons.values():
        if (button.get_node("FlyoutMark") as Control).visible:
            marked += 1
    assert_eq(marked, 3, "and the docker draws the corner mark on three buttons")
    docker.free()


## A module's tool that names no group id is a button of its own, whatever its
## category, and one that names a built-in's joins it, through the public door.
func test_a_module_tool_with_no_group_id_is_alone() -> void:
    var descriptors: Array = Fixtures.make_tool_registry().list_tools()
    var stray := Fixtures.make_tool_descriptor(&"u145_stray")
    stray.category = &"select"
    var joiner := Fixtures.make_tool_descriptor(&"u145_joiner")
    joiner.toolbox_group = &"fill"
    descriptors.append(stray)
    descriptors.append(joiner)
    var groups := SaToolBoxGroups.from_registry(descriptors)
    assert_true(groups.has(["u145_stray"]), "the module's tool with no group id is alone")
    assert_true(groups.has(["bucket_fill", "gradient", "u145_joiner"]), "and one naming fill joins the fills")


## A profile holding the old default, one group per category, written back by a
## drag that put everything where it was, is not a painter's grouping: it gets
## the new default, so a painter who never regrouped anything sees it.
func test_a_stored_old_default_gives_way_to_the_new_one() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptors := registry.list_tools()
    SaToolBoxGroups.save(SaToolBoxGroups.by_category(descriptors), descriptors)
    # In the order the stored default draws them, which is the registry's only
    # while no tool registers after a later category's, and the assistants do.
    var sequence := SaToolBoxGroups.order_sequence(descriptors)
    var expected := SaToolBoxGroups.from_registry(descriptors)
    expected.sort_custom(func(a: Array, b: Array) -> bool: return sequence.find(a[0]) < sequence.find(b[0]))
    assert_eq(SaToolBoxGroups.stored(descriptors), expected, "the old category default stored reads as the registry's groups")

    var regrouped := SaToolBoxGroups.moved(SaToolBoxGroups.by_category(descriptors), "lasso", 0, 0, false)
    SaToolBoxGroups.save(regrouped, descriptors)
    assert_eq(SaToolBoxGroups.stored(descriptors), regrouped, "while one with a tool moved stays the painter's")
