## The tablet's pen node under `/dev/input/`, read on a thread of its own, and
## the pen's state as it was last read, which is the source the module puts on
## the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Found by its key bits.** Every input device lists the keys it can send in
## `/sys/class/input/event*/device/capabilities/key`, which anyone may read, and
## a pen's node is the one that sends `BTN_TOOL_PEN`. A tablet's pad and its
## touch surface have nodes of their own and send none. udev marks all three
## `ID_INPUT_TABLET`, which is what the rule `packaging/install.sh` offers
## matches, so the seat's user may read the pen's node once it is in.
##
## **Read through `cat`, on a thread.** Godot's `FileAccess` opens regular
## files alone and refuses a character device outright, so the node is read
## by a `cat` started with `OS.execute_with_pipe`, and the thread reads the
## pipe. A read blocked on the pipe ends the moment the `cat` is killed, so
## [method stop] kills it and the thread is joined at once, and Sara's exit
## never waits on the pen to move. The `cat` is started under `setpriv
## --pdeathsig KILL`, which asks the kernel to kill it the moment the thread
## that started it ends, so a Sara ended by a timeout, a crash or SIGKILL takes
## its `cat` with it rather than leaving it blocked on the node for good, holding
## whatever its Sara held. A machine with no `setpriv` reads through a
## bare `cat`. The thread takes the [Reader]'s lock only to
## hand records over or to say what it found, so a press on the main thread
## asking [method now] never waits on it.
##
## **The thread runs the [Reader], never this source.** A source dropped
## without its module's `unregister`, as a suite that lets its registries go
## does, is freed while the thread runs, and a thread calling into an object
## being freed fails at every call. The reader outlives the source's own
## teardown, which joins the thread before it lets go of the reader.
##
## **The wheel's range is asked of the node through `python3`.** An airbrush's
## finger wheel is read against the lowest and highest values the node declares,
## which only an ioctl answers, and Godot makes none. Before the `cat` starts,
## [constant WHEEL_ASK] is run on the node, and the Tablet page's sentence says
## so when it could not run. Nothing is asked of a node that is not a device, a
## suite's pipe.
##
## **It looks again every [constant LOOK_AGAIN_MSEC].** A node not found, a
## node the user may not read, and a node that closed because the tablet went
## away are each looked for again, so a tablet plugged in after Sara started,
## or the rule installed while Sara runs, turns the source on without a
## restart.
extends SaPenSource

const PenRecords := preload("pen_records.gd")

## Where every input device lists its capabilities.
const SYS_INPUT := "/sys/class/input"
## Where the nodes themselves are.
const DEV_INPUT := "/dev/input"
## How long the thread waits before it looks for the node again.
const LOOK_AGAIN_MSEC := 2000
## The slices that wait is cut into, so a stop is heard within one.
const STOP_HEARD_MSEC := 50
## How many bytes one read asks the pipe for, sixty-four records.
const READ_BYTES := 64 * PenRecords.RECORD_BYTES
## What runs before `cat` so the `cat` dies with the thread that started it,
## `setpriv` of util-linux, which sets the parent death signal and then runs
## `cat` in its own place, so the id the pipe hands back is the `cat`'s.
const DIES_WITH_SARA: Array[String] = ["--pdeathsig", "KILL", "--"]

## The program `python3 -c` runs on a node, which prints the lowest and highest
## value it declares for `ABS_WHEEL`, or `none` for a node with no wheel or one
## that is no input node and refuses the question. The two numbers are
## `EVIOCGBIT(EV_ABS, 8)` and `EVIOCGABS(ABS_WHEEL)` from `linux/input.h`, and
## the six numbers the second answers are `struct input_absinfo`, the lowest
## and highest the second and third.
const WHEEL_ASK: Array[String] = [
    "import fcntl, struct, sys",
    "info = None",
    "try:",
    "    with open(sys.argv[1], 'rb', buffering=0) as node:",
    "        axes = fcntl.ioctl(node, 0x80084523, bytes(8))",
    "        info = fcntl.ioctl(node, 0x80184548, bytes(24)) if axes[1] & 1 else None",
    "except OSError:",
    "    pass",
    "print('none' if info is None else '%d %d' % struct.unpack('6i', info)[1:3])",
]

## The one log line for a node the user may not read, with the node.
const REFUSED_LINE := (
    "[Sara] The pen module cannot read %s: Sara's user has no read permission on it, so the upper barrel "
    + "button's release in the air is presumed as before. packaging/install.sh prints the udev rule and the one "
    + "sudo command that give the seat's user the tablet's nodes."
)

## What became of the wheel's range on a node: the node declares no wheel, the
## wheel is read, or `python3` could not ask.
enum Wheel { NONE, READ, UNASKED }


