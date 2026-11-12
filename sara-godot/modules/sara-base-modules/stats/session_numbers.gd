## The Stats docker's session numbers, read off the session log: how many
## strokes the session holds, how many a minute, the mean pressure of the
## readings inside them, and where the painting time went, by tool and by layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The session numbers come from the recorder's log**: strokes per minute,
## average pressure, time per layer and the share of the session spent on each
## tool, none of which anything else in Sara keeps.
## The log is the stroke recorder's, and the recorder counts its
## strokes as it writes them, in `SaStrokeRecorder.tally`, by the rule the
## training script reads a stroke by. This part reads that count at each run of
## the docker, so the numbers are as old as the line under the switch says,
## like every other number here.
##
## **The time is painting time**, each stroke's press to its release, so a
## pause counts for nothing, and it goes to the tool and the layer the log
## named at the press. The painting time in all comes first,
## then each tool's share of it, the most first, then each layer's time, the
## longest first, each row titled by the tool's name as the toolbox shows it or
## the layer's as the layers docker does. A row is on the page only while there
## is a tool or a layer for it, and a session past [constant MOST_TOOLS] tools
## or [constant MOST_LAYERS] layers folds the rest into the last row.
##
## **Most sessions have no log**, since the recorder runs only under
## `--record-strokes` or `SARA_RECORD_STROKES`. Then one row says so and names
## both, in place of the numbers, so a painter who wants them knows how. The
## recorder opens with the canvas, which the boot builds before the dockers, so
## the row is right from the start, and it is read again at every run.
##
## **Nothing to dispatch**, so [member SaStatsPart.reduction] stays null and the
## service never hears of this part. The log line of each stop carries these
## rows as it carries every row the page shows, a tool's or a layer's name
## among the titles.
extends SaStatsPart

## What the row says while no recorder runs, the flag and the variable filled
## in from `SaStrokeRecorder`, so the sentence names what the code reads.
const NO_LOG := (
    "No session log is being recorded. Start Sara with %s=<folder>, or with %s=<folder> set,"
    + " and the strokes are counted here."
)

## What the stroke rows say on hover: what a stroke is and what the minutes are
## over.
const HOVER := (
    "A stroke is a left button press to its release with ten readings or more,"
    + " as the cursor lead's training reads one. Strokes a minute is over the session so far, pauses included,"
    + " and the pressure is the mean of every reading inside a stroke."
)

## What the time rows say on hover: how the time is counted and whose it is.
const TIME_HOVER := (
    "Painting time runs from each stroke's press to its release, so a pause counts for nothing,"
    + " and goes to the tool in hand and the active layer at the press."
)

## The most tools and layers named, each in a row of its own.
const MOST_TOOLS := 8
const MOST_LAYERS := 12

## The row naming the flag, then the numbers, which the page shows only while
## that row is empty.
var _said: SaPageRow = null
var _strokes: SaPageRow = null
var _rate: SaPageRow = null
var _pressure: SaPageRow = null
var _time: SaPageRow = null

## The rows counting the tools and the layers, whose value is how many of the
## rows after each are in use, and those rows.
var _tool_count: SaPageRow = null
var _tools: Array[SaPageRow] = []
var _layer_count: SaPageRow = null
var _layers: Array[SaPageRow] = []
var _page: SaPage = null


## The sentence naming the flag and the variable that turn the recorder on, in
## English, as the row's value reads it.
static func no_log() -> String:
    return NO_LOG % [SaStrokeRecorder.FLAG, SaStrokeRecorder.ENV_VAR]


## *usec* as the time rows say it: "42.5 s" under a minute, "3 min 12 s" under
## an hour, and "1 h 4 min" from there.
static func duration(usec: int) -> String:
    var seconds := float(usec) / 1e6
    if seconds < 59.95:
        return TranslationServer.translate("%.1f s") % seconds
    var whole := roundi(seconds)
    if whole < 3600:
        return (
            TranslationServer.translate_plural("%d min %d s", "%d min %d s", floori(whole / 60.0))
            % [floori(whole / 60.0), whole % 60]
        )
    return (
        TranslationServer.translate_plural("%d h %d min", "%d h %d min", floori(whole / 3600.0))
        % [floori(whole / 3600.0), floori((whole % 3600) / 60.0)]
    )


## A section of its own: the sentence while there is no log, the numbers while
## there is one.
func declare(page: SaPage) -> void:
    _page = page
    var block := page.section("Session")
    var said := _readout("SessionLog", HOVER)
    said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # No title, so the sentence spans the docker.
    _said = block.custom("", said).named(&"session_log")
    # Written again in a language chosen later, because the docker is built
    # before a language module's catalogue arrives.
    SaOnLanguage.follow(said, func() -> void: _take(SaStrokeRecorder.running))
    _strokes = block.custom("Strokes", _readout("SessionStrokes", HOVER)).named(&"session_strokes")
    _rate = block.custom("Strokes a minute", _readout("SessionStrokeRate", HOVER)).named(&"strokes_a_minute")
    _pressure = block.custom("Mean pressure", _readout("SessionPressure", HOVER)).named(&"mean_pressure")
    _time = block.custom("Painting time", _readout("SessionPaintingTime", TIME_HOVER)).named(&"painting_time")
    _tool_count = block.custom("Tools", _readout("SessionToolCount", TIME_HOVER)).named(&"session_tools")
    _tools = _named_rows(block.custom, "Tool", "session_tool_%d", MOST_TOOLS, _tool_count)
    _layer_count = block.custom("Layers", _readout("SessionLayerCount", TIME_HOVER)).named(&"session_layers")
    _layers = _named_rows(block.custom, "Layer", "session_layer_%d", MOST_LAYERS, _layer_count)
    # By key, because a row holding itself in its own rule is a cycle of one
    # `RefCounted` that nothing frees.
    _said.hides(&"session_log", [no_log()])
    for row: SaPageRow in [_strokes, _rate, _pressure, _time, _tool_count, _layer_count] + _tools + _layers:
        _said.hides(row.key, [""])
    # The page applies its rules itself once it has drawn the rows.
    _take(SaStrokeRecorder.running)


