## The door answers `{"steps": true}` with the step kinds, so an agent holding
## a build and nothing else learns what it can send, and every request it
## cannot run answers help naming that request, so the agent finds it from its
## first mistake.
##
## The answer fits a small model's context: the kinds a painting needs first
## whole, every other kind by its line, under `BUDGET` characters. One answer
## of 43,030 characters was over a 32,000 character context before the first stroke.
##
## The door is opened over TCP in this process, the way `test_door_attach.gd`
## opens it, and in a checkout it reads the catalogue from the source through
## `scripts/sara_steps.py`. The packed copy a build carries is written here to
## a scratch file of the suite's own. `scripts/test_door_guide.py` asks an
## exported build the same over `curl` and compares it with the script.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const DoorCatalogue := preload("res://harness/door/sa_door_catalogue.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

## The most the list answer may be, compact. A logo painting counted 10,922 through
## the door for its whole session, so this, the logo and three whole
## descriptions at the largest, 3,200 each, stay under 32,000. The
## list grows with the step table and the budget with it, and 11,475, the
## text and font steps listed, keeps the sum at 31,997, the last room under
## 32,000. The table past that is over a small model's context, and a kind is
## listed then only once the list is cut.
const BUDGET: int = 11475
## The longest line a kind is listed by, `LINE_MAX` in `scripts/sara_steps.py`.
const LINE_MAX: int = 40
## The kinds a painting needs first, `START` in `scripts/sara_steps.py`.
const START: Array = ["path", "stroke", "colour", "layer", "tool", "shot", "state", "undo", "message", "save", "look", "quit"]

static var scratch_known: String = SaDataRoot.path("s1-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("s1-door/door.port")
static var scratch_packed: String = SaDataRoot.path("s1-door/step_catalogue.json")


## The executor's place, with every step kept rather than run.
class RecordingTable:
    extends StepTable

    var ran: Array = []

    func _init() -> void:
        super(CaptureRun.new(SaDataRoot.path("s1-door-run")))

    func run(step: Dictionary) -> void:
        ran.append(step)

    func state() -> Dictionary:
        return {"steps_run": ran.size()}


var _door: AgentDoor = null
var _table: RecordingTable = null
var _run: CaptureRun = null
var _runner: DoorRunner = null


func before_each() -> void:
    _door = AgentDoor.new(scratch_known)
    _table = RecordingTable.new()
    _run = CaptureRun.new(SaDataRoot.path("s1-door-run"))
    _runner = DoorRunner.new(_door, _table, _run, DoorRunner.ROUNDS, scratch_known)


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


func test_the_door_lists_the_start_kinds_as_mcp_tools_and_the_rest_by_their_lines() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 7, "steps": true})
    assert_true(bool(answer.get("ok", false)), "The catalogue is answered: %s" % String(JSON.stringify(answer)).left(300))
    assert_eq(answer.get("id"), 7.0, "under the request's id")
    assert_eq(answer.get("source"), "checkout", "and a checkout reads it from the source")
    var start := answer.get("start", []) as Array
    var lines := answer.get("steps", {}) as Dictionary
    var names: Array = start.map(func(one: Dictionary) -> String: return one.get("name", ""))
    var wanted := START.duplicate()
    wanted.sort()
    var got := names.duplicate()
    got.sort()
    assert_eq(got, wanted, "The start kinds are the ones a painting needs first")
    assert_eq(names.back(), "quit", "in the table's order, the door's own last")
    var stroke: Dictionary = start[names.find("stroke")]
    var fields := stroke.keys()
    fields.sort()
    assert_eq(fields, ["description", "inputSchema", "name"], "Each start kind is the three fields of an MCP tool")
    assert_eq(stroke.get("description"), "Paints one stroke", "its line")
    for kind: String in ["wait", "zoom", "fit", "import"]:
        assert_true(lines.has(kind), "The rest names %s" % kind)
    assert_eq(lines.get("zoom"), "Zooms the main canvas", "by its line alone")
    assert_eq(start.size() + lines.size(), int(answer.get("count", 0)), "and counts both")
    assert_true(String(answer.get("batch", "")).contains("array of answers"), "The batch is said beside the start list")
    assert_true(String(answer.get("whole", "")).contains('{"steps": "<name>"}'), "and the request for one kind whole")
    assert_false(answer.has("state"), "The answer carries no dump")
    assert_eq(_table.ran, [], "and nothing went through the table")
    client.disconnect_from_host()


