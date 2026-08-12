# Contributing

Adding an agent should be a copy and an edit. If it turns into anything more
than that, the build tooling is wrong and we would rather hear about it.

## Adding an agent image

1. Copy the closest existing directory. `codex` and `opencode` install a
   native binary from a release tarball, `gemini` and `grok` go through npm
   and carry a node runtime, `claude-code` uses a vendor install script.
   Start from whichever matches how your agent ships.

   ```bash
   cp -r images/codex images/myagent
   ```

2. Edit `images/myagent/Makefile` -- it is four lines. `AGENT` is the
   directory and image name, `CLI` is the binary `make check` looks for.

3. Edit `images/myagent/Dockerfile`. Change the user name, the install stanza,
   and the header comment. Pin the CLI version in an `ARG`, and run it once
   with `--version` at the end of the install layer.

4. Edit `images/myagent/Dockerfile.overlay` -- only the `LABEL` block, to name
   the agent.

5. Add `myagent` to the two lists in
   `.github/workflows/build-images.yml`: the `filters` block in the `select`
   job, and the `image` dispatch choices. If it should publish automatically,
   add it to `PUBLISHABLE` too.

6. Build it and check it:

   ```bash
   make -C images/myagent build check
   ```

Open the pull request once `check` passes. CI will build it again on a clean
runner, which catches the things that only work because of something on your
machine.

## What we look for in review

Nothing exotic, but these come up:

- The CLI version is pinned to an exact version, not `latest`.
- The agent binary is installed outside `/home`. A host directory is mounted
  over the home at boot, so anything under there is gone at runtime.
- No credential of any kind is baked into the image.
- The install tree is readable by the unprivileged user. npm and pip install
  as root; the guest does not run as root.
- `--no-install-recommends`, and the apt lists cleaned in the same layer.

The Dockerfiles are repetitive on purpose. Please resist factoring the common
parts into a shared base image -- being able to read one file top to bottom
and know exactly what is in a sandbox is worth more here than avoiding the
duplication.

## Bumping a version

Change the `ARG` and open a pull request. CI builds it and `make check` runs
the new CLI, so a broken bump fails before it reaches the registry.

Bumps are deliberate rather than automated. An agent CLI that silently moves
under you is exactly the thing these pinned images exist to prevent.

## Commits

Conventional Commits, capitalized imperative after the colon:

```
feat(gemini): Bump the CLI to 0.56.0
fix(grok): Make the unpacked launcher readable by the runtime user
```

Sign off your commits (`git commit -s`).

## Reporting a broken image

Open an issue with the image reference, the digest (`crane digest <ref>`) and
what failed. If it is a boot failure rather than a build failure, the guest
console output is the useful part.

Support is not exhaustive and we do not claim it is. If an image here breaks,
we want to know. If an agent we do not ship does not work, that is a
bring-your-own-image question -- see
[docs/bring-your-own-image.md](docs/bring-your-own-image.md).
