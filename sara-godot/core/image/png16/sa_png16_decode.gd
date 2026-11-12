## The pixels of a sixteen-bit PNG, decoded by Sara because Godot's loader keeps
## eight of the sixteen bits. `SaImageImport` decides which files come here and
## says what a file it cannot unpack lost, and this class is the decode alone:
## the stream inflated, PNG's scanline filters undone, and the samples scaled
## into full floats.
##
## **Nothing here touches the scene, a registry or a report**, so a caller may
## run it on a worker thread, and File > Open does, keeping the window drawing
## while a large picture reads (`SaPictureRead`).
##
## **The loops are written for GDScript's cost per step**, which is the whole
## of what a decode takes here: a 1920 by 1080 picture is sixteen million
## bytes to unfilter and eight million samples to scale. Each filter has a loop
## of its own rather than a `match` per byte, a sample is scaled where it is
## read rather than through a call, and both passes are shared out over the
## `WorkerThreadPool`: the filters in lanes, one place within a pixel each
## ([method lanes_of] says why that is the only cut they allow), and the
## scaling in bands of scanlines, because each sample is its own and a band's
## floats are joined to the next by one `append_array`.
##
## The floats are the samples over 65535 to the bit, `float(v) / 65535.0`
## worked in double and stored in a float, and the suite
## `test_a_sixteen_bit_png_reads_the_floats_a_decode_a_byte_at_a_time_gives`
## compares every value of a 1920 by 1080 file against a decode written a
## byte at a time.
class_name SaPng16Decode
extends RefCounted

## The fewest scanlines a band of the scaling takes, so a small picture, a
## layer of an OpenRaster file or a suite's two texels, is one band on the
## calling thread rather than a task for each of a handful of lines.
const BAND_MIN_ROWS: int = 128
## The fewest bytes whose filters are undone on the pool, so a small stream's
## lanes are undone one after another on the calling thread.
const LANES_MIN_BYTES: int = 1 << 16


## The pixels of the sixteen-bit PNG in *bytes*, whose `IHDR` *header* holds,
## as an `FORMAT_RGBAF` image, or null when the stream cannot be unpacked.
##
## Full floats rather than halves on purpose: the whole reason for decoding the
## file here is that the sixteen bits survive, and a half float keeps eleven.
## The values are the file's own samples over the full range, so a stored 0.5
## comes back at 32768 of 65535 and never at 128 of 255.
static func of(bytes: PackedByteArray, header: Dictionary[String, Variant]) -> Image:
    if bytes.is_empty():
        return null
    var whole := SaImageImport.png_of(bytes)
    var stream: PackedByteArray = whole.get("idat", PackedByteArray())
    var width := SaTyped.int_at(header, "width", 0)
    var height := SaTyped.int_at(header, "height", 0)
    var colour_type := SaTyped.int_at(header, "colour_type", -1)
    var channels := channels_of(colour_type)
    if stream.is_empty() or width <= 0 or height <= 0 or channels == 0:
        return null
    var pixel_bytes := channels * 2
    var stride := 1 + width * pixel_bytes
    # Godot's Deflate mode is zlib's own framing, which is what an `IDAT` holds
    # and what `SaPng16Writer` compresses with, so one call is the whole of the
    # decompression. The length is exact rather than guessed, because the
    # header already said how many scanlines and how wide.
    var raw := stream.decompress(stride * height, FileAccess.COMPRESSION_DEFLATE)
    if raw.size() != stride * height:
        return null
    var lanes := lanes_of(raw, width, height, pixel_bytes)
    if lanes.is_empty():
        return null
    return as_floats(lanes, width, height, channels, colour_type)


## How many samples a pixel of *colour_type* carries, and 0 for the types this
## reader does not decode.
static func channels_of(colour_type: int) -> int:
    match colour_type:
        SaImageImport.PNG_COLOUR_TYPE_GREY:
            return 1
        SaImageImport.PNG_COLOUR_TYPE_RGB:
            return 3
        SaImageImport.PNG_COLOUR_TYPE_GREY_ALPHA:
            return 2
        SaImageImport.PNG_COLOUR_TYPE_RGBA:
            return 4
    return 0


