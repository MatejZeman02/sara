## Rename Layer opened at 24,236 at 1920 by 1080, across the
## window from the Layers docker and over Brush Presets. `popup_centered` put
## it in the middle, and the fit a frame later shrank it to the docker's width
## and moved it inside the docker's rectangle, read as the main window's,
## because the dialog is the docker's child and measured its host there.
##
## The host is a `SubViewport` that embeds, standing in for the main window, so
## its size is the suite's to set where the test runner's own window is not. The
## docker is a window embedded in it at the right edge, where the default
## layout puts it, and the dialog is opened from the docker by both of its
## doors, F2's and the note mark's, the first time and the second. The
## scenario `rename-layer-opens-in-the-middle-of-the-main-window` presses a
## note mark in the running app at both sizes.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

var _host: SubViewport = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_at_1920_by_1080_it_opens_in_the_middle_every_time() -> void:
    _hold_in_the_middle(Vector2i(1920, 1080))


func test_at_1280_by_1024_it_opens_in_the_middle_every_time() -> void:
    _hold_in_the_middle(Vector2i(1280, 1024))


## The rectangle it is placed against is the host's, not the docker's, which is
## the whole of the mistake this unit mended.
func test_the_main_rectangle_is_the_hosts_and_not_the_dockers() -> void:
    var docker := _docker(Vector2i(1920, 1080))
    assert_true(docker.open_rename_dialog(), "The docker opens the dialog")
    var dialog := _dialog(docker)
    assert_true(dialog.is_embedded(), "which is embedded")
    assert_eq(dialog.main_rect(), Rect2i(Vector2i.ZERO, Vector2i(1920, 1080)), "and measures the host it is embedded in")
    assert_eq(dialog.host_rect().size.x, 1920, "and is fitted to the host's width")


func _hold_in_the_middle(host_size: Vector2i) -> void:
    var docker := _docker(host_size)
    assert_true(docker.open_rename_dialog(), "F2's door opens the dialog at %s" % host_size)
    var dialog := _dialog(docker)
    assert_not_null(dialog, "and the docker holds it")
    _assert_middle(dialog, host_size, "the first open")
    dialog.hide()
    docker.position = Vector2i(40, 60)
    assert_true(docker.open_rename_dialog(true), "the note mark's door opens it again")
    _assert_middle(dialog, host_size, "the second open, with the docker moved")
    dialog.position += Vector2i(300, -120)
    dialog.hide()
    docker.open_rename_dialog()
    _assert_middle(dialog, host_size, "an open after a drag")


## Held after the fit `SaDialogWindow` asks for on the frame after a show,
## which is the step that moved it, run here by hand because the suite has no
## frame to wait for.
func _assert_middle(dialog: SaLayerRenameDialog, host_size: Vector2i, what: String) -> void:
    dialog.fit_opening_size()
    assert_true(dialog.size.x >= 420, "At %s %s keeps the width it asks for, %d" % [host_size, what, dialog.size.x])
    var rect := Rect2i(dialog.position, dialog.size)
    var host := Rect2i(Vector2i.ZERO, host_size)
    var off := (rect.get_center() - host.get_center()).abs()
    assert_true(
        off.x <= 1 and off.y <= 1,
        "At %s %s stands at %s, its middle %s from the host's %s" % [host_size, what, rect, off, host.get_center()]
    )


## A host of *host_size* that embeds, with a layers docker in it at its right
## edge over a document with an active layer.
func _docker(host_size: Vector2i) -> LayersDocker:
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = SubViewport.new()
    _host.name = "D95Host"
    _host.size = host_size
    _host.gui_embed_subwindows = true
    _host.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_host)

    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    docker.target_canvas = canvas
    canvas.add_child(docker)
    docker.size = Vector2i(310, 600)
    docker.position = Vector2i(host_size.x - 320, 120)
    docker.sync_layer_list()
    return docker


func _dialog(docker: LayersDocker) -> SaLayerRenameDialog:
    return docker.find_child("LayerRenameDialog", true, false) as SaLayerRenameDialog
