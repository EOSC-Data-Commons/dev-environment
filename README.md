# EOSC dev-environment

The local development environment is built using [Nix](https://nixos.org/) and managed with [devenv](https://devenv.sh/).
This setup is **not** intended to replace the `docker-compose` recipes provided in each sub-repository. 
Instead, it offers a **monolithic development environment** that integrates all components into a single, unified workflow.

Pros:

- Compared to `docker-compose`, this approach manages all components in a single repository, allowing changes to be made ad hoc and tested immediately.
- By avoiding containerized file systems (which VS Code dev containers can handle if needed), you can use your preferred editor (e.g. Emacs, Neovim) without additional setup.
- The full deployment requires only ~60 MiB of disk space and uses nearly zero CPU when idle, since all services run as local Unix processes.
- Cleanup is handled via predefined tasks, and all generated data remains within this repository instead of being spread across Docker volumes and sub-repositories.
- Services are managed by [process-compose](https://github.com/F1bonacc1/process-compose), and all logs can be inspected from a single, unified interface.

Cons:

* Networking is not isolated from the host system. As a result, service ports may conflict with existing system services. In such cases, ports must be customized in `devenv.nix`.

## Getting Started

- [x] The guide is tested in Linux.
- [x] The guide is tested running using docker.

TODO:
- [ ] test on Windows with WSL2
- [ ] test on macOS (apple silicon)
- [ ] ~~test on macOS (intel) not planed~~

### Install nix and devenv

#### Install Nix

- Linux and Windows (WSL2):

```console
sh <(curl -L https://nixos.org/nix/install) --daemon
```

- macOS

```console
curl -L https://github.com/NixOS/experimental-nix-installer/releases/download/0.27.0/nix-installer.sh | sh -s -- install
```

- Docker 

```console
docker run -it nixos/nix
```

For more details if you get stucked, check [here](https://devenv.sh/getting-started/#1-install-nix)

#### Install devenv

```console
nix-env --install --attr devenv -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable
```

If you already know nix you probably want to install it though: nix profile, nix-darwin or through home-manager, check [here](https://devenv.sh/getting-started/#2-install-devenv)

#### (optional) Configure a GitHub access token

To avoid being rate-limited, **we recommend providing Nix with a GitHub access token**, which will greatly increase your API limits.

Create a new token with no extra permissions at https://github.com/settings/personal-access-tokens/new. Add the token to your ``~/.config/nix/nix.conf``:

```console
access-tokens = github.com=<GITHUB_TOKEN>
```

check [here](https://devenv.sh/getting-started/#3-configure-a-github-access-token-optional) for details.
