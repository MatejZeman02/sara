## The grip dots stand clear of a docker's title by at least the grip gap.
##
## In both floating and docked dockers across UI scales, the six grip dots
## precede the title label with room on the left and right, ensuring the first
## drawn glyph never touches or fuses with the dots.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _saved_embedding: bool = true
var _saved_scale: float = 1.0


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _saved_embedding = tree.root.gui_embed_subwindows
    _saved_scale = SaUI.user_scale
    _host = Node.new()
    _host.name = "GripGapHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _saved_embedding
    SaUI.user_scale = _saved_scale


func test_grip_dots_keep_gap_from_title_at_scales_docked_and_floating() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for scale_val: float in [1.0, 1.5, 2.0]:
        SaUI.user_scale = scale_val
        for is_floating: bool in [false, true]:
            tree.root.gui_embed_subwindows = not is_floating
            var docker := HistoryDocker.new()
            _host.add_child(docker)
            docker.visible = true

            await tree.process_frame
            await tree.process_frame

            var label := docker.find_child("TitleLabel", true, false) as Label
            assert_not_null(label, "TitleLabel exists in HistoryDocker")
            assert_eq(label.text, "Recent Presets", "docker title is Recent Presets")

            var grip := label.get_node_or_null(SaGrip.NODE_NAME) as SaGrip
            assert_not_null(grip, "SaGrip exists under TitleLabel")

            var char0_x := label.get_character_bounds(0).position.x
            var dots_right := grip.dots_right()
            var gap := char0_x - dots_right

            assert_true(
                gap >= float(SaGrip.GAP),
                (
                    "Title first glyph at %.1f starts at least GAP (%d px) right of dots edge %.1f (gap %.1f) at scale %.1f %s"
                    % [char0_x, SaGrip.GAP, dots_right, gap, scale_val, "floating" if is_floating else "docked"]
                )
            )

            docker.queue_free()
            await tree.process_frame
