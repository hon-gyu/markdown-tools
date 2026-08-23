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

(** {1 Disable}

    See {!page-"feature-configuration".disable}.  What the switch has to be
    worth is silence across the board, so this drives every handler rather
    than the one the rest of the file uses as a proxy. *)

let%expect_test "disable: every surface answers emptily" =
  with_tmp_vault
    ~files:
      (("oysterlsp.json", {|{"disable": true}|})
       :: ("links.md", "# Links\n\nSee [[idea]] and [[missing]].\n")
       :: files)
    (fun vault_root ->
       let s = start_server ~today ~vault_root () in
       printf "disabled: %b\n" (Server.disabled s);
       printf "warnings: %d\n" (List.length (Server.config_warnings s));
       printf "root: %s\n" (Option.value (Server.vault_root s) ~default:"<none>");
       let rel_path = "links.md" in
       let content = "# Links\n\nSee [[idea]] and [[missing]].\n" in
       printf
         "did_open diagnostics: %d\n"
         (List.length (Server.did_open s ~rel_path ~content));
       printf
         "did_change diagnostics: %d\n"
         (List.length (Server.did_change s ~rel_path ~content));
       printf
         "did_save documents: %d\n"
         (List.length (Server.did_save s ~rel_path));
       (* Column 6 is inside [ [[idea]] ], a link that resolves in this vault —
          so an answer here would be a real one, not an accident of position. *)
       let line, character = 2, 6 in
       printf "hover: %b\n" (Option.is_some (Server.hover s ~rel_path ~line ~character));
       printf
         "definition: %b\n"
         (Option.is_some (Server.definition s ~rel_path ~line ~character));
       printf
         "references: %b\n"
         (Option.is_some (Server.references s ~rel_path ~line ~character));
       printf
         "prepare_rename: %b\n"
         (Option.is_some (Server.prepare_rename s ~rel_path ~line ~character));
       printf
         "completion: %b\n"
         (Option.is_some (Server.completion s ~rel_path ~line ~character));
       printf
         "document_symbol: %b\n"
         (Option.is_some (Server.document_symbol s ~rel_path));
       printf "code_lens: %b\n" (Option.is_some (Server.code_lens s ~rel_path));
       printf
         "inlay_hint: %b\n"
         (Option.is_some (Server.inlay_hint s ~rel_path ~start_line:0 ~end_line:9));
       printf
         "code_action: %d\n"
         (List.length
            (Server.code_action
               s
               ~rel_path
               ~start_line:0
               ~start_character:0
               ~end_line:0
               ~end_character:0
               ()));
       (* The daily-note command is unreachable through the menus above, but a
          client that remembers it from a previous session can still send it. *)
       printf
         "execute_command: %b\n"
         (Option.is_some
            (Server.execute_command
               s
               ~command:Server.daily_note_command
               ~arguments:(Some [ `String "2026-07-26.md"; `Bool true ]))));
  [%expect
    {|
    disabled: true
    warnings: 0
    root: <none>
    did_open diagnostics: 0
    did_change diagnostics: 0
    did_save documents: 0
    hover: false
    definition: false
    references: false
    prepare_rename: false
    completion: false
    document_symbol: false
    code_lens: false
    inlay_hint: false
    code_action: 0
    execute_command: false
    |}]
;;

(* The switch is a setting like any other: the file overrides the client, in
   both directions. *)
let%expect_test "disable: the file has the last word" =
  show ~config_file:{|{"disable": false}|} ~init_options:{|{"disable": true}|} ();
  [%expect
    {|
    2026-07-26.md
    2026-07-25.md
    2026-07-27.md
    |}]
;;

let%expect_test "disable: from the client alone" =
  show ~init_options:{|{"disable": true}|} ();
  [%expect {| |}]
;;

(* Everything else stops mattering, including what would otherwise be
   reported: warnings from a server that does nothing are noise. *)
let%expect_test "disable: other settings are neither applied nor complained about" =
  show ~config_file:{|{"disable": true, "hover": {"maxChars": -1}, "nope": 1}|} ();
  [%expect {| |}]
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
