## The docker layout file is keyed by docker id, and a file keyed by title
## still restores every docker.
##
## The section was once the title the docker shows, so a translated or
## renamed title orphaned every saved layout. The key is now the
## registry id, with a rename-on-load for the files already out there. This
## pins both halves: an old file restores each docker to where it was, and the
## file is rewritten under the ids so the next load needs no migration.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_docker_layout_keys.cfg")

## Title -> id, as the four built-in dockers were registered. The toolbox has
## since become "Toolbox", and its old section is still adopted.
const LEGACY := {
    "ToolBox": "ToolBoxDocker",
    "Layers": "LayersDocker",
    "Colour Picker": "ColorDocker",
    "Info": "InfoDocker",
}


func after_each() -> void:
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(scratch_path)


func _make_main() -> Node:
    var main: Variant = load("res://ui/main/main.gd").new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_path
    var dummy_canvas := Control.new()
    dummy_canvas.name = "MainCanvas"
    main.add_child(dummy_canvas)
    main._ensure_children_initialized()
    return main


func _legacy_position(title: String) -> Vector2i:
    return Vector2i(120 + 40 * LEGACY.keys().find(title), 200)


func test_a_provider_without_an_id_is_keyed_by_its_name() -> void:
    assert_eq(DockerLayoutStore.section_for({"name": "Probe"}), "Probe", "No id, so the name is the section")
    assert_eq(DockerLayoutStore.section_for({"id": "ProbeDocker", "name": "Probe"}), "ProbeDocker", "With an id, the id")


func test_a_file_keyed_by_title_restores_every_docker_and_is_rewritten() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("_layout_meta_", "os_scale", 1.0)
    for title: String in LEGACY:
        cfg.set_value(title, "position", _legacy_position(title))
        cfg.set_value(title, "size", Vector2i(240, 240))
        cfg.set_value(title, "visible", true)
    cfg.save(scratch_path)

    var main := _make_main()
    main.dockers.load_docker_layout()

    var scale_factor: float = SaUI.scale()
    var by_id := {
        "ToolBoxDocker": main.toolbox_docker,
        "LayersDocker": main.layers_docker,
        "ColorDocker": main.color_docker,
        "InfoDocker": main.info_docker,
    }
    for title: String in LEGACY:
        var win: Window = by_id[LEGACY[title]]
        assert_true(win.visible, "%s is restored as visible from the old section" % title)
        assert_eq(
            win.position, Vector2i(Vector2(_legacy_position(title)) * scale_factor), "%s sits where the old file put it" % title
        )

    var after := ConfigFile.new()
    assert_eq(after.load(scratch_path), OK, "The file is still readable")
    for title: String in LEGACY:
        assert_false(after.has_section(title), "The %s section was moved" % title)
        assert_true(after.has_section(LEGACY[title]), "onto %s" % LEGACY[title])
        assert_eq(after.get_value(LEGACY[title], "position", Vector2i()), _legacy_position(title), "with its geometry intact")

    # A second load finds nothing to move and leaves the file alone.
    var stamp := FileAccess.get_modified_time(scratch_path)
    main.dockers.load_docker_layout()
    assert_eq(FileAccess.get_modified_time(scratch_path), stamp, "The migration ran once")
    main.free()


func test_a_saved_layout_is_keyed_by_id() -> void:
    var main := _make_main()
    main.dockers.load_docker_layout()
    main.dockers.layout_store.save()

    var cfg := ConfigFile.new()
    assert_eq(cfg.load(scratch_path), OK, "The layout was written")
    for title: String in LEGACY:
        assert_true(cfg.has_section(LEGACY[title]), "%s has a section" % LEGACY[title])
        assert_false(cfg.has_section(title), "and the title %s is not one" % title)
    main.free()
