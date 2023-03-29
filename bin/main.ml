open Current.Syntax
module Git = Current_git
open Compiler_ci_service

let jobs = Hashtbl.create 128

let forall_refs ~installations fn =
  installations
  |> Current.list_iter ~collapse_key:"org" (module Current_github.Installation)
     @@ fun installation ->
     Current_github.Installation.repositories installation
     |> Current.list_iter ~collapse_key:"repo" (module Current_github.Api.Repo)
        @@ fun repo ->
        let refs = Current_github.Api.Repo.ci_refs repo in
        refs
        |> Current.list_iter (module Current_github.Api.Commit) @@ fun head ->
           let repo = Current.map Current_github.Api.Commit.repo_id head in
           let commit =
             Git.fetch @@ Current.map Current_github.Api.Commit.id head
           in
           fn repo commit

let get_job_id x =
  let+ md = Current.Analysis.metadata x in
  match md with Some { Current.Metadata.job_id; _ } -> job_id | None -> None

let build_with_docker repo commit =
  let build =
    Current.component "build"
    |> let> commit in
       Build.(BC.run local commit ())
  in
  (* let+ state = Current.state ~hidden:true build *)
  let+ job_id = get_job_id build and+ repo and+ commit in
  let { Current_github.Repo_id.owner; name } = repo in
  match job_id with
  | None -> ()
  | Some job_id ->
      Hashtbl.add jobs
        (owner, name, Git.Commit.hash commit)
        ("macos-worker-okkkkkk", job_id)

let v ~app () =
  let installations = Current_github.App.installations app in
  forall_refs ~installations build_with_docker

let get_job_ids ~owner ~name ~hash =
  [ fst @@ Hashtbl.find jobs (owner, name, hash) ]

let main config mode app github_auth =
  Lwt_main.run
  @@
  let engine = Current.Engine.create ~config (v ~app) in
  let authn = Github.authn github_auth in
  let webhook_secret = Current_github.App.webhook_secret app in
  let has_role =
    if github_auth = None then Current_web.Site.allow_all else Github.has_role
  in
  let secure_cookies = github_auth <> None in
  let routes =
    Github.webhook_route ~engine ~get_job_ids ~webhook_secret
    :: Github.login_route github_auth
    :: Current_web.routes engine
  in
  let site =
    Current_web.Site.v ?authn ~has_role ~secure_cookies ~name:"ocaml-ci" routes
  in
  Lwt.choose [ Current.Engine.thread engine; Current_web.run ~mode site ]

open Cmdliner

let cmd =
  let doc = "Test the OCaml compiler" in
  let info = Cmd.info "compiler-ci-service" ~doc in
  Cmd.v info
    Term.(
      term_result
        (const main
        $ Current.Config.cmdliner
        $ Current_web.cmdliner
        $ Current_github.App.cmdliner
        $ Current_github.Auth.cmdliner))

let () = exit @@ Cmd.eval cmd
