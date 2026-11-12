## The Brush Presets docker reads at factory settings.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Four faults a new painter meets in the first docker they read: 5 of 21
## tiles shown, every name split inside a word ("Airbr / ush"), the muted engine
## line cut off, and 48 by 24 thumbnails nobody can tell apart. This builds the
## docker at the size the shipped layout gives it, the chooser at the icon size
## a fresh profile has, and every shipped preset in it, and asks each fault in
## turn.
##
## The suite has no frames to wait, since an `await` drops every assertion after
## it, so the containers are sorted by hand from the top down, which is
## the same pass the engine runs a frame later. No tile carries an engine line
## any more, the brush editor names the engine at its top, so the grid is built
## as a fresh profile under the Brush sees it.
##
## The shots are `scenarios/the-brush-presets-docker-reads-at-factory-settings.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The thumbnails are real strokes through the paint path.
const REQUIRES_GPU := true

## Where the section of the shipped layout this reads is.
const SECTION := "BrushPresetsDocker"

static var scratch_dir: String = SaDataRoot.path("test_u1_presets_factory")

var _saved_icon_size: int = 72
var _saved_tip: bool = false
var _embedded: bool = false
var _host: Node = null


func before_each() -> void:
    _saved_icon_size = SaSettings.preset_icon_size
    _saved_tip = SaSettings.preset_thumb_tip
    var factory := SaSettingsValues.new()
    SaSettings.preset_icon_size = factory.preset_icon_size
    SaSettings.preset_thumb_tip = factory.preset_thumb_tip
    factory.free()
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_icon_size = _saved_icon_size
    SaSettings.preset_thumb_tip = _saved_tip
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null
    ScratchFolder.clear(scratch_dir)


## The size the shipped layout opens the docker at, which is what a fresh
## profile on the host the file was written for sees.
func _shipped_size() -> Vector2i:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped layout reads")
    return cfg.get_value(SECTION, "size", Vector2i())


## The docker at its shipped size with every shipped preset bound, laid out.
func _docker() -> BrushPresetsDocker:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "PresetsFactoryHost"
    EventBus.add_child(_host)
    var docker := DockerScript.new() as BrushPresetsDocker
    _host.add_child(docker)
    # Shown, because a container in a hidden window sorts nothing, which is also
    # why the grid a boot builds is counted again on the docker's first show.
    docker.show()
    var shipped := _shipped_size()
    docker.size = shipped

    # The body text, which the boot's shared theme gives every control. A
    # suite's root may have none, and the engine's own 16 point font is not the
    # text the ask is about. Held on this docker alone, so no other suite meets it.
    var body := Theme.new()
    body.default_font = SaFonts.regular()
    body.default_font_size = SaUI.get_font_size()
    var top := docker._control_node
    top.theme = SaUI.shared_theme if SaUI.shared_theme != null else body
    top.size = Vector2(shipped)
    var column := top.get_node("VBoxContainer") as Control
    column.size = Vector2(shipped)

    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    docker.chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())

    _sort(column)
    docker.chooser._recount_columns()
    _sort(column)
    return docker


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## Where *control*'s rectangle sits inside the docker's own content.
func _in_docker(control: Control, docker: BrushPresetsDocker) -> Rect2:
    return Rect2(control.global_position - docker._control_node.global_position, control.size)


func test_a_fresh_profile_draws_a_picture_that_reads() -> void:
    var factory := SaSettingsValues.new()
    var icon := factory.preset_icon_size
    factory.free()
    assert_true(icon >= SaBrushPresetsChooser.MIN_ICON and icon <= 64, "A fresh profile opens the chooser at %d, 30 to 64" % icon)


func test_every_shipped_name_breaks_between_words_only() -> void:
    var docker := _docker()
    var chooser := docker.chooser
    assert_eq(chooser.visible_names().size(), ShippedPresetsScript.entries().size(), "Every shipped preset is in the grid")
    var font := chooser.get_theme_font("font", "Label")
    var font_size := chooser.get_theme_font_size("font_size", "Label")
    assert_eq(font_size, SaUI.get_font_size(), "The names are drawn at the body text")
    for cell: Node in chooser.grid.get_children():
        var label := cell.get_node("Name") as Label
        assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD, "'%s' wraps at word boundaries only" % label.text)
        var words := label.text.split(" ", false)
        assert_true(words.size() <= SaBrushPresetsChooser.NAME_LINES, "'%s' has a line for every word" % label.text)
        for word: String in words:
            var wide := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
            assert_true(
                wide <= label.size.x,
                "'%s' of '%s' is %.1f wide in a name %.1f wide, so it is never broken" % [word, label.text, wide, label.size.x]
            )


## The shipped height is taller than the two rows the strokes were cut for,
## so they fit with room to spare.
func test_two_full_rows_of_strokes_fit_the_shipped_docker() -> void:
    SaSettings.preset_thumb_tip = false
    _assert_whole_rows(2, false)


## And a tip is square, so it is half again as tall as a stroke and one row of
## it is what the shipped height holds. That row is the one the docker's own
## minimum is cut to keep whole, so a fresh profile opens on a full row and
## scrolls to the next rather than on a band of cut-off pictures.
func test_three_whole_rows_of_tips_fit_the_shipped_docker() -> void:
    SaSettings.preset_thumb_tip = true
    _assert_whole_rows(3)


## *rows* rows of cells end inside the shipped height and the row after them
## does not, so the number is the height's and not a floor anyone may raise by
## accident.
func _assert_whole_rows(rows: int, exact: bool = true) -> void:
    var docker := _docker()
    var chooser := docker.chooser
    var columns := chooser.grid.columns
    assert_true(columns >= 2, "The shipped width holds %d columns" % columns)
    var cells := chooser.grid.get_children()
    assert_true(cells.size() > (rows + 1) * columns, "and there are more presets than %d rows of it" % (rows + 1))
    var height := float(_shipped_size().y)
    var last_row := _in_docker(cells[rows * columns - 1] as Control, docker)
    assert_true(
        last_row.end.y <= height,
        "Row %d ends at %.1f inside the docker's %.1f, at %d columns" % [rows, last_row.end.y, height, columns]
    )
    if not exact:
        return
    var over := _in_docker(cells[(rows + 1) * columns - 1] as Control, docker)
    assert_true(over.end.y > height, "and row %d at %.1f is the one the scroll reaches" % [rows + 1, over.end.y])
