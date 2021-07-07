## Irmin HTTP Repro

*Relevant Irmin Issue: https://github.com/mirage/irmin/issues/1473*

### To reproduce

After installing the dependencies (most of them should be in `irmin-repro.opam`) you can run `make all`. Once that is serving you can go to `http://localhost:8080` and open the browser's console (tested on a Google Chrome and Brave) to see the printed errors. 

### Desired Action

The ability to sync a local Irmin store in the browser backed by IndexedDB with a remote on the server over HTTP. As far as I can tell, Irmin cannot support this directly at the moment as [ocaml-git does not yet support any server functionality](https://github.com/mirage/ocaml-git/issues/15) even for the dumb HTTP protocol. 

To stay within the Irmin world I believe this leaves one choice which is to use the `Irmin.remote_store` feature alongside `irmin-http` module. The idea being you will get the sync with the HTTP client as it always interacts remotely, this frees up the actual local store to remain "offline".

### Current Behaviour

This repository contains two submodules, `irmin-indexeddb` and `irmin`. `irmin-indexeddb` is [CraigFe's 2.6 PR + an update to 2.7.1](https://github.com/talex5/irmin-indexeddb/pull/19) and Irmin is the 2.7 branch plus [a small change I made to expose the HTTP callback](https://github.com/patricoferris/irmin/commit/f00a49034b9ad7307583525e48794fbad64bfe3f) so I could combine the irmin-http server logic with an existing server (I don't know if you can combine two Cohttp servers?). 

#### Server

On there server I'm using `Irmin_unix` with the filesystem and then wrapping it in the `irmin-http` server:

<!-- $MDX file=server/main.ml,part=0 -->
```ocaml
module Store = Irmin_unix.Git.FS.KV (Irmin.Contents.String)
module Sync = Irmin.Sync (Store)
module Http = Irmin_http.Server (Cohttp_lwt_unix.Server) (Store)

let repo = "/tmp/irmin-repro"
```

I then add a file to the `master` branch: 

<!-- $MDX file=server/main.ml,part=1 -->
```ocaml
let store () =
  let config = Irmin_git.config ~bare:true repo in
  let* repo = Store.Repo.v config in
  let* t = Store.master repo in
  let+ _ = Store.set_exn ~info t [ "hello.md" ] "# Hello World" in
  repo
```

And add set up the callbacks to serve a simple HTML page, the client and of course the irmin http server: 

<!-- $MDX file=server/main.ml,part=2 -->
```ocaml
let callback repo conn req body =
  let uri = Cohttp.Request.resource req in
  match uri with
  | "" | "/" | "/index.html" ->
      Server.respond_file ~fname:"server/index.html" ()
  | "/index.js" ->
      Server.respond_file ~fname:"_build/default/client/index.bc.js" ()
  | _irmin_path -> Http.callback repo conn req body
```

### Client 

The client is very similar, it sets up a git store using `irmin-indexeddb`, then wraps that as an `irmin-http` client.

<!-- $MDX file=client/index.ml,part=0 -->
```ocaml
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
```

**And here is the main part that is causing issues**, when trying to sync using `Irmin.remote_store` is causes an import error: 

<!-- $MDX file=client/index.ml,part=1 -->
```ocaml
type t = { store : Store.t; uri : Uri.t }

let sync t =
  let config = Irmin_http.config t.uri in
  Store.master @@ Store.repo t.store >>= fun main ->
  Remote.Repo.v config >>= fun repo ->
  Remote.master repo >>= fun remote ->
  Sync.pull main (Irmin.remote_store (module Remote) remote) `Set
```

For example, in the browser's console I get:

```
Contents import error: expected e9168dbb7daed641f96a493ae7aba8d431b148e2, got 6e08a584514644fb8ebc982a8800d4d933eddb90
```

And nothing has indeed been synced, as when we try to get the `hello.md` file:

<!-- $MDX file=client/index.ml,part=2 -->
```ocaml
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
```

We don't find it: 

```
(Invalid_argument "Irmin.Tree.get: /hello.md not found")
```

This could be somewhat related to the failing test-case reported here: https://github.com/talex5/irmin-indexeddb/pull/19 but I'm a little out of my depth either understanding what the issue is or if I'm just misusing the API in some way.
