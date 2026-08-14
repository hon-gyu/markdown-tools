(** Spec: {!page-"feature-projects"}.
    Implementation: {!Lsp_lib.Server}. *)

open Core
open Lsp_helper

let files =
  [ "oysterlsp.json", "{}"
  ; ( "outer.md"
    , "[[outer-target]]\n[[inner]]\n[[a/inner]]\n" )
  ; "outer-target.md", "# Outer target\n"
  ; "a/oysterlsp.json", "{}"
  ; ( "a/inner.md"
    , "[[inner-target]]\n[[outer-target]]\n[[../outer-target]]\n" )
  ; "a/inner-target.md", "# Inner target\n"
  ]
;;

let show_diagnostics server rel_path =
  open_doc server ~rel_path
  |> diagnostic_positions
  |> List.iter ~f:(fun (message, line, character) ->
    printf "%d:%d %s\n" (line + 1) (character + 1) message)
;;

let%expect_test "parent and nested project cannot resolve across their boundary" =
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    print_endline "outer:";
    show_diagnostics server "outer.md";
    print_endline "inner:";
    show_diagnostics server "a/inner.md");
  [%expect
    {|
    outer:
    2:1 unresolved link: inner
    3:1 unresolved link: a/inner
    inner:
    2:1 unresolved link: outer-target
    3:1 unresolved link: ../outer-target
    |}]
;;

let%expect_test "a nested project uses its own configuration" =
  let files =
    [ "outer.md", "[[missing-outer]]\n"
    ; "a/oysterlsp.json", {|{"disable": true}|}
    ; "a/inner.md", "[[missing-inner]]\n"
    ]
  in
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    print_endline "outer:";
    show_diagnostics server "outer.md";
    print_endline "inner:";
    show_diagnostics server "a/inner.md");
  [%expect
    {|
    outer:
    1:1 unresolved link: missing-outer
    inner:
    |}]
;;

let%expect_test "requests and returned locations use the owning project" =
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    let definition rel_path line =
      Server.definition server ~rel_path ~line ~character:3
      |> definition_result server
      |> [%sexp_of: Lsp_lib.Go_to_definition.definition_result option]
      |> print_s
    in
    definition "outer.md" 0;
    definition "outer.md" 1;
    definition "a/inner.md" 0;
    definition "a/inner.md" 1;
    Server.references server ~rel_path:"a/inner.md" ~line:0 ~character:3
    |> reference_positions server
    |> [%sexp_of: (string * int * int) list]
    |> print_s);
  [%expect
    {|
    (((path outer-target.md) (line 0) (character 0)))
    ()
    (((path a/inner-target.md) (line 0) (character 0)))
    ()
    ((a/inner.md 0 0))
    |}]
;;