func test_the_list_fits_the_budget_and_names_every_kind_of_the_table_once() -> void:
    var answer := DoorCatalogue.new().answer(true)
    var size := JSON.stringify(answer).length()
    assert_true(size < BUDGET, "The list answer is %d characters compact, under %d" % [size, BUDGET])
    var listed: Array = (answer.get("start", []) as Array).map(func(one: Dictionary) -> String: return one["name"])
    listed.append_array((answer.get("steps", {}) as Dictionary).keys())
    var table := FileAccess.get_file_as_string("res://harness/sa_step_table.gd")
    var branch := RegEx.create_from_string('(?m)^\\s*(?:el)?if step\\.has\\("([a-z_0-9]+)"\\)')
    var kinds: Array = ["quit"]
    for found: RegExMatch in branch.search_all(table):
        if not kinds.has(found.get_string(1)):
            kinds.append(found.get_string(1))
    var missing := kinds.filter(func(kind: String) -> bool: return listed.count(kind) != 1)
    assert_eq(missing, [], "Every kind of the table is listed once, in start or in steps, of %d" % kinds.size())
    assert_eq(listed.size(), kinds.size(), "and nothing else is")


func test_every_start_kind_says_what_its_argument_holds() -> void:
    for one: Dictionary in DoorCatalogue.new().answer(true).get("start", []) as Array:
        var kind := String(one["name"])
        var schema := one["inputSchema"] as Dictionary
        assert_eq(schema.get("required"), [kind], "%s requires its own key" % kind)
        var value := (schema.get("properties", {}) as Dictionary).get(kind, {}) as Dictionary
        var keys := (value.get("properties", {}) as Dictionary).keys()
        # A value with keys names at least one, and a value that is a string, a
        # number or true, as `shot`, `undo` and `quit` take, has no key to name
        # and says what it is instead.
        assert_true(
            not keys.is_empty() or not String(value.get("description", "")).is_empty(),
            "%s names a key of its argument or describes it: %s" % [kind, JSON.stringify(value)]
        )
        if String(value.get("type", "")) == "object":
            assert_false(keys.is_empty(), "%s takes an object and names its keys" % kind)


func test_one_kind_by_name_answers_its_whole_doc_and_an_unknown_one_is_refused() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var zoom := _ask(client, {"id": 1, "steps": "zoom"})
    assert_true(bool(zoom.get("ok", false)), "One kind is answered")
    assert_eq(zoom.get("name"), "zoom", "by its name")
    assert_true(String(zoom.get("description", "")).count("\n") > 0, "with the whole doc, not its first sentence")
    var unknown := _ask(client, {"id": 2, "steps": "no_such_kind"})
    assert_false(bool(unknown.get("ok", true)), "A kind the table has not got is refused")
    assert_true(String(unknown.get("error", "")).contains("no_such_kind"), "by name")
    client.disconnect_from_host()


## The help every refusal carries names the catalogue request.
func _names_the_catalogue(answer: Dictionary, what: String) -> void:
    var help := String(answer.get("help", ""))
    assert_true(help.contains('{"steps": true}'), "%s answers help naming the catalogue: %s" % [what, answer])


func test_every_request_the_door_cannot_run_answers_help_naming_the_catalogue() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var token := _runner.token()
    var frame := _runner.frame

    client.put_data(Fixtures.DoorHttp.request("zoom to two", token))
    var not_json := Fixtures.DoorHttp.wait(client, frame)
    assert_eq(not_json.get("status"), 400, "A body that is not JSON is a 400")
    _names_the_catalogue(not_json.get("body", {}) as Dictionary, "A body that is not JSON")

    var no_kind := _ask(client, {"id": 3, "hello": "sara"})
    assert_false(bool(no_kind.get("ok", true)), "A step with no known key is refused")
    _names_the_catalogue(no_kind, "A step with no known key")

    var misspelled := _ask(client, {"id": 4, "strok": {"from": [0, 0], "to": [10, 10]}})
    assert_false(bool(misspelled.get("ok", true)), "A misspelled kind is refused")
    _names_the_catalogue(misspelled, "A misspelled kind")
    assert_eq((misspelled.get("closest", []) as Array).front(), "stroke", "and the kind meant comes first")
    assert_true(String(misspelled.get("help", "")).contains("stroke"), "in the help as well")

    var wrong_shape := _ask(client, {"id": 5, "zoom": "big"})
    assert_false(bool(wrong_shape.get("ok", true)), "A kind with its argument the wrong shape is refused")
    assert_true(String(wrong_shape.get("error", "")).contains("a number"), "saying the shape it takes")
    _names_the_catalogue(wrong_shape, "A wrong argument")
    assert_true(String(wrong_shape.get("help", "")).contains('{"steps": "zoom"}'), "and the request that describes it")
    assert_eq(_table.ran, [], "None of them reached the table")

    var fine := _ask(client, {"id": 6, "zoom": 2})
    assert_true(bool(fine.get("ok", false)), "A whole number is a number")
    assert_false(fine.has("help"), "and a step that runs carries no help")
    assert_eq(_table.ran, [{"zoom": 2.0}], "and it ran")
    client.disconnect_from_host()


