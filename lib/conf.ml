open Current.Syntax

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
  let cap_file = cap_secrets ^ "/multicoretests-ci-admin.cap"
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

module OV = Ocaml_version
module DD = Dockerfile_opam.Distro

type arch = OV.arch

module Platform = struct
  type t = {
    builder : Builder.t;
    pool : string;
    distro : string;
    arch : arch;
    docker_tag : string;
    docker_tag_with_digest : string option;
    ocaml_version : string;
  }

  let compare = compare

  let distro_to_os = function
    | "debian-11" -> "linux"
    | "macos-homebrew" -> "macos"
    | "freebsd" -> "freebsd"
    | s ->
        failwith
          (Printf.sprintf
             "Unexpected distro: '%s'. Must be one of: 'debian-11', \
              'macos-homebrew', 'freebsd'"
             s)

  let label t =
    Printf.sprintf "%s-%s-%s" (distro_to_os t.distro) (OV.string_of_arch t.arch)
      t.ocaml_version

  let docker_label t =
    Printf.sprintf "ocaml/opam:%s-ocaml-%s" t.distro t.ocaml_version

  let pp = Fmt.of_to_string label
end

let freebsd_platforms : Platform.t list =
  List.map
    (fun ocaml_version ->
      Platform.
        {
          builder = Builders.local;
          pool = "freebsd-x86_64";
          distro = "freebsd";
          arch = `X86_64;
          docker_tag = "freebsd";
          docker_tag_with_digest = None;
          ocaml_version;
        })
    [ "5.2" ]

let pool_of_arch : arch -> string = function
  (* | `X86_64 | `I386 -> "linux-x86_64"
     | `Riscv64 -> "linux-riscv64" *)
  | `Aarch32 | `Aarch64 -> "linux-arm64"
  | `S390x -> "linux-s390x"
  | `Ppc64le -> "linux-ppc64"
  | (`X86_64 | `I386 | `Riscv64) as a ->
      failwith
        (Printf.sprintf "Unsupported architecture: %s" (OV.string_of_arch a))

let string_of_arch : arch -> string = function
  | `X86_64 -> "amd64"
  | `I386 -> "386"
  | `Aarch32 -> "arm"
  | `Aarch64 -> "arm64"
  | `S390x -> "s390x"
  | `Ppc64le -> "ppc64le"
  | `Riscv64 as a ->
      failwith
        (Printf.sprintf "Unsupported architecture: %s" (OV.string_of_arch a))

let image_of_distro = function
  | `Debian _ -> "debian"
  (* | `Ubuntu _ -> "ubuntu"
     | `Alpine _ -> "alpine"
     | `Archlinux _ -> "archlinux"
     | `Fedora _ -> "fedora"
     | `OpenSUSE _ -> "opensuse/leap" *)
  | d ->
      failwith
        (Printf.sprintf "Unhandled distro: %s" (DD.tag_of_distro (d :> DD.t)))

let get_digests platforms =
  let schedule = Current_cache.Schedule.v ~valid_for:(Duration.of_day 1) () in
  let f (p : Platform.t) =
    match Platform.distro_to_os p.distro with
    | "linux" ->
        Current.component "peek@,%s %s %s" p.distro p.ocaml_version
          (string_of_arch p.arch)
        |> (let> () = Current.return () in
            let docker_label = Platform.docker_label p in
            Current_docker.Raw.peek ~docker_context:None ~schedule
              ~arch:(string_of_arch p.arch) docker_label)
        |> Current.map Option.some
    | _ -> Current.return None
  in
  Current.list_seq @@ List.map f platforms
  |> Current.map
       (List.map2
          (fun (p : Platform.t) docker_tag_with_digest ->
            { p with docker_tag_with_digest })
          platforms)

let platforms () =
  let v ~arch distro ocaml_version =
    let distro_tag = DD.tag_of_distro distro in
    {
      Platform.arch;
      builder = Builders.local;
      pool = pool_of_arch arch;
      distro = distro_tag;
      docker_tag = image_of_distro distro;
      docker_tag_with_digest = None;
      ocaml_version;
    }
  in
  let platforms =
    [
      ("5.2", `Debian `V11, `Aarch64);
      ("5.2", `Debian `V11, `S390x);
      ("5.2", `Debian `V11, `Ppc64le);
    ]
    |> List.map (fun (ocaml_version, distro, arch) ->
           v ~arch distro ocaml_version)
  in
  platforms @ freebsd_platforms |> get_digests
