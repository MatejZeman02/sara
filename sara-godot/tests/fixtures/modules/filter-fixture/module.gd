## A module that exists to own a kernel, so a test can prove that
## `SaFilterContext.kernel()` resolves a module's own `.gmacs` the way a
## built-in's resolves.
##
## Under `tests/fixtures/modules/` rather than `res://modules/`, so the shader
## index files its kernel under the owner `filter-fixture` while ModuleLoader,
## which only walks `res://modules`, never discovers it. That is the whole
## trick: the shader half of hard rule 6 is proved without a module being
## loaded into the running app.
##
## The id has to stay the directory name. The index takes a shader's owner from
## the directory it lives under, and a module whose id says something else
## would ask for a kernel nobody filed.
extends SaModule


func get_id() -> StringName:
    return &"filter-fixture"


func get_name() -> String:
    return "Filter fixture"
