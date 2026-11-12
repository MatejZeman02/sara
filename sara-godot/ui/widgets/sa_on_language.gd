## Writes a control's words again whenever the language changes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A word a control was given through `tr()` once stays in the language of that
## moment. The top bar and the docker's controls are built before a language
## module's catalogue arrives, so under Czech the rotation slider read
## "Rotate: 0 °" and the presets' size slider "Size: 112" in English without
## one. A watcher is a child of the control that calls the
## control's own writer again on every `NOTIFICATION_TRANSLATION_CHANGED`, which
## the engine sends on a change of locale and `SaTranslationRegistry` when a
## catalogue comes or goes, and it calls it once when made. The call waits for
## the end of the frame, because a writer that frees and builds rows again
## would otherwise free children while the notification walks them, and it
## waits on the watcher's own method, which the engine drops when the host and
## its watcher were freed in that frame, where the writer would reach a freed
## control.
class_name SaOnLanguage
extends Node

var _write: Callable


func _init(write: Callable) -> void:
    _write = write
    name = "OnLanguage"


## Hangs a watcher under *host* that runs *write* now and again at each change
## of language.
static func watch(host: Node, write: Callable) -> void:
    follow(host, write)
    write.call()


## Hangs a watcher under *host* that runs *write* at each change of language
## only, for a writer the host already calls when it has something to say, as
## the presets chooser's provenance line does.
static func follow(host: Node, write: Callable) -> void:
    host.add_child(SaOnLanguage.new(write), false, Node.INTERNAL_MODE_BACK)


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and _write.is_valid():
        _rewrite.call_deferred()


func _rewrite() -> void:
    var host := get_parent()
    if _write.is_valid() and host != null and not host.is_queued_for_deletion():
        _write.call()