func test_a_get_on_the_root_answers_help_and_a_401_says_where_the_token_is() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var frame := _runner.frame
    var client := _runner.connect_client()
    var token := _runner.token()
    var head := "GET / HTTP/1.1\r\nHost: sara\r\nAuthorization: Bearer %s\r\n\r\n" % token
    client.put_data(head.to_utf8_buffer())
    var root := Fixtures.DoorHttp.wait(client, frame)
    assert_eq(root.get("status"), 200, "A GET on the root is answered")
    _names_the_catalogue(root.get("body", {}) as Dictionary, "A GET on the root")
    client.disconnect_from_host()

    var stranger := _runner.connect_client()
    stranger.put_data(Fixtures.DoorHttp.request(JSON.stringify({"steps": true}), "not-the-token"))
    var refused := Fixtures.DoorHttp.wait(stranger, frame)
    assert_eq(refused.get("status"), 401, "A request without the token keeps its 401")
    var body := refused.get("body", {}) as Dictionary
    assert_eq(body.get("token_file"), scratch_port_file, "and names the file the token is in")
    assert_false(body.has("help"), "and nothing about the steps")
    assert_false(body.has("steps"), "nor the steps themselves")
    stranger.disconnect_from_host()


func test_a_packed_catalogue_is_read_in_the_tables_order_with_the_last_branch_describing() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_packed.get_base_dir())
    var entries := [
        {"step": "import", "argument": "String", "brief": "Opens the narrow branch", "doc": "The narrow branch."},
        {"step": "zoom", "argument": "float", "brief": "Zooms", "doc": "Zooms.\n\nAll of it."},
        {"step": "import", "argument": "String", "brief": "Imports a file", "doc": "Imports a file."},
    ]
    var file := FileAccess.open(scratch_packed, FileAccess.WRITE)
    file.store_string(JSON.stringify(entries))
    file.close()
    var catalogue := DoorCatalogue.new(scratch_packed)
    var listed := catalogue.answer(true)
    assert_eq(listed.get("source"), "packed", "A build reads the packed copy")
    assert_eq(
        listed.get("steps"),
        {"import": "Imports a file", "zoom": "Zooms"},
        "every kind once by its line, the last branch describing a repeated one"
    )
    assert_eq((listed.get("steps") as Dictionary).keys(), ["import", "zoom"], "in the table's order")
    assert_eq(
        (listed.get("start") as Array).map(func(one: Dictionary) -> Array: return [one["name"], one["description"]]),
        [["quit", DoorCatalogue.DOOR_KINDS["quit"]["brief"]]],
        "and the door's own quit, a start kind, after the table's"
    )
    assert_eq(catalogue.answer("zoom").get("description"), "Zooms.\n\nAll of it.", "One kind answers its whole doc")
    DirAccess.remove_absolute(scratch_packed)


func test_a_packed_file_that_does_not_parse_is_refused_with_a_reason() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_packed.get_base_dir())
    var file := FileAccess.open(scratch_packed, FileAccess.WRITE)
    file.store_string("not json")
    file.close()
    var answer := DoorCatalogue.new(scratch_packed).answer(true)
    assert_false(bool(answer.get("ok", true)), "A broken packed catalogue is not an empty list")
    assert_true(String(answer.get("error", "")).contains("packed"), "and says which copy failed")
    DirAccess.remove_absolute(scratch_packed)


## The kinds the door lists from a checkout's catalogue, each as its `name` and
## its line as `description`, the start kinds first.
func _listed_from_the_checkout() -> Array:
    var answer := DoorCatalogue.new().answer(true)
    var listed: Array = []
    for one: Dictionary in answer.get("start", []) as Array:
        listed.append({"name": one["name"], "description": one["description"]})
    var lines := answer.get("steps", {}) as Dictionary
    for kind: String in lines:
        listed.append({"name": kind, "description": lines[kind]})
    return listed


