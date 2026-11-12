## One Sara for the painter: a start that carries files while a Sara runs
## hands them to that Sara, which opens each in a tab and comes to the front,
## and the second start quits before it builds anything.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The way in is loopback TCP everywhere.** The running Sara listens on
## 127.0.0.1 on a port the system picks and writes the port, a fresh token and
## its process id to [constant LOCK_FILE] in the data root, readable by the
## painter alone, as the door's port file is. Windows has no Unix socket the
## engine listens on, and one transport on every platform is one path to test.
## A sender proves it read the lock by sending the token, so another program on
## the machine cannot make Sara open a file.
##
## **A stale lock is taken over.** A crash leaves the file behind. A lock whose
## process no longer runs, or whose port answers nothing, or answers without
## taking the paths, is written over by the start that found it, which then
## opens its files itself as a start with no lock does.
##
## **The lock is taken over while Sara runs, too.** A start with no files
## beside a running Sara is a second window the painter asked for, and it
## leaves the lock with the first but keeps a watch on it, reading it every
## [constant WATCH_MSEC] or so. When the holder is gone it becomes the holder,
## on a port and a token of its own, since it never listened before. Two that
## wake at once both write the lock, each whole through a `.partial` rename,
## and the one whose next reading finds another's token from a live Sara
## stops listening and goes back to watching, so one holder is left. A holder
## reads the lock on the same beat, which is how it learns it lost.
##
## **Who takes part.** The painter's own Sara, `--agent-door` included, since
## that door's known file lives in the painter's folder as the lock does. A run
## with `--settings-dir`, a capture run, or one opened on its own socket or
## port file never looks for another Sara and never takes the lock, so scripts'
## and suites' Saras stay apart from each other and from the painter's.
##
## **Android takes no lock.** The system keeps one instance of an app by
## itself, so there is nothing to guard, and the preset asks for no network
## permission, so every listen would fail with two engine errors and a
## backtrace. The listener there neither listens nor watches.
##
## `SaBoot` calls [method start] before the welcome window or `Main` is built.
## The engine has mapped its own window by then, with the splash colour, and a
## start that hands over quits on that first frame. So `packaging/sara.sh`,
## when a live Sara holds the lock, first runs the binary with `--headless` and
## [constant HAND_OVER_FLAG], which asks [method handed] alone, and starts the
## windowed Sara only when that run says the files did not go. `Main` calls [method serve]
## where it opens the command line's files, so paths that arrive while the
## first Sara still boots wait for it and open after its own.
class_name SaSingleInstance
extends RefCounted

## The lock in the data root.
const LOCK_FILE := "running.json"

## The name the listener goes by under the root, which [method serve] finds.
const LISTENER_NAME := "SaSingleInstance"

const LOOPBACK := "127.0.0.1"
const TOKEN_BYTES := 16

## How long a sender waits for the connection and then for the answer, in
## milliseconds. The answer comes on the running Sara's next frame, which a
## long filter or a file loading can hold for some seconds.
const CONNECT_MSEC := 2000
const ANSWER_MSEC := 10000

## How far apart a running Sara reads the lock, in milliseconds, and the most
## added to each wait at random, so two Saras that started together do not
## read it in the same frame for ever. A reading is one small file, and a
## process check only when the lock is not this Sara's.
const WATCH_MSEC := 2500
const WATCH_JITTER_MSEC := 1000

## How long a listener keeps a connection that has not said its line.
const PEER_USEC := 5000000

## The line a listener answers with once it has the paths.
const ANSWER := "opened"

## The flag of the launch wrapper's windowless run: hand the files over and
## quit, 0 when they went and [constant NOT_HANDED] when this start should open
## its window after all. Godot maps its window before the first script runs,
## so only a run with `--headless` hands over with no window at all.
const HAND_OVER_FLAG := "--hand-over"
const NOT_HANDED := 3

## The flags that put a run apart from the painter's Sara.
const APART_FLAGS: Array[String] = ["--capture", "--capture=", "--agent-socket=", "--agent-port-file="]


## Whether a start with *args* takes part, looking for a running Sara and
## taking the lock. The data root moved by `--settings-dir` answers no, as do
## the flags in [constant APART_FLAGS].
static func wanted(args: PackedStringArray, moved: bool = SaDataRoot.moved()) -> bool:
    if moved:
        return false
    for arg: String in args:
        for flag: String in APART_FLAGS:
            if arg == flag and not flag.ends_with("="):
                return false
            # The door's flags only with a value, as `SaBoot.capture_requested`
            # reads them, since an empty one opens no door.
            var least := flag.length() + (1 if flag.begins_with("--agent") else 0)
            if flag.ends_with("=") and arg.begins_with(flag) and arg.length() >= least:
                return false
    return true


