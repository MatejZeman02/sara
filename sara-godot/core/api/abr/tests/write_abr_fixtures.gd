## Writes the `.abr` fixtures beside it from `abr_writer.gd`, the one way they
## are made. Run `godot --headless --path sara-godot -s
## res://core/api/abr/tests/write_abr_fixtures.gd` after changing a picture
## there, and commit what it writes with the change.
extends SceneTree

const AbrWriter = preload("res://core/api/abr/tests/abr_writer.gd")


func _init() -> void:
    var dir := ProjectSettings.globalize_path(AbrWriter.FIXTURE_DIR)
    var written := AbrWriter.write_all(dir)
    print("wrote %s" % dir if written else "could not write %s" % dir)
    quit(0 if written else 1)
