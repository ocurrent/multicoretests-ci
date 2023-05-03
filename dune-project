(lang dune 3.7)

(name compiler-ci)
(generate_opam_files true)
(source (github benmandrew/compiler-ci))
(authors "benmandrew@gmail.com")
(maintainers "benmandrew@gmail.com")

(package
 (name compiler-ci)
 (synopsis "Run the multicoretests suite on the GitHub repository")
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
 (allow_empty))

(package
 (name compiler-ci-lib)
 (synopsis "Core compiler-ci")
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
  obuilder-spec))
