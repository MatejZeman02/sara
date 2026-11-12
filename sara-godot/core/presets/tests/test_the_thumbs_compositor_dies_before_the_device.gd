## The preset thumbnails' shared compositor is let go before the rendering device
## is torn down.
##
## made every throwaway easel composite through one static `SaCompositor`, and
## a static var is dropped with its script class, after the engine has freed the
## device. Every capture since then ended on 22 "Attempted to free invalid ID"
## lines, the compositor's computes and scratch textures freeing RIDs into a
## device that was gone. The capture proves the count. This proves the mechanism
## the count rests on: making the compositor ties its release to the root leaving
## the tree, and a release leaves nothing holding it, so its RAII runs then.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_making_the_compositor_ties_its_release_to_the_tree_exiting() -> void:
    SaPresetThumbs.release_compositor()
    var shared: WeakRef = weakref(SaPresetThumbs.shared_compositor())
    var tree := Engine.get_main_loop() as SceneTree
    assert_true(tree.root.tree_exiting.is_connected(SaPresetThumbs.release_compositor), "The root leaving the tree releases it")
    assert_true(shared.get_ref() != null, "and until then the static holds it")


func test_a_release_leaves_nothing_holding_the_compositor() -> void:
    SaPresetThumbs.release_compositor()
    var shared: WeakRef = weakref(SaPresetThumbs.shared_compositor())
    var settings := (StateBrushScript.new() as ToolState).get("settings") as Resource
    var image := SaPresetThumbs.render_tip(StateBrushScript, settings)
    assert_true(image != null, "A tip rendered through the shared compositor")
    assert_true(SaPresetThumbs.last_compositor == shared.get_ref(), "and the last render's reference is that compositor")
    SaPresetThumbs.release_compositor()
    assert_true(shared.get_ref() == null, "Released, nothing holds it, so its computes and textures are freed there")
    assert_true(SaPresetThumbs.last_compositor == null, "and the last render's reference went with it")
    assert_true(SaPresetThumbs.shared_compositor() != null, "The next render asks for a fresh one and gets it")
