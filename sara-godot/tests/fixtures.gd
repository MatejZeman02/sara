## Shared fixtures so tests stop building UI trees to get a document.
##
## Before SaEasel and SaSurface, every tool test had to construct a SaCanvas
## (a TextureRect) and poke a document into it. A surface is now an easel plus
## a view, and both can be faked.
class_name SaTestFixtures
extends RefCounted


## A SaView that reports whatever the test tells it to, with no scene tree.
class FakeView:
    extends SaView

    var mouse_position: Vector2 = Vector2.ZERO
    var zoom: float = 1.0
    var pan: Vector2 = Vector2.ZERO
    var rotation: float = 0.0
    var flip: Vector2 = Vector2.ONE
    var viewport_size: Vector2 = Vector2(1000, 1000)

    func get_document_mouse_position() -> Vector2:
        return mouse_position

    func get_zoom() -> float:
        return zoom

    func set_zoom(value: float) -> void:
        zoom = value
        transform_changed.emit()

    func get_pan() -> Vector2:
        return pan

    func set_pan(value: Vector2) -> void:
        pan = value
        transform_changed.emit()

    func get_rotation() -> float:
        return rotation

    func set_rotation(value: float) -> void:
        rotation = value
        transform_changed.emit()

    func get_flip() -> Vector2:
        return flip

    func set_flip(value: Vector2) -> void:
        flip = value
        transform_changed.emit()

    func get_viewport_size() -> Vector2:
        return viewport_size


## A minimal module for loader and registry tests.
class FakeModule:
    extends SaModule

    var module_id: StringName = &"fake"
    var deps: PackedStringArray = []
    var api_version: int = SaContext.API_VERSION
    var register_count: int = 0
    var unregister_count: int = 0

    func get_id() -> StringName:
        return module_id

    func get_dependencies() -> PackedStringArray:
        return deps

    func get_api_version() -> int:
        return api_version

    func register(_ctx: SaContext) -> void:
        register_count += 1

    func unregister(_ctx: SaContext) -> void:
        unregister_count += 1


## A tool that records what it was given, for registry and machine tests.
class FakeTool:
    extends ToolState

    var events: Array = []
    var reset_count: int = 0
    var cursor_radius: float = -1.0

    func handle_input(event: InputEvent) -> void:
        events.append(event)

    func reset() -> void:
        reset_count += 1

    func get_cursor_radius() -> float:
        return cursor_radius


