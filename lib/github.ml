open Current.Syntax

(* Access control policy. *)
let has_role user = function
  | `Viewer | `Monitor -> true
  | `Builder | `Admin -> (
      match Option.map Current_web.User.id user with
      | Some
          ( "github:talex5" | "github:avsm" | "github:kit-ty-kate"
          | "github:mtelvers" | "github:samoht" | "github:tmcgilchrist"
          | "github:dra27" | "github:benmandrew" ) ->
          true
      | Some _ | None -> false)

let webhook_route ~engine ~get_job_ids ~webhook_secret =
  Routes.(
    (s "webhooks" / s "github" /? nil)
    @--> Current_github.webhook ~engine ~get_job_ids ~webhook_secret)

let login_route github_auth =
  Routes.((s "login" /? nil) @--> Current_github.Auth.login github_auth)

let authn github_auth =
  Option.map Current_github.Auth.make_login_uri github_auth

let list_errors ~ok errs =
  let groups =
    (* Group by error message *)
    List.sort compare errs
    |> List.fold_left
         (fun acc (msg, l) ->
           match acc with
           | (m2, ls) :: acc' when m2 = msg -> (m2, l :: ls) :: acc'
           | _ -> (msg, [ l ]) :: acc)
         []
  in
  Error
    (`Msg
      (match groups with
      | [] -> "No builds at all!"
      | [ (msg, _) ] when ok = 0 ->
          msg (* Everything failed with the same error *)
      | [ (msg, ls) ] ->
          Fmt.str "%a failed: %s" Fmt.(list ~sep:(any ", ") string) ls msg
      | _ ->
          (* Multiple error messages; just list everything that failed. *)
          let pp_label f (_, l) = Fmt.string f l in
          Fmt.str "%a failed" Fmt.(list ~sep:(any ", ") pp_label) errs))

let summarise results =
  results
  |> List.fold_left
       (fun (ok, pending, err, skip) -> function
         | _, Ok _, _ -> (ok + 1, pending, err, skip)
         | l, Error (`Msg m), _ -> (ok, pending, (m, l) :: err, skip)
         | _, Error (`Active _), _ -> (ok, pending + 1, err, skip))
       (0, 0, [], [])
  |> fun (ok, pending, err, skip) ->
  if pending > 0 then Error (`Active `Running)
  else
    match (ok, err, skip) with
    | 0, [], skip ->
        list_errors ~ok:0 skip
        (* Everything was skipped - treat skips as errors *)
    | _, [], _ -> Ok () (* No errors and at least one success *)
    | ok, err, _ -> list_errors ~ok err (* Some errors found - report *)

let status_of_state results =
  let+ results in
  let aggregated = summarise results in
  let pf f icon label result job_url =
    match job_url with
    | None -> Fmt.pf f "%s %s (%s)" icon label result
    | Some job_url -> Fmt.pf f "%s [%s (%s)](%s)" icon label result job_url
  in
  let pf_fail f icon label pp m job_url =
    match job_url with
    | None -> Fmt.pf f "%s %s (%a)" icon label pp m
    | Some job_url -> Fmt.pf f "%s [%s (%a)](%s)" icon label pp m job_url
  in
  let pp_fail prefix f m = Fmt.pf f "%s: %s" prefix (Ansi.strip m) in
  let pp_status f (label, build, job_id) =
    let job_url =
      Option.map
        (fun s -> Printf.sprintf "http://localhost:8080/job/%s" s)
        job_id
    in
    match build with
    | Ok _ -> pf f "✅" label "passed" job_url
    | Error (`Active _) -> pf f "🟠" label "active" job_url
    | Error (`Msg m) -> pf_fail f "❌" label (pp_fail "failed") m job_url
  in
  let summary = Fmt.str "@[<v>%a@]" (Fmt.list ~sep:Fmt.cut pp_status) results in
  match aggregated with
  | Ok _ -> Current_github.Api.CheckRunStatus.v (`Completed `Success) ~summary
  | Error (`Active _) -> Current_github.Api.CheckRunStatus.v `Queued ~summary
  | Error (`Msg m) when Astring.String.is_prefix ~affix:"[SKIP]" m ->
      Current_github.Api.CheckRunStatus.v (`Completed (`Skipped m)) ~summary
  | Error (`Msg m) ->
      Current_github.Api.CheckRunStatus.v (`Completed (`Failure m)) ~summary
