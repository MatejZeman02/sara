## Whether a stored view transform id is one the registry still holds, and what
## to show instead when it is not.
##
## Its own class, and not a fourth job on the preferences: a stored proof mode
## is the one setting whose read differs from what is on disk, and keeping the
## resolving read beside the raw value is what lets two known bugs of that read
## happen. `SaSettingsValues` stores what was written and this answers what can
## be shown, so a module that registers its mode on a later launch takes the
## setting back off the fallback and nothing has overwritten the file in the
## meantime.
##
## Also the two colour spaces the display chain asks for, because those are the
## same question about the same two preferences: an id resolved into the thing
## it names.
##
## `@tool` because the autoload that holds it is.
@tool
class_name SaSettingsProofs
extends RefCounted

## What the last check said about a stored id, per fallback, so the read costs
## two dictionary lookups rather than a walk. Cleared whenever the registry
## changes, which is what lets a module registering its mode late take the
## setting back off the fallback.
##
## **Keyed by the fallback as well as by the stored id**. It was keyed by the
## stored id alone, and [method mode_or] answers on both, so a profile holding
## one unregistered id in `canvas_proof_mode` and `minimap_proof_mode` got
## whichever fallback was asked for first, for both of them. Opening
## Preferences on Display was enough to reach it: the page reads the two
## dropdowns back to back, so the canvas resolved first and the Minimap
## dropdown then drew Soft Proof where its own default is Lightness Check.
##
## Nested rather than keyed by a pair because the hit path allocates nothing
## that way, and `MinimapDocker._sync_material` reads this every frame. A
## dictionary per property was the other reading in the filing and this is that
## one generalised: the key is the argument the answer depends on rather than
## the name of the setting that happened to ask.
var _answers: Dictionary[String, Dictionary] = {}

## The monitor profile file and the proof's profile file, each as last read.
## Two, because the display and the proof are set apart and a painter who holds
## both would otherwise read each file again at every sync.
var _monitor := ProfileFile.new("The display stays on sRGB: %s")
var _proof := ProfileFile.new("The soft proof stays on sRGB: %s")

## Who is asked for the system's profile of a monitor.
var _system: SaSystemProfile

## The screen the window was on when [method screen_moved] last looked, so the
## display space is told once when the window crosses to another.
var _screen: int = -1

## What the system's reading last said, so a reason goes to the log once for
## each time it changes rather than at every sync of the view.
var _system_said: String = ""


## *system* answers for the system's profile, the real system's unless a test
## hands it a stand-in.
func _init(system: SaSystemProfile = null) -> void:
    _system = system if system != null else SaSystemProfile.new()


## *stored* when the registry holds it as a mode, and *fallback* otherwise.
##
## **At read rather than at write or at load**, and the two rejected places are
## why. At write the registry cannot see a module that loads on a later launch,
## which is the case that matters: the value was valid when it was chosen and
## stops being valid while nobody is looking. At load there is no registry yet,
## the settings being an autoload and the modules arriving after. So the check
## runs where both the value and the registry exist, and the answer is remembered
## so `MinimapDocker._sync_material`, which reads this every frame, pays one
## dictionary lookup.
##
## Nothing is decided while there is no registry, and nothing is cached then
## either: the stored value comes back untouched, so a headless test or an early
## read sees the file rather than a guess.
func resolved(stored: String, fallback: String) -> String:
    return resolved_in(_view_transforms(), stored, fallback)


## [method resolved] with the registry handed to it rather than found.
##
## Split out for the reason [method mode_or] below was: a test can put a real
## registry in front of it. The property adds `_view_transforms()` and nothing
## else, and that walk reads `current_scene`, which a headless run cannot be
## given one of. `SceneTree.set_current_scene` demands a direct child of the
## root and the root is busy setting up children for the whole of a run, so the
## `add_child` is refused. The memo is on this side of that line and is proved
## by `scenarios/proof-memo-shared-key.json` on the running app.
func resolved_in(registry: SaViewTransformRegistry, stored: String, fallback: String) -> String:
    if _answers.has(fallback):
        var remembered: Dictionary[String, String] = _answers[fallback]
        if remembered.has(stored):
            return remembered[stored]
    if registry == null:
        return stored
    if not registry.changed.is_connected(_forget):
        registry.changed.connect(_forget)
    var answer := mode_or(registry, stored, fallback)
    if not _answers.has(fallback):
        var fresh: Dictionary[String, String] = {}
        _answers[fallback] = fresh
    _answers[fallback][stored] = answer
    return answer


## *stored* when *registry* holds it as a mode, and *fallback* otherwise.
##
## The decision on its own, taking the registry rather than finding one, so it
## has no memo and no tree walk in it and a test can put a real registry in
## front of it. A toggle is refused as well as an unknown id: the roll-off is a
## registered view transform and is not something a proof can be, so a settings
## file naming it would otherwise pass a bare `has` check.
func mode_or(registry: SaViewTransformRegistry, stored: String, fallback: String) -> String:
    if registry == null:
        return stored
    var descriptor := registry.get_descriptor(StringName(stored))
    var holds := descriptor != null and descriptor.kind == SaViewTransformDescriptor.Kind.MODE
    return stored if holds else fallback


func _forget() -> void:
    _answers.clear()


## The view transform registry, or null before the application has one.
##
## The same walk `core/layers/generated/sa_generated_layer.gd` makes for the
## layer types, and it is here for the same reason: a `core/` file that has to
## ask what is registered has no other door, and the alternative is a second
## copy of the registry's contents kept in step by hand.
func _view_transforms() -> SaViewTransformRegistry:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    # Read by name, because the main scene is `ui`'s and `core` never names it.
    var registries: SaRegistries = main_node.get(&"registries")
    return registries.view_transforms if registries != null else null


