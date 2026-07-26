(** Spec: {!page-"feature-command-block"}.
    Impl: {!Lsp_lib.Command_block} (finding the lines) and {!Lsp_lib.Server}
    (the four surfaces built on them).

    {!Lsp_lib.Command_block}'s own tests cover recognition; these check what a
    server answers with, which is where the block meets the vault, the clock
    and the daily-note settings. *)

open Core
open Linol_lsp.Lsp.Types
open Lsp_helper

(* Fixed so the expectations mean the same thing tomorrow. *)
let today = Date.create_exn ~y:2026 ~m:Month.Jul ~d:26

let panel =
  {|```oysterlsp
daily/today
daily/yesterday
daily/prev
daily/next
```
|}
;;

let files =
  [ "journal/2026-07-03.md", "# Early\n"
  ; "journal/2026-07-10.md", "# Middle\n"
  ; "journal/2026-07-26.md", "# Today\n\n" ^ panel
  ; "idea.md", "# An idea\n\n" ^ panel
  ]
;;

let options : Yojson.Safe.t =
  `Assoc
    [ "dailyNotes", `Assoc [ "format", `String "YYYY-MM-DD"; "folder", `String "journal" ]
    ]
;;

let start ~vault_root = start_server ~init_options:options ~today ~vault_root ()

(** Every lens in [rel_path]: its line, its title, and the command it carries
    (or nothing, when the command cannot run here). *)
let show_lenses ?(files = files) rel_path =
  with_tmp_vault ~files (fun vault_root ->
    let s = start ~vault_root in
    match Server.code_lens s ~rel_path with
    | None -> print_endline "no vault"
    | Some lenses ->
      List.iter lenses ~f:(fun (l : CodeLens.t) ->
        printf
          "%d: %s\n"
          l.range.start.line
          (match l.command with
           | Some c ->
             sprintf
               "%s -> %s"
               c.title
               (String.concat
                  ~sep:" "
                  (List.map
                     (Option.value c.arguments ~default:[])
                     ~f:Yojson.Safe.to_string))
           | None -> "(nothing to run)")))
;;

(** {1 Lenses}

    See {!page-"feature-command-block".surfaces}. *)

