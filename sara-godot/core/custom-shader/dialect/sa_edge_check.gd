## The edge check a kernel leaves out, written for it.
##
## The GPU runs a kernel in groups of 8 by 8 threads, so a dispatch over an image
## whose side is not a multiple of 8 has threads past its edge, and a store
## there is outside the image. A kernel written in the dialect may leave the
## check out, and this file writes it for the kernel's `def`:
##
##     def blur():                     void blur() { ivec2 sa_edge_at = ...;
##         ...                             if (any(greaterThanEqual(sa_edge_at,
##                                             imageSize(dst)))) return;
##
## on the signature's own line, so the count of lines holds as it does for
## every pass of the compiler.
##
## **Which texel and which image.** The texel is the thread's own,
## `gl_GlobalInvocationID.xy`, moved by `origin` when the kernel's params
## declare one, because every pass that hands a kernel an `origin` has it read
## and write at `pixel + ivec2(origin)`, which is the texel the hand-written
## checks of the box blur and its siblings compare. The image is the one the
## kernel's own body first stores to with `image_store` or `dst[at] = c`, and when the body
## stores only through a library, the box blur's `sa_finish`, the last image the
## file declares without `readonly`, which is the target in every filter's
## contract. A kernel that names neither gets no check.
##
## **A kernel that writes its own keeps it.** A body holding a `return` or
## reading an `image_size` already decides what a thread past the edge does,
## the Gaussian blur's walk before its return above all, and gets no second
## check. So a kernel written the old way transpiles to the GLSL it always did.
##
## **A barrier turns the return into a guard on each store.** A thread that
## returned never reaches a `barrier()`, and a group whose threads do not all
## reach one is undefined. The barrier is often in a library, the Gaussian's
## walk, which this file cannot see from the kernel's text alone, so the swap is
## [method finished], run by the include processor on the program the imports
## were pasted into. It takes the early return out and puts every `imageStore`
## to that image the kernel reaches inside a test of its own texel.
@tool
extends RefCounted

## What a piece of text holds, reached by path the way the dialect reaches it.
const GmacsScan := preload("res://core/custom-shader/dialect/sa_gmacs_scan.gd")

## A store written with brackets, `dst[at] = c`, which names its image too.
const ImageBrackets := preload("res://core/custom-shader/dialect/sa_image_brackets.gd")

## The local the check declares. Sara's prefix, so a kernel's own names do not
## meet it, and the marker [method finished] reads the check back by.
const AT_NAME: String = "sa_edge_at"

## The thread's own texel, written without `pixel` so the check stands in a
## file that never uses the word and the dialect declares none.
const INVOCATION: String = "ivec2(gl_GlobalInvocationID.xy)"

## The params field a pass writes the corner of its dispatch into.
const ORIGIN_FIELD: String = "origin"

## The check as it is written and as [method finished] finds it again: the
## texel, then the image.
const CHECK: String = "ivec2 %s = %s; if (any(greaterThanEqual(%s, imageSize(%s)))) return;"

## The guard a store takes in a program that waits at a barrier: the texel,
## the image, then the store itself.
const STORE_GUARD: String = "{ if (all(lessThan(%s, imageSize(%s)))) %s; }"

## The words a definition's pattern also finds in a body, `else if (x) {` and
## its kin, which are no function.
const NOT_FUNCTIONS: Array[String] = ["if", "for", "while", "switch", "return", "else"]


## Kernel name -> the check its signature line takes, for every kernel of
## *codes* that needs one. *codes* is the file's lines with their comments and
## docstrings taken out, and *indents* their indentation, as the dialect's pass
## holds them before it rewrites a line.
static func checks(codes: Array[String], indents: Array[int]) -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    var kernels := _kernel_names(codes)
    if kernels.is_empty():
        return out
    var target := _last_writable_image(codes)
    var images := _image_names(codes)
    var texel := _texel(codes, indents)
    var def_line := RegEx.new()
    def_line.compile("^\\s*def\\s+(\\w+)\\s*\\(")
    for i in codes.size():
        var found := def_line.search(codes[i])
        if found == null or not kernels.has(found.get_string(1)):
            continue
        var body := _body(codes, indents, i)
        if _checks_itself(body):
            continue
        var image := _stored_image(body, images)
        if image.is_empty():
            image = target
        if image.is_empty() or not images.has(image):
            continue
        out[found.get_string(1)] = " " + CHECK % [AT_NAME, texel, AT_NAME, image]
    return out


