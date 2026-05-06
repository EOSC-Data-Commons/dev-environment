# EOSC dev-environment

The local development environment is built using [Nix](https://nixos.org/) and managed with [devenv](https://devenv.sh/).
This setup is **not** intended to replace the `docker-compose` recipes provided with each sub-repository. 
Instead, this offers a **monolithic development environment** that integrates all components into a single, unified workflow.

What you get by using this for development is: starting all services by just run

```console
devenv up -v
```

and can immediately see the deployment by visiting http://localhost:5173/

The only not include in the automatic deploy flow is the LLM api keys, you need your own. 
See [this section](#set-the-api-keys) for instructions.

Once configured, you can develop directly within the submodules and see changes take effect immediately by starting the service via running `devenv up`.

## TL;DR

#### Step0: Clone repo

```console
git clone --recurse-submodules https://github.com/EOSC-Data-Commons/dev-environment.git
```

don't forget `--recurse-submodules` to get the submodules of components

#### Step1: Get API keys, and fill it in file `.env.development`

```
EINFRACZ_API_KEY=<your_key>
OPENROUTER_API_KEY=<your_key>
GITHUB_TOKEN=<your_pat_key>
VIP_API_KEY=<your_key>
OIDC_AGENT_TOKEN=<your_egi_oidc_token_get_using_oidc_agent>
```

don't put `"` around the key.

#### Step2: Start all sevices 

Run

```console
devenv up -v
```

It takes a while for the command to finish, once the packages are built and cached, starting the development environment will be lightning fast in the future.

#### Step3: visit http://localhost:5173 and search

You didn't get any results because data is not there yet.

Download the data file (`dump.sql.zip`) from the [releases page](https://github.com/EOSC-Data-Commons/dev-environment/releases/).
Unzip it and place the resulting `dump.sql` file in the repository root.

Import the data with:

```console
devenv tasks run db-import
```

After the import completes, visit [http://localhost:5173](http://localhost:5173) again. 
You should now be able to search the data using the AI-powered search (try search "onedata").

## Motivations

Pros:

- Compared to `docker-compose`, this approach manages all components in a single repository, allowing changes to be made ad hoc and tested immediately.
- By avoiding containerized file systems (which VS Code dev containers can handle if needed), you can use your preferred editor (e.g. Emacs, Neovim) without additional setup.
- The full deployment requires only ~60 MiB of disk space and uses nearly zero CPU when idle, since all services run as local Unix processes.
- Cleanup is handled via predefined tasks, and all generated data remains within this repository instead of being spread across Docker volumes and sub-repositories.
- Services are managed by [process-compose](https://github.com/F1bonacc1/process-compose), and all logs can be inspected from a single, unified interface.
- All environment variables and configurations are set in one file (i.e `devenv.nix`), makes it easy to inspect all changes and setup.

Cons:

- Networking is not isolated from the host system. As a result, service ports may conflict with existing system services. In such cases, ports must be customized in `devenv.nix`.
- Python environments are not separated but this can also regarded as pro because this force the python dependencies synchronous among projects.

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

Be careful with this approach where the caching is lost after container stopped.

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

### Into the dev shell

Clone the repo with all its submodules:

```console
git clone --recurse-submodules https://github.com/EOSC-Data-Commons/dev-environment.git
```

It is important to clean with submodules.
If you already cloned the project and forgot `--recurse-submodules`, you can use the foolproof `git submodule update --init --recursive`.

### Set the API keys

To run the LLM search sevice, the environment require `OPENROUTER_API_KEY` and `EINFRACZ_API_KEY`.
To get an `OPENROUTER_API_KEY`, create an account and visit https://openrouter.ai/settings/keys 
To get an `EINFRACZ_API_KEY`, register on chat.ai.e-infra.cz/ and contact Vincent Emonet (@vemonet).

After you get the keys, set them in `.env.development`.

### Spin up services

The environment is setup, to start all services run 

```console
devenv run -v
```

The first time it takes a while to install all package dependencies, all dependencies are cached and after it will be much faster.
(be careful if using docker with nixos/nix image, when exit from container, the caching is lost.)

It will start a TUI dashboard showing the status and logs of every services/processes.
You'll see all needed services are running and can visit http://localhost:5173/ to the frontend.

But when you search, you won't find any dataset because the database is empty.
The next step will guide you to import data ready for search.

### Import data

We need database include the havested data and indexing for opensearch.
The database was already havested and can be requst from Tobias Schweizer (@tobiasschweizer).

Download the data file (`dump.sql.zip`) from the [releases page](https://github.com/EOSC-Data-Commons/dev-environment/releases/).
Unzip it and place the resulting `dump.sql` file in the repository root.

Import the data with:

```console
devenv tasks run db-import
```

This import task takes about 30s to finish it import the dump, and create indexing for a small data repository. 

```console
python repo-index.py list
```

to get all available data repositories and then to indexing run:

```console
python repo-index.py indexing <repo-url>
```

Fill `<repo-url>` with a repo url.

Here is a summary of the number of entries in each data repository: [1]

[1] https://confluence.egi.eu/display/EOSCDATACOMMONS/2025-11-21+Work+Group+1+Update

### Clean up and reset

#### Cleanup and re-import the database

The postgresql service need keep on running to clean up the database.

To clean imported data, run:

```console
devenv tasks run clean:db
```

You can then import from dump and indexing for opensearch.

#### Cleanup and reset python/npm environments

To clean python venv run 

```console
devenv tasks run clean:python
```

This will delete the `venv` folder in the project (at `./.devenv/state/venv`).

You can then reset the environment by `devenv tasks run setup:python`.

To clean installed npm packages

```console
devenv tasks run clean:npm
```

You can then reset the environment by `devenv tasks run setup:npm`.

#### Cleanup and reset the whole environment

Cleanup tasks are provide to reset the environment if anything goes wrong and you want to have a clean start.

To clean all caches and start environment from scratch run:

```console
devenv tasks run purge
```

After this, go back to the beginning of "Get started" section and do setup again.

## For maintainer

For the maintainers of this repo, to update the submodules and update `uv.lock`, run:

```console
git submodule update --remote
devenv tasks run dev:uv-sync
```
