## One strip of a TIFF unpacked from PackBits or LZW, the two baseline
## compressions of TIFF 6.0 that `PackedByteArray.decompress` has no mode for.
##
## [SaTiffReader] makes one per strip, giving it the strip's bytes as the file
## holds them and the most a strip may hold unpacked, and reads [member bytes]
## back, or [member fault] when the strip does not unpack. Neither scheme
## knows the picture, so the predictor, the byte order and the rows are the
## reader's, applied after this as they are after Deflate.
##
## **PackBits** is Apple's byte-run coding: a header byte n from 0 to 127 is
## followed by n + 1 bytes copied as they are, one from -127 to -1 by one byte
## repeated 1 - n times, and -128 is skipped.
##
## **LZW** is the TIFF 6.0 variant: codes packed most significant bit first,
## nine bits wide at the start and growing to twelve, 256 clearing the table and
## 257 ending the strip. The width grows one code early, when the next entry to
## be made is the last the current width can name, which is what libtiff and
## every writer since TIFF 6.0 do. The pre-6.0 variant libtiff calls "old
## style", least significant bit first, is not read, and comes back as a fault.
##
## LZW is unpacked by [code]SaTiffLzw[/code], the native library of the base
## modules' `tiff-lzw` folder, when Godot loaded it, and by
## the GDScript below when it did not, a build or a platform without the
## library, so the file opens either way. The two give the same bytes and the
## same fault for every strip. The class is asked for through `ClassDB` by name,
## since a script that named it would not parse without the library.
class_name SaTiffUnpacker
extends RefCounted

const PACK_BITS: int = 32773
const LZW: int = 5
## The native LZW unpacker's class, asked for by name.
const LIBRARY := &"SaTiffLzw"

const LZW_CLEAR: int = 256
const LZW_END: int = 257
const LZW_FIRST_FREE: int = 258
const LZW_MIN_WIDTH: int = 9
const LZW_MAX_WIDTH: int = 12
const LZW_TABLE: int = 1 << LZW_MAX_WIDTH
## What *out* is grown by past the strip's most for LZW. Six codes can be
## unpacked between two asks of the bound, none longer than the table.
const LZW_SLACK: int = 7 * LZW_TABLE

## The strip unpacked, empty when [member fault] is not.
var bytes := PackedByteArray()
## Why the strip does not unpack, as an English clause for the console and the
## suites, "" when it did. It is never shown, since the native library words
## it too. The reader gives the painter a sentence of its own that names only the scheme.
var fault := ""
## Whether the native library unpacked the strip rather than the GDScript.
var native := false


## Unpacks *packed*, compressed with *compression*, one of [constant PACK_BITS]
## and [constant LZW], to at most *most* bytes. A strip that would unpack to
## more is a fault rather than an allocation, as a Deflate stream claiming more
## than its strip is. *library* names the native LZW class, and a name Godot has
## no class for is how a suite unpacks through the GDScript.
func _init(packed: PackedByteArray, compression: int, most: int, library: StringName = LIBRARY) -> void:
    if compression == LZW and ClassDB.class_exists(library):
        var answer: Dictionary = ClassDB.class_call_static(library, &"unpack", packed, most)
        native = true
        fault = answer.fault
        bytes = answer.bytes
        return
    var out := PackedByteArray()
    out.resize(most)
    var size := -1
    if compression == PACK_BITS:
        size = _pack_bits(packed, out)
    elif compression == LZW:
        size = _lzw(packed, out, most)
    else:
        fault = "names compression %d to the unpacker" % compression
    if size < 0:
        return
    out.resize(size)
    bytes = out


## *packed* unpacked into *out* from PackBits, answering how many bytes it
## wrote, or -1 with [member fault] set.
func _pack_bits(packed: PackedByteArray, out: PackedByteArray) -> int:
    var at := 0
    var written := 0
    var end := packed.size()
    var most := out.size()
    while at < end:
        var header := packed[at]
        at += 1
        if header < 128:
            var count := header + 1
            if at + count > end:
                fault = "its PackBits pixels run past the end of their strip"
                return -1
            if written + count > most:
                fault = "its PackBits pixels unpack to more than their strip holds"
                return -1
            for i in count:
                out[written + i] = packed[at + i]
            at += count
            written += count
        elif header > 128:
            var count := 257 - header
            if at >= end:
                fault = "its PackBits pixels run past the end of their strip"
                return -1
            if written + count > most:
                fault = "its PackBits pixels unpack to more than their strip holds"
                return -1
            var value := packed[at]
            at += 1
            for i in count:
                out[written + i] = value
            written += count
    return written


