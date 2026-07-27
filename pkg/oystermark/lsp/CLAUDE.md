Development of LSP is driven by specifications in docs/ dir.
- Docs starting with `feature-...` is a specification that needs to be implemented.
- All implementation needs to be tested.
  - Tests can exists as inline expect tests in the same file that implements it.
  - Or in the `./tests/` dir as a standalone file.
- The implementation needs to reference the specification it is implementing using odoc syntax. The same is required for its test. If the test is not in the same file as its implementation, it needs to reference both the code and spec.
- Use `dune build @doc-private @doc` regularly to make sure everything is in synced.
- Encapsulation is important:
  - Define module interface (`.mli` file and inline submodule) to explicitly control what should be exposed.
  - For testing utils, define it as `module For_test ...`
- Property-based testing is encouraged. Trace-based testing is encouraged.
- `main.ml` is the one file `dune runtest` cannot reach: it is the protocol
  adapter, and the tests drive `Server` in process. A handler hung off the
  wrong linol hook type-checks, passes every test, and is never called. After
  changing it, run `scripts/smoke.py` (see README) against the built binary.

Design
- The LSP is expected to be a glue layer on top of the core functionlities. In the long term, we would like most of the core calculations provided by upstream (oystermark/lib).
  - It's fine to experiment with new features here in a self-contained way though.
