## A zip file of stored entries, written by hand.
##
## OpenRaster asks for `mimetype` as the first entry, stored with method 0, so
## a format sniffer finds `image/openraster` at byte 38 of the file: thirty
## bytes of local header and the eight of the name. Godot's `ZIPPacker` writes
## method 8 whatever level it is given, a deflate stream of stored blocks, so
## the sniffer finds five bytes of block header there instead. Nothing inside
## an OpenRaster file needs deflate, since its PNGs are compressed already and
## `stack.xml` is a few kilobytes, so this writes every entry stored.
##
## **The layout.** An entry is its local header, its name and its bytes, in the
## order [method add] was called. [method close] writes the central directory,
## one record an entry pointing back at its local header, and the end record
## after it. Every entry is version 1.0 and method 0, with the CRC from
## [method SaPictureFile.crc32], and the time the constructor was given.
##
## **No Zip64.** An entry or an offset past four gigabytes, or more than 65535
## entries, is refused with an error rather than written as a file no reader
## opens.
##
## The entries are streamed to the file as they come, so the writer holds only
## the central directory, never the whole zip.
class_name SaZipStored
extends RefCounted

const LOCAL_SIGNATURE: int = 0x04034B50
const CENTRAL_SIGNATURE: int = 0x02014B50
const END_SIGNATURE: int = 0x06054B50
## Version 1.0, what a stored entry with no directory attributes needs.
const VERSION_NEEDED: int = 10
## Version 2.0 on MS-DOS, the most widely read "made by".
const VERSION_MADE_BY: int = 20
const METHOD_STORED: int = 0
## Bit 11 of the flags, set on an entry whose name is UTF-8 beyond ASCII.
const UTF8_NAME_FLAG: int = 0x0800
## The length of a local header before its name, which puts the first entry's
## bytes at 30 plus the length of its name.
const LOCAL_HEADER_BYTES: int = 30
const LIMIT_32: int = 0xFFFFFFFF
const LIMIT_16: int = 0xFFFF
## MS-DOS dates start in 1980, and a moment before it is written as its start.
const DOS_EPOCH_YEAR: int = 1980

var _file: FileAccess
var _error: Error = OK
var _dos_time: int
var _dos_date: int
## The central directory so far, one record an entry.
var _central := PackedByteArray()
var _count: int = 0


## A zip at *path*, its entries dated *local_unix_time*, the seconds since the
## epoch of the painter's clock. A path that cannot be opened makes every
## [method add] and [method close] return the error.
func _init(path: String, local_unix_time: int = 0) -> void:
    _file = FileAccess.open(path, FileAccess.WRITE)
    if _file == null:
        _error = FileAccess.get_open_error()
        push_error("SaZipStored: cannot open '%s' (err %d)" % [path, _error])
    var at := Time.get_datetime_dict_from_unix_time(local_unix_time)
    var year := SaTyped.int_at(at, "year", 0)
    if year < DOS_EPOCH_YEAR:
        _dos_date = (1 << 5) | 1
        _dos_time = 0
    else:
        _dos_date = ((year - DOS_EPOCH_YEAR) << 9) | (SaTyped.int_at(at, "month", 0) << 5) | SaTyped.int_at(at, "day", 0)
        _dos_time = (
            (SaTyped.int_at(at, "hour", 0) << 11)
            | (SaTyped.int_at(at, "minute", 0) << 5)
            | (SaTyped.int_at(at, "second", 0) >> 1)
        )


## Writes the entry *entry_name* holding *bytes*, after every entry added
## before it. A name beyond ASCII is written as UTF-8 and flagged so.
func add(entry_name: String, bytes: PackedByteArray) -> Error:
    if _error != OK:
        return _error
    var name := entry_name.to_utf8_buffer()
    var offset := _file.get_position()
    if bytes.size() > LIMIT_32 or offset > LIMIT_32 or name.size() > LIMIT_16 or _count >= LIMIT_16:
        push_error("SaZipStored.add: '%s' needs Zip64, which this does not write" % entry_name)
        _error = ERR_FILE_CANT_WRITE
        return _error
    var crc := SaPictureFile.crc32(bytes)
    var local := PackedByteArray()
    _put_u32(local, LOCAL_SIGNATURE)
    _put_u16(local, VERSION_NEEDED)
    var flags := UTF8_NAME_FLAG if name.size() != entry_name.length() else 0
    _put_common(local, flags, crc, bytes.size(), name.size())
    _put_u16(local, 0)
    local.append_array(name)
    _file.store_buffer(local)
    _file.store_buffer(bytes)
    _put_u32(_central, CENTRAL_SIGNATURE)
    _put_u16(_central, VERSION_MADE_BY)
    _put_u16(_central, VERSION_NEEDED)
    _put_common(_central, flags, crc, bytes.size(), name.size())
    _put_u16(_central, 0)
    _put_u16(_central, 0)
    _put_u16(_central, 0)
    _put_u16(_central, 0)
    _put_u32(_central, 0)
    _put_u32(_central, offset)
    _central.append_array(name)
    _count += 1
    return _file.get_error()


## Writes the central directory and the end record and closes the file.
func close() -> Error:
    if _error != OK:
        return _error
    var offset := _file.get_position()
    if offset > LIMIT_32:
        push_error("SaZipStored.close: the directory starts past four gigabytes")
        _error = ERR_FILE_CANT_WRITE
        return _error
    var end := PackedByteArray()
    _put_u32(end, END_SIGNATURE)
    _put_u16(end, 0)
    _put_u16(end, 0)
    _put_u16(end, _count)
    _put_u16(end, _count)
    _put_u32(end, _central.size())
    _put_u32(end, offset)
    _put_u16(end, 0)
    _file.store_buffer(_central)
    _file.store_buffer(end)
    var err := _file.get_error()
    _file.close()
    _error = ERR_UNAVAILABLE if err == OK else err
    return err


## The fields a local header and a central record share, from the flags to
## the length of the name.
func _put_common(into: PackedByteArray, flags: int, crc: int, size: int, name_size: int) -> void:
    _put_u16(into, flags)
    _put_u16(into, METHOD_STORED)
    _put_u16(into, _dos_time)
    _put_u16(into, _dos_date)
    _put_u32(into, crc)
    _put_u32(into, size)
    _put_u32(into, size)
    _put_u16(into, name_size)


static func _put_u16(into: PackedByteArray, value: int) -> void:
    into.append(value & 0xFF)
    into.append((value >> 8) & 0xFF)


static func _put_u32(into: PackedByteArray, value: int) -> void:
    into.append(value & 0xFF)
    into.append((value >> 8) & 0xFF)
    into.append((value >> 16) & 0xFF)
    into.append((value >> 24) & 0xFF)
