(** LSP feature configuration.

    Spec: {!page-"feature-configuration"}. Values come from the client's
    [initializationOptions] and from [oysterlsp.json] at the vault root; this
    module parses both, merges them, and reports everything it had to ignore. *)

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
    {!Daily_notes.type-settings}, or an error when the format is unsupported.
    See {!page-"feature-daily-notes"}. *)
type daily_notes =
  { format : string
  ; folder : string option (** [None] is the vault root. *)
  ; template : string option (** Carried; note creation ignores it (stubbed). *)
  ; link_action : bool
    (** Whether to offer [Insert link to today's daily note].  It is the one
      daily-note action that reaches its note without
      [window/showDocument], and the one that appears in every menu
      whether or not the note is wanted there — so it is the one worth
      turning off.  See {!page-"feature-daily-notes".link}. *)
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
  ; link_action = true
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

(** {1:partial Parsing}

    A source is parsed into a {!Partial.t} — every field an option, recording
    what that source {e said} rather than what the server should do — so that
    two sources can be merged field by field before defaults are applied.  See
    {!page-"feature-configuration".precedence}.

    Nothing here fails: an unusable value is dropped and described in a
    warning.  See {!page-"feature-configuration".tolerance}. *)

(** {!t} under a name {!Partial} can still refer to, having shadowed [t]. *)
type resolved = t

module Partial = struct
  type nonrec daily_notes =
    { format : string option
    ; folder : string option
    ; template : string option
    ; link_action : bool option
    }

  type t =
    { gtd_unresolved_fragment : fragment_behavior option
    ; diag_unresolved_fragment : fragment_behavior option
    ; hover_max_chars : int option
    ; daily_notes : daily_notes
    }

  let empty =
    { gtd_unresolved_fragment = None
    ; diag_unresolved_fragment = None
    ; hover_max_chars = None
    ; daily_notes = { format = None; folder = None; template = None; link_action = None }
    }
  ;;

  (** [merge ~lower ~upper] prefers [upper] wherever it has an opinion.  Nested
      objects merge field-wise too, so a file naming only [dailyNotes.folder]
      leaves a client-supplied [format] standing. *)
  let merge ~(lower : t) ~(upper : t) : t =
    let pick u l = Option.first_some u l in
    { gtd_unresolved_fragment =
        pick upper.gtd_unresolved_fragment lower.gtd_unresolved_fragment
    ; diag_unresolved_fragment =
        pick upper.diag_unresolved_fragment lower.diag_unresolved_fragment
    ; hover_max_chars = pick upper.hover_max_chars lower.hover_max_chars
    ; daily_notes =
        { format = pick upper.daily_notes.format lower.daily_notes.format
        ; folder = pick upper.daily_notes.folder lower.daily_notes.folder
        ; template = pick upper.daily_notes.template lower.daily_notes.template
        ; link_action = pick upper.daily_notes.link_action lower.daily_notes.link_action
        }
    }
  ;;
end

(** Fill a {!Partial.t}'s gaps from {!default}.  Outside {!Partial} so that the
    record fields it builds are unambiguously {!t}'s. *)
let resolve (p : Partial.t) : resolved =
  { gtd_unresolved_fragment =
      Option.value p.gtd_unresolved_fragment ~default:default.gtd_unresolved_fragment
  ; diag_unresolved_fragment =
      Option.value p.diag_unresolved_fragment ~default:default.diag_unresolved_fragment
  ; hover_max_chars = Option.value p.hover_max_chars ~default:default.hover_max_chars
  ; daily_notes =
      { format = Option.value p.daily_notes.format ~default:default_daily_notes.format
      ; folder = p.daily_notes.folder
      ; template = p.daily_notes.template
      ; link_action =
          Option.value p.daily_notes.link_action ~default:default_daily_notes.link_action
      }
  }
;;

(** Accumulates what a source asked for and could not have.  See
    {!page-"feature-configuration".tolerance}. *)
module Warnings = struct
  type t = { mutable rev : string list }

  let create () = { rev = [] }
  let add (t : t) (msg : string) : unit = t.rev <- msg :: t.rev
  let to_list (t : t) : string list = List.rev t.rev

  (** [~key] is the dotted path the user wrote, so a warning can be traced back
      to a line in their config. *)
  let bad_value (t : t) ~(key : string) ~(expected : string) (got : Yojson.Safe.t) : unit =
    add t (sprintf "%s: expected %s, got %s" key expected (Yojson.Safe.to_string got))
  ;;
end

let fields_exn (j : Yojson.Safe.t) : (string * Yojson.Safe.t) list option =
  match j with
  | `Assoc fields -> Some fields
  | _ -> None
;;

(** A non-empty string, trimmed.  [""] and whitespace are treated as unusable
    rather than as a deliberate empty value: no setting here has a meaningful
    empty case. *)
let parse_string (w : Warnings.t) ~(key : string) (j : Yojson.Safe.t) : string option =
  match j with
  | `String s when not (String.is_empty (String.strip s)) -> Some (String.strip s)
  | got ->
    Warnings.bad_value w ~key ~expected:"a non-empty string" got;
    None
;;

let parse_positive_int (w : Warnings.t) ~(key : string) (j : Yojson.Safe.t) : int option =
  match j with
  | `Int n when n > 0 -> Some n
  | got ->
    Warnings.bad_value w ~key ~expected:"a positive integer" got;
    None
;;

let parse_bool (w : Warnings.t) ~(key : string) (j : Yojson.Safe.t) : bool option =
  match j with
  | `Bool b -> Some b
  | got ->
    Warnings.bad_value w ~key ~expected:"a boolean" got;
    None
;;

let parse_fragment_behavior (w : Warnings.t) ~(key : string) (j : Yojson.Safe.t)
  : fragment_behavior option
  =
  match j with
  | `String "fallback" -> Some Fallback
  | `String "strict" -> Some Strict
  | got ->
    Warnings.bad_value w ~key ~expected:{|"fallback" or "strict"|} got;
    None
;;

(** Walk an object's fields, dispatching known keys to [f] and reporting the
    rest.  Reporting unknown keys is the point: a misspelled key is otherwise
    the quietest possible way to have a setting do nothing. *)
let parse_object
      (w : Warnings.t)
      ~(self : string)
      ~(prefix : string)
      (j : Yojson.Safe.t)
      ~(f : key:string -> string -> Yojson.Safe.t -> bool)
  : unit
  =
  match fields_exn j with
  | None -> Warnings.bad_value w ~key:self ~expected:"an object" j
  | Some fields ->
    List.iter fields ~f:(fun (name, value) ->
      let key = prefix ^ name in
      if not (f ~key name value) then Warnings.add w (sprintf "unknown key %S" key))
;;

let parse_daily_notes (w : Warnings.t) (j : Yojson.Safe.t) : Partial.daily_notes =
  let acc =
    ref { Partial.format = None; folder = None; template = None; link_action = None }
  in
  parse_object w ~self:"dailyNotes" ~prefix:"dailyNotes." j ~f:(fun ~key name value ->
    let str () = parse_string w ~key value in
    match name with
    | "format" ->
      acc := { !acc with Partial.format = str () };
      true
    | "folder" ->
      acc := { !acc with Partial.folder = str () };
      true
    | "template" ->
      acc := { !acc with Partial.template = str () };
      true
    | "linkAction" ->
      acc := { !acc with Partial.link_action = parse_bool w ~key value };
      true
    | _ -> false);
  !acc
;;

(** [parse j] reads one source.  The shape is the same for both; only the
    warning prefix differs, which the caller adds. *)
let parse (j : Yojson.Safe.t) : Partial.t * string list =
  let w = Warnings.create () in
  let acc = ref Partial.empty in
  parse_object w ~self:"configuration" ~prefix:"" j ~f:(fun ~key:_ name value ->
    match name with
    | "dailyNotes" ->
      acc := { !acc with Partial.daily_notes = parse_daily_notes w value };
      true
    | "hover" ->
      parse_object w ~self:"hover" ~prefix:"hover." value ~f:(fun ~key name value ->
        match name with
        | "maxChars" ->
          acc := { !acc with Partial.hover_max_chars = parse_positive_int w ~key value };
          true
        | _ -> false);
      true
    | "goToDefinition" ->
      parse_object
        w
        ~self:"goToDefinition"
        ~prefix:"goToDefinition."
        value
        ~f:(fun ~key name value ->
          match name with
          | "unresolvedFragment" ->
            acc
            := { !acc with
                 Partial.gtd_unresolved_fragment = parse_fragment_behavior w ~key value
               };
            true
          | _ -> false);
      true
    | "diagnostics" ->
      parse_object
        w
        ~self:"diagnostics"
        ~prefix:"diagnostics."
        value
        ~f:(fun ~key name value ->
          match name with
          | "unresolvedFragment" ->
            acc
            := { !acc with
                 Partial.diag_unresolved_fragment = parse_fragment_behavior w ~key value
               };
            true
          | _ -> false);
      true
    (* Not a setting: the association a JSON language server reads to offer
       completion and validation over this very file.  Reporting it as unknown
       would penalize the one line that makes the file self-documenting.  See
       {!page-"feature-configuration".schema-file}. *)
    | "$schema" -> true
    | _ -> false);
  !acc, Warnings.to_list w
;;

(** {1:keys Key inventory}

    Every dotted key {!parse} accepts, [$schema] aside.  It exists to be
    checked against — the published JSON Schema is a second statement of the
    same thing, and two statements drift.  See
    {!page-"feature-configuration".schema-file}. *)
let known_keys : string list =
  [ "dailyNotes.format"
  ; "dailyNotes.folder"
  ; "dailyNotes.template"
  ; "dailyNotes.linkAction"
  ; "hover.maxChars"
  ; "goToDefinition.unresolvedFragment"
  ; "diagnostics.unresolvedFragment"
  ]
;;

(** Where the published schema lives: the [$schema] value
    [--print-default-config] writes, and the [$id] the schema file itself
    carries.  A raw URL, not a [github.com/blob] one — that serves HTML, which
    a JSON language server cannot read.  See
    {!page-"feature-configuration".schema-file}. *)
let schema_url =
  "https://raw.githubusercontent.com/hon-gyu/oyster/main/pkg/oystermark/lsp/oysterlsp.schema.json"
;;

(** {1:json Emitting}

    The inverse of {!parse}, over a resolved {!t}: what a configuration file
    would have to say to produce these settings.  Used by
    [--print-default-config] to hand over a starting file. *)

let json_of_fragment_behavior : fragment_behavior -> Yojson.Safe.t = function
  | Fallback -> `String "fallback"
  | Strict -> `String "strict"
;;

let to_json (t : t) : Yojson.Safe.t =
  (* [folder] and [template] are optional with no default; omitting them says
     "vault root" and "no template" more honestly than [null] would. *)
  let optional key = function
    | None -> []
    | Some v -> [ key, `String v ]
  in
  `Assoc
    [ ( "dailyNotes"
      , `Assoc
          ([ "format", `String t.daily_notes.format ]
           @ optional "folder" t.daily_notes.folder
           @ optional "template" t.daily_notes.template
           @ [ "linkAction", `Bool t.daily_notes.link_action ]) )
    ; "hover", `Assoc [ "maxChars", `Int t.hover_max_chars ]
    ; ( "goToDefinition"
      , `Assoc
          [ "unresolvedFragment", json_of_fragment_behavior t.gtd_unresolved_fragment ] )
    ; ( "diagnostics"
      , `Assoc
          [ "unresolvedFragment", json_of_fragment_behavior t.diag_unresolved_fragment ] )
    ]
;;

(** {1:sources Sources}

    See {!page-"feature-configuration"}. *)

(** The vault-root file. *)
let file_name = "oysterlsp.json"

(** Prefix each warning with where it came from, so [oysterlsp.json] and the
    client are distinguishable in the message the user sees. *)
let from (source : string) (warnings : string list) : string list =
  List.map warnings ~f:(sprintf "%s: %s" source)
;;

let of_initialization_options (j : Yojson.Safe.t option) : Partial.t * string list =
  match j with
  | None -> Partial.empty, []
  | Some j ->
    let partial, warnings = parse j in
    partial, from "initializationOptions" warnings
;;

(** Read [oysterlsp.json] from [root].  An absent file is not a warning — the
    file is optional; an unreadable or malformed one is. *)
let of_vault_file ~(root : string) : Partial.t * string list =
  let path = Filename.concat root file_name in
  match Stdlib.Sys.file_exists path with
  | false -> Partial.empty, []
  | true ->
    (match In_channel.read_all path |> Yojson.Safe.from_string with
     | j ->
       let partial, warnings = parse j in
       partial, from file_name warnings
     (* The whole file is lost — there is no partial parse to salvage — so the
        message has to carry the parser's own position, folded onto one line
        for a [showMessage]. *)
     | exception Yojson.Json_error msg ->
       ( Partial.empty
       , [ sprintf
             "%s: not valid JSON — %s"
             file_name
             (String.concat ~sep:" " (String.split_lines msg))
         ] )
     | exception exn ->
       Partial.empty, [ sprintf "%s: unreadable — %s" file_name (Exn.to_string exn) ])
;;

(** [load ~root ~init_options] is the whole configuration story: both sources,
    merged with the file on top, plus everything either source asked for and
    could not have.  See {!page-"feature-configuration".precedence}. *)
let load ~(root : string) ~(init_options : Yojson.Safe.t option) : t * string list =
  let from_client, client_warnings = of_initialization_options init_options in
  let from_file, file_warnings = of_vault_file ~root in
  ( resolve (Partial.merge ~lower:from_client ~upper:from_file)
  , client_warnings @ file_warnings )
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

let%test_module "configuration" =
  (module struct
    (** Parse one source and show the settings it resolves to on its own,
        followed by every warning it produced. *)
    let show (s : string) =
      let partial, warnings = parse (Yojson.Safe.from_string s) in
      print_s [%sexp (resolve partial : t)];
      List.iter warnings ~f:(printf "! %s\n")
    ;;

    (** {2 Schema}

        See {!page-"feature-configuration".schema}. *)

    let%expect_test "every key" =
      show
        {|{ "dailyNotes": {"format": "YYYY/MM/YYYY-MM-DD", "folder": "journal",
                           "template": "tpl.md", "linkAction": false},
            "hover": {"maxChars": 400},
            "goToDefinition": {"unresolvedFragment": "strict"},
            "diagnostics": {"unresolvedFragment": "strict"} }|};
      [%expect
        {|
        ((gtd_unresolved_fragment Strict) (diag_unresolved_fragment Strict)
         (hover_max_chars 400)
         (daily_notes
          ((format YYYY/MM/YYYY-MM-DD) (folder (journal)) (template (tpl.md))
           (link_action false))))
        |}]
    ;;

    (* The switch is a plain boolean: anything else is dropped and named,
       rather than being read as truthy. *)
    let%expect_test "linkAction must be a boolean" =
      show {|{"dailyNotes": {"linkAction": "no"}}|};
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! dailyNotes.linkAction: expected a boolean, got "no"
        |}]
    ;;

    let%expect_test "empty object is the default" =
      let partial, warnings = parse (`Assoc []) in
      printf "%b %d\n" (equal (resolve partial) default) (List.length warnings);
      [%expect {| true 0 |}]
    ;;

    (** {2 Tolerance}

        Nothing here fails; everything ignored is named.  See
        {!page-"feature-configuration".tolerance}. *)

    let%expect_test "bad values fall back, with a warning each" =
      show
        {|{ "hover": {"maxChars": "400px"},
            "goToDefinition": {"unresolvedFragment": "lenient"},
            "dailyNotes": {"format": 42, "folder": "  "} }|};
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! hover.maxChars: expected a positive integer, got "400px"
        ! goToDefinition.unresolvedFragment: expected "fallback" or "strict", got "lenient"
        ! dailyNotes.format: expected a non-empty string, got 42
        ! dailyNotes.folder: expected a non-empty string, got "  "
        |}]
    ;;

    (* Zero and negatives are rejected: a hover budget of nothing is far more
       likely a mistake than an intent. *)
    let%expect_test "maxChars must be positive" =
      show {|{"hover": {"maxChars": 0}}|};
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! hover.maxChars: expected a positive integer, got 0
        |}]
    ;;

    (* A misspelled key is otherwise the quietest way to have a setting do
       nothing, at either level of nesting. *)
    let%expect_test "unknown keys are named" =
      show {|{"dailynotes": {}, "hover": {"maxchars": 10}, "disable": ["hover"]}|};
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! unknown key "dailynotes"
        ! unknown key "hover.maxchars"
        ! unknown key "disable"
        |}]
    ;;

    let%expect_test "a source that is not an object" =
      show {|"nonsense"|};
      show {|{"dailyNotes": []}|};
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! configuration: expected an object, got "nonsense"
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 2000)
         (daily_notes
          ((format YYYY-MM-DD) (folder ()) (template ()) (link_action true))))
        ! dailyNotes: expected an object, got []
        |}]
    ;;

    (** {2 Precedence}

        The file wins field by field.  See
        {!page-"feature-configuration".precedence}. *)

    let%expect_test "file overrides client, key by key" =
      let client =
        fst
          (parse
             (Yojson.Safe.from_string
                {|
        {"dailyNotes": {"format": "YYYY-MM-DD", "folder": "old"},
         "hover": {"maxChars": 100}} |}))
      in
      let file =
        fst (parse (Yojson.Safe.from_string {|{"dailyNotes": {"folder": "journal"}}|}))
      in
      print_s [%sexp (resolve (Partial.merge ~lower:client ~upper:file) : t)];
      [%expect
        {|
        ((gtd_unresolved_fragment Fallback) (diag_unresolved_fragment Fallback)
         (hover_max_chars 100)
         (daily_notes
          ((format YYYY-MM-DD) (folder (journal)) (template ()) (link_action true))))
        |}]
    ;;

    (** {2 The file}

        See {!page-"feature-configuration".file}. *)

    let with_root (contents : string option) ~f =
      let root = Core_unix.mkdtemp "/tmp/oysterlsp-config" in
      Option.iter contents ~f:(fun c ->
        Out_channel.write_all (Filename.concat root file_name) ~data:c);
      Exn.protect
        ~f:(fun () -> f root)
        ~finally:(fun () -> ignore (Stdlib.Sys.command (sprintf "rm -rf %s" root) : int))
    ;;

    let load_show ?init_options contents =
      with_root contents ~f:(fun root ->
        let init_options = Option.map init_options ~f:Yojson.Safe.from_string in
        let t, warnings = load ~root ~init_options in
        print_s [%sexp (t.daily_notes : daily_notes)];
        List.iter warnings ~f:(printf "! %s\n"))
    ;;

    let%expect_test "no file: the client's settings stand" =
      load_show None ~init_options:{|{"dailyNotes": {"folder": "from-client"}}|};
      [%expect
        {| ((format YYYY-MM-DD) (folder (from-client)) (template ()) (link_action true)) |}]
    ;;

    let%expect_test "file overrides the client, and says which source erred" =
      load_show
        (Some {|{"dailyNotes": {"folder": "from-file"}, "hover": {"maxChars": []}}|})
        ~init_options:{|{"dailyNotes": {"folder": "from-client"}, "nope": 1}|};
      [%expect
        {|
        ((format YYYY-MM-DD) (folder (from-file)) (template ()) (link_action true))
        ! initializationOptions: unknown key "nope"
        ! oysterlsp.json: hover.maxChars: expected a positive integer, got []
        |}]
    ;;

    (* Malformed JSON loses the whole file — there is no partial parse to
       salvage — but not the server. *)
    let%expect_test "malformed file" =
      load_show
        (Some {|{"dailyNotes": {|})
        ~init_options:{|{"dailyNotes": {"folder": "c"}}|};
      [%expect
        {|
        ((format YYYY-MM-DD) (folder (c)) (template ()) (link_action true))
        ! oysterlsp.json: not valid JSON — Line 1, bytes 15-16: Unexpected end of input
        |}]
    ;;

    (** {2 Daily-note format}

        Validated on demand rather than at parse time; see
        {!page-"feature-daily-notes".format}. *)

    let%expect_test "format is validated later" =
      let show s =
        let t = resolve (fst (parse (Yojson.Safe.from_string s))) in
        match daily_notes_settings t with
        | Ok settings ->
          printf
            "%s\n"
            (Daily_notes.path_of_date
               settings
               (Date.create_exn ~y:2026 ~m:Month.Jul ~d:6))
        | Error e -> printf "disabled: %s\n" e
      in
      show {|{"dailyNotes": {"format": "YYYY/MM/YYYY-MM-DD", "folder": "journal"}}|};
      show {|{"dailyNotes": {"format": "YYYY-ww"}}|};
      [%expect
        {|
        journal/2026/07/2026-07-06.md
        disabled: unsupported format token 'w'
        |}]
    ;;
  end)
;;
