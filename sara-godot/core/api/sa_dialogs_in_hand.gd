## The door core takes to the two windows it asks the interface for: the chooser
## Load Tip opens on an `.abr`, and the engine's file dialog a file picker builds
## on a platform with no picker of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A window a painter clicks in is interface, and `core` never names `ui`, so
## the interface attaches its two answers here when it starts and takes them
## away when it goes, the shape
## `SaPresetsInHand` has. A host with nothing attached, a headless suite, says
## in the corner that it has no window to open rather than doing nothing.
##
## Static, as `SaPresetsInHand` is: Load Tip is asked of a tool, a `RefCounted`
## handed no registries, and a file picker is opened from anywhere.
class_name SaDialogsInHand
extends RefCounted

## The object that attached the answers, which alone takes them away.
static var _owner: Object = null
## `func(path: String, on_chosen: Callable) -> void`, the chooser opened on the
## collection at *path*, or empty while nothing is attached.
static var _abr: Callable = Callable()
## `func(picker: SaFilePicker) -> Window`, the engine's dialog built for
## *picker* and put in the tree, or null where it has nowhere to stand. Empty
## while nothing is attached.
static var _file_dialog: Callable = Callable()


## Attaches the interface's two answers, *owner* the object they belong to. The
## last to attach answers, so a suite's own stands in for the app's.
static func attach(owner: Object, abr_chooser: Callable, dialog_builder: Callable) -> void:
    _owner = owner
    _abr = abr_chooser
    _file_dialog = dialog_builder


## Takes the answers away, when *owner* is still the one attached.
static func detach(owner: Object) -> void:
    if _owner == owner:
        _owner = null
        _abr = Callable()
        _file_dialog = Callable()


## Whether the interface is attached to answer.
static func is_attached() -> bool:
    return _abr.is_valid()


## What Load Tip calls with the file the picker chose: an `.abr` opens the
## chooser, whose pick reaches *loaded* with the tip's own file, and any other
## file reaches *loaded* as it is.
static func abr_ahead_of(loaded: Callable) -> Callable:
    return func(chosen: String) -> void:
        if chosen.get_extension().to_lower() == "abr":
            open_abr(chosen, loaded)
        else:
            loaded.call(chosen)


## Opens the chooser on the collection at *path*, whose pick reaches
## *on_chosen* with the path the tip was written to. Answers whether a chooser
## was asked for, and says so in the corner when nothing is attached.
static func open_abr(path: String, on_chosen: Callable) -> bool:
    if not _abr.is_valid():
        var said := TranslationServer.translate("%s is a brush collection, and there is no window here to choose its tip in.")
        EventBus.paint_refused.emit(said % path.get_file())
        return false
    _abr.call(path, on_chosen)
    return true


## The engine's file dialog built for *picker*, or null when nothing is
## attached, which is said in the corner, or the dialog had nowhere to stand.
static func file_dialog(picker: SaFilePicker) -> Window:
    if not _file_dialog.is_valid():
        EventBus.paint_refused.emit(TranslationServer.translate("There is no file picker here to open."))
        return null
    var built: Window = _file_dialog.call(picker)
    return built
