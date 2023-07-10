open Current.Syntax
open Multicoretests_ci_lib
open Lwt.Infix
module Platform = Conf.Platform

let platforms = Conf.platforms ()
let jobs = Hashtbl.create 512

(** Latest commit of opam repository *)
let opam_repo_commit =
  let repo =
    { Current_github.Repo_id.owner = "ocaml"; name = "opam-repository" }
  in
  Current_github.Api.Anonymous.head_of repo (`Ref "refs/heads/master")

let get_job_id x =
  let+ md = Current.Analysis.metadata x in
  match md with Some { Current.Metadata.job_id; _ } -> job_id | None -> None

let record_job commit (platform : Platform.t) build =
  let+ state = Current.state ~hidden:true build
  and+ job_id = get_job_id build
  and+ commit in
  match job_id with
  | None -> ()
  | Some job_id ->
      Hashtbl.add jobs
        (Current_git.Commit.hash commit)
        (Platform.label platform, state, job_id)

let build_with_docker ?ocluster ~opam_repo_commit ~platforms commit =
  let build platform =
    let build =
      match ocluster with
      (* | None -> Build.v commit *)
      | None -> failwith "Local building not supported"
      | Some ocluster ->
          Cluster_build.v ~ocluster ~platform ~opam_repo_commit commit
    in
    let _ = record_job commit platform build in
    build
  in
  List.map
    (fun platform ->
      let build = build platform in
      let+ state = Current.state ~hidden:true build
      and+ job_id = get_job_id build in
      (platform, state, job_id))
    platforms
  |> Current.list_seq

let forall_refs ~installations fn =
  installations
  |> Current.list_iter ~collapse_key:"org" (module Current_github.Installation)
     @@ fun installation ->
     Current_github.Installation.repositories installation
     |> Current.list_iter ~collapse_key:"repo" (module Current_github.Api.Repo)
        @@ fun repo ->
        let refs = Current_github.Api.Repo.ci_refs repo in
        refs
        |> Current.list_iter ~collapse_key:"ref"
             (module Current_github.Api.Commit)
           @@ fun head -> fn head

let v_ref ?ocluster ~opam_repo_commit ~platforms head =
  let builds =
    Current_git.fetch (Current.map Current_github.Api.Commit.id head)
    |> build_with_docker ?ocluster ~opam_repo_commit ~platforms
  in
  let hash = Current.map Current_github.Api.Commit.hash head in
  Current.pair builds hash
  |> Current.map (fun (builds, hash) ->
         List.iter
           (fun (platform, _, job_id) ->
             Option.iter (fun id -> Commits.record_job platform hash id) job_id)
           builds;
         builds)
  |> Current.map
       (List.map (fun (platform, state, job_id) ->
            (Platform.label platform, state, job_id)))
  |> Github.status_of_state
  |> Current_github.Api.CheckRun.set_status head "Multicoretests-CI"

let v ?ocluster ~app () =
  let ocluster =
    Option.map (Cluster_build.config ~timeout:(Duration.of_hour 5)) ocluster
  in
  Current.with_context opam_repo_commit @@ fun () ->
  Current.with_context platforms @@ fun () ->
  let installations = Current_github.App.installations app in
  Current.bind
    (fun platforms ->
      forall_refs ~installations (v_ref ?ocluster ~opam_repo_commit ~platforms))
    platforms

let get_job_ids ~owner:_ ~name:_ ~hash =
  let _, _, job_id = Hashtbl.find jobs hash in
  [ job_id ]

let run_capnp capnp_listen_address =
  let listen_address =
    match capnp_listen_address with
    | Some listen_address -> listen_address
    | None -> Capnp_rpc_unix.Network.Location.tcp ~host:"0.0.0.0" ~port:9000
  in
  let config =
    Capnp_rpc_unix.Vat_config.create ~secret_key:`Ephemeral listen_address
  in
  Capnp_rpc_unix.serve config >>= fun vat -> Lwt.return vat

let main () config mode app capnp_listen_address github_auth submission_uri =
  Lwt_main.run
  @@ ( run_capnp capnp_listen_address >>= fun vat ->
       let ocluster =
         Option.map (Capnp_rpc_unix.Vat.import_exn vat) submission_uri
       in
       let engine = Current.Engine.create ~config (v ?ocluster ~app) in
       let authn = Github.authn github_auth in
       let webhook_secret = Current_github.App.webhook_secret app in
       let has_role =
         if github_auth = None then Current_web.Site.allow_all
         else Github.has_role
       in
       let secure_cookies = github_auth <> None in
       Commits.init ();
       let routes =
         Github.webhook_route ~engine ~get_job_ids ~webhook_secret
         :: Github.login_route github_auth
         :: Current_web.routes engine
         @ Commits.routes ()
       in
       let site =
         Current_web.Site.v ?authn ~has_role ~secure_cookies
           ~name:"multicoretests-ci" routes
       in
       Lwt.choose [ Current.Engine.thread engine; Current_web.run ~mode site ]
     )

open Cmdliner

let pp_timestamp f x =
  let open Unix in
  let tm = localtime x in
  Fmt.pf f "%04d-%02d-%02d %02d:%02d.%02d" (tm.tm_year + 1900) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let reporter =
  let report src level ~over k msgf =
    let k _ =
      over ();
      k ()
    in
    let src = Logs.Src.name src in
    msgf @@ fun ?header ?tags:_ fmt ->
    Fmt.kpf k Fmt.stderr
      ("%a %a %a @[" ^^ fmt ^^ "@]@.")
      pp_timestamp (Unix.gettimeofday ())
      Fmt.(styled `Magenta string)
      (Printf.sprintf "%14s" src)
      Logs_fmt.pp_header (level, header)
  in
  { Logs.report }

let setup_log =
  Logs.set_reporter reporter;
  let docs = Manpage.s_common_options in
  Term.(const (fun _ -> ()) $ Logs_cli.level ~docs ())

let capnp_listen_address =
  let i =
    Arg.info ~docv:"ADDR"
      ~doc:
        "Address to listen on, e.g. $(b,unix:/run/my.socket) (default: no RPC)."
      [ "capnp-listen-address" ]
  in
  Arg.(
    value
    @@ opt (Arg.some Capnp_rpc_unix.Network.Location.cmdliner_conv) None
    @@ i)

let submission_service =
  Arg.value
  @@ Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None
  @@ Arg.info ~doc:"The submission.cap file for the build scheduler service"
       ~docv:"FILE" [ "submission-service" ]

let cmd =
  let doc = "CI for multicoretests, run on a GitHub repository" in
  let info = Cmd.info "multicoretests-ci-service" ~doc in
  Cmd.v info
    Term.(
      term_result
        (const main
        $ setup_log
        $ Current.Config.cmdliner
        $ Current_web.cmdliner
        $ Current_github.App.cmdliner
        $ capnp_listen_address
        $ Current_github.Auth.cmdliner
        $ submission_service))

let () = exit @@ Cmd.eval cmd
