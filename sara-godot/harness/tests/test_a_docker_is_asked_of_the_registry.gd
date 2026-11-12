## The `docker` step finds a docker through the registry it
## registered with, and a name nobody registered is answered with the ids that
## are.
##
## Before, the step found the window with `find_child` on the name it was given,
## so a typo in a scenario printed "no docker called" and the next step aimed at
## whatever the profile had left open. The registry is handed to the driver here
## because a suite has no `Main` to own one, and in the app each step asks the
## tree's.
extends "res://tests/test_framework.gd"

const CaptureRun := preload("res://harness/sa_capture_run.gd")
const DockerDriver := preload("res://harness/drivers/sa_docker_driver.gd")

## A module's docker, whose id is its own and in no constant of the skeleton.
const MODULE_DOCKER := &"kaleidoscope.mirrors"


func _registry() -> SaUIRegistry:
    var registry := SaUIRegistry.new()
    var factory := func() -> Window: return Window.new()
    registry.register_docker(SaDockerIds.LAYERS, "Layers", factory)
    registry.register_docker(MODULE_DOCKER, "Mirrors", factory, &"", &"kaleidoscope")
    return registry


func test_an_unregistered_docker_is_answered_with_the_registered_ids() -> void:
    var driver := DockerDriver.new(CaptureRun.new(), _registry())
    var answer := driver.docker("LayresDocker")
    assert_true(
        answer.contains("no docker registered as 'LayresDocker'"), "the step says the name is not registered: %s" % answer
    )
    assert_true(answer.contains(String(SaDockerIds.LAYERS)), "and lists the built-in that is: %s" % answer)
    assert_true(answer.contains(String(MODULE_DOCKER)), "and the module's: %s" % answer)


func test_a_registered_docker_without_a_window_says_so() -> void:
    var driver := DockerDriver.new(CaptureRun.new(), _registry())
    var answer := driver.docker({"id": String(SaDockerIds.LAYERS)})
    assert_true(
        answer.contains("no window yet for docker"), "a registered docker nothing built is not called unknown: %s" % answer
    )


## The window is found through the registry by the module's id, whatever the
## Window happens to be called in the tree.
func test_a_modules_docker_is_found_by_its_own_id() -> void:
    var registry := _registry()
    var window := Window.new()
    window.name = "SomethingElse"
    window.visible = false
    registry.set_docker_node(MODULE_DOCKER, window)
    var driver := DockerDriver.new(CaptureRun.new(), registry)
    var answer := driver.docker({"id": String(MODULE_DOCKER), "at": [120, 80]})
    assert_true(answer.contains("docker %s shown at" % MODULE_DOCKER), "the step shows it: %s" % answer)
    assert_eq(window.position, Vector2i(120, 80), "where the step put it")
    assert_eq(CaptureRun.DockerLookup.window_in(registry, MODULE_DOCKER), window, "the lookup answers the registered Window")
    assert_null(CaptureRun.DockerLookup.window_in(registry, &"SomethingElse"), "and not by the node's name")
    window.free()


func test_no_registry_is_a_refusal_rather_than_a_crash() -> void:
    assert_true(
        CaptureRun.DockerLookup.refusal(null, SaDockerIds.LAYERS).begins_with("no docker registry"), "a host with no Main says so"
    )
    assert_eq(CaptureRun.DockerLookup.refusal(_registry(), SaDockerIds.LAYERS), "", "a registered id is no refusal")
