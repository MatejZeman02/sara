## What the three suites that build a scenario's `.sad` share:
## the file this build saves is held against the one under `tests/data/`, and
## the tracked file is rewritten only when the run asks for it.
##
## A difference fails the suite, naming the fixture, so a run never leaves
## `git status` showing changed fixtures and a change to the format never goes by on a
## green run.
## `SARA_REWRITE_FIXTURES=1 ./run_tests.sh` is the one way to write it again.
extends RefCounted

## The variable that lets a run write the tracked fixtures.
const FLAG: String = "SARA_REWRITE_FIXTURES"
## The relief light a fresh install starts a document under. A document takes
## its light from Preferences, and a suite earlier in the run can leave those
## moved, so a fixture saved without pinning it held strength 4 after a whole
## run and 2 after its own suite alone.
const ANGLE: float = 315.0
const STRENGTH: float = 2.0


## Sets what *document* took from the run's Preferences to a fresh install's,
## so the bytes it saves do not depend on the suites before it.
static func pin(document: SaDocument) -> void:
    document.relief_light.angle = ANGLE
    document.relief_light.strength = STRENGTH


## Whether *fixture* differs from *written*, the bytes this build saved. With
## the flag set, a fixture that differs is rewritten and counts as current.
## Without it, the bytes are left at `saved_beside` for a comparison.
static func stale(fixture: String, written: PackedByteArray) -> bool:
    if written == FileAccess.get_file_as_bytes(fixture):
        return false
    if OS.get_environment(FLAG) != "1":
        var kept := FileAccess.open(saved_beside(fixture), FileAccess.WRITE)
        kept.store_buffer(written)
        kept.close()
        return true
    var file := FileAccess.open(ProjectSettings.globalize_path(fixture), FileAccess.WRITE)
    file.store_buffer(written)
    file.close()
    return false


## Where the bytes a stale *fixture* was held against are left, in the run's
## own data folder.
static func saved_beside(fixture: String) -> String:
    return ProjectSettings.globalize_path(SaDataRoot.path("saved_now_" + fixture.get_file()))


## The line a suite fails with when *fixture* is stale.
static func why(fixture: String) -> String:
    return (
        "%s is not what this build saves, which is at %s, and %s=1 ./run_tests.sh writes it again"
        % [fixture, saved_beside(fixture), FLAG]
    )
