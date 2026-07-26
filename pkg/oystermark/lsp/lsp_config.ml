(** LSP feature configuration. *)

open Core

(** How to treat a link whose file exists but whose heading or block-ID
    fragment cannot be found. *)
type fragment_behavior =
  | Fallback
  (** Go-to-definition falls back to the top of the file;
      diagnostics produce no warning. *)
  | Strict
  (** Go-to-definition returns no result;
      diagnostics report the fragment as unresolved. *)
[@@deriving sexp, equal]

(** Daily-note settings as written by the client, before validation.  Held as
    strings so {!t} stays comparable; {!daily_notes_settings} turns them into a
    {!Daily_notes.settings}, or an error when the format is unsupported.
    See {!page-"feature-daily-notes"}. *)
type daily_notes =
  { format : string
  ; folder : string option (** [None] is the vault root. *)
  ; template : string option (** Carried; note creation ignores it (stubbed). *)
  }
[@@deriving sexp, equal]

type t =
  { gtd_unresolved_fragment : fragment_behavior
    (** Fragment behavior for {!Go_to_definition}. *)
  ; diag_unresolved_fragment : fragment_behavior
    (** Fragment behavior for {!Diagnostics}. *)
  ; hover_max_chars : int
    (** Maximum number of bytes of note content to include in a hover
      response.  Content exceeding this limit is truncated at the
      previous newline and a [*(truncated)*] suffix is appended.
      See {!page-"feature-hover".truncation}. *)
  ; daily_notes : daily_notes (** See {!page-"feature-daily-notes"}. *)
  }
[@@deriving sexp, equal]

let default_daily_notes =
  { format = Daily_notes.Format.to_string Daily_notes.default_format
  ; folder = None
  ; template = None
  }
;;

(** Default configuration: both features use {!Fallback}, matching the
    lenient behavior described in the go-to-definition spec.
    Hover content is capped at 2 000 bytes. *)
let default =
  { gtd_unresolved_fragment = Fallback
  ; diag_unresolved_fragment = Fallback
  ; hover_max_chars = 2000
  ; daily_notes = default_daily_notes
  }
;;

(** {1 Client-supplied configuration}

    Settings arrive once, in [initialize]'s [initializationOptions].  Parsing is
    tolerant by design: a malformed object leaves the defaults in place rather
    than failing initialization, matching {!Oystermark.Config}. *)

let string_field (j : Yojson.Safe.t) (key : string) : string option =
  match j with
  | `Assoc fields ->
    (match List.Assoc.find fields key ~equal:String.equal with
     | Some (`String s) when not (String.is_empty (String.strip s)) ->
       Some (String.strip s)
     | _ -> None)
  | _ -> None
;;

(** [of_initialization_options j] reads [{ "dailyNotes": { ... } }].  Absent or
    unusable fields keep their {!default}. *)
let of_initialization_options (j : Yojson.Safe.t option) : t =
  match j with
  | None -> default
  | Some j ->
    let daily =
      match j with
      | `Assoc fields ->
        (match List.Assoc.find fields "dailyNotes" ~equal:String.equal with
         | Some (`Assoc _ as d) ->
           { format =
               Option.value (string_field d "format") ~default:default_daily_notes.format
           ; folder = string_field d "folder"
           ; template = string_field d "template"
           }
         | _ -> default_daily_notes)
      | _ -> default_daily_notes
    in
    { default with daily_notes = daily }
;;

(** [daily_notes_settings t] validates the configured format.  An [Error]
    disables the daily-note actions; the message names what was wrong.
    See {!page-"feature-daily-notes".format}. *)
let daily_notes_settings (t : t) : (Daily_notes.settings, string) Result.t =
  Daily_notes.Format.of_string t.daily_notes.format
  |> Result.map ~f:(fun format ->
    { Daily_notes.format
    ; folder = t.daily_notes.folder
    ; template = t.daily_notes.template
    })
;;

(** {1:test Test} *)

let%test_module "initialization options" =
  (module struct
    let show (s : string) =
      let t = of_initialization_options (Some (Yojson.Safe.from_string s)) in
      print_s [%sexp (t.daily_notes : daily_notes)];
      match daily_notes_settings t with
      | Ok settings ->
        printf
          "  -> %s\n"
          (Daily_notes.path_of_date settings (Date.create_exn ~y:2026 ~m:Month.Jul ~d:6))
      | Error e -> printf "  -> disabled: %s\n" e
    ;;

    let%expect_test "well-formed" =
      show {|{"dailyNotes": {"format": "YYYY/MM/YYYY-MM-DD", "folder": "journal"}}|};
      [%expect
        {|
        ((format YYYY/MM/YYYY-MM-DD) (folder (journal)) (template ()))
          -> journal/2026/07/2026-07-06.md
        |}]
    ;;

    (* Tolerance: anything unusable falls back to the default rather than
       failing initialization. *)
    let%expect_test "malformed shapes fall back" =
      List.iter
        [ {|{}|}
        ; {|{"dailyNotes": null}|}
        ; {|{"dailyNotes": []}|}
        ; {|{"dailyNotes": {"format": 42}}|}
        ; {|{"dailyNotes": {"format": "  "}}|}
        ; {|"not an object"|}
        ]
        ~f:show;
      [%expect
        {|
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        ((format YYYY-MM-DD) (folder ()) (template ()))
          -> 2026-07-06.md
        |}]
    ;;

    (* A syntactically fine but unsupported format parses into the config and
       disables the feature at use time, with a message. *)
    let%expect_test "unsupported format disables the feature" =
      show {|{"dailyNotes": {"format": "YYYY-ww"}}|};
      [%expect
        {|
        ((format YYYY-ww) (folder ()) (template ()))
          -> disabled: unsupported format token 'w'
        |}]
    ;;

    let%expect_test "none" =
      let t = of_initialization_options None in
      print_s [%sexp (equal t default : bool)];
      [%expect {| true |}]
    ;;
  end)
;;