## *packed* unpacked into *out* from LZW, answering how many bytes it wrote, or
## -1 with [member fault] set. *out* holds *most* bytes on the way in.
##
## Every entry of the table is the previous code's string and one byte more,
## and the current code's string is written straight after the previous one,
## so an entry is the place in *out* where the previous string starts and a
## length one longer. No string is built and no prefix walked: a code is copied
## forward from what is already written, which also gives the one code past the
## table, the previous string and its own first byte, since the copy reaches
## that byte only after writing it. The codes come off a buffer filled six
## bytes at once by `decode_u64` from a reversed copy of the strip, which reads
## them most significant first, and byte by byte only over the strip's last
## seven. Whether the strip unpacks to more than *most* is asked once a fill,
## so *out* is grown by [constant LZW_SLACK] for the codes between two asks. A
## strip that ends without the end code is read to its last whole code, as
## libtiff reads it.
##
## Copying forward and filling the code buffer six bytes at once is what keeps
## an LZW strip within a few times the cost of a PackBits one: walking a string
## back along its prefixes and filling the codes a byte at a time costs a Full
## HD picture several times as long to open. What is left is GDScript's own
## cost of a few statements a code, which is why the native library exists and
## this is its fallback.
func _lzw(packed: PackedByteArray, out: PackedByteArray, most: int) -> int:
    out.resize(most + LZW_SLACK)
    var start := PackedInt32Array()
    start.resize(LZW_TABLE)
    var length := PackedInt32Array()
    length.resize(LZW_TABLE)
    var end := packed.size()
    var turned := packed.duplicate()
    turned.reverse()
    var at := 0
    # Bits read ahead of the code being built, the newest at the bottom. Below
    # twelve of them are left when it fills, so the twelve lowest are kept.
    var held := 0
    var ahead := 0
    var width := LZW_MIN_WIDTH
    var mask := (1 << width) - 1
    # The width grows when the table reaches this, never past twelve bits.
    var grow := mask
    var next := LZW_FIRST_FREE
    # Where the previous code's string starts in *out*, -1 after a clear.
    var previous := -1
    var written := 0
    while true:
        if ahead < width:
            if written > most:
                break
            if at + 8 <= end:
                held = ((held & 0xFFF) << 48) | ((turned.decode_u64(end - 8 - at) >> 16) & 0xFFFFFFFFFFFF)
                at += 6
                ahead += 48
            else:
                while ahead < width and at < end:
                    held = ((held & 0xFFF) << 8) | packed[at]
                    at += 1
                    ahead += 8
                if ahead < width:
                    break
        ahead -= width
        var code := (held >> ahead) & mask
        # The previous string ends where this one starts, so each entry made
        # below is its start and its length and one byte more.
        if code < LZW_CLEAR:
            if previous >= 0 and next < LZW_TABLE:
                start[next] = previous
                length[next] = written - previous + 1
                next += 1
            previous = written
            out[written] = code
            written += 1
        elif code >= LZW_FIRST_FREE:
            if previous < 0:
                fault = "its LZW pixels name code %d before the table holds it" % code
                return -1
            if next < LZW_TABLE:
                start[next] = previous
                length[next] = written - previous + 1
                next += 1
            if code >= next:
                fault = "its LZW pixels name code %d, which the table does not hold" % code
                return -1
            var from := start[code]
            var count := length[code]
            if count == 2:
                out[written] = out[from]
                out[written + 1] = out[from + 1]
            else:
                for i in count:
                    out[written + i] = out[from + i]
            previous = written
            written += count
        elif code == LZW_END:
            break
        else:
            next = LZW_FIRST_FREE
            width = LZW_MIN_WIDTH
            mask = (1 << width) - 1
            grow = mask
            previous = -1
            continue
        if next >= grow:
            width += 1
            mask = (1 << width) - 1
            grow = mask if width < LZW_MAX_WIDTH else LZW_TABLE + 1
    if written > most:
        fault = "its LZW pixels unpack to more than their strip holds"
        return -1
    return written
