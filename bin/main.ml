open Current.Syntax
module Git = Current_git
module Github = Current_github

let forall_refs ~installations fn =
  installations
  |> Current.list_iter ~collapse_key:"org" (module Github.Installation)
     @@ fun installation ->
     Github.Installation.repositories installation
     |> Current.list_iter ~collapse_key:"repo" (module Github.Api.Repo)
        @@ fun repo ->
        let refs = Github.Api.Repo.ci_refs repo in
        refs
        |> Current.list_iter (module Github.Api.Commit) @@ fun head ->
           fn (Git.fetch (Current.map Github.Api.Commit.id head))

let build_with_docker commit =
  Current.component "build"
  |> let> commit in
     Build.(BC.run local commit ())

let v ~app () : unit Current.t =
  let installations = Github.App.installations app in
  forall_refs ~installations build_with_docker

let main config app : ('a, [ `Msg of string ]) result =
  Lwt_main.run
  @@
  let engine = Current.Engine.create ~config (v ~app) in
  Current.Engine.thread engine

open Cmdliner

let cmd =
  let doc = "Test the OCaml compiler" in
  let info = Cmd.info "compiler-ci-service" ~doc in
  Cmd.v info
    Term.(
      term_result (const main $ Current.Config.cmdliner $ Github.App.cmdliner))

let () = exit @@ Cmd.eval cmd
