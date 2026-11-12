## Every built-in docker is registered under a constant of
## `SaDockerIds`, and every constant there names a docker the list registers.
##
## The harness and `ui` name a built-in by the constant so a rename is a parse
## error. That only holds while the constants and the registration list are one
## list, which is what this pins: a docker added to `register_builtin_dockers`
## without a constant, or a constant left behind by a docker taken out, fails
## here rather than in a scenario that quietly found nothing.
extends "res://tests/test_framework.gd"

const DockerIds := preload("res://ui/main/sa_docker_ids.gd")


## The ids the built-in list registers into a registry of its own, in order.
func _registered_ids() -> Array[StringName]:
    var registry := SaUIRegistry.new()
    var dockers := MainDockers.new(registry)
    dockers.register_builtin_dockers()
    var ids: Array[StringName] = []
    for entry: Dictionary in registry.list_dockers():
        var docker_id: StringName = entry["id"]
        ids.append(docker_id)
    dockers.free()
    return ids


func test_every_registered_built_in_has_a_constant() -> void:
    var ids := _registered_ids()
    assert_eq(ids.size(), DockerIds.ALL.size(), "the list registers as many dockers as there are constants: %s" % [ids])
    for docker_id in ids:
        assert_true(DockerIds.ALL.has(docker_id), "'%s' is registered and has no constant in SaDockerIds" % docker_id)


func test_every_constant_is_registered() -> void:
    var ids := _registered_ids()
    for docker_id in DockerIds.ALL:
        assert_true(ids.has(docker_id), "SaDockerIds names '%s' and the built-in list does not register it" % docker_id)
    assert_eq(ids, DockerIds.ALL, "and in the order they register in")


## A constant written and never put in `ALL` would pass the two above, so every
## id constant of the class is read off the script.
func test_every_id_constant_is_in_the_list() -> void:
    var constants := (DockerIds as Script).get_script_constant_map()
    var named := 0
    for key: String in constants:
        var value: Variant = constants[key]
        if value is StringName:
            named += 1
            assert_true(DockerIds.ALL.has(value), "SaDockerIds.%s is not in ALL" % key)
    assert_eq(named, DockerIds.ALL.size(), "one constant per built-in, none spare")
