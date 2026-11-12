## The settings of the document's ground, a Paper or a Canvas or a module's
## own, in a dialog window of their own: the rows of `SaGroundRows` under a
## title strip, opened from the Ground button under the layers list.
##
## A dialog window rather than a `PopupPanel` over the docker, which closes on
## any press outside it and cannot be moved. This is an `SaDialogWindow` like
## Relief Light and the filter windows, so it is dragged
## by its strip, closed from its own button and kept above the main window.
##
## **It stays open while the painter paints.** The window is not exclusive and
## no press outside it closes it, which is what the dialog base allows, so a
## stroke on the canvas lands while it shows and its rows follow the ground
## the docker hands them on every sync. Each row writes its own history step,
## so nothing is recorded on close.
##
## **It is as tall as the ground's rows.** A swap from Paper to Canvas shows
## three thread rows more and one from Canvas to Paper hides them, so `fit`
## takes the height the rows ask for each time, the rule the rename dialog
## keeps for its note.
@tool
class_name SaGroundDialog
extends SaDialogWindow

## The narrowest the window is dragged to, in logical units, the width a
## slider's words and number need side by side.
const FLOOR_WIDTH: int = 300

## Logical room left between the window and the docker it opens beside.
const GAP: int = 8

## The rows the window holds.
var rows: SaGroundRows


func _init() -> void:
    _init_dialog("GroundDialog", tr("Ground"), Vector2i(340, 300), Vector2i(FLOOR_WIDTH, 120))
    visible = false
    number_field_answers = false
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    rows = SaGroundRows.new()
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_child(rows)


## The Ground button of *docker*: shows the rows of *document*'s ground, the
## active layer or the uppermost ground under it, and opens the window beside
## the docker or closes it. False when the document has no ground, where the
## button is dimmed.
func toggle_for(document: SaDocument, registry: SaLayerTypeRegistry, docker: Window) -> bool:
    var ground := SaGroundRows.ground_of(document, registry)
    if ground == null:
        return false
    rows.show_layer(document, ground, registry)
    _seat_beside(docker)
    toggle_beside(docker)
    return true


## Follows *docker*'s document on every sync: the rows show its ground, the
## window closes when it has none and opens beside the docker when *added*,
## a ground just added, because its tooth and colours are what a painter adds a
## ground to set. A row made active by PageDown, an undo or a press leaves it
## open on the document's ground.
func follow(document: SaDocument, registry: SaLayerTypeRegistry, docker: Window, added: bool) -> void:
    rows.show_layer(document, SaGroundRows.ground_of(document, registry), registry)
    if visible and not rows.visible:
        hide()
    elif added and not visible and docker.is_inside_tree():
        _seat_beside(docker)
        open_beside(docker)
    fit()


## Hangs the window from the node *docker* hangs from, once, so its host is
## the main window's and not the docker's. A window that is the child of a
## docker measures its room in the docker's own viewport, so the window opened
## clamped into the docker's 310 by 556 at the screen's top left corner,
## measured in the running app. A docker with no parent yet holds it.
func _seat_beside(docker: Window) -> void:
    if get_parent() != null:
        return
    var host := docker.get_parent()
    if host != null:
        host.add_child(self)
    else:
        docker.add_child(self)


## Shows the window beside *beside*, the docker it was opened from, on
## whichever side has the room, or closes it when it shows. The rows are
## filled by the caller first.
func toggle_beside(beside: Window) -> void:
    if visible:
        hide()
    else:
        open_beside(beside)


## Shows the window beside *beside*, or where it stands when it shows already.
func open_beside(beside: Window) -> void:
    if not is_inside_tree():
        return
    if visible:
        fit()
        return
    retitle(_title_for(rows))
    popup_centered()
    fit()
    if beside != null and beside.visible:
        position = _clamped_to_host(_beside_of(beside))


## Takes the height the rows ask for, after a swap showed or hid the thread
## rows, and keeps the top where it was.
func fit() -> void:
    if not is_inside_tree() or SaDockerMaximise.is_maximised(self):
        return
    var needed := content_minimum_size()
    logical_min_size = Vector2i(FLOOR_WIDTH, needed.y).max(Vector2i(needed.x, 0))
    logical_size = Vector2i(maxi(logical_size.x, logical_min_size.x), needed.y)
    min_size = SaUI.window_size_for(self, logical_min_size)
    size = SaUI.window_size_for(self, logical_size)
    if visible:
        retitle(_title_for(rows))
        _keep_inside_host()


## The window's place left of *docker* when the host has the room for it there,
## and right of it otherwise, level with the docker's top.
func _beside_of(docker: Window) -> Vector2i:
    var gap := SaUI.window_size_for(self, Vector2i(GAP, GAP)).x
    var left := docker.position.x - size.x - gap
    var host := host_rect()
    if host.size.x <= 0 or left >= host.position.x:
        return Vector2i(left, docker.position.y)
    return Vector2i(docker.position.x + docker.size.x + gap, docker.position.y)


## The title names the ground the rows are tuning, "Paper" or "Canvas", so a
## painter who opened it from a paint layer reads which layer it changes.
static func _title_for(ground_rows: SaGroundRows) -> String:
    var layer := ground_rows._layer
    if layer == null:
        return TranslationServer.translate("Ground")
    return TranslationServer.translate("Ground") + ": " + str(layer.name)
