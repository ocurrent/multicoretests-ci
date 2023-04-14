open Current.Syntax
open Capnp_rpc_lwt
open Lwt.Infix

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
      distro : string;
      commit : Current_git.Commit_id.t;
    }

    let to_json t =
      `Assoc
        [
          ("pool", `String t.pool);
          ("commit", `String (Current_git.Commit_id.hash t.commit));
        ]

    let digest t = Yojson.Safe.to_string (to_json t)
  end

  module Value = Current.Unit
  module Outcome = Current.Unit

  let hash_packages packages =
    Digest.string (String.concat "," packages) |> Digest.to_hex

  let get_cache_hint (k : Key.t) =
    Fmt.str "%s/%s/%s" k.pool
      (Ocaml_version.string_of_arch k.arch)
      (Current_git.Commit_id.hash k.commit)

  let run t job (k : Key.t) () =
    Current.Job.on_cancel job (fun reason ->
        Logs.debug (fun l ->
            l "Calling the cluster on_cancel callback with reason: %s" reason);
        if reason <> "Job complete" then t.on_cancel reason;
        Lwt.return_unit)
    >>= fun () ->
    let spec =
      Fmt.to_to_string Obuilder_spec.pp
      @@
      match Conf.DD.distro_of_tag k.distro with
      | None -> Spec.v "macos-homebrew-ocaml-5.0" `Macos k.arch
      | Some d -> Spec.v "ocaml/opam" (Conf.DD.os_family_of_distro d) k.arch
    in
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
    Fmt.pf f "test %s/%s" k.pool (Current_git.Commit_id.hash k.commit)

  let auto_cancel = true
  let latched = true
end

module BC = Current_cache.Generic (Op)

let config ?timeout sr =
  let connection = Current_ocluster.Connection.create sr in
  { connection; timeout; on_cancel = ignore }

let v ~ocluster ~platform commit =
  let { Conf.Platform.pool; arch; distro; _ } = platform in
  Current.component "build %s" platform.label
  |> let> commit in
     let commit = Current_git.Commit.id commit in
     BC.run ocluster { pool; arch; distro; commit } ()
