## Where the groups around the active layer can show something, read from the
## positions the active tier holds.
##
## The walk gathers the active tier from the chunks its layers hold, and
## [method SaFilterChain.scope_sweeps] composites a group's scope only at the
## positions so gathered. A blur on a group the active layer is a member of
## draws into the ring around its members' chunks, which holds none, so with a
## member active the canvas stopped at the chunk's border while a layer outside
## the group showed the spill. Each enclosing group widens the gather as the
## active layer's own filters do, by its reach and by where its records land,
## from the innermost out, so an outer group's ring is grown from the inner's.
##
## The walk keeps what it gathers to the dirty set, so a stroke on a member
## draws over the ring its region and the reach make dirty and nowhere else.
## A clip scope is left alone, its base runs its filters as a step of its own,
## and a group with no enabled record adds nothing.
##
## Beside the walk, its one caller, and not in `sa_filter_chain.gd`, which
## stands at its thousand lines.
class_name SaScopeReach
extends RefCounted


## *chunks*, a set of grid positions, grown by every non-clip scope of
## *document*'s active tier whose group carries an enabled record, through
## *chain*'s [method SaFilterChain.walked].
static func walked(chain: SaFilterChain, document: SaDocument, chunks: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
    var out := chunks
    var scopes := document.fold.active_scopes
    for i in range(scopes.size() - 1, -1, -1):
        var scope: Dictionary = scopes[i]
        if SaLayerStack.is_clip_scope(scope):
            continue
        var group: SaLayer = scope[SaLayerStack.GROUP]
        if group != null and SaFilterChain.has_enabled(group.filters):
            out = chain.walked(group, out)
    return out
