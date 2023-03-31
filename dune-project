(lang dune 3.7)

(name compiler-ci)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name")

(maintainers "Maintainer Name")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name compiler-ci)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends
  ocaml
  dune
  logs
  fmt
  capnp-rpc-unix
  current
  current_github
  current_docker
  (cmdliner (>= 1.1.0)))
 (tags
  (topics "to describe" your project)))

(package
 (name compiler-ci-lib)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends
  ocaml
  dune
  logs
  fmt
  capnp-rpc-lwt
  current
  current_github
  current_docker
  current_ocluster
  (cmdliner (>= 1.1.0))
  dockerfile-opam
  obuilder-spec)
 (tags
  (topics "to describe" your project)))
