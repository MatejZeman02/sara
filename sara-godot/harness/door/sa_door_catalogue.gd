## The step kinds the door answers `{"steps": true}` with.
##
## An agent holding a build and nothing else asks the door what it can send.
## The catalogue is what `scripts/sara_steps.py --json` writes, parsed out of
## the doc comments above the handlers `SaStepTable` dispatches to, and an
## exported build carries no doc comments. So `packaging/build.sh` packs that
## output into the build as `step_catalogue.json`, the way it packs the
## changelog, and this reads the packed copy back. A checkout has no packed
## copy and runs the script instead, so an editor run answers from the source
## as it stands rather than from the last build.
##
## `{"steps": true}` answers every kind once, in two parts that fit a small
## model's context. `start` holds the kinds a painting needs first, the ones
## `sara_steps.py` flags, in the three fields of an MCP tool: `name`,
## `description`, the kind's line, and `inputSchema`, which types the keys of
## its argument from the doc's `Arguments` paragraph. `steps` holds
## every other kind as its name and its line in one object. The line is the
## doc's first sentence up to a colon or a backtick, forty characters at most,
## so the whole answer stays under ten thousand. Every first sentence with its
## example would be several times that, and a small model would be over its
## context before it painted.
## `{"steps": "zoom"}` answers one kind with its whole doc as the description.
## A kind the table tries twice, as it does `import` for an `.ora`, is
## described by its last branch, the one with no condition, which is what
## `scripts/sara_steps.py` lists.
##
## **The door's own kinds are listed after the table's.** `quit` is answered
## by the door before the table is asked, so the table has no branch for it and
## a catalogue read off the table alone left an agent that read only the list
## with no way to end a session. `DOOR_KINDS` carries them, and both the packed
## copy and the checkout's script get them on the way in.
##
## **No two kinds share a line.** A list an agent reads by its lines is worth
## nothing where two kinds read the same, which happened when kinds sharing a
## handler shared its doc. A catalogue that holds two is refused, with the kinds
## named, so a suite holds the table to it by asking for the list and finding
## it answered.
##
## **A line opens on a word that says what the step does.** A model with a
## small context reads the first words of each line to choose, and an example
## tells it the shape before it tells it the job, so the job comes first and the
## example follows in the same sentence, after the colon or the backtick the
## line is cut at. The suite fails a first character that is not a capital
## letter, and `sara_steps.py --check` a line that does not open on a verb.
##
## **Help where an agent first goes wrong.** An agent tries something, the
## door refuses it, and the refusal names the catalogue request, so the next
## thing the agent sends is the one that lists what it can do. `HELP` is that
## text, carried by every answer the door cannot run: a body that is not
## JSON, a route or method it does not serve, a step with no kind the table
## knows, and a step whose argument is the wrong shape. `refusal` checks the
## last two before the table runs a step, and for a guessed kind names the
## kinds closest to it.
extends RefCounted

## What the door is and how to ask it for its steps, in two sentences.
const HELP := (
    "This is Sara's door: POST one JSON object to /step, a painting step such as"
    + ' {"zoom": 2.0}, or an array of them, and each answer says what the step did.'
    + ' Send {"steps": true} for every step kind and its argument, and'
    + ' {"steps": "<kind>"} for one kind\'s whole description.'
)
## The sentence beside the start list, because an agent reads the list and
## nothing else, and would not find the array otherwise. `look`, which shows a
## stroke without a pan, is a start kind for the same reason.
const BATCH := "An array of steps gets an array of answers."
## The list's last sentence, which says where a kind's whole text is.
const WHOLE := '{"steps": "<name>"} gives one kind whole.'

