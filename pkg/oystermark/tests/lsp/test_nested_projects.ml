(** Spec: {!page-"feature-projects"}.
    Implementation: {!Lsp_lib.Server}. *)

open Core
open Lsp_helper

let files =
  [ "oysterlsp.json", "{}"
  ; "outer.md", "[[outer-target]]\n[[inner]]\n[[a/inner]]\n"
  ; "outer-target.md", "# Outer target\n"
  ; "a/oysterlsp.json", "{}"
  ; "a/inner.md", "[[inner-target]]\n[[outer-target]]\n[[../outer-target]]\n"
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

let%expect_test "an import selectively unprunes a nested project" =
  let files =
    [ "oysterlsp.json", {|{"imports": ["./a"]}|}
    ; "outer.md", "[[a/inner]]\n[[inner]]\n"
    ; "a/oysterlsp.json", "{}"
    ; "a/inner.md", "[[outer]]\n"
    ]
  in
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    print_endline "outer:";
    show_diagnostics server "outer.md";
    print_endline "inner:";
    show_diagnostics server "a/inner.md";
    Server.definition server ~rel_path:"outer.md" ~line:0 ~character:3
    |> definition_result server
    |> [%sexp_of: Lsp_lib.Go_to_definition.definition_result option]
    |> print_s;
    Server.definition server ~rel_path:"outer.md" ~line:1 ~character:3
    |> definition_result server
    |> [%sexp_of: Lsp_lib.Go_to_definition.definition_result option]
    |> print_s);
  [%expect
    {|
    outer:
    inner:
    1:1 unresolved link: outer
    (((path a/inner.md) (line 0) (character 0)))
    (((path a/inner.md) (line 0) (character 0)))
    |}]
;;

let%expect_test "imports are direct and invalid paths are reported" =
  let files =
    [ "oysterlsp.json", {|{"imports": ["./a", "a", "../outside", "missing"]}|}
    ; "outer.md", "[[a/inner]]\n[[a/b/deep]]\n"
    ; "a/oysterlsp.json", "{}"
    ; "a/inner.md", "# Inner\n"
    ; "a/b/oysterlsp.json", "{}"
    ; "a/b/deep.md", "# Deep\n"
    ]
  in
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    show_diagnostics server "outer.md";
    Server.config_warnings server |> List.iter ~f:print_endline);
  [%expect
    {|
    2:1 unresolved link: a/b/deep
    imports: duplicate project "a"
    imports: "../outside" must not contain ..
    imports: "missing" does not name a descendant project
    |}]
;;

let%expect_test "references and rename cross a loaded import edge" =
  let files =
    [ "oysterlsp.json", {|{"imports": ["a"]}|}
    ; "outer.md", "[[a/inner]]\n[[inner]]\n"
    ; "a/oysterlsp.json", "{}"
    ; "a/inner.md", "# Inner\n\n[[inner]]\n"
    ]
  in
  with_tmp_vault ~files (fun vault_root ->
    let server = start_server ~vault_root () in
    Server.references server ~rel_path:"a/inner.md" ~line:2 ~character:3
    |> reference_positions server
    |> [%sexp_of: (string * int * int) list]
    |> print_s;
    Server.code_lens server ~rel_path:"a/inner.md"
    |> Option.value ~default:[]
    |> List.iter ~f:(fun lens ->
      Option.iter lens.command ~f:(fun command -> printf "lens %s\n" command.title));
    let edit =
      Server.rename server ~rel_path:"outer.md" ~line:0 ~character:3 ~new_name:"renamed"
    in
    Option.value edit.documentChanges ~default:[]
    |> List.iter ~f:(function
      | `TextDocumentEdit change ->
        printf
          "edit %s %d\n"
          (Server.rel_path_of_uri server change.textDocument.uri)
          (List.length change.edits)
      | `RenameFile change ->
        printf
          "rename %s -> %s\n"
          (Server.rel_path_of_uri server change.oldUri)
          (Server.rel_path_of_uri server change.newUri)
      | `CreateFile _ -> print_endline "unexpected create"
      | `DeleteFile _ -> print_endline "unexpected delete"));
  [%expect
    {|
    ((a/inner.md 2 0) (outer.md 0 0) (outer.md 1 0))
    lens 2 backlinks, 1 in-note link
    edit a/inner.md 1
    edit outer.md 2
    rename a/inner.md -> a/renamed.md
    |}]
;;
