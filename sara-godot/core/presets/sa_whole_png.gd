## A cached PNG on the disk that is whole or not there at all: written beside
## itself and renamed over its old self, and checked at both ends before it is
## read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why it exists.** Measured on the Android emulator: the smoke run stops
## the emulator with `emu kill` a minute after the start, and the preset pictures
## the first start wrote in its last seconds were never flushed to the disk
## image. The next start found Storm Cloud to Wood Grain, the last eight by name,
## as files of nothing, and `Image.load_from_file` printed an error line for each
## on every start after. `SaPresetThumbs` asks here before it trusts a
## cached picture, and writes through here.
class_name SaWholePng
extends RefCounted

## A picture is written under this name beside its own and then renamed over it,
## so a write cut short never stands where a whole picture is looked for.
const PART_SUFFIX: String = ".part"

## The last eight bytes of every PNG: the `IEND` chunk's type and its fixed
## checksum.
const PNG_END: Array[int] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]


## Writes *image* to *png* as a whole file or not at all. Answers whether it did.
static func write(png: String, image: Image) -> bool:
    var part := png + PART_SUFFIX
    var file := FileAccess.open(part, FileAccess.WRITE)
    if file == null:
        return false
    file.store_buffer(image.save_png_to_buffer())
    file.close()
    return DirAccess.rename_absolute(part, png) == OK


## Whether the file at *png* holds a whole PNG: the signature at the start and the
## `IEND` chunk at the end. Read from its ends alone, so the chooser's look at
## seventy cached pictures costs two short reads each rather than a decode.
static func reads(png: String) -> bool:
    var signature := PackedByteArray(SaImageImport.PNG_SIGNATURE)
    var end := PackedByteArray(PNG_END)
    var file := FileAccess.open(png, FileAccess.READ)
    if file == null or file.get_length() < signature.size() + end.size():
        return false
    if file.get_buffer(signature.size()) != signature:
        return false
    file.seek(file.get_length() - end.size())
    return file.get_buffer(end.size()) == end
