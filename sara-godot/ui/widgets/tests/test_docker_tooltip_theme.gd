## A docker's tooltip is drawn in the panel the main window's is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every docker built at boot reaches `_ready` before `Main`'s boot builds the
## shared theme, so the adoption in `_setup_docker_ready` found nothing, and
## with the chain above the docker cut at `MainRoot` a tooltip under it fell
## through to the engine's own panel. The docker now follows the root window's
## `theme_changed` and adopts on it.
##
## Adding a `Window` to the tree hangs a headless suite, which is an engine
## fault, so what is asserted here is the seam: the connection the docker makes, why it has to be deferred, and
## what the tooltip report reads. The picture is
## `scenarios/a-dockers-tooltip-is-drawn-in-a-different-panel-from-the-main-windows.json`.
extends "res://tests/test_framework.gd"

## The docker is a Window and its `_init` builds real controls.
const REQUIRES_GPU := true

var _root_theme: Theme = null
var _kept_theme: Theme = null
var _seen_at_signal: Theme = null


## The root's theme and the shared one are put back afterwards, because both
## objects are process-global and a suite that left a new one behind would be a
## second scale authority for every suite after it.
func before_each() -> void:
    _root_theme = (Engine.get_main_loop() as SceneTree).root.theme
    _kept_theme = SaUI.shared_theme


func after_each() -> void:
    (Engine.get_main_loop() as SceneTree).root.theme = _root_theme
    SaUI.shared_theme = _kept_theme


func _on_root_theme_changed() -> void:
    _seen_at_signal = SaUI.shared_theme


## The Colour Picker, because its foreground swatch is the tooltip under
## test, and the listening is the base class's so any docker would do.
func test_a_docker_follows_the_root_taking_a_theme() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var docker := ColorDocker.new()
    docker.follow_root_theme(root)
    docker.follow_root_theme(root)

    var found := 0
    for connection: Dictionary in root.theme_changed.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_object() != docker:
            continue
        found += 1
        assert_eq(String(callable.get_method()), "_adopt_shared_theme", "and what runs is the adoption")
        assert_true((int(connection["flags"]) & CONNECT_DEFERRED) != 0, "deferred, for the reason the next test measures")
    assert_eq(found, 1, "The docker listens to the root once however often it is readied")

    root.theme_changed.disconnect(Callable(docker, &"_adopt_shared_theme"))
    docker.free()


## Why the connection is deferred. `SaUI.init_global_theme` hands the root its
## theme a dozen lines before it stores the same object as the shared one, so a
## docker adopting there and then would read the theme from before.
func test_the_root_takes_the_theme_before_sa_ui_stores_it() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var before := SaUI.shared_theme
    _seen_at_signal = null
    tree.root.theme_changed.connect(_on_root_theme_changed)
    SaUI.init_global_theme(tree)
    tree.root.theme_changed.disconnect(_on_root_theme_changed)

    assert_true(SaUI.shared_theme != before, "A new shared theme was built")
    assert_eq(tree.root.theme, SaUI.shared_theme, "and the root holds it once the build returns")
    assert_eq(_seen_at_signal, before, "but a listener called as the root takes it still reads the one before")


## The two words the scenario compares, told apart by identity, since the
## shared theme's box and the engine's are both a `StyleBoxFlat`.
func test_the_report_names_the_theme_a_box_came_from() -> void:
    SaUI.init_global_theme(Engine.get_main_loop() as SceneTree)
    var shared := SaUI.shared_theme.get_stylebox(&"panel", &"TooltipPanel")
    var engine := ThemeDB.get_default_theme().get_stylebox(&"panel", &"TooltipPanel")

    assert_eq(SaTooltip.box_source(shared), "shared", "The shared theme's tooltip box is named for it")
    assert_eq(SaTooltip.box_source(engine), "engine", "the engine's own is named for the engine")
    assert_eq(SaTooltip.box_source(StyleBoxFlat.new()), "other", "and a box of the same class from neither is neither")


## Which node the theme is read from, on a panel no theme reaches and on the
## same panel holding the shared theme.
##
## Only the holder and not the box, because a `Window` outside the tree does
## not read its own theme's items, and a panel inside it hangs the suite.
func test_the_report_names_the_node_a_panel_reads_its_theme_from() -> void:
    SaUI.init_global_theme(Engine.get_main_loop() as SceneTree)
    var panel := PopupPanel.new()
    panel.name = "Panel"
    panel.theme_type_variation = &"TooltipPanel"
    var label := Label.new()
    label.theme_type_variation = &"TooltipLabel"
    panel.add_child(label)

    var bare := SaTooltip.look(panel, label)
    assert_true(bare.ends_with("theme from nothing"), "A panel no theme reaches says nothing holds one: %s" % bare)
    panel.theme = SaUI.shared_theme
    var themed := SaTooltip.look(panel, label)
    assert_true(themed.ends_with("theme from Panel (shared)"), "and holding the shared theme names itself: %s" % themed)
    panel.free()
