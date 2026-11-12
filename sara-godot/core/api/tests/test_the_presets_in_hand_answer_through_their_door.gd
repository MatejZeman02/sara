## A module asks the presets in hand through `SaPresetsInHand`, and the group
## that answers it is the one in the tree.
##
## Liquify and the Krita import each walked the tree for a node name and called
## it by a method name, which the structure scan could not see. The door answers nothing until a group attaches, and a
## group that leaves takes only its own answers with it.
extends "res://tests/test_framework.gd"


class Group:
    extends RefCounted
    var loaded: Array[String] = []

    func engine() -> StringName:
        return &"liquify"

    func import_through(importer: Callable) -> Array[Dictionary]:
        var results: Array[Dictionary] = []
        results.assign(importer.call(null, null))
        return results

    func load_by_name(stored_name: String) -> bool:
        loaded.append(stored_name)
        return stored_name == "Kept"


func _attach(group: Group) -> void:
    SaPresetsInHand.attach_group(group.engine, group.import_through, group.load_by_name)


func test_with_no_group_the_door_answers_nothing() -> void:
    assert_false(SaPresetsInHand.has_group(), "No group is attached before one enters the tree")
    assert_eq(SaPresetsInHand.engine(), &"", "and there is no engine in hand")
    assert_false(SaPresetsInHand.load_preset("Kept"), "nothing loads")
    var nothing := func(_s: Variant, _t: Variant) -> Array: return [{}]
    assert_true(SaPresetsInHand.import_through(nothing).is_empty(), "and nothing imports")


func test_an_attached_group_answers_and_a_leaving_one_takes_only_its_own() -> void:
    var group := Group.new()
    _attach(group)
    assert_eq(SaPresetsInHand.engine(), &"liquify", "The engine is the group's")
    assert_true(SaPresetsInHand.load_preset("Kept"), "a load reaches the group")
    assert_false(SaPresetsInHand.load_preset("Gone"), "and its answer comes back")
    assert_eq(group.loaded, ["Kept", "Gone"] as Array[String], "in the order asked")
    var imported := SaPresetsInHand.import_through(func(_s: Variant, _t: Variant) -> Array: return [{"name": "A"}])
    assert_eq(imported.size(), 1, "An import runs inside the group")

    var other := Group.new()
    SaPresetsInHand.detach_group(other)
    assert_true(SaPresetsInHand.has_group(), "A group that is not the attached one detaches nothing")
    SaPresetsInHand.detach_group(group)
    assert_false(SaPresetsInHand.has_group(), "The attached group takes its answers away")
