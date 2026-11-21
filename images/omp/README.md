# Oh My Pi

[Oh My Pi](https://github.com/can1357/oh-my-pi) is a provider-agnostic
coding agent. This image installs the pinned Linux release outside the guest
home. The embedded native addon is extracted on first run without a network fetch.

No credentials are baked into the image. Pass a provider key at runtime (for
example, `OPENROUTER_API_KEY`). OMP stores its configuration and in-guest login
state under `~/.omp`, which lives in the sandbox home.

```sh
make -C images/omp build check
make -C images/omp stock check-stock AGENT_UID=0 AGENT_USER=root AGENT_HOME=/root
```
