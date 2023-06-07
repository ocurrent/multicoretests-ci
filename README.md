# Multicoretests-CI

This is an OCurrent pipeline that provides CI for the [ocaml-multicore/multicoretests](https://github.com/ocaml-multicore/multicoretests) repository, which itself intensively tests the consistency of the OCaml multicore compiler runtime. Multicoretests-CI runs the tests on a variety of platforms to ensure coverage of operating systems, architectures, and versions of OCaml.

If you have a fork of `ocaml-multicore/multicoretests`, you can test it by installing the [`multicoretests` GitHub App](https://github.com/apps/multicoretests-ci) on the organisation that owns the fork, and then adding the fork to the list of checked repositories. You must choose the fork explicitly rather than allowing all repositories on the organisation to be checked. You must also request @benmandrew or @mtelvers to add you to the list of alpha-testers.

You can observe the results of the tests on GitHub on the corresponding commit, via Check Runs (shown as an orange circle, a red cross, or a green tick next to the commit).

### Platforms

The current platforms are:

- MacOS, ARM64, OCaml 5.0
- MacOS, ARM64, OCaml 5.1~alpha1
- MacOS, ARM64, OCaml 5.2
- Linux*, ARM64, OCaml 5.0
- Linux*, ARM64, OCaml 5.1
- Linux*, ARM64, OCaml 5.2
- Linux*, S390x, OCaml 5.1
- Linux*, S390x, OCaml 5.2

*Specifically Debian 11.

This list can be expanded to other platforms very easily, as specified in [conf.ml](lib/conf.ml).

### Pipeline

Multicoretests-CI is able to test multiple repositories by the structure of the OCurrent pipeline, which is defined in [main.ml](bin/main.ml). It:

1. Gets the list of installations of its GitHub app
2. For each installation, gets the list of repositories to check
3. For each repository, gets the branches and PRs to check
4. For each target, it fetches the head commit, generates a Dockerfile and builds it

The generated Dockerfile `opam install`s the dependencies according to Multicoretests' `*.opam` files, and then adds the rest of the source files. It then executes `dune build && dune runtest -j1` to first completely build the project, and then run the tests sequentially. As the tests are timing- and load-sensitive, these choices serve to avoid disruption.


## Installation

Get the code with:
```
git clone --recursive https://github.com/ocurrent/multicoretests-ci.git
cd multicoretests-ci
```

Then you need an opam 2.1 switch using OCaml 5.0. Recommend using this command to setup a local switch just for multicoretests-ci.
```
# Create a local switch with packages and test dependencies installed
opam switch create . 5.0.0 --deps-only --with-test -y
# Run the build
dune build
# Run the tests
dune build @runtest
```

## Deployment

`multicoretests-ci` is deployed with [ocurrent-deployer](https://deploy.ci.dev/?repo=ocurrent/multicoretests-ci&). It is deployed as a Docker image built from `Dockerfile`, with the live service following the `live` branch. An `ocurrent-deployer` pipeline watches this branch, performing a Docker build and deploy whenever it sees a new commit. The `live` branch should typically contain commits from `main` plus potentially short lived commits for testing changes that are later merged into `main`.

The infrastructure for `multicoretests-ci` is managed via Ansible. Contact @tmcgilchrist or @mtelvers if you need access or have questions.


## Local Development

This document sets you up to use a locally running instance of `multicoretests-ci` to build a `multicoretests` fork owned by your GitHub user.

### GitHub App

Since `multicoretests-ci` is a GitHub App, create a GitHub App ([settings/apps](https://github.com/settings/apps)) under your own user and point it to localhost via a webhook payload delivery service like [smee.io](https://smee.io).

To do this, follow the instructions in [Setting up your development environment to create a GitHub App](https://docs.github.com/en/developers/apps/getting-started-with-apps/setting-up-your-development-environment-to-create-a-github-app) but when it comes to setting permissions for your app, set the following as the "Repository permissions":

```
Checks: Read and write
Commit statuses: Read and write
Contents: Read-only
Metadata: Read-only
Pull requests: Read-only
```

Also, subscribe to the following events:

```
Create
Pull request
Push
```

### Running the pipeline locally

You will need the following:

1. The GitHub App ID of the app you created
2. The `pem` file containing the private key associated to the app
3. A comma separated list of GitHub accounts to allow - this could start out as just your GitHub account
4. A capability file for submitting jobs to a cluster, in this case the main cluster as documented in https://github.com/ocurrent/ocluster#admin
5. The app webhook secret that is used to authenticate to the app

```
dune exec -- multicoretests-ci \
  --github-app-id <your-github-app-id> \
  --github-private-key-file <path-to/private-key.pem> \
  --github-account-allowlist <your-github-username> \
  --github-webhook-secret-file <path-to-the-app-secret> \
  --submission-service <path-to-the-submission-capability-file> \
  --capnp-listen-address tcp:127.0.0.1:9001
```

You should see the site on `localhost:8080`. You can then install the GitHub App onto your account and add the desired repository, the builds for which should then show up on the website.