## The door's client in a suite: a request written as `curl` writes one, and
## the answer read back off a stream peer the suite polls by hand, since the
## door's own frames run in the same process.
class DoorHttp:
    extends RefCounted

    ## Rounds of polling both ends before a wait gives up, a few milliseconds
    ## each.
    const ROUNDS: int = 400

    ## A `POST` of *body* to *target* carrying *token* as `Authorization:
    ## Bearer`, or no such header when *token* is empty.
    static func request(body: String, token: String, target: String = "/step") -> PackedByteArray:
        var head := "POST %s HTTP/1.1\r\nHost: sara\r\nContent-Type: application/json\r\n" % target
        if not token.is_empty():
            head += "Authorization: Bearer %s\r\n" % token
        var bytes := (head + "Content-Length: %d\r\n\r\n" % body.to_utf8_buffer().size()).to_utf8_buffer()
        bytes.append_array(body.to_utf8_buffer())
        return bytes

    ## Sends *step* as one request and waits for its answer, calling *frame*
    ## between reads so the door runs. The answer's JSON comes back with the
    ## characters of its body under `"chars"`, the figure a client pays for it,
    ## `{"closed": true}` when the door closed first, and `{"timed_out": true}`
    ## when nothing came within *rounds*.
    static func ask(client: StreamPeerSocket, step: Variant, token: String, frame: Callable, rounds: int = ROUNDS) -> Dictionary:
        client.put_data(request(JSON.stringify(step), token))
        var answer := wait(client, frame, PackedByteArray(), rounds)
        if not answer.has("body"):
            return answer
        var body: Variant = answer["body"]
        var parsed: Dictionary = (body as Dictionary).duplicate() if body is Dictionary else {"body": body}
        parsed["status"] = answer["status"]
        parsed["chars"] = int(answer["chars"])
        return parsed

    ## Polls until *client* holds a whole answer, calling *frame* each round,
    ## and returns `{"status": n, "headers": {...}, "body": parsed, "chars": n}`,
    ## or `{"closed": true}` or `{"timed_out": true}`. What arrives after the
    ## answer is kept in *received* for the next wait.
    static func wait(
        client: StreamPeerSocket, frame: Callable, received: PackedByteArray = PackedByteArray(), rounds: int = ROUNDS
    ) -> Dictionary:
        for _i in rounds:
            frame.call()
            client.poll()
            if client.get_status() == StreamPeerSocket.STATUS_CONNECTED:
                var available := client.get_available_bytes()
                if available > 0:
                    var got: Array = client.get_data(available)
                    received.append_array(got[1])
            var answer := parse(received)
            if not answer.is_empty():
                var rest := received.slice(int(answer["used"]))
                received.clear()
                received.append_array(rest)
                return answer
            if client.get_status() != StreamPeerSocket.STATUS_CONNECTED:
                return {"closed": true}
            OS.delay_msec(2)
        return {"timed_out": true}

    ## The whole answer at the front of *bytes*, with the bytes it took under
    ## `"used"`, or {} while it is not whole.
    static func parse(bytes: PackedByteArray) -> Dictionary:
        var head_end := -1
        for i in range(0, bytes.size() - 3):
            if bytes[i] == 13 and bytes[i + 1] == 10 and bytes[i + 2] == 13 and bytes[i + 3] == 10:
                head_end = i
                break
        if head_end < 0:
            return {}
        var lines := bytes.slice(0, head_end).get_string_from_utf8().split("\r\n")
        var headers := {}
        for i in range(1, lines.size()):
            var colon := lines[i].find(":")
            headers[lines[i].left(colon).to_lower()] = lines[i].substr(colon + 1).strip_edges()
        var length := int(headers.get("content-length", "0"))
        if bytes.size() < head_end + 4 + length:
            return {}
        var text := bytes.slice(head_end + 4, head_end + 4 + length).get_string_from_utf8()
        var json := JSON.new()
        var body: Variant = json.data if json.parse(text) == OK else text
        return {
            "status": int(lines[0].split(" ")[1]),
            "headers": headers,
            "body": body,
            "chars": text.strip_edges().length(),
            "used": head_end + 4 + length,
        }


## A GPU-backed easel plus a fake view. Free with `surface.easel.free()`.
static func make_surface(size: Vector2i = Vector2i(256, 256), embedded: bool = false) -> SaSurface:
    var easel := SaEasel.create_default(size)
    var surface := SaSurface.create(&"test", easel, FakeView.new())
    surface.is_embedded = embedded
    return surface


## Registries wired the way the application wires them, including the skeleton's
## own built-in blend modes.
static func make_registries(surface: SaSurface = null) -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(
        func() -> SaEasel: return surface.easel if surface != null else null,
        func() -> Array: return [surface] if surface != null else []
    )
    registries.register_builtins()
    return registries


## The base modules' image formats module, TIFF, Radiance HDR and OpenRaster.
const IMAGE_FORMATS_MODULE := "res://modules/sara-base-modules/image-formats/module.gd"

## The base modules' Stats docker module, which a suite of the skeleton reaches
## by its path because no script of the skeleton names the docker.
const STATS_MODULE := "res://modules/sara-base-modules/stats/module.gd"

## The module's TIFF writer, for a suite that needs a TIFF file to read.
const TIFF_WRITER := "res://modules/sara-base-modules/image-formats/tiff/sa_export_tiff.gd"


## Registries whose picture formats are the app's: the skeleton's four and the
## image formats module's three after them, as the running app registers them
## once its loader has read `modules/`. A suite keeps the registries it is
## handed, since the format registry is installed weakly and a dropped one
## leaves the skeleton's four behind.
static func make_picture_registries(surface: SaSurface = null) -> SaRegistries:
    var registries := make_registries(surface)
    var module: SaModule = load(IMAGE_FORMATS_MODULE).new()
    module.register(registries.context.for_module(module.get_id()))
    return registries


