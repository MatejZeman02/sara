extends "res://tests/test_framework.gd"
## A fresh profile's Brush Presets shows small thumbnails, and the Default and
## Useful layouts give the docker the height of at least three rows of them.

const LAYOUTS := ["res://layouts/default.cfg", "res://layouts/useful.cfg", "res://docker_layout_default.cfg"]
const MIN_HEIGHT := 480


func test_the_default_thumbnail_is_small() -> void:
    var factory := SaSettingsValues.new()
    var icon := factory.preset_icon_size
    factory.free()
    assert_true(icon <= 64, "The default thumbnail is %d, at most 64" % icon)


func test_the_shipped_layouts_give_the_docker_three_rows() -> void:
    for path: String in LAYOUTS:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s loads" % path)
        var size: Vector2i = cfg.get_value("BrushPresetsDocker", "size", Vector2i.ZERO)
        assert_true(size.y >= MIN_HEIGHT, "%s gives Brush Presets %d tall, at least %d" % [path, size.y, MIN_HEIGHT])
