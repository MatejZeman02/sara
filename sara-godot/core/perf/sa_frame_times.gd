## How long a run of frames took, kept as a distribution a percentile is read
## from, in the same few integers however many frames are folded.
##
## The stroke ledger keeps a minimum, a sum, a maximum and a count, because those
## are what its table shows. A painter's freeze is not in them: a stroke of two
## hundred frames with ten over a second has the maximum of one slow frame and
## the mean of a fast stroke. The 95th percentile and the count over a frame's
## budget are what tell the two apart, and a percentile needs every frame. So
## the frames are counted into buckets a sixteenth of an octave wide, about four
## per cent, sized once, and the percentile is the upper edge of the bucket its
## rank falls in, never past the longest frame. A bucket's edge is the answer
## because "95 % of the frames took at most this" is then true as written.
##
## Its own class rather than more statics on the ledger, because the window and
## each stroke hold one apiece, and because the ledger keeps no list of any kind
## and its suite holds it to that by reading its source.
##
## **The budget is the display's, not a constant.** A frame is late when it
## misses one refresh of the screen it is on, so a count against a fixed 60 Hz
## reads every frame of a 50 Hz panel as a miss and hides the ones that really
## were. The window's budget is taken from the rate the start-up block read and
## the rate is the display's, so the same twenty four milliseconds is a late
## frame at 120 Hz and an early one at 50.
class_name SaFrameTimes
extends RefCounted

## A frame's budget at sixty frames a second, the count a rate the driver will
## not name falls back to.
const BUDGET_USEC: int = 16667
## Buckets an octave. Sixteen puts neighbouring edges 4.4 % apart.
const PER_OCTAVE: int = 16
## Octaves from one microsecond, so the last bucket starts past 16.7 s and
## holds every frame longer than that.
const OCTAVES: int = 24

## The frames folded.
var count: int = 0
## Their times added up, in microseconds.
var total_usec: int = 0
## The longest of them.
var longest_usec: int = 0
## How many took longer than [member budget_usec].
var slow: int = 0
## The line a slow frame is over, one refresh of the display the window is on,
## given by [method _init] and [constant BUDGET_USEC] while no rate is known.
var budget_usec: int = BUDGET_USEC

## Frames a bucket, sized once by [method _init] and never grown.
var _buckets := PackedInt32Array()


func _init(budget: int = BUDGET_USEC) -> void:
    budget_usec = budget
    _buckets.resize(OCTAVES * PER_OCTAVE)


## The budget one refresh of a display at *hz* leaves, in whole microseconds,
## and [constant BUDGET_USEC] where the driver answered no rate at all.
static func budget_for_hz(hz: float) -> int:
    return roundi(1000000.0 / hz) if hz > 0.0 else BUDGET_USEC


## Folds one frame that took *usec* microseconds.
func fold(usec: int) -> void:
    var took := maxi(usec, 0)
    count += 1
    total_usec += took
    longest_usec = maxi(longest_usec, took)
    if took > budget_usec:
        slow += 1
    _buckets[bucket_of(took)] += 1


## The time *fraction* of the frames took at most, to a bucket's width, and
## nought when none was folded. The rank is the nearest one at or above the
## fraction, so the 95th percentile of twenty frames is the nineteenth.
func percentile_usec(fraction: float) -> int:
    if count == 0:
        return 0
    var rank := clampi(ceili(fraction * count), 1, count)
    var seen := 0
    for at: int in _buckets.size():
        seen += _buckets[at]
        if seen >= rank:
            return mini(longest_usec, upper_edge(at))
    return longest_usec


## What the frames come to, every figure in whole microseconds.
func block() -> Dictionary[String, int]:
    @warning_ignore("integer_division")
    var mean := total_usec / maxi(count, 1)
    return {
        "count": count,
        "mean": mean,
        "p95": percentile_usec(0.95),
        "max": longest_usec,
        "slow": slow,
        "total": total_usec,
        "budget": budget_usec,
    }


## The bucket a frame of *usec* microseconds is counted in. Under two
## microseconds is the first, which no frame reaches.
static func bucket_of(usec: int) -> int:
    if usec < 2:
        return 0
    var octaves := log(float(usec)) / log(2.0)
    return clampi(floori(octaves * PER_OCTAVE), 0, OCTAVES * PER_OCTAVE - 1)


## The longest time bucket *at* holds, in whole microseconds rounded up.
static func upper_edge(at: int) -> int:
    return ceili(pow(2.0, float(at + 1) / PER_OCTAVE))
