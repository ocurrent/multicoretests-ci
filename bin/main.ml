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
        (* let default = Github.Api.Repo.head_commit repo in *)
        let refs = Github.Api.Repo.ci_refs repo in
        refs
        |> Current.list_iter (module Github.Api.Commit) @@ fun head ->
           fn (Git.fetch (Current.map Github.Api.Commit.id head))

let build_with_docker commit =
  (* let build ~platforms ~spec ~repo commit = *)
    Current.component "build"
    |> let> { Spec.variant; ty; label } = spec
       and> commit
       and> platforms
       and> repo in
       match
         List.find_opt
           (fun p -> Variant.equal p.Platform.variant variant)
           platforms
       with
       | Some { Platform.builder; variant; base; _ } ->
           BC.run builder
             { Op.Key.commit; repo; label }
             { Op.Value.base; ty; variant }
       | None ->
           (* We can only get here if there is a bug. If the set of platforms changes, [Analyse] should recalculate. *)
           let msg =
             Fmt.str "BUG: variant %a is not a supported platform" Variant.pp
               variant
           in
           Current_incr.const (Error (`Msg msg), None)


let v ~app () : unit Current.t =
  let installations = Github.App.installations app in
  forall_refs ~installations (fun src ->
      let builds =
        let repo =
          Current.map
            (fun x ->
              Github.Api.Repo.id x |> fun repo ->
              { Repo_id.owner = repo.owner; name = repo.name })
            repo
        in
        build_with_docker ?ocluster ?on_cancel ~repo ~analysis ~platforms src
      in
      ())

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