## *glsl* with every check this file wrote swapped for a guard on each store,
## when the program waits at a `barrier()`, and *glsl* as it stands otherwise.
##
## Run by the include processor on the program a kernel's imports were pasted
## into, because the barrier and the store are often both in a library. A store
## is guarded where the kernel that carried the check reaches it, its own body
## and every function it calls down the chain, so a sibling kernel in the same
## file that checks for itself keeps its program. A helper both call is guarded
## for both, a test the sibling's own check already made true. Run twice it
## answers the same, since a program already swapped holds no check to swap.
static func finished(glsl: String) -> String:
    var waits := RegEx.new()
    waits.compile("\\bbarrier\\s*\\(\\s*\\)")
    if waits.search(glsl) == null:
        return glsl
    var marker := RegEx.new()
    marker.compile(
        " ?ivec2 %s = [^;]*; if \\(any\\(greaterThanEqual\\(%s, imageSize\\((\\w+)\\)\\)\\)\\) return;" % [AT_NAME, AT_NAME]
    )
    var found_all := marker.search_all(glsl)
    if found_all.is_empty():
        return glsl
    var bodies := _bodies(glsl)
    # Image -> the names of the functions whose stores to it are guarded.
    var guarded: Dictionary[String, Array] = {}
    for found: RegExMatch in found_all:
        var kernel := _holding(bodies, found.get_start())
        if kernel.is_empty():
            continue
        var image := found.get_string(1)
        var names: Array = guarded.get(image, [])
        for name: String in _reached(glsl, bodies, kernel):
            if not names.has(name):
                names.append(name)
        guarded[image] = names
    # From the end, so a span read before an edit still points at its text.
    var edits: Array = []
    for image: String in guarded:
        for name: String in guarded[image]:
            var span: Vector2i = bodies[name]
            edits.append_array(_store_edits(glsl, image, span))
    for found: RegExMatch in found_all:
        edits.append([found.get_start(), found.get_end(), ""])
    edits.sort_custom(_later_first)
    var out := glsl
    for edit: Array in edits:
        var from: int = edit[0]
        var to: int = edit[1]
        out = out.substr(0, from) + str(edit[2]) + out.substr(to)
    return out


## True when the edit *a* starts after *b*, so the edits run from the end.
static func _later_first(a: Array, b: Array) -> bool:
    var a_from: int = a[0]
    var b_from: int = b[0]
    return a_from > b_from


## Function name -> the span of its body in *glsl*, from its opening brace to
## its closing one, for every function the text defines.
static func _bodies(glsl: String) -> Dictionary[String, Vector2i]:
    var out: Dictionary[String, Vector2i] = {}
    var definition := RegEx.new()
    definition.compile("\\b(\\w+)[ \\t]+(\\w+)[ \\t]*\\(([^(){};]*)\\)[ \\t]*\\{")
    for found: RegExMatch in definition.search_all(glsl):
        var name := found.get_string(2)
        if name in NOT_FUNCTIONS or found.get_string(1) in NOT_FUNCTIONS:
            continue
        var open := found.get_end() - 1
        var close := _closing(glsl, open, "{", "}")
        if close > open:
            out[name] = Vector2i(open, close)
    return out


## The function of *bodies* whose body holds *at*, or nothing.
static func _holding(bodies: Dictionary[String, Vector2i], at: int) -> String:
    for name: String in bodies:
        var span: Vector2i = bodies[name]
        if at > span.x and at < span.y:
            return name
    return ""


## *kernel* and every function of *bodies* it calls, down the chain.
static func _reached(glsl: String, bodies: Dictionary[String, Vector2i], kernel: String) -> Array[String]:
    var called := RegEx.new()
    called.compile("\\b(\\w+)\\s*\\(")
    var reached: Array[String] = [kernel]
    var i := 0
    while i < reached.size():
        var span: Vector2i = bodies[reached[i]]
        for found: RegExMatch in called.search_all(glsl.substr(span.x, span.y - span.x)):
            var name := found.get_string(1)
            if bodies.has(name) and not reached.has(name):
                reached.append(name)
        i += 1
    return reached


## The edits that put every `imageStore` to *image* inside *span* of *glsl*
## inside a test of the texel it names, each `[from, to, text]`. A store whose
## brackets or semicolon cannot be found is left as it stands, which is a store
## the check never covered rather than a broken file.
static func _store_edits(glsl: String, image: String, span: Vector2i) -> Array:
    var store := RegEx.new()
    store.compile("\\bimageStore\\s*\\(\\s*%s\\s*," % image)
    var edits: Array = []
    for found: RegExMatch in store.search_all(glsl, span.x, span.y):
        var open := glsl.find("(", found.get_start())
        var close := _closing(glsl, open, "(", ")")
        var semicolon := close + 1
        while semicolon < glsl.length() and glsl[semicolon] == " ":
            semicolon += 1
        if close < 0 or semicolon >= glsl.length() or glsl[semicolon] != ";":
            continue
        var args := GmacsScan.split_args(glsl.substr(open + 1, close - open - 1))
        var stored := glsl.substr(found.get_start(), close + 1 - found.get_start())
        edits.append([found.get_start(), semicolon + 1, STORE_GUARD % [args[1], image, stored]])
    return edits