## How alike a guess and a kind must be, by `String.similarity`, to be named
## as the kind meant, and how many are named at most.
const CLOSE_ENOUGH: float = 0.5
const CLOSEST_COUNT: int = 3
## The requests the door answers itself, before the table is asked, in the
## fields of a kind the catalogue reads out of the table. `attach` and `steps`
## are the door's too and are not here: they are how a client takes hold of a
## Sara and asks it what to send, and neither is a step a session is painted with.
const DOOR_KINDS := {
    "quit":
    {
        "step": "quit",
        "argument": "bool",
        "summary": 'Ends the session, and Sara closes: `{"quit": true}`.',
        "brief": "Ends the session, and Sara closes",
        "start": true,
        "doc":
        (
            'Ends the session, and Sara closes: `{"quit": true}`. The door answers'
            + ' `{"ok": true, "quit": true}` and goes down with the app, which is'
            + " how a client that launched a Sara or attached to one lets it go.\n\n"
            + "Nothing else ends a session but the idle timeout, since a client that hangs up"
            + " is let go and the door listens for the next. A batch ends at a `quit`, its answer last."
        ),
        "inputSchema":
        {
            "type": "object",
            "properties": {"quit": {"type": "boolean", "description": "true, and Sara closes"}},
            "required": ["quit"],
        },
        "handler": "SaAgentDoor._run_request",
        "file": "harness/door/sa_agent_door.gd",
    },
}
## The GDScript types a JSON value arrives as, by the schema type the
## catalogue gives a kind's argument. JSON has one number, so an `integer`
## takes a float as the table's `int()` cast does.
const SHAPES := {
    "object": [TYPE_DICTIONARY],
    "array": [TYPE_ARRAY],
    "string": [TYPE_STRING],
    "boolean": [TYPE_BOOL],
    "integer": [TYPE_INT, TYPE_FLOAT],
    "number": [TYPE_INT, TYPE_FLOAT],
}
## What a refusal calls each shape, for a person reading the error.
const SHAPE_WORDS := {
    "object": "an object",
    "array": "an array",
    "string": "a string",
    "boolean": "a boolean",
    "integer": "a number",
    "number": "a number",
}

## Where a build carries the catalogue, which `packaging/build.sh` packs for
## the length of an export.
const PACKED := "res://step_catalogue.json"
## The script that writes it, run in a checkout.
const SCRIPT := "res://scripts/sara_steps.py"
## The names Python goes by, tried in order. A Windows checkout often has
## only `python`.
const PYTHONS: Array[String] = ["python3", "python"]

var _packed: String
## Every kind by name, loaded once, at the first request that needs it, since
## neither the packed file nor the table changes under a running Sara.
var _kinds: Dictionary = {}
var _loaded: bool = false
## Where `_kinds` came from, `packed` or `checkout`, which the answer names.
var _source: String = ""
## Why there is no catalogue, when there is none.
var _why: String = ""


## *packed* is where a build carries the catalogue, and a suite names its own.
func _init(packed: String = PACKED) -> void:
    _packed = packed


## The answer to a request whose `steps` is *asked*: one kind by name for a
## string, and for anything else every kind, the start kinds whole and the rest
## by their lines.
func answer(asked: Variant) -> Dictionary:
    if not _has_kinds():
        return {"ok": false, "error": _why, "help": HELP}
    if asked is String:
        var kind := String(asked)
        if not _kinds.has(kind):
            return _unknown([kind])
        var entry := _kinds[kind] as Dictionary
        return {
            "ok": true,
            "name": kind,
            "description": entry.get("doc", ""),
            "inputSchema": entry.get("inputSchema", {}),
            "handler": entry.get("handler", ""),
            "file": entry.get("file", ""),
            "source": _source,
        }
    var start: Array = []
    var lines: Dictionary = {}
    for kind: String in _kinds:
        var entry := _kinds[kind] as Dictionary
        if bool(entry.get("start", false)):
            start.append({"name": kind, "description": entry.get("brief", ""), "inputSchema": entry.get("inputSchema", {})})
        else:
            lines[kind] = entry.get("brief", "")
    return {
        "ok": true,
        "start": start,
        "batch": BATCH,
        "steps": lines,
        "count": _kinds.size(),
        "whole": WHOLE,
        "source": _source,
    }


## The refusal of *step* before the table runs it, or {} when it may run: a
## step with no kind the table knows, or whose kind's argument is the wrong
## shape. With no catalogue to check against every step runs, as it did
## before the door could check, and the table warns of what it does not know.
func refusal(step: Dictionary) -> Dictionary:
    if step.is_empty() or not _has_kinds():
        return {}
    var kind := ""
    for known: String in _kinds:
        if step.has(known):
            kind = known
            break
    if kind.is_empty():
        return _unknown(step.keys())
    if DOOR_KINDS.has(kind):
        # The door acts on a true one before it gets here, so one that arrives
        # is a value it did not act on, and the table has no branch for it.
        if bool(step[kind]):
            return {}
        return {
            "ok": false,
            "error": "`%s` takes true, and this one is %s" % [kind, JSON.stringify(step[kind])],
            "help": HELP + ' {"steps": "%s"} describes it.' % kind,
        }
    var schema := (_kinds[kind] as Dictionary).get("inputSchema", {}) as Dictionary
    var wanted := String(((schema.get("properties", {}) as Dictionary).get(kind, {}) as Dictionary).get("type", ""))
    if wanted.is_empty() or (SHAPES[wanted] as Array).has(typeof(step[kind])):
        return {}
    return {
        "ok": false,
        "error": "`%s` takes %s, and this one is %s" % [kind, SHAPE_WORDS[wanted], _word_for(step[kind])],
        "help": HELP + ' {"steps": "%s"} describes it.' % kind,
    }


