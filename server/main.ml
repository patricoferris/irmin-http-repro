(* ~~~ Irmin Store ~~~ *)
open Lwt.Syntax
open Cohttp_lwt_unix

let info = Irmin_unix.info "set"

[@@@part "0"]
module Store = Irmin_unix.Git.FS.KV (Irmin.Contents.String)
module Sync = Irmin.Sync (Store)
module Http = Irmin_http.Server (Cohttp_lwt_unix.Server) (Store)

let repo = "/tmp/irmin-repro"

[@@@part "1"]
let store () =
  let config = Irmin_git.config ~bare:true repo in
  let* repo = Store.Repo.v config in
  let* t = Store.master repo in
  let+ _ = Store.set_exn ~info t [ "hello.md" ] "# Hello World" in
  repo

[@@@part "2"]
let callback repo conn req body =
  let uri = Cohttp.Request.resource req in
  match uri with
  | "" | "/" | "/index.html" ->
      Server.respond_file ~fname:"server/index.html" ()
  | "/index.js" ->
      Server.respond_file ~fname:"_build/default/client/index.bc.js" ()
  | _irmin_path -> Http.callback repo conn req body

[@@@part "3"]
let serve repo = Server.create (Server.make ~callback:(callback repo) ())

let main () =
  let* repo = store () in
  serve repo

let () = Lwt_main.run @@ main ()
