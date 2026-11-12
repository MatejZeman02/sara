## The Keyboard Shortcuts page lists the brush slots in number order and each
## docker's summon beside its locked twin.
##
## The Brush section must not read as slot 1, 10, 2 and on, sorted as
## text, and the Dockers section with every locked summon in one block between
## the Layers summon and the Minimap's. `SaShortcutRows._by_importance` compares
## what `ORDER` does not name, and it compared the plain text of the ids. The
## suite reads the order through `actions_for`, which is what the page draws its
## rows from, over the app's own commands rather than ids written here, so a
## slot or a docker added later is held to the same rule.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The registries the app's commands were registered into, held so the actions
## they made are the app's for the length of the suite.
var _registries: SaRegistries = null


func before_each() -> void:
    if _registries == null:
        _registries = Fixtures.make_menu_registries()


# ---------------------------------------------------------------------------
# The brush slots
# ---------------------------------------------------------------------------


func test_the_slot_rows_run_in_number_order() -> void:
    var slots: Array[StringName] = []
    for action: StringName in SaShortcutRows.actions_for("brush_"):
        if String(action).begins_with("brush_slot_"):
            slots.append(action)

    var wanted: Array[StringName] = []
    for slot in range(1, SaBrushSlotCommands.COUNT + 1):
        wanted.append(SaBrushSlotCommands.command_id(slot))
    assert_eq(slots.size(), SaBrushSlotCommands.COUNT, "Every slot has a row on the page")
    assert_eq(slots, wanted, "and they read 1, 2, 3 up to 10, not 1, 10, 2")


func test_the_slots_still_follow_the_rows_order_names() -> void:
    var actions := SaShortcutRows.actions_for("brush_")
    var first_slot := actions.find(SaBrushSlotCommands.command_id(1))
    var named_last := -1
    for action: StringName in actions:
        if SaShortcutRows.ORDER.has(action):
            named_last = maxi(named_last, actions.find(action))

    assert_true(first_slot >= 0, "The first slot is listed")
    assert_true(named_last < first_slot, "and the rows ORDER names still lead the section, the slots after them")


# ---------------------------------------------------------------------------
# The summons
# ---------------------------------------------------------------------------


func test_each_locked_summon_sits_right_after_its_summon() -> void:
    var actions := SaShortcutRows.actions_for("docker_")
    var pairs := 0
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        var summon := SaAppCommands.summon_id(entry[0])
        var locked := SaAppCommands.locked_summon_id(entry[0])
        var at := actions.find(summon)
        assert_true(at >= 0, "%s is listed" % summon)
        assert_eq(actions.find(locked), at + 1, "and %s is the row under it" % locked)
        pairs += 1
    assert_true(pairs >= 10, "Every docker with a summon was read, %d of them" % pairs)


func test_a_word_boundary_sorts_before_a_longer_word() -> void:
    var actions := SaShortcutRows.actions_for("docker_")
    var tool_options := actions.find(SaAppCommands.summon_id(&"docker_tool_options"))
    var toolbox := actions.find(SaAppCommands.summon_id(&"docker_toolbox"))

    assert_true(tool_options >= 0 and toolbox >= 0, "Both summons are listed")
    assert_true(tool_options < toolbox, "Tool Options before Toolbox, as the titles read, where an underscore sorted after the b")
