let install_project_deps opam_repo_commit os arch =
  let prefix =
    match os with
    | `Macos -> "~/local"
    | `Linux -> "/usr"
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let ln =
    match os with
    | `Macos -> "ln"
    | `Linux -> "sudo ln"
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let open Obuilder_spec in
  let cache =
    match os with
    | `Linux ->
        [
          Obuilder_spec.Cache.v "opam-archives"
            ~target:"/home/opam/.opam/download-cache";
        ]
    | `Macos ->
        [
          Obuilder_spec.Cache.v "opam-archives"
            ~target:"/Users/mac1000/.opam/download-cache";
          Obuilder_spec.Cache.v "homebrew"
            ~target:"/Users/mac1000/Library/Caches/Homebrew";
        ]
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let network = [ "host" ] in
  let home_dir =
    match os with
    | `Macos -> None
    | `Linux -> Some "/src"
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let work_dir =
    match os with
    | `Macos -> "./src/"
    | `Linux -> "./"
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let setup_pins =
    let copy_opam_files =
      copy
        [
          "multicoretests.opam";
          "qcheck-lin.opam";
          "qcheck-multicoretests-util.opam";
          "qcheck-stm.opam";
        ]
        ~dst:work_dir
    in
    let do_pins =
      run ~network ~cache
        "opam pin --no-action qcheck-multicoretests-util.dev %s && opam pin \
         --no-action qcheck-lin.dev %s && opam pin --no-action qcheck-stm.dev \
         %s && opam pin --no-action multicoretests.dev %s"
        work_dir work_dir work_dir work_dir
    in
    [ copy_opam_files; do_pins ]
  in
  let opam_depext =
    run ~network ~cache
      "opam update --depexts && opam install --cli=2.1 --depext-only -y %s"
      work_dir
  in
  (if Ocaml_version.arch_is_32bit arch then
     [ shell [ "/usr/bin/linux32"; "/bin/sh"; "-c" ] ]
   else [])
  @ (match home_dir with
    | Some home_dir -> [ Obuilder_spec.workdir home_dir ]
    | None -> [])
  @ [
      run "%s -f %s/bin/opam-2.1 %s/bin/opam && opam init --reinit -ni" ln
        prefix prefix;
    ]
  @ (match home_dir with
    | Some home_dir -> [ workdir home_dir; run "sudo chown opam /src" ]
    | None -> [])
  @ [
      (* Fetch the latest ocaml/opam-repository *)
      run ~network ~cache
        "cd ~/opam-repository && (git cat-file -e %s || git fetch origin \
         master) && git reset -q --hard %s && git log --no-decorate -n1 \
         --oneline && opam update -u"
        opam_repo_commit opam_repo_commit;
      run ~network
        "opam repository add override \
         https://github.com/shym/custom-opam-repository.git --all-switches \
         --set-default";
    ]
  @ setup_pins
  @ [
      env "CI" "true";
      opam_depext;
      run ~network ~cache "opam install %s" work_dir;
    ]

let v opam_repo_commit base os arch =
  let open Obuilder_spec in
  let home_dir =
    match os with
    | `Macos -> "./src"
    | `Linux -> "/src"
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let run_build =
    (* Build all before test to minimise disruption of interleaved compilation.
       Run with [-j1] to run tests sequentially, as tests are timing- and load-sensitive *)
    let build_and_test =
      "eval $(opam env) && dune build && dune runtest -j1 --no-buffer \
       --display=quiet"
    in
    match os with
    | `Macos -> run "cd ./src && %s" build_and_test
    | `Linux -> run "%s" build_and_test
    | `Windows | `Cygwin -> failwith "Windows and Cygwin not supported"
  in
  let opam_repo_commit = Current_git.Commit_id.hash opam_repo_commit in
  stage ~from:base
    (env "QCHECK_MSG_INTERVAL" "60"
     :: run "ocaml --version && opam --version"
     :: user_unix ~uid:1000 ~gid:1000
     :: install_project_deps opam_repo_commit os arch
    @ [ copy [ "." ] ~dst:home_dir; run_build ])
