## The known file, `door.json` in the data root, read from outside the door
## that writes it: where it is, and which live Sara it names.
##
## A door asks before it writes the file and before it opens on it, and
## Modules › Local Server asks before it opens a door at all, so the painter
## hears that another Sara already listens rather than a door that failed.
## Whether that Sara still runs is `SaProcess`'s question, which the run log
## asks as well.
class_name SaKnownFile
extends RefCounted

const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")


## *given*, or the data root's known file when it is empty.
static func path(given: String = "") -> String:
    return given if not given.is_empty() else SaDataRoot.path(AgentInvite.KNOWN_FILE)


## The process id the known file at *file* names when that is a live Sara
## other than this one, and 0 when the file is free to write.
static func live_holder(file: String) -> int:
    var holder := int(read(file).get("pid", 0))
    return holder if SaProcess.another_runs(holder) else 0


## The JSON object in *file*, or an empty one when there is none to read.
static func read(file: String) -> Dictionary:
    if file.is_empty() or not FileAccess.file_exists(file):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
    return parsed as Dictionary if parsed is Dictionary else {}
