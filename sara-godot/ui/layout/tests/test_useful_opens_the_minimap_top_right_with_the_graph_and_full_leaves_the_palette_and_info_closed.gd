## Useful puts the Minimap at the top right and opens the Graph, and Full opens
## without the Info and the Pop-up Palette.
##
## Useful is default plus what a painter watches, so its Minimap heads the right
## column as default's does, over the Colour Picker and the Layers with no
## docker lapping another, and the Graph stands open. Full opens every docker
## but the Info and the Pop-up Palette, which a painter opens for a reason, and
## their close order entries go with them because the order names what opens.
extends "res://tests/test_framework.gd"


func _load(path: String) -> ConfigFile:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(path), OK, "%s reads" % path)
    return cfg


func _rect(cfg: ConfigFile, section: String) -> Rect2i:
    return Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))


func _open(cfg: ConfigFile, section: String) -> bool:
    return bool(cfg.get_value(section, "visible", false))


func test_useful_stacks_its_right_column_under_the_minimap() -> void:
    var cfg := _load("res://layouts/useful.cfg")
    var minimap := _rect(cfg, "MinimapDocker")
    var colour := _rect(cfg, "ColorDocker")
    var layers := _rect(cfg, "LayersDocker")
    assert_true(_open(cfg, "MinimapDocker"), "the Minimap is open")
    assert_eq(minimap.position, Vector2i(1600, 79), "at the top of the right column")
    assert_eq(colour.position, Vector2i(1600, minimap.end.y + 10), "the Colour Picker under it")
    assert_eq(layers.position, Vector2i(1600, colour.end.y + 10), "and the Layers under that")
    assert_eq(layers.end.y, 1065, "to the foot the column always had")


func test_useful_opens_the_graph_and_closes_the_minimap_then_the_graph_on_a_small_host() -> void:
    var cfg := _load("res://layouts/useful.cfg")
    assert_true(_open(cfg, "GraphDocker"), "the Graph is open")
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    assert_eq(String(order[0]), "MinimapDocker", "the Minimap closes first")
    assert_eq(String(order[1]), "GraphDocker", "then the Graph")


func test_useful_leaves_no_two_dockers_over_one_another() -> void:
    var cfg := _load("res://layouts/useful.cfg")
    var sections := cfg.get_sections()
    for i in sections.size():
        for j in range(i + 1, sections.size()):
            if not cfg.has_section_key(sections[i], "position") or not cfg.has_section_key(sections[j], "position"):
                continue
            assert_false(
                _rect(cfg, sections[i]).intersects(_rect(cfg, sections[j])), "%s and %s are apart" % [sections[i], sections[j]]
            )


func test_full_opens_without_the_info_and_the_palette() -> void:
    var cfg := _load("res://layouts/full.cfg")
    assert_false(_open(cfg, "InfoDocker"), "the Info ships closed")
    assert_false(_open(cfg, "PaletteDocker"), "and so does the Pop-up Palette")
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    assert_false(order.has("InfoDocker"), "the close order does not name the Info")
    assert_false(order.has("PaletteDocker"), "or the Palette")
    for section: String in ["RecorderDocker", "GraphDocker", "MinimapDocker", "StatsDocker", "HistoryDocker", "UndoDocker"]:
        assert_true(_open(cfg, section), "%s stays open" % section)
