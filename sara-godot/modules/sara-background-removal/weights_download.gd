## One download of the model's weights: the request, the bytes as they arrive,
## the hash checked at the end, and the file kept only when it matches.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A node, because Godot's `HTTPRequest` is one and has to stand in the tree to
## run. The bytes go to a `.part` file beside the one kept, never into memory,
## and the `.part` file is renamed into place only after its SHA-256 matched,
## so a half file, a wrong file or a page of HTML is never found where the
## command looks. Whatever ends the download, the `.part` file goes.
extends Node

## The end of a download, *kept* true when the file is in place, and *line* the
## sentence the dialog shows for it.
signal finished(kept: bool, line: String)

## How a download ended.
enum Outcome { RUNNING, KEPT, MISMATCH, FAILED, CANCELLED }

## The most bytes read from the connection in one frame. The request runs
## without a thread of its own, polled by the engine once a frame in
## non-blocking mode, so a read takes what has arrived and never waits for
## more, and the bar moves with every frame that brought bytes. A thread would
## sit in a blocking read on a line that stalls, and Cancel and the timeout
## wait for that thread on the main one, which froze the window until the
## operating system gave up on the socket. A frame's read caps the speed, and
## 1 MiB lets the socket's own buffer set it instead: at 60 frames a second the
## 4.7 MB file came from the Google Drive link in about 2.0 s, the thread's
## 1.7 s, and from a server on the same machine in 0.15 s, where 256 KiB took
## 0.35 s.
const CHUNK_BYTES := 1048576

## The seconds a download may take before it is called failed. Four times the
## thirty seconds a download is meant to take, so a slow line still finishes
## and a dead one ends.
const TIMEOUT_SECONDS := 120.0

## The redirects followed. Google Drive's link redirects once or twice.
const REDIRECTS := 8

## Where the bytes come from, the file they are kept as, the SHA-256 they must
## have and the size the progress is measured against when the server sends
## none.
var source: String = ""
var target: String = ""
var sha256: String = ""
var expected_bytes: int = 0

## How it ended, and the share of the bytes read, 0 to 1, as last measured.
var outcome: Outcome = Outcome.RUNNING
var progress: float = 0.0
## The largest share measured before the end, which a suite reads to know the
## bar moved while the bytes arrived.
var progress_before_end: float = 0.0

## The seconds from the request to the end, which the log line reports.
var seconds: float = 0.0

var _request: HTTPRequest = null
var _started_msec: int = 0


## *limit* is the seconds the download may take, TIMEOUT_SECONDS unless a
## suite asks for a stall to end sooner.
func _init(from: String, into: String, digest: String, size: int, limit: float = TIMEOUT_SECONDS) -> void:
    name = "WeightsDownload"
    source = from
    target = into
    sha256 = digest.to_lower()
    expected_bytes = size
    _request = HTTPRequest.new()
    _request.name = "Request"
    _request.use_threads = false
    _request.download_chunk_size = CHUNK_BYTES
    _request.max_redirects = REDIRECTS
    _request.timeout = limit
    _request.download_file = part_path()
    _request.request_completed.connect(_on_completed)
    add_child(_request)


## The file the bytes are written to until the hash is checked.
func part_path() -> String:
    return target + ".part"


## Sends the request. Nothing is asked of the network before this.
func start() -> void:
    DirAccess.make_dir_recursive_absolute(target.get_base_dir())
    _started_msec = Time.get_ticks_msec()
    var asked := _request.request(source)
    if asked != OK:
        _end(Outcome.FAILED, tr("The download could not start. Nothing was stored."))


## Stops the download and keeps nothing.
func cancel() -> void:
    if outcome != Outcome.RUNNING:
        return
    _request.cancel_request()
    _end(Outcome.CANCELLED, tr("The download was cancelled. Nothing was stored."))


