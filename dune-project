(lang dune 3.7)

(name multicoretests-ci)
(generate_opam_files true)
(source (github benmandrew/multicoretests-ci))
(authors "benmandrew@gmail.com")
(maintainers "benmandrew@gmail.com")

(package
 (name multicoretests-ci)
 (synopsis "Run the multicoretests suite on the GitHub repository")
 (depends
  (ocaml (>= 4.14))
  dune
  logs
  fmt
  capnp-rpc-unix
  current
  current_github
  current_docker
  (cmdliner (>= 1.1.0)))
 (allow_empty))

(package
 (name multicoretests-ci-lib)
 (synopsis "Core multicoretests-ci")
 (depends
  (ocaml (>= 4.14))
  dune
  logs
  fmt
  capnp-rpc-lwt
  current
  current_github
  current_docker
  current_ocluster
  (cmdliner (>= 1.1.0))
  (dockerfile-opam (>= 8.2.1))
  obuilder-spec
  (ocaml-version (>= 3.6.1))))