## Writes the picture *easel* shows as the format registered as *format_id*,
## through the writer the Export dialog calls, at *depth* or the format's own
## default when it is 0, with the eight-bit rounding dithered when *dither* is
## on. `ERR_UNAVAILABLE` when no registered format has the
## id, which for TIFF and OpenRaster means the suite holds no
## [method make_picture_registries].
## The bytes of a TIFF holding *picture* with *profile*, encoded by the image
## formats module's writer, which a suite outside the module reaches by its
## path because the skeleton names none of the module's classes.
static func tiff_bytes(picture: Image, dpi: float, profile: PackedByteArray) -> PackedByteArray:
    return load(TIFF_WRITER).encode(picture, dpi, profile)


static func export_through(format_id: StringName, easel: SaEasel, path: String, depth: int = 0, dither: bool = false) -> Error:
    var format := SaImageFormatRegistry.shared().find(format_id)
    if format == null or not format.writes():
        return ERR_UNAVAILABLE
    var write := SaImageFormat.Write.new()
    write.depth = depth if depth > 0 else format.default_depth
    write.dither = dither
    return format.writer.call(easel, path, write)


## Registries holding every command a menu lists: the app's and the shortcut
## table's on top of the skeleton's, the way main registers them. A menu is a
## list of commands, so a bar bound to anything less draws only the rows whose
## commands it was given. Help's Take a Note is the note mode's, a node, so a
## suite that wants that row passes one and frees it.
static func make_menu_registries(note_mode: SaNoteMode = null) -> SaRegistries:
    var registries := make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    if note_mode != null:
        SaNoteMode.register_command(registries.commands, note_mode)
    return registries


static func make_tool_descriptor(tool_id: StringName, script: Script = null) -> SaToolDescriptor:
    var descriptor := SaToolDescriptor.create(tool_id, script if script != null else FakeTool)
    return descriptor


## A registry holding the built-in tools with their real descriptors, so a test
## exercising quick tools does not have to restate the priorities.
##
## Both modules of `sara-base-modules`, and **the stamp brush first**:
## the brush and the eraser live there, and `ToolMachine` starts on the
## first painting tool it is given. Registering `base/` first put a fresh
## machine on the bucket fill, which is what
## `test_the_two_controls_are_docker_rows_and_not_bar_ones` reads as "the
## machine starts on the brush" and what a painter would have met as a fresh
## profile opening on the fill.
static func make_tool_registry() -> SaToolRegistry:
    var registry := SaToolRegistry.new()
    # A role registry as well, because the base module
    # registers its flood and its gradient under a role, and a context with
    # nowhere to put them refuses with an error line per role.
    var ctx := SaContext.create(
        registry,
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        SaRoleRegistry.new()
    )
    for path: String in [
        "res://modules/sara-base-modules/stamp-brush/module.gd",
        "res://modules/sara-base-modules/base/module.gd",
    ]:
        var module: SaModule = load(path).new()
        var scoped := ctx.for_module(module.get_id())
        module.register(scoped)
        # The module connects to EventBus, which is an autoload: leaving it
        # connected keeps the module, and every descriptor and shared settings
        # object it made, alive for the rest of the process.
        module.unregister(ctx)
        # And everything but its tools is taken back out, because only the
        # tool registry is handed on. A registration that holds its module's
        # context closes a cycle through the registry it sits in, the
        # Colourise layer's type and docker for one, and the cycle kept the
        # context and every registry in it alive to the end of the run, 458
        # objects a call. The app keeps its context for as long as it runs,
        # so only a context thrown away, as this one is, meets it.
        scoped.tools = SaToolRegistry.new()
        scoped.remove_all_registrations()
    return registry


## A ToolMachine already bound to a surface and the built-in tool registry.
## *wayland* says whether it tells the pen's upper button from the tip, which
## is the display server's answer unless a suite asks for the other.
static func make_bound_machine(surface: SaSurface, wayland: bool = DisplayServer.get_name() == "Wayland") -> ToolMachine:
    var machine := ToolMachine.new(wayland)
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, make_tool_registry())
    return machine


## Releases what the make_* helpers built. Registries hold descriptors,
## descriptors hold shared settings, and a surface holds an easel Node.
static func teardown(surface: SaSurface = null, machine: ToolMachine = null) -> void:
    if machine != null:
        # A ToolMachine built outside a scene tree is nobody's child, so nothing
        # frees it - and it holds the registry, which holds every descriptor,
        # which holds the tool scripts and their shared settings.
        machine.registered_tools.clear()
        machine.active_tool = null
        machine.surface = null
        machine.registry = null
        machine.free()
    if surface != null:
        # The back-reference to the front surface, cleared before the machine
        # it names is freed, so nothing here reads a dangling Node.
        surface.tool_machine = null
        if surface.easel != null:
            surface.easel.free()
            surface.easel = null
            surface.view = null