func _process(_delta: float) -> void:
    if outcome != Outcome.RUNNING:
        return
    var total := _request.get_body_size()
    if total <= 0:
        total = expected_bytes
    if total > 0:
        progress = clampf(float(_request.get_downloaded_bytes()) / float(total), 0.0, 1.0)
        progress_before_end = maxf(progress_before_end, progress)


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
    if outcome != Outcome.RUNNING:
        return
    if result != HTTPRequest.RESULT_SUCCESS:
        print("Select Subject: the weights' download failed, %s, HTTPRequest result %d" % [failure_cause(result), result])
        _end(Outcome.FAILED, failure_line(result))
        return
    if code != 200:
        _end(
            Outcome.FAILED,
            (
                tr("The download's link answered with the code %s and not the file. Press Try again later. Nothing was stored.")
                % str(code)
            )
        )
        return
    var found := FileAccess.get_sha256(part_path())
    if found != sha256:
        _end(Outcome.MISMATCH, tr("The download did not match what Sara expects, its SHA-256 is %s. Nothing was stored.") % found)
        return
    if FileAccess.file_exists(target):
        DirAccess.remove_absolute(target)
    var moved := DirAccess.rename_absolute(part_path(), target)
    if moved != OK:
        _end(Outcome.FAILED, tr("The file could not be kept in the module's folder. Nothing was stored."))
        return
    progress = 1.0
    print("Select Subject: kept %d bytes with SHA-256 %s" % [FileAccess.get_file_as_bytes(target).size(), found])
    _end(Outcome.KEPT, tr("The weights are in place."))


func _end(how: Outcome, line: String) -> void:
    outcome = how
    seconds = (Time.get_ticks_msec() - _started_msec) / 1000.0
    # One line on the log for each download, how it ended and how long it took,
    # which is what a check of the thirty seconds a download should take reads.
    var kept := target if how == Outcome.KEPT else "nothing kept"
    var ended: String = Outcome.keys()[how]
    print("Select Subject: the weights' download from %s ended %s after %.2f s, %s" % [source, ended, seconds, kept])
    if how != Outcome.KEPT and FileAccess.file_exists(part_path()):
        DirAccess.remove_absolute(part_path())
    finished.emit(how == Outcome.KEPT, line)


## The sentence for an `HTTPRequest` result that is not a success, each one
## whole so a translation never has a phrase dropped into it. Each says what
## happened and what the painter can do about it, in words a painter who never
## met a network term reads, and keeps that nothing was stored. A machine with
## no network fails the name lookup, so that sentence is the one met most. The
## cause in the network's own terms goes to the log, `failure_cause`.
func failure_line(result: int) -> String:
    match result:
        HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
            return tr(
                # gdlint:ignore=max-line-length
                "Sara could not reach the internet, the computer may be offline. Check the connection and press Try again. Nothing was stored."
            )
        HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
            return tr(
                # gdlint:ignore=max-line-length
                "Sara could not open a safe connection for the download. The computer's date may be wrong, or the network may be blocking it. Check the date and press Try again. Nothing was stored."
            )
        HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
            return tr(
                # gdlint:ignore=max-line-length
                "The download's link kept leading elsewhere and never reached the file. Press Try again later. Nothing was stored."
            )
        HTTPRequest.RESULT_TIMEOUT:
            return tr(
                # gdlint:ignore=max-line-length
                "The connection is too slow, the download did not finish in time. Press Try again, perhaps on a faster network. Nothing was stored."
            )
        HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
            return (
                tr(
                    # gdlint:ignore=max-line-length
                    "The file could not be written in %s. The disk may be full, or the folder may not be writable. Nothing was stored."
                )
                % target.get_base_dir()
            )
    return tr("The connection broke before the download finished. Check the connection and press Try again. Nothing was stored.")


## The cause of a failed result in the network's own terms, which the log
## keeps for the painter who reports the failure, never translated.
static func failure_cause(result: int) -> String:
    match result:
        HTTPRequest.RESULT_CANT_CONNECT:
            return "the server could not be reached"
        HTTPRequest.RESULT_CANT_RESOLVE:
            return "the server's name could not be found"
        HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
            return "the secure connection could not be made"
        HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
            return "the link redirected too many times"
        HTTPRequest.RESULT_TIMEOUT:
            return "the server took too long"
        HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
            return "the file could not be written"
    return "the connection broke or the server did not answer"