## PNG's five scanline filters undone, as one array of bytes for each place
## within a pixel, the lane, holding that byte of every pixel, scanline after
## scanline with no filter byte. An empty array when a scanline names a filter
## PNG does not define. *raw* is only read.
##
## Every byte is predicted from the byte one pixel to its left and the bytes
## above it, and those have been undone when they are read, so one pass left
## to right and top to bottom leaves the raw samples behind. The arithmetic
## wraps at eight bits because that is the width a filtered byte is stored in,
## which is why the additions are masked rather than clamped. The first
## scanline has nothing above it, which PNG reads as zeros, so there Up adds
## nothing and Paeth always picks the left neighbour.
##
## **Why lanes.** A byte's three neighbours are all at its own place within a
## pixel, one pixel left, above, or both, so the bytes at one place of every
## pixel are a chain no other place reads, and a pixel of four sixteen-bit
## samples is eight chains a task of the pool each undoes. The scanlines
## cannot be cut instead, since each waits for the one above. Each lane writes
## an array of its own, because a packed array shared between threads is
## copied by the first write while another holds it, and eight tasks undoing
## one buffer in place undid eight copies and read back nonsense.
static func lanes_of(raw: PackedByteArray, width: int, height: int, pixel_bytes: int) -> Array[Lane]:
    var stride := 1 + width * pixel_bytes
    for y in height:
        if raw[y * stride] > SaImageImport.PNG_FILTER_PAETH:
            return []
    var lanes: Array[Lane] = []
    for place in pixel_bytes:
        lanes.append(Lane.new(raw, width, height, pixel_bytes, place))
    if raw.size() < LANES_MIN_BYTES:
        for lane in lanes:
            lane.run()
    else:
        var undo := func(at: int) -> void: lanes[at].run()
        var group := WorkerThreadPool.add_group_task(undo, pixel_bytes, pixel_bytes, true)
        WorkerThreadPool.wait_for_group_task_completion(group)
    return lanes


## The bytes at one place of every pixel, undone by [method run]. It reads the
## filtered stream and writes only [member bytes], so a lane runs beside the
## others with nothing shared that anyone writes.
class Lane:
    extends RefCounted

    ## The lane's undone bytes, one a pixel, a scanline after another.
    var bytes: PackedByteArray = PackedByteArray()
    var _raw: PackedByteArray
    var _width: int
    var _height: int
    var _pixel_bytes: int
    var _place: int

    func _init(raw: PackedByteArray, width: int, height: int, pixel_bytes: int, place: int) -> void:
        _raw = raw
        _width = width
        _height = height
        _pixel_bytes = pixel_bytes
        _place = place

    ## Undoes the lane through every scanline in turn. Within the lane the
    ## pixel to the left is one byte back and the scanline above is a width
    ## back, and the filtered byte of pixel x is `pixel_bytes` further on in
    ## the stream than pixel x - 1's.
    func run() -> void:
        var out := PackedByteArray()
        out.resize(_width * _height)
        for y in _height:
            var line := y * (1 + _width * _pixel_bytes)
            _undo_line(out, _raw[line], y == 0, y * _width, line + 1 + _place)
        bytes = out

    ## One scanline of the lane into *out* from index *into*, its filtered
    ## bytes starting at *at* in the stream and filtered by *kind*. The first
    ## scanline, *top*, reads zeros above.
    func _undo_line(out: PackedByteArray, kind: int, top: bool, into: int, at: int) -> void:
        var raw := _raw
        var step := _pixel_bytes
        var width := _width
        var end := into + width
        if kind == SaImageImport.PNG_FILTER_NONE or (top and kind == SaImageImport.PNG_FILTER_UP):
            for i in range(into, end):
                out[i] = raw[at]
                at += step
            return
        if kind == SaImageImport.PNG_FILTER_UP:
            for i in range(into, end):
                out[i] = (raw[at] + out[i - width]) & 0xFF
                at += step
            return
        # Sub, Average and Paeth all read the pixel to the left, which the
        # first pixel has not, and above it Average adds half and Paeth adds
        # the byte above, the only neighbour of the three not zero.
        if top:
            out[into] = raw[at]
        elif kind == SaImageImport.PNG_FILTER_AVERAGE:
            out[into] = (raw[at] + (out[into - width] >> 1)) & 0xFF
        elif kind == SaImageImport.PNG_FILTER_PAETH:
            out[into] = (raw[at] + out[into - width]) & 0xFF
        else:
            out[into] = raw[at]
        if kind == SaImageImport.PNG_FILTER_SUB or (top and kind == SaImageImport.PNG_FILTER_PAETH):
            for i in range(into + 1, end):
                at += step
                out[i] = (raw[at] + out[i - 1]) & 0xFF
        elif kind == SaImageImport.PNG_FILTER_AVERAGE and top:
            for i in range(into + 1, end):
                at += step
                out[i] = (raw[at] + (out[i - 1] >> 1)) & 0xFF
        elif kind == SaImageImport.PNG_FILTER_AVERAGE:
            for i in range(into + 1, end):
                at += step
                out[i] = (raw[at] + ((out[i - 1] + out[i - width]) >> 1)) & 0xFF
        else:
            _undo_paeth(out, into + 1, end, at)

    ## Filter four's undo past the first pixel of a scanline with one above
    ## it: the neighbour the gradient from left to above predicts best, left
    ## winning a tie and above winning over the corner.
    func _undo_paeth(out: PackedByteArray, first: int, end: int, at: int) -> void:
        var raw := _raw
        var step := _pixel_bytes
        var width := _width
        for i in range(first, end):
            at += step
            var left := out[i - 1]
            var up := out[i - width]
            var corner := out[i - width - 1]
            # The three distances from the estimate `left + up - corner`, each
            # written without the estimate, which cancels out of every one.
            var to_left := up - corner
            var to_up := left - corner
            var to_corner := to_left + to_up
            if to_left < 0:
                to_left = -to_left
            if to_up < 0:
                to_up = -to_up
            if to_corner < 0:
                to_corner = -to_corner
            if to_left <= to_up and to_left <= to_corner:
                out[i] = (raw[at] + left) & 0xFF
            elif to_up <= to_corner:
                out[i] = (raw[at] + up) & 0xFF
            else:
                out[i] = (raw[at] + corner) & 0xFF


