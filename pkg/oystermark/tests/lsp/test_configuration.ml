(** Spec: {!page-"feature-configuration"}.
    Impl: {!Lsp_lib.Config} (parsing and merging) and {!Lsp_lib.Server}
    (adoption at [initialize], and the warnings the adapter reports).

    {!Lsp_lib.Config}'s own tests cover the schema case by case; these run the
    whole path — a file on disk, a client's [initializationOptions], and the
    settings a running server ends up behaving by. *)

open Core
open Lsp_helper

(* Fixed so daily-note expectations mean the same thing tomorrow. *)
let today = Date.create_exn ~y:2026 ~m:Month.Jul ~d:26
let files = [ "journal/2026-07-26.md", "# Today\n"; "idea.md", "# Not a daily note\n" ]

(** Start a server against a vault that does or does not contain
    [oysterlsp.json], and show what it decided plus anything it complained
    about.  The daily-note path stands in for the resolved settings: it is the
    one setting whose effect is visible without a request. *)
let show ?(config_file : string option) ?(init_options : string option) () =
  let files =
    match config_file with
    | None -> files
    | Some contents -> ("oysterlsp.json", contents) :: files
  in
  with_tmp_vault ~files (fun vault_root ->
    let init_options = Option.map init_options ~f:Yojson.Safe.from_string in
    let s = start_server ?init_options ~today ~vault_root () in
    Server.code_action
      s
      ~rel_path:"idea.md"
      ~start_line:0
      ~start_character:0
      ~end_line:0
      ~end_character:0
      ()
    |> List.iter ~f:(fun (a : Linol_lsp.Lsp.Types.CodeAction.t) ->
      match a.command with
      | Some { arguments = Some (`String path :: _); _ } -> printf "%s\n" path
      | _ -> ());
    List.iter (Server.config_warnings s) ~f:(printf "! %s\n"))
;;

(** {1 Sources} *)

let%expect_test "no configuration at all: defaults, and nothing to say" =
  show ();
  [%expect
    {|
    2026-07-26.md
    2026-07-25.md
    2026-07-27.md
    |}]
;;

let%expect_test "the file alone" =
  show ~config_file:{|{"dailyNotes": {"folder": "journal"}}|} ();
  [%expect
    {|
    journal/2026-07-26.md
    journal/2026-07-25.md
    journal/2026-07-27.md
    |}]
;;

let%expect_test "initializationOptions alone" =
  show ~init_options:{|{"dailyNotes": {"folder": "journal"}}|} ();
  [%expect
    {|
    journal/2026-07-26.md
    journal/2026-07-25.md
    journal/2026-07-27.md
    |}]
;;

(* The vault's own file describes the vault, so it wins — but only key by key:
   the client's [format] survives a file that names only [folder]. *)
let%expect_test "the file wins, field by field" =
  (* The file names only [folder], and the client's [format] is deliberately
     not the default — so a nested path proves the client's key survived while
     the file's overrode the same key. *)
  show
    ~config_file:{|{"dailyNotes": {"folder": "journal"}}|}
    ~init_options:
      {|{"dailyNotes": {"folder": "elsewhere", "format": "YYYY/MM/YYYY-MM-DD"}}|}
    ();
  [%expect
    {|
    journal/2026/07/2026-07-26.md
    journal/2026/07/2026-07-25.md
    journal/2026/07/2026-07-27.md
    |}]
;;

(** {1 Tolerance}

    Nothing below prevents the server from starting, and nothing is ignored
    quietly.  See {!page-"feature-configuration".tolerance}. *)

let%expect_test "a broken file leaves the client's settings, and is reported" =
  show
    ~config_file:{|{"dailyNotes": {"folder":|}
    ~init_options:{|{"dailyNotes": {"folder": "journal"}}|}
    ();
  [%expect
    {|
    journal/2026-07-26.md
    journal/2026-07-25.md
    journal/2026-07-27.md
    ! oysterlsp.json: not valid JSON — Line 1, bytes 24-25: Unexpected end of input
    |}]
;;

let%expect_test "unusable values and unknown keys are named, with their source" =
  show
    ~config_file:{|{"dailyNotes": {"folder": "journal"}, "hover": {"maxChars": -1}}|}
    ~init_options:{|{"dailynotes": {"folder": "typo"}}|}
    ();
  [%expect
    {|
    journal/2026-07-26.md
    journal/2026-07-25.md
    journal/2026-07-27.md
    ! initializationOptions: unknown key "dailynotes"
    ! oysterlsp.json: hover.maxChars: expected a positive integer, got -1
    |}]
;;

(* A format that parses but names no single day disables the feature.  It is
   validated after merging, so it joins the same warning list. *)
let%expect_test "a rejected daily-note format" =
  show ~config_file:{|{"dailyNotes": {"format": "YYYY-ww"}}|} ();
  [%expect {| ! daily notes disabled: unsupported format token 'w' |}]
;;

(* The file is read from the vault root, so a server that never saw a root
   never reads one. *)
let%expect_test "config file in a subfolder is not read" =
  with_tmp_vault
    ~files:(("sub/oysterlsp.json", {|{"dailyNotes": {"folder": "journal"}}|}) :: files)
    (fun vault_root ->
       let s = start_server ~today ~vault_root () in
       printf "%s\n" (Server.rel_path_of_uri s (Server.uri_of_rel_path s "x.md"));
       List.iter (Server.config_warnings s) ~f:(printf "! %s\n");
       Server.code_action
         s
         ~rel_path:"idea.md"
         ~start_line:0
         ~start_character:0
         ~end_line:0
         ~end_character:0
         ()
       |> List.iter ~f:(fun (a : Linol_lsp.Lsp.Types.CodeAction.t) ->
         match a.command with
         | Some { arguments = Some (`String path :: _); _ } -> printf "%s\n" path
         | _ -> ()));
  [%expect
    {|
    x.md
    2026-07-26.md
    2026-07-25.md
    2026-07-27.md
    |}]
;;