(* From a daily note, every line of the panel resolves: the calendar three
   against the clock, previous/next against *this* note's date. *)
let%expect_test "a panel inside a daily note" =
  show_lenses "journal/2026-07-26.md";
  [%expect
    {|
    3: Open today's daily note -> "journal/2026-07-26.md" false
    4: Create yesterday's daily note -> "journal/2026-07-25.md" true
    5: Open previous daily note (journal/2026-07-10.md) -> "journal/2026-07-10.md" false
    6: (nothing to run)
    |}]
;;

(* The same block in an ordinary note: the calendar commands are unchanged,
   but previous/next have no date to move from.  They keep their lens and say
   so — a lens that vanished would look like a server that failed. *)
let%expect_test "the same panel in an ordinary note" =
  show_lenses "idea.md";
  [%expect
    {|
    3: Open today's daily note -> "journal/2026-07-26.md" false
    4: Create yesterday's daily note -> "journal/2026-07-25.md" true
    5: (nothing to run)
    6: (nothing to run)
    |}]
;;

(* The point of putting the panel in a note: the identical block means
   different things in two of them. *)
let%expect_test "previous and next follow the host note" =
  (* Replace, rather than prepend: {!with_tmp_vault} writes in order, so a
     second entry for the same path would overwrite the panel. *)
  let files =
    List.map files ~f:(fun (path, content) ->
      if String.equal path "journal/2026-07-10.md"
      then path, "# Middle\n\n" ^ panel
      else path, content)
  in
  show_lenses ~files "journal/2026-07-10.md";
  [%expect
    {|
    3: Open today's daily note -> "journal/2026-07-26.md" false
    4: Create yesterday's daily note -> "journal/2026-07-25.md" true
    5: Open previous daily note (journal/2026-07-03.md) -> "journal/2026-07-03.md" false
    6: Open next daily note (journal/2026-07-26.md) -> "journal/2026-07-26.md" false
    |}]
;;

let%expect_test "a note with no block has no lenses" =
  show_lenses ~files:[ "plain.md", "# Nothing here\n" ] "plain.md";
  [%expect {| |}]
;;

(* An unsupported daily-note format disables the commands; the lines still
   report why rather than going quiet. *)
let%expect_test "daily notes disabled" =
  with_tmp_vault ~files (fun vault_root ->
    let s =
      start_server
        ~init_options:(`Assoc [ "dailyNotes", `Assoc [ "format", `String "YYYY-ww" ] ])
        ~today
        ~vault_root
        ()
    in
    Option.iter (Server.code_lens s ~rel_path:"idea.md") ~f:(fun lenses ->
      List.iter lenses ~f:(fun (l : CodeLens.t) ->
        printf "%d: %b\n" l.range.start.line (Option.is_some l.command))));
  [%expect
    {|
    3: false
    4: false
    5: false
    6: false
    |}]
;;

(** {1 Code action}

    The keyboard route to the same command, for clients that render no
    lenses. *)

let show_action ?(rel_path = "journal/2026-07-26.md") line =
  with_tmp_vault ~files (fun vault_root ->
    let s = start ~vault_root in
    Server.code_action
      s
      ~rel_path
      ~start_line:line
      ~start_character:0
      ~end_line:line
      ~end_character:0
      ()
    |> List.iter ~f:(fun (a : CodeAction.t) -> printf "%s\n" a.title))
;;

(* On a panel line, exactly one action: the line's own.  The daily-note menu
   would otherwise bury it under five. *)
let%expect_test "one action on a command line" =
  show_action 4;
  [%expect {| Create yesterday's daily note |}]
;;

(* Off the panel, the ordinary menu is unchanged. *)
let%expect_test "the usual actions elsewhere in the note" =
  show_action 0;
  [%expect
    {|
    Open today's daily note
    Create yesterday's daily note
    Create tomorrow's daily note
    Open previous daily note
    |}]
;;

(* A line whose command cannot run offers no action — there is nothing to
   apply.  The lens still explains it. *)
let%expect_test "no action for an inapplicable command" =
  show_action ~rel_path:"idea.md" 5;
  [%expect
    {|
    Open today's daily note
    Create yesterday's daily note
    Create tomorrow's daily note
    |}]
;;

(** {1 Completion and diagnostics} *)

let%expect_test "completion inside the block offers the catalogue" =
  with_tmp_vault ~files (fun vault_root ->
    let s = start ~vault_root in
    match Server.completion s ~rel_path:"idea.md" ~line:4 ~character:0 with
    | None -> print_endline "none"
    | Some items ->
      List.iter items ~f:(fun (i : CompletionItem.t) ->
        printf "%-16s %s\n" i.label (Option.value i.detail ~default:"")));
  [%expect
    {|
    daily/today      Open today's daily note, creating it when missing
    daily/yesterday  Open yesterday's daily note, creating it when missing
    daily/tomorrow   Open tomorrow's daily note, creating it when missing
    daily/prev       Open the previous existing daily note, relative to this note
    daily/next       Open the next existing daily note, relative to this note
    |}]
;;

(* A misspelling is inert, and inert looks exactly like unimplemented — so it
   is diagnosed. *)
let%expect_test "an unknown command name is diagnosed" =
  let content =
    {|# Note

```oysterlsp
daily/today
daily/yesterdya
```
|}
  in
  with_tmp_vault
    ~files:[ "typo.md", content ]
    (fun vault_root ->
       let s = start ~vault_root in
       Server.did_open s ~rel_path:"typo.md" ~content
       |> List.iter ~f:(fun (d : Diagnostic.t) ->
         printf
           "%d:%d %s\n"
           d.range.start.line
           d.range.start.character
           (match d.message with
            | `String m -> m
            | _ -> "")));
  [%expect
    {|
    4:0 unknown oysterlsp command "daily/yesterdya"; expected one of daily/today, daily/yesterday, daily/tomorrow, daily/prev, daily/next
    |}]
;;
