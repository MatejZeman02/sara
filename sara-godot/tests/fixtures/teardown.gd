## The nodes a suite built for a test freed at its end, for every suite that
## holds a canvas, an easel and often a window outside the scene tree.
##
## Thirty-eight suites each freed them in a row of `if _x != null` blocks. A
## suite now hands them here in the order they are freed, the one that reads
## another first, and sets its fields to null after, and `rg "Teardown\."`
## lists them.
extends RefCounted


## Frees each node of *nodes* in order, passing over a null and one already
## freed, so a test that failed before building them all ends cleanly.
static func free_nodes(nodes: Array) -> void:
    for node: Variant in nodes:
        if node != null and is_instance_valid(node):
            (node as Node).free()
