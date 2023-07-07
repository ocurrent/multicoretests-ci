open Current.Syntax
open Lwt.Infix
module Raw = Current_docker.Raw

let checkout_pool = Current.Pool.create ~label:"git-clone" 1

module Op = struct
  type t = {
    docker_context : string option;
    pool : unit Current.Pool.t;
    build_timeout : Duration.t;
  }

  let id = "ci-build"
  let dockerignore = ".git"

  module Key = struct
    type t = Current_git.Commit.t

    let to_json commit =
      `Assoc [ ("commit", `String (Current_git.Commit.hash commit)) ]

    let digest t = Yojson.Safe.to_string (to_json t)
  end

  module Value = Current.Unit
  module Outcome = Current.Unit

  let or_raise = function Ok () -> () | Error (`Msg m) -> raise (Failure m)

  let dockerfile =
    {|
((from debian)
 (run
  (network host)
  (shell "apt-get update && apt-get install -yq --no-install-recommends opam ocaml git ca-certificates"))
 (run
  (network host)
  (shell "opam init -ya -c 5.0.0 --disable-sandboxing && git clone https://github.com/ocaml-multicore/multicoretests.git"))
 (workdir "multicoretests")
 (run
  (network host)
  (shell "opam install . --deps-only --with-test -y"))
 (run (shell "eval $(opam env) && dune build && dune runtest -j1 --no-buffer --display=quiet test/ && dune build @ci -j1 --no-buffer --display=quiet --error-reporting=twice")))
    |}

  let run { docker_context; pool; build_timeout } job commit () =
    Current.Job.start ~timeout:build_timeout ~pool job
      ~level:Current.Level.Average
    >>= fun () ->
    Current_git.with_checkout ~pool:checkout_pool ~job commit @@ fun dir ->
    Current.Job.write job
      (Fmt.str "Writing BuildKit Dockerfile:@.%s@." dockerfile);
    Bos.OS.File.write Fpath.(dir / "Dockerfile") (dockerfile ^ "\n") |> or_raise;
    Bos.OS.File.write Fpath.(dir / ".dockerignore") dockerignore |> or_raise;
    let cmd =
      Raw.Cmd.docker ~docker_context @@ [ "build"; "--"; Fpath.to_string dir ]
    in
    let pp_error_command f = Fmt.string f "Docker build" in
    Current.Process.exec ~cancellable:true ~pp_error_command ~job cmd

  let pp f (commit, _) = Fmt.pf f "test %a" Current_git.Commit.pp commit
  let auto_cancel = true
  let latched = true
end

let dev_pool = Current.Pool.create ~label:"docker" 1
let build_timeout = Duration.of_hour 1
let local = { Op.docker_context = None; pool = dev_pool; build_timeout }

module BC = Current_cache.Generic (Op)

let v commit =
  Current.component "build"
  |> let> commit in
     BC.run local commit ()
