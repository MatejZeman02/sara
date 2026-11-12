## The `presets_docker` capture step, the Brush Presets docker's half of the
## capture door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own file by responsibility: this file owns the door and the docker owns
## the buttons. It stays in the docker's folder rather than in `harness/captures`,
## because a docker describes itself to the harness, and the docker's
## `capture_docker` hands the step here so the step table names one door.
##
## It presses the docker's buttons by their own `pressed` signal and calls only
## the docker's public functions, so a step that says it pressed Delete went
## through what a click on Delete does.
extends RefCounted

const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")


## The docker's own half of the capture door, so a scenario can press a cell
## without an injected click, which does not route into a docker's window.
##
## **There was a `{"refresh": true}` here and it is gone**. It called `rebind` by
## hand because the docker is visible from launch, so nothing toggles while a
## preset is being saved and a save announced itself to nobody. A door step that
## exists to work around a missing signal is a placeholder for the signal, and
## `EventBus.preset_store_changed` is the signal.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var docker := tree.root.find_child(SaDockerIds.BRUSH_PRESETS, true, false)
    if docker == null:
        return "SaCapture: no Brush Presets docker"
    # `{"presets_docker": {"foreign": {...}}}` writes a preset of another engine,
    # and `{"engines": true}` answers which engine each cell is for, which are
    # dimmed and the corner line a refused apply left.
    if spec is Dictionary and (spec as Dictionary).has("foreign"):
        return PresetEngineMarks.write_foreign(ToolOptionsPresets.in_tree(docker), (spec as Dictionary)["foreign"])
    if spec is Dictionary and bool((spec as Dictionary).get("engines", false)):
        var marks: PresetEngineMarks = docker.get("engine_marks")
        return "SaCapture: presets docker engines %s" % JSON.stringify(marks.report() if marks != null else {})
    if spec is Dictionary and (spec as Dictionary).has("apply"):
        var wanted := String((spec as Dictionary)["apply"])
        if not docker.call("apply_preset", wanted):
            return "SaCapture: the presets docker would not apply '%s'" % wanted
        return "SaCapture: presets docker applied '%s'" % wanted
    # `{"presets_docker": {"close": true}}`: the docker is open from launch, so a
    # scenario proving that the button and the right click open it has to be able
    # to shut it first. Through the registered command, which is the door the
    # Dockers menu row and the chord both take, so the checkmark and the saved
    # layout follow the way they do for a painter.
    if spec is Dictionary and bool((spec as Dictionary).get("close", false)):
        if docker.call("conceal"):
            return "SaCapture: presets docker closed"
        return "SaCapture: the presets docker would not close"
    # `{"presets_docker": {"toggle": true}}`, which is the button's own press:
    # the window has to open on the button and close on a second press, and a click injected at the bar reaches the button but a
    # scenario that wants both halves in one dump wants the call.
    if spec is Dictionary and bool((spec as Dictionary).get("toggle", false)):
        var presets := ToolOptionsPresets.in_tree(docker)
        if presets == null:
            return "SaCapture: no tool options bar, so the Presets button is not there to press"
        return "SaCapture: presets docker toggled, open=%s" % str(presets.toggle_presets_docker())
    # `{"presets_docker": {"delete": true}}`, the Delete button's own press. The
    # button is inside a docker's `Window`, which an injected click does not
    # route into, and what that press does is the whole point, so it needs a door
    # of its own rather than the bar's `{"preset": {"delete": "name"}}`, which
    # goes straight to the store and asks nobody.
    if spec is Dictionary and bool((spec as Dictionary).get("delete", false)):
        var loaded := ToolOptionsPresets.in_tree(docker)
        var named := loaded.selected_preset if loaded != null else ""
        (docker.get("delete_button") as Button).pressed.emit()
        return "SaCapture: presets docker delete pressed on '%s'" % named
    # `{"presets_docker": {"new": true}}`, the New preset... button's own press,
    # which opens the dialog behind it, and `{"new_dialog": {"pick":
    # "noise", "name": "Grain", "create": true}}` drives that dialog once open.
    if spec is Dictionary and bool((spec as Dictionary).get("new", false)):
        var group := ToolOptionsPresets.in_tree(docker)
        if group == null:
            return "SaCapture: no tool options bar, so there is no store to make a preset in"
        (docker.get("new_button") as Button).pressed.emit()
        return "SaCapture: presets docker new preset pressed, dialog %s" % JSON.stringify(docker.call("new_dialog_report"))
    if spec is Dictionary and (spec as Dictionary).has("new_dialog"):
        var group := ToolOptionsPresets.in_tree(docker)
        var dialog := group.get_node_or_null(SaNewPresetDialog.NODE_NAME) as SaNewPresetDialog if group != null else null
        if dialog == null or not dialog.visible:
            return "SaCapture: new preset dialog failed, it is not open"
        return dialog.capture_dialog((spec as Dictionary)["new_dialog"] as Dictionary)
    # `{"presets_docker": {"legacy": "Older"}}`, the version 2 fixture the
    # migration is graded on. Written from the live settings' own script rather
    # than shipped as a `.tres`, for the reason `SHIPPED` gives one file over: a
    # hand-written preset names the module's script and its property set by
    # hand, and one generated here is valid for the build that wrote it.
    if spec is Dictionary and (spec as Dictionary).has("legacy"):
        return _write_legacy_fixture(docker, String((spec as Dictionary)["legacy"]))
    # `{"presets_docker": {"pen_settings": true}}`, what the live settings carry
    # after a load: the stamp and every option's `use_curve`. The stroke dump
    # has the same two booleans and only inside a stroke, and the claim here is
    # about a preset that has just been loaded and not yet painted with.
    if spec is Dictionary and bool((spec as Dictionary).get("pen_settings", false)):
        return _read_pen_settings(docker)
    return "SaCapture: presets docker %s" % JSON.stringify(docker.call("capture_state"))


