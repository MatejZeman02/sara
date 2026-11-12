## Owns secondary workspace host lifecycle and docker reparenting.
class_name WorkspaceController
extends RefCounted

var secondary_workspaces: Array[Window] = []


func create_secondary_workspace(owner: Node) -> Window:
    var host := SecondaryWorkspaceHost.new()
    host.name = "SecondaryWorkspace_%d" % (secondary_workspaces.size() + 1)
    host.title = tr("Sara - Second Monitor")
    host.size = SaUI.to_physical_v(Vector2i(1280, 720))
    host.min_size = SaUI.to_physical_v(Vector2i(400, 300))
    host.gui_embed_subwindows = SaSettings.embed_subwindows
    owner.add_child(host)
    host.place_from_settings()
    SaUI.apply_to_window(host)
    CursorOverlay.attach_to(host)
    secondary_workspaces.append(host)
    host.close_requested.connect(_close_workspace.bind(owner, host))
    return host


func reparent_dockers(configs: Array[Dictionary], docker_name: String, target_host: Node, fallback_parent: Node) -> void:
    var target_parent := target_host if target_host != null else fallback_parent
    for config in configs:
        if docker_name != "*all*" and config["name"] != docker_name:
            continue
        var docker := config["node"] as Window
        if docker != null and docker.get_parent() != target_parent:
            docker.reparent(target_parent)
        if docker_name != "*all*":
            return


func _close_workspace(owner: Node, host: SecondaryWorkspaceHost) -> void:
    host.remember()
    for child in host.get_children():
        if child is Window:
            child.reparent(owner)
    host.hide()
    host.queue_free()
    secondary_workspaces.erase(host)
