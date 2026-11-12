extends "res://tests/test_framework.gd"


## Overridden to pin the order: these tests share a settings file and a
## layout file, so they are not independent of each other.
func run_all_tests(suite_name: String) -> bool:
    var started := Time.get_ticks_msec()
    test_docker_layout_scaling_and_visibility()
    duration_ms = Time.get_ticks_msec() - started
    _print_suite_line(suite_name)
    return failed_count == 0


func test_docker_layout_scaling_and_visibility() -> void:
    if FileAccess.file_exists(SaDataRoot.path("docker_layout.cfg")):
        DirAccess.remove_absolute(SaDataRoot.path("docker_layout.cfg"))

    # Step 1: Mock a configuration file that simulates being saved natively at 1x scale
    var cfg := ConfigFile.new()
    cfg.set_value("_layout_meta_", "os_scale", 1.0)
    cfg.set_value("Info", "position", Vector2i(100, 150))
    cfg.set_value("Info", "size", Vector2i(200, 200))
    cfg.set_value("Info", "visible", true)
    cfg.save(SaDataRoot.path("test_docker_layout.cfg"))

    var main: Variant = load("res://ui/main/main.gd").new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = SaDataRoot.path("test_docker_layout.cfg")

    # Inject dummy MainCanvas to prevent GPU initialization crash in headless test environment
    var dummy_canvas: Control = Control.new()
    dummy_canvas.name = "MainCanvas"
    main.add_child(dummy_canvas)

    # Initialize dockers but bypass the rest of _ready() which requires Vulkan and ModuleLoader
    main._ensure_children_initialized()
    main.dockers.load_docker_layout()

    # Step 2: Try to load it. Info docker should be visible and scaled.
    assert_true(main.info_docker.visible, "Info docker should be loaded as visible")

    # Coordinates are stored normalised to 1x, so loading multiplies them back by
    # the app's effective scale. That is SaUI.scale(), not the raw OS scale: the
    # user's UI Scale preference also moves the physical geometry.
    var scale_factor: float = SaUI.scale()
    var expected_pos: Vector2i = Vector2i(Vector2(100, 150) * scale_factor)

    # We must ensure the expected rect intersects usable_rect before asserting position override.
    var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
    if usable_rect.size.x <= 0 or usable_rect.size.y <= 0 or usable_rect.intersects(Rect2i(expected_pos, Vector2i(400, 400))):
        assert_eq(main.info_docker.position, expected_pos, "Info docker position should be multiplied by the app scale")

    # Step 3: Edit the position a little
    var edited_pos: Vector2i = main.info_docker.position + Vector2i(50, 50)
    main.info_docker.position = edited_pos

    # Step 4: Save it
    main.dockers.layout_store.save()

    # Step 5: Check if correct values are stored normalized to 1x scale
    var cfg2: ConfigFile = ConfigFile.new()
    assert_eq(cfg2.load(SaDataRoot.path("test_docker_layout.cfg")), OK, "Should be able to load saved layout")

    # The file was written under the docker's title and comes back under its
    # id: reading the old section once and saving the new one is the migration.
    assert_false(cfg2.has_section("Info"), "The title-keyed section is gone after the first load")
    var saved_pos: Vector2i = cfg2.get_value("InfoDocker", "position", Vector2i())
    var expected_normalized_pos: Vector2i = Vector2i(Vector2(edited_pos) / scale_factor)
    assert_eq(saved_pos, expected_normalized_pos, "Saved position should match the newly edited position normalized to 1x scale")

    var saved_scale: float = cfg2.get_value("_layout_meta_", "app_scale", 0.0)
    assert_eq(saved_scale, scale_factor, "Saved layout should record the app scale it was normalised by")

    # Step 6: Verify toggling visibility multiple times does not shrink or move the docker towards (0, 0)
    var initial_toggle_pos: Vector2i = main.info_docker.position
    var initial_toggle_size: Vector2i = main.info_docker.size
    for i in range(3):
        main.dockers.toggle_docker(2)  # Toggle InfoDocker off/on
    assert_eq(main.info_docker.position, initial_toggle_pos, "Docker position must remain constant across visibility toggles")
    assert_eq(main.info_docker.size, initial_toggle_size, "Docker size must remain constant across visibility toggles")
    # Cleanup
    if FileAccess.file_exists(SaDataRoot.path("test_docker_layout.cfg")):
        DirAccess.remove_absolute(SaDataRoot.path("test_docker_layout.cfg"))
    main.free()