## A preset written the way an older build wrote one: stamped at version 2 and
## with the curve switched off on every option.
##
## By method name and by property name throughout, so the skeleton names no
## module script and a third-party tool whose settings carry neither is told so
## rather than half written.
static func _write_legacy_fixture(docker: Node, preset_name: String) -> String:
    var presets := ToolOptionsPresets.in_tree(docker)
    var live := presets.settings_source.call() as Resource if presets != null and presets.settings_source.is_valid() else null
    var script := live.get_script() as Script if live != null else null
    if script == null:
        return "SaCapture: no settings resource, so there is nothing to write a legacy preset from"
    var fixture := script.new() as Resource
    if fixture == null or not fixture.has_method("options") or not ("format_version" in fixture):
        return "SaCapture: these settings carry no curve options, so there is no version 2 state to write"
    for key: String in fixture.call("options"):
        var option: Resource = fixture.call("options")[key]
        if option != null:
            option.set("use_curve", false)
    fixture.set("format_version", 2)
    var stored := presets.preset_store.save_preset(preset_name, fixture)
    if stored.is_empty():
        return "SaCapture: the legacy preset '%s' would not save" % preset_name
    EventBus.preset_store_changed.emit(stored, true)
    return "SaCapture: legacy preset '%s' written at version 2 with every curve off" % stored


## The stamp and the nine `use_curve` flags on the settings in front of the
## painter, which is what a load of the fixture above has to have corrected.
static func _read_pen_settings(docker: Node) -> String:
    var presets := ToolOptionsPresets.in_tree(docker)
    var live := presets.settings_source.call() as Resource if presets != null and presets.settings_source.is_valid() else null
    if live == null or not live.has_method("options"):
        return "SaCapture: no settings resource with curve options to read"
    var flags: Dictionary = {}
    for key: String in live.call("options"):
        var option: Resource = live.call("options")[key]
        # Written out rather than as a ternary, because a ternary whose arms are
        # a bool and a null is an incompatible one and the LSP check says so.
        if option == null:
            continue
        flags[key] = option.get("use_curve")
    var stamp: Variant = live.get("format_version") if "format_version" in live else null
    return (
        "SaCapture: pen_settings preset='%s' format_version=%s use_curve=%s"
        % [presets.selected_preset, str(stamp), JSON.stringify(flags)]
    )
