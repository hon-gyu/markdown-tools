(** Spec: {!page-"feature-daily-notes"}.
    Impl: {!Lsp_lib.Daily_notes} (pure layer) and {!Lsp_lib.Server} (actions and
    the command).

    The pure layer's own tests live beside it; these drive the server, where
    settings, the clock, and the disk meet. *)

open Core
open Linol_lsp.Lsp.Types
open Lsp_helper

(* "Today" is fixed so these expectations mean the same thing tomorrow; the
   fixture dates are chosen around it, with gaps to exercise previous/next. *)
let today = Date.create_exn ~y:2026 ~m:Month.Jul ~d:26

let files =
  [ "journal/2026-07-03.md", "# Friday\n"
  ; "journal/2026-07-10.md", "# Friday again\n"
  ; "journal/2026-07-26.md", "# Today\n"
  ; "idea.md", "# Not a daily note\n"
  ]
;;

let options ?(folder = "journal") (format : string) : Yojson.Safe.t =
  `Assoc [ "dailyNotes", `Assoc [ "format", `String format; "folder", `String folder ] ]
;;

(** Every code action offered at [rel_path], as [title -> command arguments]. *)
let show_actions ?(init_options = options "YYYY-MM-DD") ~(vault_root : string) rel_path =
  let s = start_server ~init_options ~today ~vault_root () in
  did_open s ~rel_path;
  Server.code_action
    s
    ~rel_path
    ~start_line:0
    ~start_character:0
    ~end_line:0
    ~end_character:0
    ()
  |> List.iter ~f:(fun (a : CodeAction.t) ->
    let args =
      match a.command with
      | None -> "no command"
      | Some c ->
        List.map (Option.value c.arguments ~default:[]) ~f:Yojson.Safe.to_string
        |> String.concat ~sep:" "
    in
    printf "%-32s %s\n" a.title args)
;;

let%expect_test "actions from a daily note: calendar plus previous/next" =
  with_tmp_vault ~files (fun vault_root ->
    show_actions ~vault_root "journal/2026-07-26.md");
  [%expect
    {|
    Open today's daily note          "journal/2026-07-26.md" false
    Create yesterday's daily note    "journal/2026-07-25.md" true
    Create tomorrow's daily note     "journal/2026-07-27.md" true
    Open previous daily note         "journal/2026-07-10.md" false
    |}]
;;

(* Previous/next skip the gap between the 3rd and the 10th, and stop at the
   ends of what exists — they never create. *)
let%expect_test "previous and next from the middle of the range" =
  with_tmp_vault ~files (fun vault_root ->
    show_actions ~vault_root "journal/2026-07-10.md");
  [%expect
    {|
    Open today's daily note          "journal/2026-07-26.md" false
    Create yesterday's daily note    "journal/2026-07-25.md" true
    Create tomorrow's daily note     "journal/2026-07-27.md" true
    Open previous daily note         "journal/2026-07-03.md" false
    Open next daily note             "journal/2026-07-26.md" false
    |}]
;;

(* Off a daily note the calendar family is still offered; the existing family
   is not, because there is no current date to move from. *)
let%expect_test "actions from an ordinary note" =
  with_tmp_vault ~files (fun vault_root -> show_actions ~vault_root "idea.md");
  [%expect
    {|
    Open today's daily note          "journal/2026-07-26.md" false
    Create yesterday's daily note    "journal/2026-07-25.md" true
    Create tomorrow's daily note     "journal/2026-07-27.md" true
    |}]
;;

(* A format with [/] nests the note in folders; the paths follow. *)
let%expect_test "nested format" =
  with_tmp_vault ~files (fun vault_root ->
    show_actions ~init_options:(options "YYYY/MM/YYYY-MM-DD") ~vault_root "idea.md");
  [%expect
    {|
    Create today's daily note        "journal/2026/07/2026-07-26.md" true
    Create yesterday's daily note    "journal/2026/07/2026-07-25.md" true
    Create tomorrow's daily note     "journal/2026/07/2026-07-27.md" true
    |}]
;;

(* An unsupported format disables the feature rather than naming a wrong file.
   The unrelated quick-fix actions are unaffected. *)
let%expect_test "unsupported format offers nothing" =
  with_tmp_vault ~files (fun vault_root ->
    show_actions ~init_options:(options "YYYY-ww") ~vault_root "idea.md");
  [%expect {| |}]
;;

(** {1 The command}

    [workspace/executeCommand] decides {i what} should happen; the adapter
    performs it.  See {!page-"feature-daily-notes"}. *)

let show_command ?(arguments : Yojson.Safe.t list option) ~(vault_root : string) command =
  let s = start_server ~init_options:(options "YYYY-MM-DD") ~today ~vault_root () in
  match Server.execute_command s ~command ~arguments with
  | None -> print_endline "no intent"
  | Some { uri; create } ->
    printf
      "%s create=%s\n"
      (Server.rel_path_of_uri s uri)
      (match create with
       | None -> "none"
       | Some edit -> String.concat ~sep:"," (document_change_kinds edit))
;;

let%expect_test "existing note is opened without an edit" =
  with_tmp_vault ~files (fun vault_root ->
    show_command
      ~vault_root
      ~arguments:[ `String "journal/2026-07-26.md"; `Bool true ]
      Server.daily_note_command);
  [%expect {| journal/2026-07-26.md create=none |}]
;;

let%expect_test "missing note is created, then opened" =
  with_tmp_vault ~files (fun vault_root ->
    show_command
      ~vault_root
      ~arguments:[ `String "journal/2026-07-27.md"; `Bool true ]
      Server.daily_note_command);
  [%expect {| journal/2026-07-27.md create=create |}]
;;

(* An editor may send anything; neither an unknown command nor unusable
   arguments should reach the disk. *)
let%expect_test "unknown command and bad arguments yield no intent" =
  with_tmp_vault ~files (fun vault_root ->
    show_command
      ~vault_root
      ~arguments:[ `String "x.md"; `Bool true ]
      "some.other.command";
    show_command ~vault_root Server.daily_note_command;
    show_command ~vault_root ~arguments:[ `Int 3 ] Server.daily_note_command);
  [%expect
    {|
    no intent
    no intent
    no intent
    |}]
;;
