## The first message a coding agent needs to reach Sara, which Sara hands over
## itself: the button in Modules › Local Server's dialog puts it on the
## clipboard and `-- --agent-help` prints it and quits.
##
## Without it, a painter who asks an agent to "connect to running Sara" leaves
## first contact to the agent's luck, because a refused request does not say
## where the token is. The paragraph says that Sara listens, the file that says
## where, and the one request to send first, the door's own help, with the
## token as a Bearer. It names no step kind
## beyond that request, so it cannot go stale as the table grows, and it names
## the file rather than copying the token, so the clipboard, which every
## program on the machine can read, never carries it.
##
## Beside the boot, because `--agent-help` is answered by the first scene
## before `Main` or the harness is loaded, and the harness names this file for
## the menu's half and for the known file's name.
class_name SaAgentInvite
extends RefCounted

## The known file's name in the data root, `user://door.json` for a painter's
## Sara and `<settings-dir>/data/door.json` for a scratch run. The door writes
## it and reads its name from here, so the paragraph and the door cannot name
## two files.
const KNOWN_FILE := "door.json"

## The user argument that prints the paragraph and quits.
const HELP_FLAG := "--agent-help"


## The paragraph, naming *where*, the file that says where the door listens.
## *listening* opens it with the door open, as the menu row leaves it, and
## otherwise with how to open it, which is what `--agent-help` can say of a
## Sara it has not started.
static func paragraph(where: String, listening: bool) -> String:
    var server := "a small HTTP server on 127.0.0.1 that takes painting steps as JSON."
    var opening := (
        "Sara is running on this computer and its door is listening: " + server
        if listening
        else (
            "Sara has a door for coding agents: "
            + server
            + " It listens once Sara is started with `-- --agent-door`, "
            + "or once Modules › Local Server is ticked in a running Sara."
        )
    )
    var sentences := PackedStringArray([opening])
    sentences.append(
        (
            (
                "Where it listens is in `%s`, a JSON file holding the `port` and the `token`, "
                + "which Sara writes when the door opens and removes when it closes."
            )
            % where
        )
    )
    sentences.append(
        (
            "Send this request first: `POST http://127.0.0.1:<port>/step` with the header "
            + '`Authorization: Bearer <token>` and the body `{"steps": true}`.'
        )
    )
    sentences.append(
        (
            "The answer holds `start`, the steps a painting needs first, each with a `name`, a "
            + "`description` and an `inputSchema`, and `steps`, every other step by its name and one line, "
            + 'and the body `{"steps": "<name>"}` describes one of them whole.'
        )
    )
    sentences.append("A POST of an array of steps runs them in order and answers an array of answers.")
    return " ".join(sentences)


## The known file of this run as a path outside Godot, which is the one an
## agent can open.
static func known_path() -> String:
    return ProjectSettings.globalize_path(SaDataRoot.path(KNOWN_FILE))


## Prints the paragraph for a Sara whose door is not open yet and quits, when
## *args* hold `--agent-help`. True when it did, and the boot then stops.
static func answer_help_flag(args: PackedStringArray, tree: SceneTree) -> bool:
    if not args.has(HELP_FLAG):
        return false
    print(paragraph(known_path(), false))
    tree.quit()
    return true
