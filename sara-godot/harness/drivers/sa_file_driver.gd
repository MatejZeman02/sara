## What a scenario does to the files on disk that a painter does outside Sara.
##
## A file deleted in a file manager, or a painting opened on another machine where the files it
## names are not, is a state a scenario reaches with no shell to hand. A scenario can delete the
## originals of the pictures on a Reference board and open the painting again.
class_name SaFileDriver
extends RefCounted


## Deletes files: each path in the list, and every file in a folder under
## Sara's data root named as `data:` and the folder, as a painter tidying a
## folder outside Sara would, and never a file of the project's own `res://`,
## `{"delete_files": ["user://picture.png", "data:reference-pastes"]}`.
static func delete_files(spec: Variant) -> String:
    var gone := 0
    for raw: Variant in spec if spec is Array else [spec]:
        var path := String(raw)
        var files := PackedStringArray([path])
        if path.begins_with("data:"):
            var folder := ProjectSettings.globalize_path(SaDataRoot.path(path.trim_prefix("data:")))
            files.clear()
            for name in DirAccess.get_files_at(folder):
                files.append(folder.path_join(name))
        for file in files:
            if not file.begins_with("res://") and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK:
                gone += 1
    return "SaCapture: deleted %d files" % gone
