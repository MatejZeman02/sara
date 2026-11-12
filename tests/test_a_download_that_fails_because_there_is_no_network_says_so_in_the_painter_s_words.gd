## A download that fails because there is no network says so
## in the painter's words.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every result `failure_line` maps is handed to a download that never starts,
## the failed name lookup first, and each sentence is read for the network's
## words a beginner does not know. The lookup's failure, ended as a request
## ends, still leaves its cause on the log in the old terms.
extends "res://tests/test_framework.gd"

const WeightsDownload = preload("../weights_download.gd")

## The results a download can fail with, the one a machine with no network
## meets first.
const FAILURES: Array[int] = [
    HTTPRequest.RESULT_CANT_RESOLVE,
    HTTPRequest.RESULT_CANT_CONNECT,
    HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
    HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED,
    HTTPRequest.RESULT_TIMEOUT,
    HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN,
    HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR,
    HTTPRequest.RESULT_CONNECTION_ERROR,
    HTTPRequest.RESULT_NO_RESPONSE,
    HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED,
]

## The words of the network a sentence for the painter never holds.
const NETWORK_WORDS: Array[String] = ["server", "name", "certificate"]

## A folder of the system's temporary one, which a failure that never wrote
## leaves as it found it.
var _folder := OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())

var _download: Node = null
var _lines: SaErrorCatcher = null


func before_each() -> void:
    _download = WeightsDownload.new("http://127.0.0.1:9/weights.pth", _folder.path_join("weights.pth"), "", 0)
    _lines = SaErrorCatcher.new()
    OS.add_logger(_lines)


func after_each() -> void:
    OS.remove_logger(_lines)
    _lines = null
    _download.free()
    _download = null


func test_each_failure_says_what_happened_in_the_painter_s_words() -> void:
    for result: int in FAILURES:
        var line: String = _download.failure_line(result)
        # The folder a file failure names is the painter's own, read apart.
        var words := line.replace(_folder, "").to_lower()
        for word: String in NETWORK_WORDS:
            assert_false(words.contains(word), 'Result %d\'s sentence holds no "%s": %s' % [result, word, line])
        assert_true(line.ends_with("Nothing was stored."), "Result %d's sentence keeps that nothing was stored" % result)
        # What happened, what the painter can do about it, and that nothing was stored.
        assert_true(line.split(". ").size() >= 3, "Result %d's sentence says what to do about it: %s" % [result, line])
    var lookup: String = _download.failure_line(HTTPRequest.RESULT_CANT_RESOLVE)
    assert_true(lookup.contains("internet"), "The failed lookup's sentence names the internet: %s" % lookup)
    assert_true(lookup.contains("connection"), "and the connection to check")
    assert_true(lookup.contains("Try again"), "and the button that tries again")
    var written: String = _download.failure_line(HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR)
    assert_true(written.contains(_folder), "A file that could not be written names its folder: %s" % written)
    assert_true(written.contains("disk"), "and says the disk may be full")


func test_a_code_that_is_not_the_file_names_no_server_either() -> void:
    var said: Array[String] = []
    _download.finished.connect(func(_kept: bool, sentence: String) -> void: said.append(sentence))
    _download._on_completed(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
    assert_eq(said.size(), 1, "A 404 ends the download once")
    var line := said[0]
    for word: String in NETWORK_WORDS:
        assert_false(line.to_lower().contains(word), 'The 404\'s sentence holds no "%s": %s' % [word, line])
    assert_true(line.contains("404") and line.contains("Try again"), "and gives the code and the press to try: %s" % line)
    assert_true(line.ends_with("Nothing was stored."), "and keeps that nothing was stored")


func test_the_lookup_s_failure_keeps_the_old_cause_on_the_log() -> void:
    _download._on_completed(HTTPRequest.RESULT_CANT_RESOLVE, 0, PackedStringArray(), PackedByteArray())
    assert_eq(_download.outcome, WeightsDownload.Outcome.FAILED, "The lookup's failure ends the download as failed")
    var found := false
    for line: String in _lines.printed():
        found = found or line.contains("the server's name could not be found")
    assert_true(found, "The log carries the cause in the old terms: %s" % "\n".join(_lines.printed()))
