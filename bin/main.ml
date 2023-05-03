open Current.Syntax
open Compiler_ci_lib
open Lwt.Infix

let platforms = Conf.platforms ()
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
             Current_git.fetch @@ Current.map Current_github.Api.Commit.id head
           in
           Current.list_iter
             (module Current.Unit)
             (fun _ -> Current.return ())
             (fn repo commit)

let get_job_id x =
  let+ md = Current.Analysis.metadata x in
  match md with Some { Current.Metadata.job_id; _ } -> job_id | None -> None

let cartesian_prod l0 l1 =
  List.(flatten @@ map (fun a -> map (fun b -> (a, b)) l1) l0)

let record_job repo commit (platform : Conf.Platform.t) build =
  let+ state = Current.state ~hidden:true build
  and+ job_id = get_job_id build
  and+ repo
  and+ commit in
  let { Current_github.Repo_id.owner; name } = repo in
  match job_id with
  | None -> ()
  | Some job_id ->
      Hashtbl.add jobs
        (owner, name, Current_git.Commit.hash commit)
        (platform.label, (state, job_id))

let build_with_docker ?ocluster repo commit =
  (* Cartesian product of platforms and desired OCaml versions *)
  let platforms = cartesian_prod platforms [ "5.0"; "5.1"; "5.2" ] in
  Current.list_seq
  @@ List.map
       (fun (platform, version) ->
         let build =
           match ocluster with
           | None -> Build.v commit
           | Some ocluster -> Cluster_build.v ~ocluster ~platform version commit
         in
         record_job repo commit platform build)
       platforms

let v ?ocluster ~app () =
  let ocluster =
    Option.map (Cluster_build.config ~timeout:(Duration.of_hour 5)) ocluster
  in
  let installations = Current_github.App.installations app in
  forall_refs ~installations (build_with_docker ?ocluster)

let get_job_ids ~owner ~name ~hash =
  [ snd @@ snd @@ Hashtbl.find jobs (owner, name, hash) ]

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
       let routes =
         Github.webhook_route ~engine ~get_job_ids ~webhook_secret
         :: Github.login_route github_auth
         :: Current_web.routes engine
       in
       let site =
         Current_web.Site.v ?authn ~has_role ~secure_cookies ~name:"compiler-ci"
           routes
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
  let info = Cmd.info "compiler-ci-service" ~doc in
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
