## File > Save as JPEG XL is a command the menu, the search
## and the door's `command` step find, its words promise a smaller file that an
## older Sara cannot open, and with no codec called `jxl` registered it says why
## and opens no file picker, so nothing is written. The save it starts when the
## module is loaded is held by
## `core/sad-codec/tests/test_file_save_as_jpeg_xl_writes_a_smaller_file_the_painter_asked_for_by_name.gd`.
extends "res://tests/test_framework.gd"

const COMMAND := &"file_save_as_jpeg_xl"

var _flow: SaDocumentFiles = null
var _was_installed: SaCodecRegistry = null
var _was_sink: Callable = Callable()
var _was_announcing: bool = true
var _refused: PackedStringArray = PackedStringArray()


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _was_sink = SaProblems._sink
    _was_announcing = SaProblems.announce
    _refused.clear()
    _flow = SaDocumentFiles.new()


func after_each() -> void:
    _flow.free()
    _flow = null
    SaCodecRegistry.install(_was_installed)
    # A run with no sink before keeps its reports, and a sink that is gone
    # would be called with every one of them.
    if _was_sink.is_valid():
        SaProblems.attach_sink(_was_sink)
    else:
        SaProblems.detach_sink()
    SaProblems.announce = _was_announcing


func _heard(line: String, kind: SaProblems.Kind) -> void:
    if kind == SaProblems.Kind.REFUSAL:
        _refused.append(line)


func test_the_command_is_a_file_row_that_promises_a_smaller_file_an_older_sara_cannot_open() -> void:
    var found: SaCommandDescriptor = null
    for command: SaCommandDescriptor in SaMenuCommands.new(Callable(), Callable(), Callable(), Callable()).commands():
        if command.id == COMMAND:
            found = command
    assert_not_null(found, "Save as JPEG XL is a command")
    if found == null:
        return
    assert_eq(found.category, &"file", "under File")
    assert_true(found.sentence.contains("smaller"), "its tip says the file is smaller")
    assert_false(found.sentence.contains("twice"), "and never twice as small")
    assert_true(found.sentence.contains("older Sara cannot open"), "and that an older Sara cannot open it")


func test_with_no_codec_registered_it_says_why_and_opens_no_picker() -> void:
    var bare := SaCodecRegistry.new()
    SaCodecRegistry.install(bare)
    SaProblems.announce = false
    SaProblems.attach_sink(_heard)
    # Attaching hands over every refusal an earlier suite left kept, so only
    # what the command says from here on is counted.
    _refused.clear()
    var pickers := SaFilePicker._open.size()
    _flow.run_action(COMMAND)
    assert_eq(SaFilePicker._open.size(), pickers, "No file picker opens, so nothing can be written")
    assert_eq(_refused.size(), 1, "The painter is told why")
    if _refused.size() == 1:
        assert_true(_refused[0].contains("JPEG XL module"), "naming the module it needs")
        assert_true(_refused[0].contains("Nothing was saved"), "and that nothing was saved")
