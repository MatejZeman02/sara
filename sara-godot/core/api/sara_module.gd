## The old name of `SaModule`, kept for a module written outside the tree.
##
## The base class of every module was `SaraModule` before the door's classes
## took the `Sa` prefix, and a module somebody wrote then still says
## `extends SaraModule`. It loads as it did, because this class is `SaModule`
## and adds nothing. A new module writes `extends SaModule`, and nothing in the
## tree names this class but the suite that keeps it working.
class_name SaraModule extends SaModule
