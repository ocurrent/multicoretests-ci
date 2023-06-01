# Multicoretests-CI

CI for the [ocaml-multicore/multicoretests](https://github.com/ocaml-multicore/multicoretests) repository.

To run:
```
dune exec -- multicoretests-ci \
	--github-app-id <APP ID> \
	--github-private-key-file <PRIVATE KEY> \
	--github-account-allowlist <GITHUB ACCOUNT> \
	--github-webhook-secret-file <WEBHOOK SECRET> \
	--submission-service <CLUSTER CAPABILITY> \
	--capnp-listen-address tcp:127.0.0.1:9001
```
