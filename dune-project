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
  current
  current_github
  current_docker
  (cmdliner (>= 1.1.0)))
 (tags
  (topics "to describe" your project)))

(package
 (name compiler-ci-service)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends
  ocaml
  dune
  current
  current_github
  current_docker
  (cmdliner (>= 1.1.0)))
 (tags
  (topics "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
