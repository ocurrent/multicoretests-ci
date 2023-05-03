open Compiler_ci_lib
open Lwt.Infix

let platforms = Conf.platforms ()

let cartesian_prod l0 l1 =
  List.(flatten @@ map (fun a -> map (fun b -> (a, b)) l1) l0)

let build_with_docker ?ocluster commit =
  let platforms = cartesian_prod platforms [ "5.0"; "5.1"; "5.2" ] in
  Current.list_seq
  @@ List.map
       (fun (platform, version) ->
         match ocluster with
         | None -> Build.v commit
         | Some ocluster -> Cluster_build.v ~ocluster ~platform version commit)
       platforms

let v ?ocluster ~repo () =
  let ocluster =
    Option.map (Cluster_build.config ~timeout:(Duration.of_hour 5)) ocluster
  in
  let repo = Current_git.Local.v (Fpath.v repo) in
  let commit = Current_git.Local.head_commit repo in
  Current.list_iter
    (module Current.Unit)
    (fun _ -> Current.return ())
    (build_with_docker ?ocluster commit)

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

let main () config mode repo capnp_listen_address submission_uri =
  Lwt_main.run
  @@ ( run_capnp capnp_listen_address >>= fun vat ->
       let ocluster =
         Option.map (Capnp_rpc_unix.Vat.import_exn vat) submission_uri
       in
       let engine = Current.Engine.create ~config (v ?ocluster ~repo) in
       let site =
         Current_web.(
           Site.(v ~has_role:allow_all)
             ~name:"compiler-ci-local" (routes engine))
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

let repo =
  Arg.(
    value
    @@ opt string "."
    @@ info ~doc:"The path to the local repository to be tested."
         ~docv:"DIRECTORY" [ "repository" ])

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
  Arg.(
    value
    @@ opt (some Capnp_rpc_unix.sturdy_uri) None
    @@ info ~doc:"The submission.cap file for the build scheduler service"
         ~docv:"FILE" [ "submission-service" ])

let cmd =
  let doc = "CI for multicoretests, run on a local Git repository" in
  let info = Cmd.info "compiler-ci-local" ~doc in
  Cmd.v info
    Term.(
      term_result
        (const main
        $ setup_log
        $ Current.Config.cmdliner
        $ Current_web.cmdliner
        $ repo
        $ capnp_listen_address
        (* $ Current_github.Auth.cmdliner *)
        $ submission_service))

let () = exit @@ Cmd.eval cmd