## The suite's canvas held as the document in front, the way `main` holds the
## painter's.
##
## Every harness step and every door line finds the document it
## acts on through the front surface, which is the one the current scene's
## owner holds. The scene a test run is given is `run_all.gd`, so this puts
## the suite's surface in that runner's `documents` and takes it out again,
## and a suite that drives a step at a canvas of its own holds one of these
## from `before_each` to `after_each`.
##
## A suite cannot be the current scene itself: the tree takes only a child of
## its root for that, and root refuses a child while it is setting its own
## up, which is the whole of a run.
class FrontDocuments:
    extends RefCounted

    ## The surface put in front, the suite's own or one made for its canvas.
    var surface: SaSurface = null

    ## The surface this made for a canvas whose holder had none, let go of in
    ## [method put_back]. One the holder made is the holder's to free.
    var _made: SaSurface = null

    ## *held* is the document in front until [method put_back], for a suite
    ## that built a surface itself. *mine* says the surface is this one's to
    ## let go of at the end.
    func _init(held: SaSurface, mine: bool = false) -> void:
        surface = held
        _made = held if mine else null
        var owner := FrontDocuments.owner_in_the_run()
        if owner != null:
            owner.add(held)

    ## *canvas* is the document in front until [method put_back]. The surface
    ## a node above it built, the way `MainCanvas` does, and one over its easel
    ## and view when no node did.
    static func over(canvas: SaCanvas) -> FrontDocuments:
        var held := FrontDocuments.surface_over(canvas)
        if held != null:
            return FrontDocuments.new(held)
        # The easel the canvas has, never one made here: a suite that wants no
        # GPU builds a canvas without one, and a surface over a null easel
        # still answers which canvas is in front.
        return FrontDocuments.new(SaSurface.create(&"suite", canvas.easel, canvas.view()), true)

    ## The surface a node above *canvas* built for it, or null when the canvas
    ## is a bare one a suite made. The view it draws through says which canvas
    ## a surface is for, so a host holding two does not answer the wrong one.
    static func surface_over(canvas: SaCanvas) -> SaSurface:
        var node := canvas.get_parent() if canvas != null else null
        while node != null:
            var held: Object = node.get("surface")
            if held is SaSurface and (held as SaSurface).view == canvas.view():
                return held as SaSurface
            node = node.get_parent()
        return null

    ## Brings *another* forward, in front of whichever is there, the way
    ## opening a second document does. It is the caller's to free. Answers
    ## whether it came forward, which a surface already in front does not.
    func also(another: SaSurface) -> bool:
        var held := FrontDocuments.owner_in_the_run()
        if held == null:
            return false
        held.add(another)
        return held.bring_to_front(another)

    ## Lets *another* go, whoever brought it forward, so a suite can close a
    ## document and see which one comes forward in its place.
    func close(another: SaSurface) -> void:
        var held := FrontDocuments.owner_in_the_run()
        if held != null:
            held.remove(another)

    ## The runner's owner lets the surface go, and a surface this made goes
    ## with it. Called from `after_each`, because the owner outlives the suite.
    func put_back() -> void:
        var held := FrontDocuments.owner_in_the_run()
        if held != null and surface != null:
            held.remove(surface)
        if _made != null:
            # The easel is the canvas's, freed with the node that holds it, so
            # only the surface over it is let go of here.
            _made.tool_machine = null
            _made = null
        surface = null

    ## The open documents of the run, the runner's own, or null outside one.
    ##
    ## Made here when the runner has none, since a suite may swap its own
    ## owner in and put null back, and a suite after it still needs one.
    static func owner_in_the_run() -> SaDocuments:
        var tree := Engine.get_main_loop() as SceneTree
        var scene := tree.current_scene if tree != null else null
        if scene == null:
            return null
        var held: Object = scene.get("documents")
        if held == null:
            held = SaDocuments.new()
            scene.set("documents", held)
        return held as SaDocuments