func test_no_two_steps_share_a_line_and_each_opens_on_a_capital_within_the_length() -> void:
    var listed := _listed_from_the_checkout()
    var answer := DoorCatalogue.new().answer(true)
    assert_true(bool(answer.get("ok", false)), "No two kinds read the same, or the list is refused: %s" % answer.get("error", ""))
    assert_true(listed.size() > 100, "The checkout's catalogue is read, %d kinds" % listed.size())
    var mid_sentence: Array = []
    var too_long: Array = []
    for kind: Dictionary in listed:
        var description := String(kind["description"])
        # A capital letter, so a line says what the step does before it shows
        # the step's example, and never begins on a lower case word, the tail of
        # a sentence whose head was lost, as the TIFF export's step once did.
        var first := description.left(1)
        if first == "" or first != first.to_upper() or first == first.to_lower():
            mid_sentence.append(String(kind["name"]))
        if description.length() > LINE_MAX:
            too_long.append("%s (%d)" % [kind["name"], description.length()])
    assert_eq(mid_sentence, [], "Every line opens on a capital letter, no kind begins on its example or a lower case word")
    assert_eq(too_long, [], "and none is over %d characters" % LINE_MAX)


func test_the_kinds_that_shared_a_neighbours_description_each_have_a_line_of_their_own() -> void:
    var described: Dictionary = {}
    for kind: Dictionary in _listed_from_the_checkout():
        described[String(kind["name"])] = String(kind["description"])
    # The groups whose kinds once shared a handler's doc, and so a line.
    var groups := [
        ["ring_predict", "ring_cost", "ring_dump"],
        ["kpp", "preset_import", "krita_import"],
        ["pattern", "preset"],
        ["pressure_curve", "pressure_pad"],
        ["press", "release"],
        ["undo", "redo"],
        ["checker", "fine_checker"],
        ["levels", "curve", "palette"],
    ]
    for group: Array in groups:
        var lines: Array = []
        for kind: String in group:
            assert_true(described.has(kind), "%s is listed" % kind)
            if not lines.has(described.get(kind)):
                lines.append(described.get(kind))
        assert_eq(lines.size(), group.size(), "%s each read their own: %s" % [", ".join(group), lines])


func test_quit_is_listed_with_its_schema_and_a_quit_that_is_not_true_is_refused() -> void:
    var kinds := _listed_from_the_checkout().map(func(one: Dictionary) -> String: return one["name"])
    assert_true(kinds.has("quit"), "The list a session ends by names quit")
    assert_eq(kinds.count("quit"), 1, "once")
    var catalogue := DoorCatalogue.new()
    var quit := catalogue.answer("quit")
    assert_true(bool(quit.get("ok", false)), "and it is described by name")
    assert_eq(
        ((quit.get("inputSchema") as Dictionary)["properties"] as Dictionary)["quit"]["type"], "boolean", "typed as a boolean"
    )
    assert_true(String(quit.get("description", "")).contains("Ends the session"), "saying what it does")
    assert_eq(catalogue.refusal({"quit": true}), {}, "A quit of true is no refusal")
    var refused := catalogue.refusal({"quit": false})
    assert_false(bool(refused.get("ok", true)), "A quit of false is refused, the door having nothing to end")
    assert_true(String(refused.get("error", "")).contains("takes true"), "saying what it takes")
    assert_true(String(refused.get("help", "")).contains('{"steps": "quit"}'), "and the request that describes it")


func test_a_catalogue_with_two_kinds_of_one_line_is_refused_naming_them() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_packed.get_base_dir())
    var entries := [
        {"step": "press", "argument": "any", "brief": "Presses or releases", "doc": "Presses or releases."},
        {"step": "release", "argument": "any", "brief": "Presses or releases", "doc": "Presses or releases."},
        {"step": "zoom", "argument": "float", "brief": "Zooms", "doc": "Zooms."},
    ]
    var file := FileAccess.open(scratch_packed, FileAccess.WRITE)
    file.store_string(JSON.stringify(entries))
    file.close()
    var catalogue := DoorCatalogue.new(scratch_packed)
    var answer := catalogue.answer(true)
    assert_false(bool(answer.get("ok", true)), "Two kinds of one line are not listed")
    var error := String(answer.get("error", ""))
    assert_true(error.contains("press and release"), "the kinds are named: %s" % error)
    assert_true(String(answer.get("help", "")).contains('{"steps": true}'), "and the help stands")
    assert_eq(catalogue.refusal({"zoom": "big"}), {}, "and every step runs as it did before there was a catalogue")
    DirAccess.remove_absolute(scratch_packed)