## The undone lanes as an image of full floats, each sample the high lane of
## its two bytes over the low one, scaled by the full range of the sixteen
## bits it arrived in.
##
## A grey file is widened to three channels and one with no alpha is opaque, so
## every colour type leaves here in the one shape `SaImageImport.place`
## uploads.
static func as_floats(lanes: Array[Lane], width: int, height: int, channels: int, colour_type: int) -> Image:
    var bands: Array[Band] = []
    @warning_ignore("integer_division")
    var count := clampi(height / BAND_MIN_ROWS, 1, maxi(OS.get_processor_count(), 1))
    for at in count:
        @warning_ignore("integer_division")
        var first := height * at / count
        @warning_ignore("integer_division")
        var last := height * (at + 1) / count
        bands.append(Band.new(lanes, first * width, last * width, channels, colour_type))
    if count == 1:
        bands[0].run()
    else:
        var scale := func(at: int) -> void: bands[at].run()
        var group := WorkerThreadPool.add_group_task(scale, count, count, true)
        WorkerThreadPool.wait_for_group_task_completion(group)
    var floats := PackedFloat32Array()
    for band in bands:
        floats.append_array(band.floats)
    return Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, floats.to_byte_array())


## One band of pixels scaled into floats, the part of [method as_floats] a
## worker runs. It reads the lanes and writes only floats of its own, so no
## two bands touch the same memory and none waits for another.
class Band:
    extends RefCounted

    ## The band's four floats a pixel, filled by [method run].
    var floats: PackedFloat32Array = PackedFloat32Array()
    var _lanes: Array[Lane]
    var _first: int
    var _last: int
    var _channels: int
    var _colour_type: int

    func _init(lanes: Array[Lane], first: int, last: int, channels: int, colour_type: int) -> void:
        _lanes = lanes
        _first = first
        _last = last
        _channels = channels
        _colour_type = colour_type

    ## Scales the pixels from *first* up to *last*. Each channel's two lanes
    ## are held as locals, and what a type lacks is filled with its grey or
    ## with an alpha of one.
    func run() -> void:
        var full := float(SaImageImport.PNG_SAMPLE_MAX)
        var colour := _colour_type == SaImageImport.PNG_COLOUR_TYPE_RGB or _colour_type == SaImageImport.PNG_COLOUR_TYPE_RGBA
        var alpha := (
            _colour_type == SaImageImport.PNG_COLOUR_TYPE_GREY_ALPHA or _colour_type == SaImageImport.PNG_COLOUR_TYPE_RGBA
        )
        var high := _lanes[0].bytes
        var low := _lanes[1].bytes
        var alpha_high := _lanes[_channels * 2 - 2].bytes
        var alpha_low := _lanes[_channels * 2 - 1].bytes
        var out := PackedFloat32Array()
        out.resize((_last - _first) * 4)
        var next := 0
        if colour:
            var green_high := _lanes[2].bytes
            var green_low := _lanes[3].bytes
            var blue_high := _lanes[4].bytes
            var blue_low := _lanes[5].bytes
            for i in range(_first, _last):
                out[next] = float((high[i] << 8) | low[i]) / full
                out[next + 1] = float((green_high[i] << 8) | green_low[i]) / full
                out[next + 2] = float((blue_high[i] << 8) | blue_low[i]) / full
                out[next + 3] = float((alpha_high[i] << 8) | alpha_low[i]) / full if alpha else 1.0
                next += 4
        else:
            for i in range(_first, _last):
                var grey := float((high[i] << 8) | low[i]) / full
                out[next] = grey
                out[next + 1] = grey
                out[next + 2] = grey
                out[next + 3] = float((alpha_high[i] << 8) | alpha_low[i]) / full if alpha else 1.0
                next += 4
        floats = out