## The display profile as a colour space: *profile*'s preset, or for the
## monitor file choice the profile read from *path*, and sRGB when that file
## cannot be read. The reason goes to the log once for each reading of the file,
## and the Display page's file row says it too.
##
## For the system's choice, the profile the system assigns the monitor the
## main window is on, see [method display_space_on].
func display_space(profile: String, path: String, custom: Dictionary = {}) -> SaColorSpace:
    return display_space_on(profile, path, DisplayServer.window_get_current_screen(), SaSystemProfile.godot_screens(), custom)


## [method display_space] for the window standing on *screen* of *screens*, each
## Godot screen's rectangle by its index, so a test can move the window.
## *custom* is the gamut and white the custom choice holds.
func display_space_on(
    profile: String, path: String, screen: int, all_screens: Array[Rect2i], custom: Dictionary = {}
) -> SaColorSpace:
    var read: SaIccProfile = null
    if profile == SaSettingsValues.DISPLAY_PROFILE_FILE:
        read = _monitor_profile(path)
    elif profile == SaSettingsValues.DISPLAY_PROFILE_SYSTEM:
        read = system_reading(screen, all_screens).profile
    else:
        return space_for(profile, custom)
    return read.space if read.space != null else SaColorSpace.srgb()


## The proof gamut as a colour space: *profile*'s preset or the gamut by value
## *custom* holds, or for the profile file choice the profile read from *path*,
## and sRGB when that file cannot be read, as [method display_space] does for
## the monitor.
func proof_space(profile: String, path: String, custom: Dictionary = {}) -> SaColorSpace:
    if profile != SaSettingsValues.PROOF_PROFILE_FILE:
        return space_for(profile, custom)
    var read := _proof.profile(path)
    return read.space if read.space != null else SaColorSpace.srgb()


## What the system says for *screen* of *all_screens*: the monitor, the file,
## and its profile read, or refused with the reason, the system's own when it
## names none and [SaIccProfile]'s when the file it names cannot be used. The
## profile's [member SaIccProfile.name] is the monitor's when there is no file.
func system_reading(screen: int, all_screens: Array[Rect2i]) -> SaSystemProfile.Reading:
    var reading := _system.reading(screen, all_screens)
    if reading.path.is_empty():
        reading.profile = SaIccProfile.new()
        reading.profile.name = reading.monitor
        reading.profile.problem = reading.problem
    else:
        reading.profile = _monitor_profile(reading.path)
    var said := "%s|%s" % [reading.path, reading.profile.problem]
    if said != _system_said and reading.answered:
        _system_said = said
        if reading.profile.space == null:
            push_warning("The display stays on sRGB: %s" % reading.profile.problem)
    return reading


## Whether the display space has to be asked for again because the window
## stands on another screen than when this last looked, or the system's answer
## has just arrived. Asked every frame, and only while the system's profile is
## the choice, by the settings' own `_process`.
func screen_moved(screen: int) -> bool:
    var moved := screen != _screen
    _screen = screen
    return _system.just_answered() or moved


## The monitor profile file at *path* as read, remembered until the path or
## the file's modified time changes.
func _monitor_profile(path: String) -> SaIccProfile:
    return _monitor.profile(path)


## A profile id as the colour space it names, for the matrix the view finishes
## with. The custom id names *custom*, the gamut and white it holds.
static func space_for(profile: String, custom: Dictionary = {}) -> SaColorSpace:
    match profile:
        SaSettingsValues.DISPLAY_PROFILE_CUSTOM:
            return custom_space(custom)
        "display_p3":
            return SaColorSpace.display_p3()
        "rec2020":
            return SaColorSpace.rec2020()
    return SaColorSpace.srgb()


## The gamut and white *stored* holds as a colour space on sRGB's curve, the
## display's own, since the display and the proof take a gamut and a white and
## no curve. *stored* is a colour space as a header writes it, the shape a
## saved space keeps too. sRGB for one with no three primaries and a white, so
## a hand edited profile cannot leave the screen without a matrix.
static func custom_space(stored: Dictionary) -> SaColorSpace:
    if not (stored.get("primaries") is Array and stored.get("white") is Array):
        return SaColorSpace.srgb()
    var lights: Array = stored["primaries"]
    var white: Array = stored["white"]
    if lights.size() != 3 or white.size() != 2:
        return SaColorSpace.srgb()
    var header: Dictionary[String, Variant] = {"color_space": stored}
    var read := SaColorSpace.from_header(header)
    var space := SaColorSpace.create(SaColorSpace.ID_CUSTOM, read.primaries, read.white, SaTransferFunction.srgb())
    # A value that is a preset's gamut and white reads as that preset, so the
    # proof's line names it.
    for preset: SaColorSpace in SaColorSpace.presets():
        if preset.with_depth(space.depth).matches(space):
            space.id = preset.id
    return space


## A profile file as read, remembered until its path or its modified time
## changes, so the canvas, which asks for the space whenever it syncs its view,
## reads the file once rather than every time, and a file written over takes.
class ProfileFile:
    extends RefCounted

    ## The log line for a refused file, with the reason where `%s` stands.
    var _refused_line: String = ""
    var _read: SaIccProfile = null
    var _key: String = ""

    func _init(refused_line: String) -> void:
        _refused_line = refused_line

    ## The file at *path* as read, its space null and its problem said when
    ## it holds none.
    func profile(path: String) -> SaIccProfile:
        var stamp := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else -1
        var key := "%s|%d" % [path, stamp]
        if _read == null or key != _key:
            _read = SaIccProfile.read(path)
            _key = key
            if _read.space == null:
                push_warning(_refused_line % _read.problem)
        return _read
