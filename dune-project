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
  (current (>= 0.6.4))
  (current_github (>= 0.6.4))
  (current_docker (>= 0.6.4))
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
  (current (>= 0.6.4))
  (current_github (>= 0.6.4))
  (current_docker (>= 0.6.4))
  (current_ocluster (>= 0.2.1))
  (cmdliner (>= 1.1.0))
  (dockerfile-opam (>= 8.2.1))
  (obuilder-spec (>= 0.5.1))
  (ocaml-version (>= 3.6.1))))
