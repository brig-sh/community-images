# Gemini CLI guest image

Gemini CLI as a bootable guest image: Ubuntu 24.04 (arm64), the `gemini` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/gemini:arm64`.

Gemini CLI publishes no native Linux binary, only an npm package whose entry
point is bundled JavaScript. So this is the one image here that carries a node
runtime (node 22 from NodeSource, since Ubuntu 24.04 ships node 18 and the
package needs 20 or newer).

The image runs as user `gemini` (uid 501 by default), and `/home/gemini`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** Either interactively, or from a `GEMINI_API_KEY` forwarded by the host. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `gemini` the unprivileged user can run.

Pinned at `GEMINI_VERSION=0.55.1`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
