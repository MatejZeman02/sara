# AGENTS.md

Sara is a GPU-first painting program in Godot, under the GPLv3. This page is
for a coding agent opened in a clone of the public repository.

- Read `CONTRIBUTING.md` first. It has the setup, the seven
  hard rules, the rules of structure and the conventions, and it is the only
  copy of them here.
- Obey the seven hard rules. The ones a change is most likely to break: the
  canvas never leaves the graphics card during a stroke (1), a compute shader is
  never dispatched over the whole canvas (2), `SaTexture` and `SaCompute` are
  never freed by hand (4), and only `SaUI.apply_to_window()` writes
  `Window.content_scale_factor` (7).
- A comment is prose. British spelling in prose and in every string Sara shows,
  American in identifiers, and no em dashes or semicolons.
- Before you call a change done, from `sara-godot`:

  ```bash
  SARA_TEST_OFFSCREEN=1 ./run_tests.sh     # exit code 0, not the summary line
  ./scripts/check_style.sh                 # gdformat and gdlint, needs gdtoolkit
  ```

  `./run_tests.sh <word>` runs the suites whose names hold the word, which is
  what to use while working. The tests need a Vulkan device and `weston`.
- To see a change work, drive the running program through its door, described in
  `packaging/agent-guide.md`. Start your own Sara
  with `--settings-dir=<folder>` so it never touches a painter's settings.
- Building is `packaging/README.md`, and the manual is in
  `sara-godot/manual/`.
