module Db = Current.Db

module Jobs = struct
  type t = { get_job_ids : Sqlite3.stmt; record_job : Sqlite3.stmt }

  let db =
    lazy
      (let db = Lazy.force Db.v in
       Current_cache.Db.init ();
       let get_job_ids =
         Sqlite3.prepare db
           "SELECT label, hash, job_id FROM ci_build_index WHERE hash LIKE ?"
       in
       let record_job =
         Sqlite3.prepare db
           "INSERT OR REPLACE INTO ci_build_index (label, hash, job_id) VALUES \
            (?, ?, ?)"
       in
       { get_job_ids; record_job })

  let db_init =
    lazy
      (let db = Lazy.force Db.v in
       Sqlite3.prepare db
         {|CREATE TABLE IF NOT EXISTS ci_build_index (
              label  TEXT NOT NULL,
              hash   TEXT NOT NULL,
              job_id TEXT NOT NULL,
              PRIMARY KEY (label, hash, job_id)
            );|})

  let get_jobs hash_prefix =
    let t = Lazy.force db in
    (* The string 'hash%' matches prefix *)
    let hash_prefix =
      Option.value ~default:"" hash_prefix |> Printf.sprintf "%s%%"
    in
    Db.query t.get_job_ids Sqlite3.Data.[ TEXT hash_prefix ]
    |> List.map @@ function
       | Sqlite3.Data.[ TEXT label; TEXT hash; TEXT id ] -> (label, hash, id)
       | row -> Fmt.failwith "get_job_ids: invalid row %a" Db.dump_row row
end

let init () =
  let t = Lazy.force Jobs.db_init in
  Db.exec t []

let record_job platform hash job_id =
  let label = Conf.Platform.label platform in
  let t = Lazy.force Jobs.db in
  Db.exec t.record_job Sqlite3.Data.[ TEXT label; TEXT hash; TEXT job_id ]

open Tyxml_html

let string_param name uri =
  match Uri.get_query_param uri name with
  | None | Some "" -> None
  | Some x -> Some x

let string_option ~placeholder ~title name value =
  let value = Option.value value ~default:"" in
  input
    ~a:
      [
        a_name name;
        a_input_type `Text;
        a_value value;
        a_placeholder placeholder;
        a_title title;
      ]
    ()

let enum_option ~choices name (value : string option) =
  let value = Option.value value ~default:"" in
  let choices = "" :: choices in
  select
    ~a:[ a_name name ]
    (choices
    |> List.map (fun form_value ->
           let sel = if form_value = value then [ a_selected () ] else [] in
           let label = if form_value = "" then "(any)" else form_value in
           option ~a:(a_value form_value :: sel) (txt label)))

let commit_tip = "Any prefix of the commit hash can be used here."

let filter_jobs ?os ?arch ?version jobs =
  let optional_filter f input =
    match Option.map f input with Some b -> b | None -> true
  in
  let f (label, _, _) =
    let open Astring in
    optional_filter (fun os -> String.is_infix ~affix:os label) os
    && optional_filter (fun arch -> String.is_infix ~affix:arch label) arch
    && optional_filter
         (fun version -> String.is_infix ~affix:version label)
         version
  in
  List.filter f jobs

let render_page ctx =
  let uri = Cohttp.Request.uri @@ Current_web.Context.request ctx in
  let render_row (label, hash, id) =
    let link = Printf.sprintf "http://localhost:8080/job/%s" id in
    tr
      [
        td [ txt label ];
        td [ a ~a:[ a_href link ] [ txt id ] ];
        td [ txt hash ];
      ]
  in
  let hash = string_param "hash" uri in
  let os = string_param "os" uri in
  let arch = string_param "arch" uri in
  let version = string_param "version" uri in
  (* Sorted in newest-first order, by lexicographic ordering on job ID: [YYYY-MM-DD/HHMMSS-...] *)
  let jobs =
    Jobs.get_jobs hash
    |> filter_jobs ?os ?arch ?version
    |> List.sort (fun (_, _, id0) (_, _, id1) -> -String.compare id0 id1)
  in
  let content =
    if jobs = [] then [ txt "No jobs satisfy these criteria." ]
    else
      [
        form
          ~a:[ a_action "/commits"; a_method `Post ]
          [
            table
              ~a:[ a_class [ "table" ] ]
              ~thead:
                (thead
                   [
                     tr
                       [
                         th [ txt "Platform" ];
                         th [ txt "Job" ];
                         th [ txt "Hash" ];
                       ];
                   ])
              (List.map render_row jobs);
          ];
      ]
  in
  [
    form
      ~a:[ a_action "/commits"; a_method `Get ]
      [
        ul
          ~a:[ a_class [ "query-form" ] ]
          [
            li
              [
                txt "Operating system:";
                enum_option ~choices:[ "linux"; "macos" ] "os" os;
              ];
            li
              [
                txt "Architecture:";
                enum_option ~choices:[ "arm64"; "s390x" ] "arch" arch;
              ];
            li
              [
                txt "OCaml version:";
                enum_option ~choices:[ "5.0"; "5.1"; "5.2" ] "version" version;
              ];
            li
              [
                txt "Commit hash:";
                string_option "hash" hash ~placeholder:"" ~title:commit_tip;
              ];
            li [ input ~a:[ a_input_type `Submit; a_value "Submit" ] () ];
          ];
      ];
  ]
  @ content

let handle =
  object
    inherit Current_web.Resource.t
    method! nav_link = Some "Commit search"
    val! can_get = `Viewer

    method! private get context =
      Current_web.Context.respond_ok context (render_page context)
  end

let routes () = Routes.[ (s "commits" /? nil) @--> handle ]
