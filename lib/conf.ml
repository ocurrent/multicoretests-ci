let ci_profile =
  match Sys.getenv_opt "CI_PROFILE" with
  | Some "production" -> `Production
  | Some "dev" | None -> `Dev
  | Some x -> Fmt.failwith "Unknown $CI_PROFILE setting %S." x

let cmdliner_envs =
  let values = [ "production"; "dev" ] in
  let doc =
    Printf.sprintf "CI profile settings, must be %s."
      (Cmdliner.Arg.doc_alts values)
  in
  [ Cmdliner.Cmd.Env.info "CI_PROFILE" ~doc ]

(* GitHub defines a stale branch as more than 3 months old.
   Don't bother testing these. *)
let max_staleness = Duration.of_day 93

module Capnp = struct
  (* Cap'n Proto RPC is enabled by passing --capnp-public-address. These values are hard-coded
     (because they're just internal to the Docker container). *)

  let cap_secrets =
    match ci_profile with
    | `Production -> "/capnp-secrets"
    | `Dev -> "./capnp-secrets"

  let secret_key = cap_secrets ^ "/secret-key.pem"
  let cap_file = cap_secrets ^ "/ocaml-ci-admin.cap"
  let internal_port = 9000
end

let dev_pool = Current.Pool.create ~label:"docker" 1

(** Maximum time for one Docker build. *)
let build_timeout = Duration.of_hour 1

module Builders = struct
  let v docker_context =
    let docker_context, pool =
      ( Some docker_context,
        Current.Pool.create ~label:("docker-" ^ docker_context) 20 )
    in
    { Builder.docker_context; pool; build_timeout }

  let local = { Builder.docker_context = None; pool = dev_pool; build_timeout }
end

type arch =
  [ `X86_64 | `I386 | `Aarch32 | `Aarch64 | `S390x | `Ppc64le | `Riscv64 ]

module DD = Dockerfile_opam.Distro

type platform = {
  label : string;
  builder : Builder.t;
  pool : string;
  distro : string;
  arch : arch;
  docker_tag : string;
}

(* TODO Hardcoding the versions for now, this should expand to OV.Releases.recent.
   Currently we only have base images for these 2 compiler variants. See ocurrent/macos-infra playbook.yml.
*)
let macos_distros : platform list =
  [
    {
      label = "macos-homebrew";
      builder = Builders.local;
      pool = "macos-x86_64";
      distro = "macos-homebrew";
      arch = `X86_64;
      docker_tag = "homebrew/brew";
    };
    {
      label = "macos-homebrew";
      builder = Builders.local;
      pool = "macos-x86_64";
      distro = "macos-homebrew";
      arch = `X86_64;
      docker_tag = "homebrew/brew";
    };
    (* Homebrew doesn't yet seem to have arm64 base images on Dockerhub *)
    (* {
         label = "macos-homebrew";
         builder = Builders.local;
         pool = "macos-arm64";
         distro = "macos-homebrew";
         arch = `Aarch64;
         docker_tag = "homebrew/brew";
       };
       {
         label = "macos-homebrew";
         builder = Builders.local;
         pool = "macos-arm64";
         distro = "macos-homebrew";
         arch = `Aarch64;
         docker_tag = "homebrew/brew";
       }; *)
  ]

let pool_of_arch = function
  | `X86_64 | `I386 -> "linux-x86_64"
  | `Aarch32 | `Aarch64 -> "linux-arm64"
  | `S390x -> "linux-s390x"
  | `Ppc64le -> "linux-ppc64"
  | `Riscv64 -> "linux-riscv64"

let arch_to_string = function
  | `X86_64 | `I386 -> "x86_64"
  | `Aarch32 | `Aarch64 -> "arm64"
  | `S390x -> "s390x"
  | `Ppc64le -> "ppc64"
  | `Riscv64 -> "riscv64"

let image_of_distro = function
  | `Ubuntu _ -> "ubuntu"
  | `Debian _ -> "debian"
  | `Alpine _ -> "alpine"
  | `Archlinux _ -> "archlinux"
  | `Fedora _ -> "fedora"
  | `OpenSUSE _ -> "opensuse/leap"
  | d ->
      failwith
        (Printf.sprintf "Unhandled distro: %s" (DD.tag_of_distro (d :> DD.t)))

let platforms () =
  let v ?(arch = `X86_64) label distro =
    {
      arch;
      label;
      builder = Builders.local;
      pool = pool_of_arch arch;
      distro = DD.tag_of_distro distro;
      docker_tag = image_of_distro distro;
    }
  in
  let distro_arches =
    DD.active_tier1_distros `X86_64 @ DD.active_tier2_distros `X86_64
    |> List.map (fun d ->
           DD.distro_arches (Ocaml_version.v 5 0) d
           |> List.map (fun a -> (d, a)))
    |> List.flatten
  in
  List.map
    (fun (distro, arch) ->
      let distro_str = DD.tag_of_distro distro in
      v ~arch distro_str distro)
    distro_arches

(* let pull ~arch ~schedule ~builder ~distro ~docker_tag =
   Current.component "pull@,%s %s" distro (arch_to_string arch)
   |> let> () = Current.return () in
      Builder.pull ~schedule ~arch builder @@ docker_tag *)

(* let fetch_platforms ~include_macos () =
   let schedule = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) () in
   let v { label; builder; pool; distro; arch; docker_tag } =
     let base = pull ~arch ~schedule ~builder ~distro ~docker_tag in
     let host_base =
       match arch with
       | `X86_64 -> base
       | _ -> pull ~arch:`X86_64 ~schedule ~builder ~distro ~docker_tag
     in
     Platform.get ~arch ~label ~builder ~pool ~distro ~ocaml_version ~host_base
       ~opam_version base
   in
   let v2_1 = platforms ~ci_profile `V2_1 ~include_macos in
   Current.list_seq (List.map v v2_1) *)
