open Current.Syntax
open Capnp_rpc_lwt
open Lwt.Infix
module Platform = Conf.Platform

type t = {
  connection : Current_ocluster.Connection.t;
  timeout : Duration.t option;
  on_cancel : string -> unit;
}

let ( >>!= ) = Lwt_result.bind

module Op = struct
  type nonrec t = t

  let id = "ci-ocluster-build"

  module Key = struct
    type t = {
      pool : string;
      arch : Ocaml_version.arch;
      version : string;
      distro : string;
      docker_tag : string;
      commit : Current_git.Commit_id.t;
      opam_repo_commit : Current_git.Commit_id.t;
    }

    let to_json t =
      `Assoc
        [
          ("pool", `String t.pool);
          ("arch", `String (Ocaml_version.string_of_arch t.arch));
          ("version", `String t.version);
          ("commit", `String (Current_git.Commit_id.hash t.commit));
        ]

    let digest t = Yojson.Safe.to_string (to_json t)
  end

  module Value = Current.Unit
  module Outcome = Current.Unit

  let get_cache_hint (k : Key.t) =
    Fmt.str "%s/%s/%s/%s" k.pool
      (Ocaml_version.string_of_arch k.arch)
      k.version
      (Current_git.Commit_id.hash k.commit)

  let spec (k : Key.t) =
    Fmt.to_to_string Obuilder_spec.pp
    @@
    match Conf.DD.distro_of_tag k.distro with
    | None ->
        let os_family =
          if String.equal k.distro "macos-homebrew" then `Macos
          else if String.equal k.distro "freebsd" then `Freebsd
          else
            raise
              (Failure (Printf.sprintf "Distro '%s' is not available" k.distro))
        in
        Spec.v k.opam_repo_commit
          (Printf.sprintf "%s-ocaml-%s" k.distro k.version)
          os_family k.arch
    | Some d ->
        Spec.v k.opam_repo_commit k.docker_tag
          (Conf.DD.os_family_of_distro d)
          k.arch

  let run t job (k : Key.t) () =
    Current.Job.on_cancel job (fun reason ->
        Logs.debug (fun l ->
            l "Calling the cluster on_cancel callback with reason: %s" reason);
        if reason <> "Job complete" then t.on_cancel reason;
        Lwt.return_unit)
    >>= fun () ->
    let spec = spec k in
    let action = Cluster_api.Submission.obuilder_build spec in
    let src = Current_git.Commit_id.(repo k.commit, [ hash k.commit ]) in
    let cache_hint = get_cache_hint k in
    Current.Job.log job "Using cache hint %S" cache_hint;
    Current.Job.log job "Using OBuilder spec:@.%s@." spec;
    let build_pool =
      Current_ocluster.Connection.pool ~job ~pool:k.pool ~action ~cache_hint
        ~src t.connection
    in
    Current.Job.start_with ~pool:build_pool job ?timeout:t.timeout
      ~level:Current.Level.Average
    >>= fun build_job ->
    Capability.with_ref build_job (Current_ocluster.Connection.run_job ~job)
    >>!= fun (_ : string) -> Lwt_result.return ()

  let pp f ((k : Key.t), _) =
    Fmt.pf f "test %s/%s/%s/%s" k.pool
      (Ocaml_version.string_of_arch k.arch)
      k.version
      (Current_git.Commit_id.hash k.commit)

  let auto_cancel = true
  let latched = true
end

module BC = Current_cache.Generic (Op)

let config ?timeout sr =
  let connection = Current_ocluster.Connection.create sr in
  { connection; timeout; on_cancel = ignore }

let build ~ocluster ~platform ~opam_repo_commit commit =
  let {
    Platform.pool;
    arch;
    distro;
    docker_tag;
    docker_tag_with_digest;
    ocaml_version = version;
    _;
  } =
    platform
  in
  Current.component "build %s" (Platform.label platform)
  |> let> commit and> opam_repo_commit in
     let commit = Current_git.Commit.id commit in
     let docker_tag =
       match docker_tag_with_digest with None -> docker_tag | Some d -> d
     in
     BC.run ocluster
       { pool; arch; distro; docker_tag; version; commit; opam_repo_commit }
       ()

let get_job_id x =
  let+ md = Current.Analysis.metadata x in
  match md with Some { Current.Metadata.job_id; _ } -> job_id | None -> None

let v ~ocluster ~platform ~opam_repo_commit commit =
  let+ (_ : unit) = build ~ocluster ~platform ~opam_repo_commit commit in
  Platform.label platform
