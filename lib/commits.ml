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

  let get_job_ids hash_fragment =
    let t = Lazy.force db in
    (* The string 'hash%' matches prefix *)
    let hash_infix = Printf.sprintf "%s%%" hash_fragment in
    Db.query t.get_job_ids Sqlite3.Data.[ TEXT hash_infix ]
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

let render_commit hash =
  let job_ids = Jobs.get_job_ids hash in
  let open Tyxml_html in
  let f (label, hash, id) =
    let link = Printf.sprintf "http://localhost:8080/job/%s" id in
    let text = Printf.sprintf "%s - commit %s" label hash in
    p [ a ~a:[ a_href link ] [ txt text ] ]
  in
  Ok (List.map f job_ids)

let handle () hash =
  object
    inherit Current_web.Resource.t
    val! can_get = `Viewer

    method! private get context =
      let response =
        match render_commit hash with
        | Ok page -> page
        | Error msg ->
            Tyxml_html.[ txt "An error occured:"; br (); i [ txt msg ] ]
      in
      Current_web.Context.respond_ok context response
  end

let routes () = Routes.[ (s "commits" / str /? nil) @--> handle () ]