## What [method Reader.ask_wheel] learnt of a node's wheel.
class Asked:
    extends RefCounted

    ## What became of the wheel, [constant Wheel.NONE] as well for a range with
    ## no room in it.
    var wheel: Wheel = Wheel.NONE
    ## The lowest and highest value the node declares, as `x` and `y`, nought
    ## unless the wheel is read.
    var declared := Vector2i.ZERO

    func _init(found: Wheel, wheel_range: Vector2i = Vector2i.ZERO) -> void:
        wheel = found if found != Wheel.READ or wheel_range.y > wheel_range.x else Wheel.NONE
        declared = wheel_range if wheel == Wheel.READ else Vector2i.ZERO


## Everything the thread touches, behind one lock. The source keeps one and
## hands its questions on.
class Reader:
    extends RefCounted

    ## Over every member below the thread writes.
    var _lock := Mutex.new()

    ## The records read off the node, which the thread feeds and [method now]
    ## asks.
    var _records := PenRecords.new()

    ## The node to read in place of looking for one, empty to look.
    var _named: String = ""

    ## Where the capabilities are listed, which a suite points at a tree of its
    ## own.
    var _sys_root: String = SYS_INPUT

    ## The node read or tried last, empty when none was found.
    var _node: String = ""

    ## Whether the thread holds the node open and reads it.
    var _reads: bool = false

    ## What became of the wheel on the node read, see [enum Wheel].
    var _wheel: Wheel = Wheel.NONE

    ## Whether the node found may not be read.
    var _refused: bool = false

    ## Whether the thread has looked for a node once, so the page can say what
    ## it found rather than nothing.
    var _looked: bool = false

    ## Whether the refusal's log line has been printed, which happens once.
    var _refusal_logged: bool = false

    ## Whether [method stop] was asked.
    var _stopping: bool = false

    ## The `cat` reading the node, 0 while none runs.
    var _pid: int = 0

    ## Whether `setpriv` ran here, asked once when the thread starts.
    var _setpriv: bool = false

    func _init(named_node: String, sys_root: String) -> void:
        _named = named_node
        _sys_root = sys_root

    ## Says the thread is to end, and kills the `cat`, which lets a blocked
    ## read go at once.
    func stop() -> void:
        _lock.lock()
        _stopping = true
        if _pid != 0:
            OS.kill(_pid)
            _pid = 0
        _lock.unlock()

    func now() -> SaPenSource.State:
        _lock.lock()
        var out := _records.now() if _reads else null
        _lock.unlock()
        return out

    func wheel() -> float:
        _lock.lock()
        var out := _records.wheel() if _reads else 0.0
        _lock.unlock()
        return out

    func reads() -> bool:
        _lock.lock()
        var out := _reads
        _lock.unlock()
        return out

    func reads_wheel() -> bool:
        _lock.lock()
        var out := _reads and _wheel == Wheel.READ
        _lock.unlock()
        return out

    func said() -> String:
        _lock.lock()
        var node := _node
        var reads_now := _reads
        var wheel_now := _wheel
        var refused := _refused
        var looked := _looked
        _lock.unlock()
        if reads_now and wheel_now == Wheel.READ:
            return "The pen module reads %s, the airbrush's finger wheel with it." % node
        if reads_now and wheel_now == Wheel.UNASKED:
            return (
                (
                    "The pen module reads %s, but not the airbrush's finger wheel, because python3, which asks the node "
                    + "for the wheel's range, did not run."
                )
                % node
            )
        if reads_now:
            return "The pen module reads %s." % node
        if refused:
            return (
                (
                    "The pen module is off, because Sara may not read %s. To turn it on, run the one sudo command "
                    + "packaging/install.sh prints, and the module reads the pen within two seconds."
                )
                % node
            )
        if looked:
            return (
                "The pen module is off, because no tablet's pen was found under %s. It looks again every two seconds." % DEV_INPUT
            )
        return ""

    ## The pen's node under [constant DEV_INPUT], the first one whose key bits in
    ## *sys_root* carry `BTN_TOOL_PEN`, or empty when none does.
    static func find(sys_root: String = SYS_INPUT) -> String:
        var names: Array[String] = []
        var listing := DirAccess.open(sys_root)
        if listing == null:
            return ""
        listing.list_dir_begin()
        var name := listing.get_next()
        while not name.is_empty():
            if name.begins_with("event") and name.substr(5).is_valid_int():
                names.append(name)
            name = listing.get_next()
        listing.list_dir_end()
        names.sort_custom(func(a: String, b: String) -> bool: return a.substr(5).to_int() < b.substr(5).to_int())
        for each: String in names:
            var bits := FileAccess.open(sys_root.path_join(each).path_join("device/capabilities/key"), FileAccess.READ)
            if bits != null and carries(bits.get_line(), PenRecords.BTN_TOOL_PEN):
                return DEV_INPUT.path_join(each)
        return ""

    ## Whether *words*, a key bitmap as sysfs writes it, carries the key *code*.
    ## The words are hexadecimal, 64 bits each on a 64-bit kernel, the highest
    ## first and the leading empty ones left out.
    static func carries(words: String, code: int) -> bool:
        var parts := words.strip_edges().split(" ", false)
        var word := code >> 6
        if word >= parts.size():
            return false
        var hex := parts[parts.size() - 1 - word]
        var digit := (code & 63) >> 2
        if digit >= hex.length():
            return false
        var nibble := hex.substr(hex.length() - 1 - digit, 1).hex_to_int()
        return (nibble >> (code & 3)) & 1 == 1

    ## The lowest and highest value *node* declares for its wheel, asked
    ## through [constant WHEEL_ASK]. [constant Wheel.NONE] for a node that is
    ## not a device or declares no wheel, and [constant Wheel.UNASKED] when
    ## `python3` did not answer.
    static func ask_wheel(node: String) -> Asked:
        if OS.execute("test", ["-c", node]) != 0:
            return Asked.new(Wheel.NONE)
        var output: Array = []
        var code := OS.execute("python3", ["-c", "\n".join(WHEEL_ASK), node], output)
        var said_back: String = output[0] if code == 0 and not output.is_empty() else ""
        var words := said_back.strip_edges().split(" ", false)
        if words.size() == 1 and words[0] == "none":
            return Asked.new(Wheel.NONE)
        if words.size() == 2 and words[0].is_valid_int() and words[1].is_valid_int():
            return Asked.new(Wheel.READ, Vector2i(words[0].to_int(), words[1].to_int()))
        return Asked.new(Wheel.UNASKED)

    ## The thread's whole life: look for the node, read it while it can, and
    ## look again, until [method stop].
    func run() -> void:
        _setpriv = OS.execute("setpriv", DIES_WITH_SARA + ["true"]) == 0
        while not _stopped():
            var node := _named if not _named.is_empty() else find(_sys_root)
            if node.is_empty():
                _found(node, false)
            elif OS.execute("test", ["-r", node]) != 0:
                _found(node, true)
            else:
                _read(node)
            _wait()

    ## Notes what the look found, *node* or nothing, and whether it is
    ## *refused*, and prints the refusal's line the first time.
    func _found(node: String, refused: bool) -> void:
        _lock.lock()
        _node = node
        _refused = refused
        _looked = true
        var first := refused and not _refusal_logged
        if first:
            _refusal_logged = true
        _lock.unlock()
        if first:
            print(REFUSED_LINE % node)

    ## Reads *node* until its `cat` ends, killed by [method stop] or by the
    ## node going away.
    func _read(node: String) -> void:
        var wheel_asked := ask_wheel(node)
        var pipe := (
            OS.execute_with_pipe("setpriv", DIES_WITH_SARA + ["cat", "--", node])
            if _setpriv
            else OS.execute_with_pipe("cat", ["--", node])
        )
        if pipe.is_empty():
            return
        var pid: int = pipe["pid"]
        _lock.lock()
        var stopping := _stopping
        if not stopping:
            _pid = pid
            _node = node
            _refused = false
            _looked = true
            _reads = true
            _wheel = wheel_asked.wheel
            _records = PenRecords.new(wheel_asked.declared)
        _lock.unlock()
        if stopping:
            OS.kill(pid)
            return
        var out: FileAccess = pipe["stdio"]
        while true:
            var got := out.get_buffer(READ_BYTES)
            if got.is_empty():
                break
            _lock.lock()
            _records.feed(got)
            _lock.unlock()
        _lock.lock()
        var left := _pid
        _pid = 0
        _reads = false
        _lock.unlock()
        # A `cat` that ended by itself is reaped here. One [method stop] killed
        # is already, and its id was taken back under the lock first.
        if left != 0:
            OS.kill(left)

    func _wait() -> void:
        for slice: int in range(0, LOOK_AGAIN_MSEC, STOP_HEARD_MSEC):
            if _stopped():
                return
            OS.delay_msec(STOP_HEARD_MSEC)

    func _stopped() -> bool:
        _lock.lock()
        var out := _stopping
        _lock.unlock()
        return out


## What the thread reads and says.
var _reader: Reader = null
var _thread := Thread.new()


## *named_node* is read in place of looking for one, and *sys_root* is where
## the looking happens.
func _init(named_node: String = "", sys_root: String = SYS_INPUT) -> void:
    _reader = Reader.new(named_node, sys_root)


## A source let go of with its thread still running joins it here. Inline
## rather than a call to [method stop], because a call on `self` fails while
## the object is torn down.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _reader.stop()
        if _thread.is_started():
            _thread.wait_to_finish()


func start() -> void:
    _thread.start(_reader.run)


## Kills the `cat` and joins the thread, which a blocked read lets go of at
## once and a wait within [constant STOP_HEARD_MSEC].
func stop() -> void:
    _reader.stop()
    if _thread.is_started():
        _thread.wait_to_finish()


# The five answers below are SaPenSource's own interface, which the door hands out
# and callers reach as `SaPenSource`, so each one answers from the reader and has to stay.
func now() -> SaPenSource.State:
    return _reader.now()


func wheel() -> float:
    return _reader.wheel()


func reads() -> bool:
    return _reader.reads()


func reads_wheel() -> bool:
    return _reader.reads_wheel()


func said() -> String:
    return _reader.said()
