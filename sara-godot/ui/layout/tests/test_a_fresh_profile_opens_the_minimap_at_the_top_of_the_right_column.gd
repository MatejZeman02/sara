## A fresh profile opens the Minimap at the top of the right column.
##
## A painter looks for the minimap above the colour wheel and the layers, so the
## default opens it there, and the three dockers share the column from the bar
## to the foot with the same gap between each pair, so they read as docked and
## not as windows hanging free. It heads the close order, so a host short of
## room loses it before anything else, and the docker under it then rises to
## the top of the column instead of hanging from a hole.
extends "res://tests/test_framework.gd"

## The first row below a two-row bar.
const TOP := 79

## The gap the default keeps between two dockers of a column.
const GAP := 0

## The floors the fit is handed, the suite's own read off a running app.
const FLOORS := {
    "MinimapDocker": Vector2i(168, 132),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
}

const FILES: Array[String] = [DockerLayoutStore.SHIPPED_DEFAULTS, "res://layouts/default.cfg"]


func _rect(cfg: ConfigFile, section: String) -> Rect2i:
    return Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))


func test_both_files_open_the_minimap_above_the_colour_picker_and_the_layers() -> void:
    for path: String in FILES:
        var cfg := ConfigFile.new()
        assert_eq(cfg.load(path), OK, "%s reads" % path)
        assert_true(bool(cfg.get_value("MinimapDocker", "visible", false)), "the Minimap opens in %s" % path)
        var minimap := _rect(cfg, "MinimapDocker")
        var colour := _rect(cfg, "ColorDocker")
        var layers := _rect(cfg, "LayersDocker")
        assert_eq(minimap.position, Vector2i(1600, TOP), "at the top of the right column in %s" % path)
        assert_eq(colour.position.x, minimap.position.x, "the Colour Picker in its column in %s" % path)
        assert_eq(layers.position.x, minimap.position.x, "and the Layers in %s" % path)
        assert_eq(colour.position.y, minimap.end.y + GAP, "the Colour Picker under the Minimap in %s" % path)
        assert_eq(layers.position.y, colour.end.y + GAP, "and the Layers under that in %s" % path)
        assert_eq(minimap.size.x, colour.size.x, "one width down the column in %s" % path)
        assert_eq(layers.end.y, 1065, "the column runs to the foot the Layers always had in %s" % path)


func test_the_minimap_closes_first_and_the_column_closes_up() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    assert_eq(String(order[0]), "MinimapDocker", "the Minimap heads the close order")
    var dockers: Dictionary = {}
    for section: String in FLOORS:
        dockers[section] = {"rect": _rect(cfg, section), "min": FLOORS[section]}
    var written_for := Vector2i(1920, 1080)
    var roomy := SaDockerLayoutFit.new(written_for, TOP, written_for, order).place(dockers)
    assert_eq(roomy["MinimapDocker"], _rect(cfg, "MinimapDocker"), "on the host the file was written for it is the file's")
    # 212 and 212 and the gap, short of the 132 the Minimap also asks.
    var short := SaDockerLayoutFit.new(Vector2i(1920, 600), TOP, written_for, order).place(dockers)
    assert_false(short.has("MinimapDocker"), "a host with no room for the column closes the Minimap")
    assert_eq(short["ColorDocker"].position.y, TOP, "and the Colour Picker rises to the top of the column")
    assert_eq(short["LayersDocker"].position.y, short["ColorDocker"].end.y + GAP, "with the Layers still under it")