## Where the bracket *opener* at *open* in *text* closes, or -1. A `//` comment
## is passed over, because the dialect's text still carries its comments.
static func _closing(text: String, open: int, opener: String, closer: String) -> int:
    var depth := 0
    var i := open
    while i < text.length():
        if text[i] == "/" and i + 1 < text.length() and text[i + 1] == "/":
            var end := text.find("\n", i)
            if end < 0:
                return -1
            i = end
        elif text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


## The names every `kernel` directive of *codes* gives.
static func _kernel_names(codes: Array[String]) -> Array[String]:
    var names: Array[String] = []
    var directive := RegEx.new()
    directive.compile("^\\s*kernel\\s+(.+)$")
    for code: String in codes:
        var found := directive.search(code)
        if found == null:
            continue
        for name: String in GmacsScan.split_args(found.get_string(1)):
            names.append(name.strip_edges())
    return names


## Every image *codes* declares, writable or not.
static func _image_names(codes: Array[String]) -> Array[String]:
    var names: Array[String] = []
    for found: RegExMatch in _images(codes):
        names.append(found.get_string(1))
    return names


## The last image *codes* declares without `readonly`, or nothing.
static func _last_writable_image(codes: Array[String]) -> String:
    var last := ""
    for found: RegExMatch in _images(codes):
        if not "readonly" in GmacsScan.split_args(found.get_string(2)):
            last = found.get_string(1)
    return last


## The `image` declarations of *codes*, name then qualifiers, in file order.
static func _images(codes: Array[String]) -> Array[RegExMatch]:
    var out: Array[RegExMatch] = []
    var declaration := RegEx.new()
    declaration.compile("^\\s*image\\s+(\\w+)\\s*(?::\\s*(.+))?$")
    for code: String in codes:
        var found := declaration.search(code.strip_edges(false, true))
        if found != null:
            out.append(found)
    return out


## The texel a thread's check compares: its own, moved by the params' `origin`
## when the file declares one, read through the block's instance when it has a
## name.
static func _texel(codes: Array[String], indents: Array[int]) -> String:
    var header := RegEx.new()
    header.compile("^\\s*params(?:\\s+(\\w+))?\\s*:\\s*$")
    var field := RegEx.new()
    field.compile("^\\s*i?vec2\\s+%s\\s*$" % ORIGIN_FIELD)
    for i in codes.size():
        var found := header.search(codes[i])
        if found == null:
            continue
        for line: String in _body(codes, indents, i):
            if field.search(line) != null:
                var instance := found.get_string(1)
                var named := ORIGIN_FIELD if instance.is_empty() else "%s.%s" % [instance, ORIGIN_FIELD]
                return "%s + ivec2(%s)" % [INVOCATION, named]
    return INVOCATION


## The code lines of the block whose header is line *at* of *codes*, the text
## after the header's colon included, so a one-line `def` is read too.
static func _body(codes: Array[String], indents: Array[int], at: int) -> Array[String]:
    var lines: Array[String] = []
    var colon := codes[at].rfind(":")
    if colon >= 0 and not codes[at].substr(colon + 1).strip_edges().is_empty():
        lines.append(codes[at].substr(colon + 1))
    for i in range(at + 1, codes.size()):
        if codes[i].strip_edges().is_empty():
            continue
        if indents[i] <= indents[at]:
            break
        lines.append(codes[i])
    return lines


## True when *body* decides for itself what a thread past the edge does.
static func _checks_itself(body: Array[String]) -> bool:
    var own := RegEx.new()
    own.compile("\\breturn\\b|\\b(?:image_size|imageSize)\\s*\\(")
    for line: String in body:
        if own.search(line) != null:
            return true
    return false


## The image the first store of *body* names, `image_store` or a bracket on one
## of *images*, or nothing.
static func _stored_image(body: Array[String], images: Array[String]) -> String:
    var store := RegEx.new()
    store.compile("\\b(?:image_store|imageStore)\\s*\\(\\s*(\\w+)\\s*,")
    for line: String in body:
        var found := store.search(line)
        if found != null:
            return found.get_string(1)
        var bracketed := ImageBrackets.stored(line, images)
        if not bracketed.is_empty():
            return bracketed
    return ""