## The boot's one call. True when *paths* were handed to a running Sara and
## this start should quit. Otherwise this start takes the lock when it takes
## part, and goes on with its boot.
static func start(
    args: PackedStringArray, paths: PackedStringArray, tree: SceneTree, lock: String = SaDataRoot.path(LOCK_FILE)
) -> bool:
    if not wanted(args):
        return false
    if handed(args, paths, lock):
        return true
    # A start beside a running Sara that handed nothing is a second window the
    # painter asked for, and the lock stays with the first until it closes.
    var beside := SaProcess.another_runs(int(read_lock(lock).get("pid", 0)))
    tree.root.add_child.call_deferred(Listener.new(lock, not beside))
    return false


## Whether *paths* went to the running Sara the lock names. What a start asks
## first, and all the launch wrapper's windowless run with [constant
## HAND_OVER_FLAG] asks.
static func handed(args: PackedStringArray, paths: PackedStringArray, lock: String = SaDataRoot.path(LOCK_FILE)) -> bool:
    var held := read_lock(lock)
    var pid := int(held.get("pid", 0))
    if paths.is_empty() or not wanted(args) or not SaProcess.another_runs(pid):
        return false
    if hand_over(int(held.get("port", 0)), str(held.get("token", "")), absolute(paths)):
        print("Sara: handed %d file(s) to the Sara already running, process %d." % [paths.size(), pid])
        return true
    print("Sara: the Sara named in %s did not answer, so this one opens the file(s) itself." % lock)
    # Gone quiet, so whoever starts next takes the lock over.
    DirAccess.remove_absolute(lock)
    return false


## What `Main` calls once its window can take a document: opens *paths*, the
## command line's, through *open*, then whatever arrived while it booted, and
## hands *open* to the listener for every later start.
static func serve(tree: SceneTree, open: Callable, paths: PackedStringArray) -> void:
    for path in paths:
        open.call(path)
    var listener := tree.root.get_node_or_null(LISTENER_NAME) as Listener
    if listener != null:
        listener.serve(open)


## The JSON object in *lock*, or an empty one.
static func read_lock(lock: String) -> Dictionary:
    if not FileAccess.file_exists(lock):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(lock))
    return parsed as Dictionary if parsed is Dictionary else {}


## *paths* with a relative one read against the folder this start runs in,
## which the running Sara does not share.
static func absolute(paths: PackedStringArray) -> PackedStringArray:
    var here := DirAccess.open(".")
    var out := PackedStringArray()
    for path in paths:
        out.append(here.get_current_dir().path_join(path).simplify_path() if path.is_relative_path() and here != null else path)
    return out


## Sends *paths* with *token* to the Sara listening on *port* and waits for
## its answer. False when nothing listens, or nothing answers in time, and then
## nothing was handed over that the running Sara will open.
static func hand_over(port: int, token: String, paths: PackedStringArray) -> bool:
    if port <= 0 or token.is_empty():
        return false
    var peer := StreamPeerTCP.new()
    if peer.connect_to_host(LOOPBACK, port) != OK:
        return false
    var started := Time.get_ticks_msec()
    while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - started < CONNECT_MSEC:
        OS.delay_msec(10)
        peer.poll()
    if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        return false
    peer.put_data((JSON.stringify({"token": token, "paths": Array(paths)}) + "\n").to_utf8_buffer())
    var said := ""
    started = Time.get_ticks_msec()
    while not said.contains("\n") and Time.get_ticks_msec() - started < ANSWER_MSEC:
        OS.delay_msec(10)
        peer.poll()
        if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() == 0:
            break
        var waiting := peer.get_available_bytes()
        if waiting > 0:
            said += peer.get_utf8_string(waiting)
    peer.disconnect_from_host()
    return said.strip_edges() == ANSWER