func refresh(_surface: SaSurface) -> void:
    follow(SaStrokeRecorder.running)


## Writes what *recorder* has counted into the rows, or the sentence naming the
## flag while *recorder* is null or records nothing.
func follow(recorder: SaStrokeRecorder) -> void:
    if _said == null:
        return
    _take(recorder)
    if _page != null:
        _page.apply_rules()


## *most* rows made by *custom*, a section's `custom`, keyed by *key_format*
## from 1, each on the page only while *count*'s value reaches it, which is how
## many are in use.
static func _named_rows(custom: Callable, title: String, key_format: String, most: int, count: SaPageRow) -> Array[SaPageRow]:
    var rows: Array[SaPageRow] = []
    for at in most:
        var key := StringName(key_format % (at + 1))
        var made: SaPageRow = custom.call(title, _readout(String(key).to_pascal_case(), TIME_HOVER))
        var row := made.named(key)
        row.value = ""
        count.hides(key, range(at + 1, most + 1))
        rows.append(row)
    return rows


## The rows' values and words for *recorder*, without the page's rules.
func _take(recorder: SaStrokeRecorder) -> void:
    var on := recorder != null and recorder.is_recording()
    _said.value = "" if on else no_log()
    _write(_said, "" if on else TranslationServer.translate(NO_LOG) % [SaStrokeRecorder.FLAG, SaStrokeRecorder.ENV_VAR])
    var strokes: int = recorder.tally.strokes if on else 0
    var rate: float = recorder.strokes_a_minute() if on else 0.0
    var pressure: float = recorder.tally.mean_pressure() if on else 0.0
    _strokes.value = strokes
    _write(_strokes, "%d" % strokes)
    _rate.value = snappedf(rate, 0.1)
    _write(_rate, "%.1f" % rate)
    _pressure.value = snappedf(pressure, 0.01)
    _write(_pressure, "%.2f" % pressure if strokes > 0 else String(TranslationServer.translate("No stroke yet")))
    var painting: int = recorder.tally.painting_usec if on else 0
    _time.value = snappedf(painting / 1e6, 0.1)
    _write(_time, duration(painting))
    var by_tool: Array[Dictionary] = []
    var by_layer: Array[Dictionary] = []
    if on:
        by_tool = recorder.tally.by_tool()
        by_layer = recorder.tally.by_layer()
    _share_out(_tool_count, _tools, by_tool, "%d other tools", true)
    _share_out(_layer_count, _layers, by_layer, "%d other layers", false)


## Writes *spent*, the tally's tools or layers the longest first, into *rows*
## and their number into *count*, each row titled by its name and saying its
## share in per cent when *as_share*, its time otherwise. What *rows* has no
## room for is added up in the last row, titled by *others*.
static func _share_out(
    count: SaPageRow, rows: Array[SaPageRow], spent: Array[Dictionary], others: String, as_share: bool
) -> void:
    var used := mini(spent.size(), rows.size())
    count.value = used
    _write(count, "%d" % spent.size())
    for at in rows.size():
        var row := rows[at]
        if at >= used:
            row.value = ""
            continue
        var title := String(spent[at]["name"])
        var usec: int = spent[at]["usec"]
        var share: float = spent[at]["share"]
        if at == rows.size() - 1 and spent.size() > rows.size():
            title = TranslationServer.translate(others) % (spent.size() - at)
            for rest in range(at + 1, spent.size()):
                usec += int(spent[rest]["usec"])
                share += float(spent[rest]["share"])
        if title.is_empty():
            title = TranslationServer.translate("Not named")
        row.retitle(title, "")
        row.value = snappedf(share * 100.0, 0.1) if as_share else snappedf(usec / 1e6, 0.1)
        _write(row, "%d %%" % roundi(share * 100.0) if as_share else duration(usec))


static func _readout(node_name: String, hover: String) -> Label:
    var shown := SaMake.label(null, node_name)
    shown.mouse_filter = Control.MOUSE_FILTER_PASS
    shown.tooltip_text = TranslationServer.translate(hover)
    return shown


## Writes *words* into the label *row* was declared with, which is there from
## the declaration on, before the page has drawn it.
static func _write(row: SaPageRow, words: String) -> void:
    var shown := row.custom_control as Label
    if shown != null and is_instance_valid(shown):
        shown.text = words
