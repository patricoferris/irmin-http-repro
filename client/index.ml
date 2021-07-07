(* ~~~ Irmin Store ~~~ *)
open Lwt.Infix
open Js_of_ocaml_lwt

module Client = struct
  include Cohttp_lwt_jsoo.Client

  let ctx () = None
end

[@@@part "0"]
module Store =
  Irmin_git.Generic
    (Irmin_indexeddb.Content_store)
    (Irmin_indexeddb.Branch_store)
    (Irmin.Contents.String)
    (Irmin.Path.String_list)
    (Irmin.Branch.String)

(* No ocaml-git server... so using HTTP remote... *)
module Remote = Irmin_http.Client (Client) (Store)
module Sync = Irmin.Sync (Store)

[@@@part "1"]
type t = { store : Store.t; uri : Uri.t }

let sync t =
  let config = Irmin_http.config t.uri in
  Store.master @@ Store.repo t.store >>= fun main ->
  Remote.Repo.v config >>= fun repo ->
  Remote.master repo >>= fun remote ->
  Sync.pull main (Irmin.remote_store (module Remote) remote) `Set

[@@@part "2"]
let () =
  let main () =
    let config = Irmin_indexeddb.config "client-db" in
    Store.Repo.v config >>= Store.master >>= fun store ->
    sync { store; uri = Uri.of_string "http://localhost:8080" }
    >>= fun status ->
    match status with
    | Ok _ ->
        print_endline "All done!";
        Lwt.return ()
    | Error err ->
        Fmt.pr "%a%!" Sync.pp_pull_error err;
        Lwt.return () >>= fun () ->
        Store.get store [ "hello.md" ] >>= fun s ->
        print_endline s;
        Lwt.return ()
  in
  Lwt_js_events.async main