## Up to `CLOSEST_COUNT` kinds most like *guess*, the most alike first.
func closest(guess: String) -> Array:
    if not _has_kinds():
        return []
    var scored: Array = []
    for kind: String in _kinds:
        var alike := guess.to_lower().similarity(kind)
        if alike >= CLOSE_ENOUGH:
            scored.append([alike, kind])
    scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
    return scored.slice(0, CLOSEST_COUNT).map(func(one: Array) -> String: return one[1])


## The refusal of a step whose keys, *guesses*, name no kind.
func _unknown(guesses: Array) -> Dictionary:
    var named: Array = []
    for guess: Variant in guesses:
        for kind: String in closest(String(guess)):
            if not named.has(kind):
                named.append(kind)
    var said := ", ".join(guesses.map(func(one: Variant) -> String: return "'%s'" % String(one)))
    var help := HELP
    if not named.is_empty():
        help += " The kinds closest to %s are %s." % [said, ", ".join(named)]
    return {"ok": false, "error": "no step kind called %s" % said, "help": help, "closest": named}


## The lines of *kinds* that more than one kind carries, each by the kinds
## that carry it, or {} when every kind has its own. It is the line the list
## gives that is compared, since that is what an agent chooses a kind by.
static func _sharing(kinds: Dictionary) -> Dictionary:
    var by_description: Dictionary = {}
    for kind: String in kinds:
        var description := String((kinds[kind] as Dictionary).get("brief", ""))
        if not by_description.has(description):
            by_description[description] = []
        (by_description[description] as Array).append(kind)
    var shared: Dictionary = {}
    for description: String in by_description:
        if (by_description[description] as Array).size() > 1:
            shared[description] = by_description[description]
    return shared


## What *value* is called in JSON, for a refusal.
static func _word_for(value: Variant) -> String:
    match typeof(value):
        TYPE_DICTIONARY:
            return "an object"
        TYPE_ARRAY:
            return "an array"
        TYPE_STRING:
            return "a string"
        TYPE_INT, TYPE_FLOAT:
            return "a number"
        TYPE_BOOL:
            return "a boolean"
    return "null"


## Whether the catalogue is loaded, loading it the first time.
func _has_kinds() -> bool:
    if not _loaded:
        _loaded = true
        _load()
    return not _kinds.is_empty()


## Fills `_kinds` from the packed file, or from the script in a checkout, or
## says in `_why` that neither was there.
func _load() -> void:
    _why = ""
    var parsed: Variant = null
    if FileAccess.file_exists(_packed):
        # A JSON of its own rather than `parse_string`, which pushes an engine
        # error that would land in the answer's `errors` besides `_why`.
        var json := JSON.new()
        if json.parse(FileAccess.get_file_as_string(_packed)) == OK:
            parsed = json.data
        else:
            _why = "the packed step catalogue did not parse, %s" % json.get_error_message()
        _source = "packed"
    else:
        parsed = _from_checkout()
        _source = "checkout"
    if not (parsed is Array):
        if _why.is_empty():
            _why = "this Sara carries no step catalogue, and %s did not parse" % _source
        return
    for entry: Variant in parsed as Array:
        if entry is Dictionary and (entry as Dictionary).has("step"):
            # Assigning an existing key keeps its place, so the list stays in
            # the table's order and the last branch describes the kind.
            _kinds[String((entry as Dictionary)["step"])] = entry
    _kinds.merge(DOOR_KINDS)
    var shared := _sharing(_kinds)
    if not shared.is_empty():
        var named: Array = []
        for description: String in shared:
            named.append("%s (%s)" % [" and ".join(shared[description] as Array), description.left(60)])
        _why = "the step catalogue gives one line to more than one kind, %s" % ", ".join(named)
        _kinds = {}


## What `sara_steps.py --json` prints in this checkout, parsed, or null with
## `_why` said.
func _from_checkout() -> Variant:
    var script := ProjectSettings.globalize_path(SCRIPT)
    if script.is_empty() or not FileAccess.file_exists(script):
        _why = "this build carries no step catalogue, packaging/build.sh packs one"
        return null
    for python in PYTHONS:
        var printed: Array = []
        if OS.execute(python, [script, "--json"], printed) == 0 and not printed.is_empty():
            return JSON.parse_string(String(printed[0]))
    _why = "no Python ran %s, which a checkout's catalogue is read by" % SCRIPT
    return null
