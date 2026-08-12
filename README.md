<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brig-mark-on-dark.svg">
    <img alt="brig" src="assets/brig-mark-on-light.svg" width="72">
  </picture>
</p>

# community-images

Guest images for the coding agents brig runs, with open Dockerfiles.

brig boots each agent from an OCI image rather than running it on your
machine. Those images have to come from somewhere, and baking them into the
runtime would make them opaque -- you would be trusting a binary blob with
your source tree and your provider keys. So they live here instead, one small
Dockerfile per agent, in a public repo, built and published by a workflow you
can read.

The point is that you can check what is in the sandbox before you put an agent
in it. Read the Dockerfile, verify the signature on what we published, or
ignore our images entirely and build your own. Any Linux CLI already works as
a bring-your-own image; see [docs/bring-your-own-image.md](docs/bring-your-own-image.md).

## The images

| Agent | CLI | Vendor | Image |
| --- | --- | --- | --- |
| Claude Code | `claude` | Anthropic | `ghcr.io/brig-sh/claude-code:arm64` |
| Codex | `codex` | OpenAI | `ghcr.io/brig-sh/codex:arm64` |
| Gemini CLI | `gemini` | Google | `ghcr.io/brig-sh/gemini:arm64` |
| Grok CLI | `grok` | xAI | `ghcr.io/brig-sh/grok:arm64` |
| opencode | `opencode` | OSS | `ghcr.io/brig-sh/opencode:arm64` |
| Cursor Agent | `cursor-agent` | Cursor | not published, see below |

Claude Code and Codex are the proven core. Gemini, Grok and opencode are
example templates -- they build, and the CLI runs, but they have had less
mileage than the first two.

Image names match the agent template names, so a template row and an image
reference stay the same string.

Every image is credential-free by design. No key, no token and no session is
baked into any of them. The agent authenticates at runtime and its state lands
in the home directory, which is what brig persists for you.

### Cursor

`images/cursor/` builds and is exercised on every pull request, but we do not
publish it. Publishing would mean hosting a redistribution of Cursor's binary
from our registry, and that is a question their terms have to answer first.
That check is still open, so the image stays unpublished rather than published
and quietly hoped about.

Nothing stops you building it yourself today. `make -C images/cursor build`
fetches the CLI straight from Cursor and never touches our registry.

## Pulling and verifying

```bash
docker pull ghcr.io/brig-sh/claude-code:arm64
```

Everything we publish is signed with keyless cosign. There is no key to
distribute and no key for us to lose: the signature is bound to the workflow
that produced the image, and it is recorded in Sigstore's public transparency
log. To check a signature is really ours:

```bash
cosign verify \
  --certificate-identity-regexp \
    '^https://github.com/brig-sh/community-images/.github/workflows/build-images.yml@refs/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/brig-sh/claude-code:arm64
```

That command is the interesting one. It does not ask "was this signed?" -- it
asks "was this built by that workflow, in that repo?". A signature from
anywhere else fails it.

Each image also carries an SPDX SBOM as a signed attestation, so you can see
the packages inside before you boot it:

```bash
cosign verify-attestation --type spdxjson \
  --certificate-identity-regexp \
    '^https://github.com/brig-sh/community-images/.github/workflows/build-images.yml@refs/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/brig-sh/claude-code:arm64 \
  | jq -r '.payload | @base64d | fromjson | .predicate.name'
```

Alongside the moving `:arm64` tag, each build also publishes an immutable
`:arm64-<short-sha>` tag, so you can pin a specific build without pinning a
digest by hand.

## Building locally

You need Docker and nothing else. The guest binaries are compiled inside
containers, so there is no host toolchain to install -- this runs on an Apple
Silicon Mac as-is.

```bash
make -C images/claude-code build check
```

`build` produces `ghcr.io/brig-sh/claude-code:arm64` locally. `check` then
asserts the result is actually bootable and that the agent runs as the image's
unprivileged user. Useful knobs, all overridable on the command line:

| Variable | Default | What it does |
| --- | --- | --- |
| `IMAGE` | `ghcr.io/brig-sh/<agent>:arm64` | Tag to build |
| `PLATFORM` | `linux/arm64` | Build platform |
| `AGENT_UID` | `501` | uid of the in-guest user |
| `URUNC_SRC` / `URUNIT_SRC` | cloned into `dist/src` | Guest init checkouts |

`AGENT_UID` defaults to 501 because that is the first human user on macOS.
Files the agent writes to a shared directory then carry your ownership and
stay writable from both sides. On a Linux host, set it to your own uid.

## How an image is put together

Two stages, and the split matters.

The `Dockerfile` is a [bunny](https://github.com/nubificus/bunny) build. The
`#syntax` line at the top swaps in bunny as the BuildKit frontend, which
packages the result as a bootable microVM image rather than a plain container:
a guest kernel under `/.boot`, the urunc metadata in `/urunc.json`, and the
rootfs. Delete that one line and you get an ordinary OCI image, which is a
perfectly good thing to have.

`Dockerfile.overlay` is then a plain `docker build` on top, copying in the
guest init (`urunit`) and the exec agent (`urunit-agent`). It is separate on
purpose: bunny injects its own stock `urunit`, and the agent-capable one has
to override it. Both are compiled from source at build time, from public
repos, so an image always ships the current init rather than whatever was
vendored months ago.

`images/agent.mk` holds the actual build rules. A per-agent `Makefile` is four
lines of data on top of it.

## What is not here yet

Worth being explicit about, since these are the questions people ask.

**arm64 only.** That is what brig boots on Apple Silicon today. The
Dockerfiles are already architecture-neutral and build for amd64 locally with
`PLATFORM=linux/amd64`, but an amd64 guest needs a kernel with the block-root
virtio drivers compiled in, and that kernel build is not wired into CI yet.

**No boot test in CI.** `make check` proves an image has a kernel, its urunc
metadata, both guest binaries and a runnable CLI. It does not prove the thing
boots, because booting needs Apple Virtualization.framework and therefore an
Apple Silicon runner. Treat the published images as build-verified, not
boot-verified.

**Reproducibility is version-pinned, not bit-for-bit.** Every agent CLI is
pinned to an exact version in its Dockerfile, so a rebuild installs the same
agent. The Ubuntu package set underneath still moves.

## Adding an agent

Copy the closest existing directory and change the install stanza. That is the
whole design -- the Dockerfiles are small and repetitive on purpose, so adding
an agent is a copy and an edit rather than an exercise in build-system
archaeology. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache-2.0, see [LICENSE](LICENSE). That covers the Dockerfiles and the build
tooling in this repo. The agent CLIs the images install are each under their
own vendor's terms.
