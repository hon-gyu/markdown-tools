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
    Insert link to today's daily note no command
    Insert oysterlsp command block   no command
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
    Insert link to today's daily note no command
    Insert oysterlsp command block   no command
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
    Insert link to today's daily note no command
    Insert oysterlsp command block   no command
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
    Insert link to today's daily note no command
    Insert oysterlsp command block   no command
    |}]
;;

(* An unsupported format disables the feature rather than naming a wrong file.
   The unrelated quick-fix actions are unaffected. *)
let%expect_test "unsupported format offers nothing" =
  with_tmp_vault ~files (fun vault_root ->
    show_actions ~init_options:(options "YYYY-ww") ~vault_root "idea.md");
  [%expect {| |}]
;;

(* ...and says why.  Offering nothing is also what a correctly configured
   server does when it has nothing to offer, so the rejection has to be
   reported for the two to be distinguishable.  It joins the configuration
   warnings, which the adapter turns into [window/showMessage] at initialize —
   see {!page-"feature-configuration".tolerance}. *)
let%expect_test "a rejected format is reported" =
  let show ?init_options () =
    with_tmp_vault ~files (fun vault_root ->
      let s = start_server ?init_options ~today ~vault_root () in
      print_s [%sexp (Server.config_warnings s : string list)])
  in
  show ~init_options:(options "YYYY-ww") ();
  show ~init_options:(options "/YYYY-MM-DD") ();
  show ~init_options:(options "YYYY-MM-DD") ();
  (* Unconfigured: the default format is usable, so there is nothing to say. *)
  show ();
  [%expect
    {|
    ("daily notes disabled: unsupported format token 'w'")
    ("daily notes disabled: format must not start with /")
    ()
    ()
    |}]
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

(** {1 Linking instead of opening}

    See {!page-"feature-daily-notes".link}.  The one action in the family that
    needs no [window/showDocument]: it writes a link, and go-to-definition
    follows it. *)

(** The link action offered at [rel_path], as the operations its edit performs
    and the text it writes. *)
let show_link ?(init_options = options "YYYY-MM-DD") ~(vault_root : string) rel_path =
  let s = start_server ~init_options ~today ~vault_root () in
  did_open s ~rel_path;
  Server.code_action
    s
    ~rel_path
    ~start_line:0
    ~start_character:6
    ~end_line:0
    ~end_character:6
    ()
  |> List.filter ~f:(fun (a : CodeAction.t) ->
    String.is_prefix a.title ~prefix:"Insert link")
  |> List.iter ~f:(fun (a : CodeAction.t) ->
    Option.iter a.edit ~f:(fun edit ->
      printf
        "%s: [%s] %s\n"
        a.title
        (String.concat ~sep:"; " (document_change_kinds edit))
        (String.concat ~sep:" " (inserted_texts edit))))
;;

(* Today's note exists: nothing to create, just the link. *)
let%expect_test "links to an existing daily note" =
  with_tmp_vault ~files (fun vault_root -> show_link ~vault_root "idea.md");
  [%expect {| Insert link to today's daily note: [text-edits] [[2026-07-26]] |}]
;;

(* When today's note is missing the same action creates it, so the link it
   writes resolves immediately rather than landing unresolved. *)
let%expect_test "creates today's note when it is missing" =
  let files =
    List.filter files ~f:(fun (p, _) -> not (String.equal p "journal/2026-07-26.md"))
  in
  with_tmp_vault ~files (fun vault_root -> show_link ~vault_root "idea.md");
  [%expect {| Insert link to today's daily note: [create; text-edits] [[2026-07-26]] |}]
;;

(* The link is the base name, not the path: resolution matches a path
   subsequence, so the folders need not be spelled out. *)
let%expect_test "a nested format still links by base name" =
  with_tmp_vault ~files (fun vault_root ->
    show_link ~init_options:(options "YYYY/MM/YYYY-MM-DD") ~vault_root "idea.md");
  [%expect {| Insert link to today's daily note: [create; text-edits] [[2026-07-26]] |}]
;;

(* Nothing resolves with the feature disabled, so there is nothing to link. *)
let%expect_test "no link action when daily notes are disabled" =
  with_tmp_vault ~files (fun vault_root ->
    show_link ~init_options:(options "YYYY-ww") ~vault_root "idea.md");
  [%expect {| |}]
;;

(* The action appears in every menu in the vault, which is not always wanted;
   [linkAction] withdraws it without disabling daily notes.  See
   {!page-"feature-configuration"}. *)
let%expect_test "linkAction: false withdraws the action, and nothing else" =
  let init_options : Yojson.Safe.t =
    `Assoc
      [ ( "dailyNotes"
        , `Assoc
            [ "format", `String "YYYY-MM-DD"
            ; "folder", `String "journal"
            ; "linkAction", `Bool false
            ] )
      ]
  in
  with_tmp_vault ~files (fun vault_root ->
    show_link ~init_options ~vault_root "idea.md";
    print_endline "-- the rest of the menu:";
    show_actions ~init_options ~vault_root "idea.md");
  [%expect
    {|
    -- the rest of the menu:
    Open today's daily note          "journal/2026-07-26.md" false
    Create yesterday's daily note    "journal/2026-07-25.md" true
    Create tomorrow's daily note     "journal/2026-07-27.md" true
    Insert oysterlsp command block   no command
    |}]
;;
