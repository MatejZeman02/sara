## A `.sad` that holds a shared source: its chunks stored once, in the entry of
## the first layer the document holds that is drawn from it, and every user's
## entry naming that layer under `SaSharedSource.KEY`.
##
## **Why a version.** A build before this one reads a user's entry as a layer
## with no chunks and shows it empty, the way a build before version 9 would
## have shown a transformed layer where it was painted. So a document with a
## shared source is stamped [constant VERSION], as `SAD_VERSION_LIVE_TRANSFORM`
## was given its own, and an older build refuses it by name.
class_name SaSadSharedSource
extends RefCounted

## What a document with a shared source is written as.
const VERSION := 15


## The chunks a save writes into *layer*'s entry: none for a user of a shared
## source whose entry does not keep it, and otherwise what its kind stores.
static func stored_chunks(layer: SaLayer) -> Dictionary[Vector2i, SaChunk]:
    if not SaSharedSource.keeps_chunks(layer):
        var none: Dictionary[Vector2i, SaChunk] = {}
        return none
    return SaSceneLayer.stored_chunks(layer) if layer.is_scene() else SaEffectLayer.stored_chunks(layer)


## The version *layer*, drawn through a live transform, asks of a save:
## [constant VERSION] when it shares its source with another layer of its
## document, and `SaSadFile.SAD_VERSION_LIVE_TRANSFORM` otherwise.
static func version_of(layer: SaLayer) -> int:
    return VERSION if not SaSharedSource.names_sharing(layer).is_empty() else SaSadFile.SAD_VERSION_LIVE_TRANSFORM


## Puts the users of each source a loaded *document* names back on one source,
## `SaSharedSource.join`, before its caches are built.
static func join(document: SaDocument) -> void:
    SaSharedSource.join(document)
