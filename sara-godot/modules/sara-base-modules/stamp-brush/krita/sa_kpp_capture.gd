## The door's `kpp` step: reads a Krita preset, a folder or a bundle through
## [SaKppReader] and writes what it found where a reviewer reads it.
##
## A reader with no button has nothing a scenario can click, and a feature is
## proved on the running app, so this is the step that proves one. It prints a
## line per preset, appends the same lines to `kpp.txt` in the capture's output
## folder, and leaves the tip bytes out of both: what a reviewer checks is the
## name, the engine, the tip's kind and size, the option count, the tags and
## the licence, which is a line, and the bytes are what the test checks.
class_name SaKppCapture
extends RefCounted

const REPORT_FILE: String = "kpp.txt"


## `{"kpp": "<path>"}`: reads a `.kpp`, a `.bundle` or a folder of them,
## prints one line per preset and appends the lines to `kpp.txt` beside the
## shots. The path is taken as given, `res://` and `user://` included, since a
## fixture the module commits is addressed the same way its test addresses it.
static func capture_read(out_dir: String, path: String) -> String:
    var presets := SaKppReader.read_path(path)
    var lines := PackedStringArray()
    for preset in presets:
        lines.append(describe(preset))
    for line in lines:
        _append_line(out_dir, line)
    return "SaCapture: kpp read %d preset(s) from %s\n%s" % [presets.size(), path, "\n".join(lines)]


## One preset as one line, the same line the console and `kpp.txt` carry.
static func describe(preset: Dictionary) -> String:
    var error := String(preset["error"])
    if not error.is_empty():
        return "refused %s: %s" % [String(preset["source"]).get_file(), error]
    var tip: Dictionary = preset["tip"]
    var tip_text := String(tip["kind"])
    match String(tip["kind"]):
        SaKppReader.TIP_GENERATED:
            var generator: Dictionary = tip["generator"]
            tip_text = "generated %s %s" % [String(generator.get("type", "")), String(generator.get("diameter", ""))]
        SaKppReader.TIP_IMAGE:
            var size: Vector2i = tip["size"]
            tip_text = "%s %s %dx%d" % [String(tip["format"]), String(tip["file_name"]), size.x, size.y]
        SaKppReader.TIP_REFUSED:
            tip_text = "refused: %s" % String(tip["error"])
    var tags: PackedStringArray = preset["tags"]
    return (
        "%s | engine %s | tip %s | %d options | tags [%s] | licence '%s' | %s"
        % [
            String(preset["name"]),
            String(preset["engine"]),
            tip_text,
            (preset["options"] as Dictionary).size(),
            ", ".join(tags),
            String(preset["licence"]),
            String(preset["source"]).get_file(),
        ]
    )


## The folder is the run's, handed in as the string it is: a step reports into
## the folder the runner chose, which is the same place its shots go, and an
## empty one means there is nowhere to write. It was read off the capture node
## by name, which was all this file took that node for.
static func _append_line(dir: String, line: String) -> void:
    if dir.is_empty():
        return
    var path := dir.path_join(REPORT_FILE)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaKppCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line)
