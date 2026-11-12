## A step that names a control takes the docker's copy of it.
##
## The top bar builds its own copy of every tool option it shows, from the same
## `SaOptionSpec` list and through the same `ToolOptionControls` the Tool Options
## docker builds from, so `StabilizerModeOpt`, `RadiusSlider` and the layers
## docker's `BlendModeOpt` each answer at two or three paths and a popup opened
## from one of them carries that copy's row names again. A step that takes the first
## in tree order takes the top bar's, which drives a control nobody wrote the
## scenario against.
##
## Over detached nodes, for the reason `test_focus_follows_the_pointer.gd`
## gives: a `Window` added to the tree maps a real OS window and hangs the
## runner. `SaCaptureRun` holds no node, so a lookup over one needs no tree.
extends "res://tests/test_framework.gd"

const RUN := preload("res://harness/sa_capture_run.gd")

## The tree every test builds, freed whole afterwards rather than in each test,
## so a suite that stops at a failed assertion leaks nothing.
var _root: Node = null


func after_each() -> void:
    if _root != null:
        _root.free()
        _root = null


## A node named *name* under *parent*, which is what a lookup walks for.
func _named(parent: Node, name: String) -> Control:
    var control := Control.new()
    control.name = name
    parent.add_child(control)
    return control


## A docker holding a control of its own, added under *parent*.
func _docker_holding(parent: Node, docker_name: String, name: String) -> Control:
    var docker := DockerWindow.new()
    docker.name = docker_name
    parent.add_child(docker)
    return _named(docker, name)


## The two surfaces: the top bar's copy of a tool option and the Tool
## Options docker's, the bar's first in tree order the way it is in the app.
func _two_copies(name: String) -> Dictionary:
    _root = Node.new()
    _root.name = "MainRoot"
    var bar := Node.new()
    bar.name = "CustomTitleBar"
    _root.add_child(bar)
    var docker := DockerWindow.new()
    docker.name = "ToolOptionsDocker"
    _root.add_child(docker)
    return {"bar": bar, "top_bar": _named(bar, name), "docker": _named(docker, name)}


func test_the_dockers_copy_is_the_one_a_name_finds() -> void:
    var made := _two_copies("StabilizerModeOpt")
    var found: Array[Node] = RUN.new().nodes_named(_root, "StabilizerModeOpt")

    assert_eq(found.size(), 2, "Both surfaces answer to the name")
    assert_eq(found[0], made["docker"], "and the docker's copy is the one a step tries first")
    assert_eq(found[1], made["top_bar"], "with the top bar's behind it")


func test_a_step_that_means_the_top_bar_says_so() -> void:
    var made := _two_copies("StabilizerModeOpt")
    var found: Array[Node] = RUN.new().nodes_named(_root, "StabilizerModeOpt", "CustomTitleBar")

    assert_eq(found.size(), 1, "Narrowed to one subtree, the name answers once")
    assert_eq(found[0], made["top_bar"], "and it is the copy inside it")


func test_a_name_only_one_surface_has_is_still_the_one_found() -> void:
    var made := _two_copies("StabilizerModeOpt")
    _named(made["bar"], "KeepBlendChk")
    var found: Array[Node] = RUN.new().nodes_named(_root, "KeepBlendChk")

    assert_eq(found.size(), 1, "A name one node answers to is not ambiguous")
    assert_eq(found[0].name, "KeepBlendChk", "and it is that node")


func test_a_name_nothing_answers_to_finds_nothing() -> void:
    _two_copies("StabilizerModeOpt")

    assert_eq(RUN.new().nodes_named(_root, "NoSuchControl").size(), 0, "A name nothing answers to finds nothing")


func test_the_first_docker_in_tree_order_is_the_first_copy() -> void:
    _root = Node.new()
    _root.name = "MainRoot"
    var near := _docker_holding(_root, "ToolOptionsDocker", "BlendModeOpt")
    var far := _docker_holding(_root, "LayersDocker", "BlendModeOpt")
    var found: Array[Node] = RUN.new().nodes_named(_root, "BlendModeOpt")

    assert_eq(found.size(), 2, "Two dockers answer to it")
    assert_eq(found[0], near, "and among docker copies the first in tree order wins")
    assert_eq(found[1], far, "which is every answer the tree gave before the top bar had a copy")