## The running Sara's half: holds the lock and the port, takes the paths a
## later start sends, and opens them once `Main` has said how. In a Sara that
## found another holding the lock it listens on nothing and watches the lock
## until that one is gone.
class Listener:
    extends Node

    var _server := TCPServer.new()
    var _token := ""
    var _lock := ""
    ## Each connection with what it has said so far and when it came.
    var _peers: Array[Dictionary] = []
    ## Paths that came before `Main` could open them.
    var _pending := PackedStringArray()
    var _open := Callable()
    ## When the lock is read next, in the engine's milliseconds.
    var _next_watch := 0
    ## Whether a failed listen was said once, so a watch that fails again
    ## every few seconds says nothing more.
    var _warned := false
    ## Whether the system keeps one instance by itself, so this one never
    ## listens nor watches and only passes paths on to `Main`.
    var _system_keeps_one := false

    ## Takes the lock at once when *hold*, else only watches it, and on
    ## Android, the *platform* a suite can name, does neither.
    func _init(lock: String, hold: bool, platform: String = OS.get_name()) -> void:
        name = LISTENER_NAME
        _lock = lock
        _system_keeps_one = platform == "Android"
        if _system_keeps_one:
            return
        if hold:
            _hold()
        _plan_watch()

    ## Whether this one listens, which it does only while it holds the lock.
    func listening() -> bool:
        return _server.is_listening()

    ## Listens on a port the system picks and writes the lock with a fresh
    ## token. A Sara that takes the lock over gets a port it never had.
    func _hold() -> void:
        if _server.listen(0, LOOPBACK) != OK:
            if not _warned:
                push_warning("SaSingleInstance: could not listen on %s, so a second start opens its own window." % LOOPBACK)
            _warned = true
            return
        _token = Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
        if not _write_lock(_fields()):
            _server.stop()

    func _fields() -> Dictionary:
        return {"pid": OS.get_process_id(), "port": _server.get_local_port(), "token": _token}

    func _plan_watch() -> void:
        _next_watch = Time.get_ticks_msec() + WATCH_MSEC + randi_range(0, WATCH_JITTER_MSEC)

    ## One reading of the lock. A holder whose lock names another live Sara
    ## lost a race and stops listening, and one whose lock is gone or names a
    ## process that ended writes it again. A watcher takes the lock once the
    ## process it names has ended or no lock is left.
    func watch() -> void:
        if _system_keeps_one:
            return
        _plan_watch()
        var held := SaSingleInstance.read_lock(_lock)
        var pid := int(held.get("pid", 0))
        if listening():
            if str(held.get("token", "")) == _token:
                return
            if SaProcess.another_runs(pid):
                print("Sara: process %d holds the lock now, so this one goes back to watching it." % pid)
                _server.stop()
            else:
                _write_lock(_fields())
        elif not SaProcess.another_runs(pid):
            _hold()
            if listening():
                var port := _server.get_local_port()
                print("Sara: the Sara that held the lock is gone, so this one holds it now on port %d." % port)

    func serve(open: Callable) -> void:
        _open = open
        _take(PackedStringArray())

    func _process(_delta: float) -> void:
        if not _system_keeps_one and Time.get_ticks_msec() >= _next_watch:
            watch()
        while _server.is_connection_available():
            _peers.append({"peer": _server.take_connection(), "said": "", "since": Time.get_ticks_usec()})
        for entry: Dictionary in _peers.duplicate():
            var peer: StreamPeerTCP = entry.peer
            peer.poll()
            var waiting := peer.get_available_bytes()
            if waiting > 0:
                entry.said += peer.get_utf8_string(waiting)
            if str(entry.said).contains("\n"):
                var paths := _paths_in(str(entry.said).get_slice("\n", 0))
                if not paths.is_empty():
                    peer.put_data((ANSWER + "\n").to_utf8_buffer())
                    _take(paths)
            elif peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_usec() - int(entry.since) < PEER_USEC:
                continue
            peer.disconnect_from_host()
            _peers.erase(entry)

    func _exit_tree() -> void:
        _server.stop()
        if int(SaSingleInstance.read_lock(_lock).get("pid", 0)) == OS.get_process_id():
            DirAccess.remove_absolute(_lock)

    ## The paths a line carries when its token is this lock's, else none.
    func _paths_in(line: String) -> PackedStringArray:
        var said: Variant = JSON.parse_string(line)
        if not said is Dictionary or str(said.get("token", "")) != _token or not said.get("paths") is Array:
            return PackedStringArray()
        return PackedStringArray(said.paths)

    ## Opens *paths* behind any that waited, once `Main` has said how, and
    ## brings the window forward.
    func _take(paths: PackedStringArray) -> void:
        _pending.append_array(paths)
        if not _open.is_valid() or _pending.is_empty():
            return
        for path in _pending:
            print("Sara: opening %s, handed over by a second start." % path)
            _open.call(path)
        _pending.clear()
        SaWindowForward.bring(get_window())

    func _write_lock(fields: Dictionary) -> bool:
        DirAccess.make_dir_recursive_absolute(_lock.get_base_dir())
        var partial := _lock + ".partial"
        var handle := FileAccess.open(partial, FileAccess.WRITE)
        if handle == null:
            return false
        if OS.get_name() != "Windows":
            FileAccess.set_unix_permissions(partial, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
        handle.store_string(JSON.stringify(fields) + "\n")
        handle.close()
        return DirAccess.rename_absolute(partial, _lock) == OK
