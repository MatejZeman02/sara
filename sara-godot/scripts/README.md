# scripts

Helpers that run beside the Godot project, in Python and shell.

- The door client: `sara.py` and its helpers reach a running Sara over the local door from Python or a notebook, see `packaging/agent-guide.md` for the same door by `curl`.
- Build helpers: what `packaging/build.sh` and the exports call.
- Style and lint checks: `check_style.sh` and `check_lsp.sh` run `gdformat` and `gdlint` and read the editor's diagnostics, and they need a `gdtoolkit` environment under `.conda` or `.venv`.
- Each `test_*.py` beside a script is its unittest suite, run with `python -m unittest`.
