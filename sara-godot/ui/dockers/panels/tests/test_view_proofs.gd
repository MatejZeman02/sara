## The two proofs and the minimap's rim.
##
## The minimap and viewport need their own soft proofing, for example grayscale
## while painting in colour, as a values check. The orange rim that shows where
## the camera is looking must not render over the drag bar.
##
## A docker is a `Window`, and adding one to the tree in a headless test hangs,
## so nothing here enters the tree. The docker's own `_init` builds every child
## this asks about.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _registry() -> SaViewTransformRegistry:
    var registry := SaViewTransformRegistry.new()
    var grey := SaViewTransformDescriptor.create(&"lightness_check", "Lightness Check", SaViewTransformDescriptor.Kind.MODE)
    grey.view_mode = 1
    registry.register(grey)
    var proof := SaViewTransformDescriptor.create(&"soft_proof", "Soft Proof", SaViewTransformDescriptor.Kind.MODE)
    proof.view_mode = 3
    registry.register(proof)
    var toggle := SaViewTransformDescriptor.create(&"gamut_warning", "Gamut Warning", SaViewTransformDescriptor.Kind.TOGGLE)
    registry.register(toggle)
    return registry


## The rim is a polyline through the view's corners, and a view zoomed out puts
## those corners outside the map. Godot clips nothing by default, which is how
## the orange line reached the drag bar above it.
func test_the_rim_is_clipped_to_the_picture() -> void:
    var docker := MinimapDocker.new()
    var overlay: Control = docker.find_child("ViewOverlay", true, false)
    assert_not_null(overlay, "the docker has its overlay")
    assert_true(overlay.clip_contents, "which draws nothing outside the picture, in any direction")
    docker.free()


## The two proofs are separate answers, so the map can be a values
## check while the painting stays in colour.
func test_the_minimap_proof_is_its_own_toggle() -> void:
    var docker := MinimapDocker.new()
    assert_false(docker.proof_on, "the minimap starts on the canvas's own view")
    assert_true(docker.toggle_proof(), "Ctrl+Shift+Y turns its proof on")
    assert_true(docker.proof_on, "and it says so")
    assert_false(docker.toggle_proof(), "and off again")
    docker.free()


## The mode the map shows is the preference's, read every time rather than
## remembered, so a change in Preferences shows without a second press.
func test_the_minimap_shows_the_mode_the_preference_names() -> void:
    var docker := MinimapDocker.new()
    docker.view_transforms = _registry()
    var was := SaSettings.minimap_proof_mode

    SaSettings.minimap_proof_mode = "lightness_check"
    assert_eq(docker._proof_descriptor().view_mode, 1, "the greyscale check is the shader's mode 1")
    SaSettings.minimap_proof_mode = "soft_proof"
    assert_eq(docker._proof_descriptor().view_mode, 3, "and the soft proof its mode 3")

    # A toggle is not a mode, and neither is a name nobody registered. Either
    # one leaves the map showing what the canvas shows rather than a blank.
    SaSettings.minimap_proof_mode = "gamut_warning"
    assert_null(docker._proof_descriptor(), "a toggle is refused")
    SaSettings.minimap_proof_mode = "no_such_transform"
    assert_null(docker._proof_descriptor(), "and so is a mode nobody registered")

    SaSettings.minimap_proof_mode = was
    docker.free()


## The picture takes a copy of the canvas material with one uniform changed, so
## the rolloff, the exposure and the display profile still read the same on the
## map as on the painting, and only the mode differs.
func test_the_proof_copies_the_canvas_material_and_changes_the_mode() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var canvas := SaCanvas.new()
    canvas.easel = easel
    canvas.sync_tonemap()
    var canvas_material := canvas.material as ShaderMaterial
    assert_not_null(canvas_material, "the canvas built its material")
    canvas_material.set_shader_parameter("display_exposure", 2.0)

    var docker := MinimapDocker.new()
    docker.target_canvas = canvas
    docker.view_transforms = _registry()
    var was := SaSettings.minimap_proof_mode
    SaSettings.minimap_proof_mode = "lightness_check"

    var picture: TextureRect = docker.find_child("Picture", true, false)
    docker._sync_material()
    assert_eq(picture.material, canvas_material, "with its proof off the map paints with the canvas's own material")

    docker.toggle_proof()
    docker._sync_material()
    var own := picture.material as ShaderMaterial
    assert_true(own != canvas_material, "with it on the map paints with a copy")
    assert_eq(own.get_shader_parameter("view_mode"), 1, "at the mode the preference names")
    assert_eq(canvas_material.get_shader_parameter("view_mode"), 0, "and the canvas is left where it was")
    assert_almost_eq(float(own.get_shader_parameter("display_exposure")), 2.0, 0.001, "carrying everything else across")

    SaSettings.minimap_proof_mode = was
    docker.free()
    canvas.free()
    easel.free()
