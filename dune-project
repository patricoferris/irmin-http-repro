(lang dune 2.9)
(using mdx 0.1)

(generate_opam_files true)

(package
 (name irmin-repro)
 (synopsis "Irmin HTTP Repro")
 (description "Things aren't syncing?")
 (depends 
  js_of_ocaml
  js_of_ocaml-lwt
  digestif.ocaml
  checkseum.ocaml
  unix
  irmin
  irmin-http
  irmin-git
  irmin-indexeddb
  cohttp-lwt-jsoo))