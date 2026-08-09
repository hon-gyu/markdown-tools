(** Implementation of {!Server}

    Two content sources are in play and the difference is deliberate:
    diagnostics and the cursor-position features answer against
    {!buffer_content} (what the user sees, unsaved edits included), while
    everything vault-wide answers against {!disk_content}.  See
    {!page-"feature-document-sync"}. *)

open Core

(* Feature modules are aliased before [open Lsp.Types] so that names the
   protocol also claims — [Hover], [Diagnostic]-adjacent ones — keep
   referring to the pure logic layer. *)
module Feature = struct
  module Completion = Completion
  module Create_unresolved_note = Create_unresolved_note
  module Diagnostics = Diagnostics
  module Document_outline = Document_outline
  module Find_references = Find_references
  module Go_to_definition = Go_to_definition
  module Hover = Hover
  module Inlay_hints = Inlay_hints
  module Rename = Rename
  module Toc = Toc
end

open Linol_lsp.Lsp.Types

(* State
   ====== *)

type t =
  { mutable vault : Oystermark.Vault.t option
    (** [None] until {!initialize} has seen a workspace root. *)
  ; open_docs : string String.Table.t
    (** Vault-relative path → in-flight buffer content for every document
          the editor currently has open.  Diagnostics and the
          cursor-position features answer against this; the rest read from
          disk.  See {!page-"feature-document-sync"}. *)
  ; mutable config : Lsp_config.t
    (** Client-supplied settings, seen once at {!initialize}. *)
  ; mutable config_warnings : string list
    (** Everything the configuration sources asked for and could not have,
          gathered at {!initialize} for the adapter to report.  A setting
          ignored in silence is indistinguishable from one that does not
          exist.  See {!page-"feature-configuration".tolerance}. *)
  ; mutable daily_table : (Date.t * Daily_notes.Table.t) option
    (** Memoized recognition table with the date it was built for; a server
          left running overnight rebuilds it.  See
          {!page-"feature-daily-notes".recognition}. *)
  ; now : unit -> Date.t
    (** The clock, as a dependency: daily-note answers depend on today's date,
          and a test that cannot fix "today" would change meaning overnight. *)
  }

let build_vault = Oystermark.Vault.of_root_path ~skip_expand:true

(** Today in the machine's own timezone — the real clock, used unless a caller
    substitutes one. *)
let system_today () : Date.t = Date.today ~zone:(Lazy.force Time_float_unix.Zone.local)

let create ?(now : unit -> Date.t = system_today) () : t =
  { vault = None
  ; open_docs = String.Table.create ()
  ; config = Lsp_config.default
  ; config_warnings = []
  ; daily_table = None
  ; now
  }
;;

let initialize (t : t) ~(root : string) ?(init_options : Yojson.Safe.t option) () : unit =
  let config, warnings = Lsp_config.load ~root ~init_options in
  t.config <- config;
  t.daily_table <- None;
  match config.disable with
  (* Leaving the vault unbuilt is the whole of the disabling: every handler
     already answers emptily without one, so there is no second place where
     the switch has to be remembered.  It also means the vault is never
     indexed, which is the cost the switch exists to avoid.  See
     {!page-"feature-configuration".disable}. *)
  | true ->
    (* Warnings about settings that were never going to take effect would be
       noise from a server that is doing nothing; the adapter says the one
       thing worth saying instead. *)
    t.config_warnings <- [];
    t.vault <- None
  | false ->
    (* The daily-note format is validated here rather than at parse time — it
       is the one setting whose usability is a property of its {e value} — but
       it joins the same list, so the user hears about it the same way. *)
    let daily_notes_warning =
      match Lsp_config.daily_notes_settings config with
      | Ok _ -> []
      | Error e -> [ sprintf "daily notes disabled: %s" e ]
    in
    t.config_warnings <- warnings @ daily_notes_warning;
    t.vault <- Some (build_vault root)
;;

(** Whether the configuration turned the server off.  The adapter reports it,
    since a server that answers nothing and says nothing is indistinguishable
    from a broken one.  See {!page-"feature-configuration".disable}. *)
let disabled (t : t) : bool = t.config.disable

(** What the configuration sources asked for and could not have.  Empty when
    the configuration is clean; meaningful only after {!initialize}, which is
    also the only time it is computed.  See
    {!page-"feature-configuration".tolerance}. *)
let config_warnings (t : t) : string list = t.config_warnings

let rebuild_vault (t : t) : unit =
  match t.vault with
  | None -> ()
  | Some v -> t.vault <- Some (build_vault v.vault_root)
;;

let vault_root (t : t) : string option =
  Option.map t.vault ~f:(fun (v : Oystermark.Vault.t) -> v.vault_root)
;;

(* Paths and URIs
   =============== *)

let rel_path_of_uri (t : t) (uri : DocumentUri.t) : string =
  let file_path = DocumentUri.to_path uri in
  match t.vault with
  | None -> file_path
  | Some v ->
    (match String.chop_prefix file_path ~prefix:(v.vault_root ^ "/") with
     | Some rel -> rel
     | None -> file_path)
;;

let uri_of_rel_path (t : t) (rel_path : string) : DocumentUri.t =
  match t.vault with
  | None -> DocumentUri.of_path rel_path
  | Some v -> DocumentUri.of_path (Filename.concat v.vault_root rel_path)
;;

let read_file (t : t) (rel_path : string) : string option =
  match t.vault with
  | None -> None
  | Some v ->
    (try Some (In_channel.read_all (Filename.concat v.vault_root rel_path)) with
     | _ -> None)
;;

let disk_content (t : t) (rel_path : string) : string =
  Option.value (read_file t rel_path) ~default:""
;;

let buffer_content (t : t) (rel_path : string) : string =
  match Hashtbl.find t.open_docs rel_path with
  | Some content -> content
  | None -> disk_content t rel_path
;;

(* Position conversion
   ==================== *)

let position_of_byte (content : string) (offset : int) : Position.t =
  let line, character = Lsp_util.position_of_byte_offset content offset in
  Position.create ~line ~character
;;

let range_of_bytes (content : string) ~(first_byte : int) ~(last_byte : int) : Range.t =
  Range.create
    ~start:(position_of_byte content first_byte)
    ~end_:(position_of_byte content last_byte)
;;

let byte_of_position (content : string) ~(line : int) ~(character : int) : int =
  Lsp_util.byte_offset_of_position content ~line ~character
;;

(* Document synchronization
   ========================= *)

(** Every line of a command block that names nothing.  A misspelling would
    otherwise be inert, and inert looks exactly like unimplemented. *)
let command_block_diagnostics (content : string) : Diagnostic.t list =
  Command_block.entries content
  |> List.filter_map ~f:(fun (e : Command_block.entry) ->
    match e.command with
    | Some _ -> None
    | None ->
      let line_start = Lsp_util.line_start_byte content ~line:e.line in
      Some
        (Diagnostic.create
           ~range:
             (range_of_bytes
                content
                ~first_byte:line_start
                ~last_byte:(line_start + String.length e.text))
           ~severity:DiagnosticSeverity.Warning
           ~source:"oystermark"
           ~message:
             (`String
                 (sprintf
                    "unknown oysterlsp command %S; expected one of %s"
                    e.text
                    (String.concat
                       ~sep:", "
                       (List.map
                          Command_block.all_of_command
                          ~f:Command_block.name_of_command))))
           ()))
;;

(** A table of contents that no longer describes the document, and a [::: toc]
    fence left unclosed.  Unlike the link diagnostics this needs no vault: a
    TOC describes one file.  See {!page-"feature-toc".diagnostics}. *)
let toc_diagnostics (content : string) : Diagnostic.t list =
  Feature.Toc.diagnostics content
  |> List.map ~f:(fun (d : Feature.Toc.diagnostic) ->
    Diagnostic.create
      ~range:(range_of_bytes content ~first_byte:d.first_byte ~last_byte:d.last_byte)
      ~severity:DiagnosticSeverity.Warning
      ~source:"oystermark"
      ~message:(`String d.message)
      ())
;;

let diagnostics (t : t) ~(rel_path : string) ~(content : string) : Diagnostic.t list =
  match t.vault with
  | None -> []
  | Some v ->
    let links =
      Feature.Diagnostics.compute ~index:v.index ~rel_path ~content ()
      |> List.map ~f:(fun (d : Feature.Diagnostics.diagnostic) ->
        Diagnostic.create
          ~range:(range_of_bytes content ~first_byte:d.first_byte ~last_byte:d.last_byte)
          ~severity:DiagnosticSeverity.Warning
          ~source:"oystermark"
          ~message:(`String d.message)
          ())
    in
    links @ command_block_diagnostics content @ toc_diagnostics content
;;

let did_open (t : t) ~(rel_path : string) ~(content : string) : Diagnostic.t list =
  Hashtbl.set t.open_docs ~key:rel_path ~data:content;
  rebuild_vault t;
  diagnostics t ~rel_path ~content
;;

let did_change (t : t) ~(rel_path : string) ~(content : string) : Diagnostic.t list =
  Hashtbl.set t.open_docs ~key:rel_path ~data:content;
  diagnostics t ~rel_path ~content
;;

let did_close (t : t) ~(rel_path : string) : unit = Hashtbl.remove t.open_docs rel_path

let did_save (t : t) : (string * Diagnostic.t list) list =
  rebuild_vault t;
  match t.vault with
  | None -> []
  | Some _ ->
    Hashtbl.keys t.open_docs
    |> List.sort ~compare:String.compare
    |> List.filter_map ~f:(fun rel_path ->
      match read_file t rel_path with
      | None -> None
      | Some content -> Some (rel_path, diagnostics t ~rel_path ~content))
;;

(* Features
   ========= *)

let hover (t : t) ~(rel_path : string) ~(line : int) ~(character : int) : Hover.t option =
  match t.vault with
  | None -> None
  | Some v ->
    let content = buffer_content t rel_path in
    (match
       Feature.Hover.hover
         ~index:v.index
         ~rel_path
         ~content
         ~line
         ~character
         ~read_file:(read_file t)
         ()
     with
     | None -> None
     | Some (text, first_byte, last_byte) ->
       let contents =
         `MarkupContent (MarkupContent.create ~kind:MarkupKind.Markdown ~value:text)
       in
       Some
         (Hover.create
            ~contents
            ~range:(range_of_bytes content ~first_byte ~last_byte)
            ()))
;;

(* {!definition} answers command-block lines too, so it is defined with the
   other handlers that need {!resolve_command} — below the command-block
   section, alongside {!code_action} and {!completion}. *)

let references (t : t) ~(rel_path : string) ~(line : int) ~(character : int)
  : Location.t list option
  =
  match t.vault with
  | None -> None
  | Some v ->
    let refs =
      Feature.Find_references.find_references
        ~index:v.index
        ~docs:(Oystermark.Vault.docs v)
        ~rel_path
        ~content:(disk_content t rel_path)
        ~line
        ~character
        ()
    in
    Some
      (List.map refs ~f:(fun (r : Feature.Find_references.reference) ->
         Location.create
           ~uri:(uri_of_rel_path t r.rel_path)
           ~range:
             (range_of_bytes
                (disk_content t r.rel_path)
                ~first_byte:r.first_byte
                ~last_byte:r.last_byte)))
;;

let prepare_rename (t : t) ~(rel_path : string) ~(line : int) ~(character : int)
  : Range.t option
  =
  match t.vault with
  | None -> None
  | Some v ->
    (match
       Feature.Find_references.detect_target
         ~index:v.index
         ~rel_path
         ~content:(disk_content t rel_path)
         ~line
         ~character
     with
     | None -> None
     | Some _ ->
       let pos = Position.create ~line ~character in
       Some (Range.create ~start:pos ~end_:pos))
;;

let rename
      (t : t)
      ~(rel_path : string)
      ~(line : int)
      ~(character : int)
      ~(new_name : string)
  : WorkspaceEdit.t
  =
  match t.vault with
  | None -> WorkspaceEdit.create ()
  | Some v ->
    let content = disk_content t rel_path in
    let edits =
      Feature.Rename.rename
        ~index:v.index
        ~docs:(Oystermark.Vault.docs v)
        ~read_file:(read_file t)
        ~rel_path
        ~content
        ~line
        ~character
        ~new_name
        ()
    in
    let text_document_edits =
      List.group edits ~break:(fun a b -> not (String.equal a.rel_path b.rel_path))
      |> List.filter_map ~f:(function
        | [] -> None
        | { Feature.Rename.rel_path; _ } :: _ as edits ->
          let content = disk_content t rel_path in
          let textDocument =
            OptionalVersionedTextDocumentIdentifier.create
              ~uri:(uri_of_rel_path t rel_path)
              ()
          in
          let edits =
            List.map edits ~f:(fun (edit : Feature.Rename.edit) ->
              `TextEdit
                (TextEdit.create
                   ~range:
                     (range_of_bytes
                        content
                        ~first_byte:edit.first_byte
                        ~last_byte:edit.last_byte)
                   ~newText:edit.new_text))
          in
          Some (`TextDocumentEdit (TextDocumentEdit.create ~edits ~textDocument)))
    in
    let documentChanges =
      match
        Feature.Find_references.detect_target
          ~index:v.index
          ~rel_path
          ~content
          ~line
          ~character
      with
      | Some (Path_only { path }) when Feature.Rename.valid_note_name new_name ->
        let new_path = Feature.Rename.renamed_note_path ~path ~new_name in
        let rename_file =
          RenameFile.create
            ~oldUri:(uri_of_rel_path t path)
            ~newUri:(uri_of_rel_path t new_path)
            ()
        in
        text_document_edits @ [ `RenameFile rename_file ]
      | _ -> text_document_edits
    in
    WorkspaceEdit.create ~documentChanges ()
;;

let document_symbol (t : t) ~(rel_path : string) : DocumentSymbol.t list option =
  match t.vault with
  | None -> None
  | Some v ->
    let content = disk_content t rel_path in
    let to_position offset = position_of_byte content offset in
    let rec to_lsp (symbol : Feature.Document_outline.symbol) : DocumentSymbol.t =
      let kind, detail =
        match symbol.kind with
        | Heading level -> SymbolKind.Namespace, sprintf "heading %d" level
        | Block_id -> SymbolKind.Key, "block id"
        | Attribute_id -> SymbolKind.Key, "attribute id"
      in
      DocumentSymbol.create
        ~name:symbol.name
        ~kind
        ~detail
        ~range:
          (Range.create
             ~start:(to_position symbol.first_byte)
             ~end_:(to_position symbol.last_byte))
        ~selectionRange:
          (Range.create
             ~start:(to_position symbol.selection_first_byte)
             ~end_:(to_position symbol.selection_last_byte))
        ~children:(List.map symbol.children ~f:to_lsp)
        ()
    in
    Feature.Document_outline.document_outline ~index:v.index ~rel_path ~content
    |> List.map ~f:to_lsp
    |> Option.return
;;

(* Daily notes
   ============

   See {!page-"feature-daily-notes"}. *)

(** The command a daily-note code action carries.  A code action cannot focus
    an editor by itself, so the action defers to this command, which the client
    sends back as [workspace/executeCommand]. *)
let daily_note_command = "oystermark.dailyNote.open"

(** What {!execute_command} decided should happen.  Returning an intent rather
    than performing it keeps the protocol effects — [workspace/applyEdit] and
    [window/showDocument] — in the adapter, and this decision testable. *)
type open_note =
  { uri : DocumentUri.t
  ; create : WorkspaceEdit.t option (** [None] when the note already exists. *)
  ; report_unfocused : bool
    (** Whether a client that cannot focus should be told where the note
            is.  [false] when the caller already gave the client an edit that
            opens it, so the reader has the note in front of them and the
            message would only contradict what they can see. *)
  }

(** Whether a vault-relative path exists on disk.  Read from disk rather than
    the index because a note created moments ago by this very command has not
    been indexed yet. *)
let file_exists (t : t) (rel_path : string) : bool =
  match vault_root t with
  | None -> false
  | Some root -> Stdlib.Sys.file_exists (Filename.concat root rel_path)
;;

(** The recognition table for the configured settings, rebuilt when the day
    turns over.  [Error] when the configured format is unsupported, which
    disables the daily-note actions. *)
let daily_table (t : t) : (Daily_notes.Table.t, string) Result.t =
  match Lsp_config.daily_notes_settings t.config with
  | Error _ as e -> e
  | Ok settings ->
    let today = t.now () in
    (match t.daily_table with
     | Some (built_for, table) when Date.equal built_for today -> Ok table
     | _ ->
       let table = Daily_notes.Table.create settings ~today in
       t.daily_table <- Some (today, table);
       Ok table)
;;

(** The edit that brings a missing note into existence, carried by the code
    action itself rather than deferred to {!daily_note_command}.

    A [CreateFile] on its own leaves a client with nothing to show: the file
    lands on disk and no editor opens, which is why creation used to end in the
    same silence as opening where [window/showDocument] is missing.  A
    [TextDocumentEdit] cannot be applied to a document without opening it, so
    the empty text edit below — it writes nothing, the created note stays empty
    — is what puts the note in front of the reader on such a client.  Focusing
    is still the client's (see {!page-"feature-daily-notes".focus}); this only
    makes creation reach a document by the better-supported half. *)
let create_note_edit (uri : DocumentUri.t) : WorkspaceEdit.t =
  let zero = Position.create ~line:0 ~character:0 in
  WorkspaceEdit.create
    ~documentChanges:
      [ `CreateFile
          (CreateFile.create
             ~uri
             ~options:(CreateFileOptions.create ~ignoreIfExists:true ~overwrite:false ())
             ())
      ; `TextDocumentEdit
          (TextDocumentEdit.create
             ~textDocument:(OptionalVersionedTextDocumentIdentifier.create ~uri ())
             ~edits:
               [ `TextEdit
                   (TextEdit.create
                      ~range:(Range.create ~start:zero ~end_:zero)
                      ~newText:"")
               ])
      ]
    ()
;;

(** One daily-note code action: a title that says whether the note will be
    created, the edit that creates it when it is missing, and the command that
    opens it.

    The command is asked to open only ([create = false]): the edit above has
    already created the note by the time it runs, and a second [CreateFile]
    would race the buffer the client just opened — unsaved, so the file may not
    be on disk yet. *)
let daily_note_action (t : t) ~(title : string) ~(path : string) : CodeAction.t =
  let exists = file_exists t path in
  CodeAction.create
    ~title:(sprintf "%s %s" (if exists then "Open" else "Create") title)
    ~kind:CodeActionKind.Refactor
    ?edit:(if exists then None else Some (create_note_edit (uri_of_rel_path t path)))
    ~command:
      (Command.create
         ~title
         ~command:daily_note_command
         ~arguments:[ `String path; `Bool false; `Bool (not exists) ]
         ())
    ()
;;

(** The daily-note actions available at [rel_path].

    The calendar family is always offered and creates on demand; the existing
    family is offered only from a file that is itself a daily note, and only
    when there is somewhere to go.  See {!page-"feature-daily-notes"}. *)
let daily_note_actions (t : t) ~(rel_path : string) : CodeAction.t list =
  match daily_table t with
  | Error _ -> []
  | Ok table ->
    let settings = table.Daily_notes.Table.settings in
    let today = t.now () in
    let calendar =
      [ "today's daily note", today
      ; "yesterday's daily note", Date.add_days today (-1)
      ; "tomorrow's daily note", Date.add_days today 1
      ]
      |> List.map ~f:(fun (title, date) ->
        daily_note_action t ~title ~path:(Daily_notes.path_of_date settings date))
    in
    let existing =
      match Daily_notes.Table.date_of_path table rel_path with
      | None -> []
      | Some date ->
        let exists p = file_exists t p in
        let step title f =
          match f table ~exists date with
          | None -> []
          | Some (_, path) ->
            [ CodeAction.create
                ~title
                ~kind:CodeActionKind.Refactor
                ~command:
                  (Command.create
                     ~title
                     ~command:daily_note_command
                     ~arguments:[ `String path; `Bool false ]
                     ())
                ()
            ]
        in
        step "Open previous daily note" Daily_notes.Table.previous_existing
        @ step "Open next daily note" Daily_notes.Table.next_existing
    in
    calendar @ existing
;;

(** Write a wikilink to today's daily note at the cursor, creating the note
    when it is missing.

    Every other action in the family reaches its note through
    [window/showDocument], which the protocol makes optional and not every
    client implements.  This one asks for nothing but a [WorkspaceEdit], and
    leaves behind a link that go-to-definition follows — so the note stays
    reachable wherever that capability is missing.  It is also, independently,
    an ordinary thing to want in a note.

    The link is the note's base name: [resolve_file] matches a path
    subsequence, so [ [[2026-07-26]] ] finds [2026/07/2026-07-26.md] under a
    nested format without the writer spelling out the folders.  See
    {!page-"feature-daily-notes".link}. *)
let daily_note_link_actions (t : t) ~(rel_path : string) ~(line : int) ~(character : int)
  : CodeAction.t list
  =
  match daily_table t with
  | Error _ -> []
  (* Unlike the rest of the family this one is offered in every menu in the
     vault, wanted there or not, so it is the one worth being able to turn off
     without disabling daily notes.  See {!page-"feature-daily-notes".link}. *)
  | Ok _ when not t.config.daily_notes.link_action -> []
  | Ok table ->
    let path = Daily_notes.path_of_date table.Daily_notes.Table.settings (t.now ()) in
    let name = Filename.chop_extension (Filename.basename path) in
    let create =
      if file_exists t path
      then []
      else
        [ `CreateFile
            (CreateFile.create
               ~uri:(uri_of_rel_path t path)
               ~options:
                 (CreateFileOptions.create ~ignoreIfExists:true ~overwrite:false ())
               ())
        ]
    in
    let at = Position.create ~line ~character in
    let insert =
      `TextDocumentEdit
        (TextDocumentEdit.create
           ~textDocument:
             (OptionalVersionedTextDocumentIdentifier.create
                ~uri:(uri_of_rel_path t rel_path)
                ())
           ~edits:
             [ `TextEdit
                 (TextEdit.create
                    ~range:(Range.create ~start:at ~end_:at)
                    ~newText:(sprintf "[[%s]]" name))
             ])
    in
    (* Creation first: the link should resolve the moment it is written. *)
    [ CodeAction.create
        ~title:"Insert link to today's daily note"
        ~kind:CodeActionKind.Refactor
        ~edit:(WorkspaceEdit.create ~documentChanges:(create @ [ insert ]) ())
        ()
    ]
;;

(* Command blocks
   ===============

   See {!page-"feature-command-block"}.  Nothing new happens here: a block line
   is another way to reach the daily-note command, lifted from the code-action
   menu onto a line where a lens can render it. *)

(** What a command-block line amounts to right now, in this note.  [target] is
    [None] when the command is understood but cannot run — then [label] says
    why, and the surfaces show it without anything to click. *)
type resolved_command =
  { label : string
  ; target : (string * bool) option (** [(path, create_it)]. *)
  }

let resolve_command (t : t) ~(rel_path : string) (c : Command_block.command)
  : resolved_command
  =
  match daily_table t with
  | Error _ -> { label = "daily notes disabled"; target = None }
  | Ok table ->
    let settings = table.Daily_notes.Table.settings in
    let today = t.now () in
    (* Calendar commands always have a target: a missing note is created. *)
    let calendar (what : string) (date : Date.t) =
      let path = Daily_notes.path_of_date settings date in
      let exists = file_exists t path in
      { label = sprintf "%s %s daily note" (if exists then "Open" else "Create") what
      ; target = Some (path, not exists)
      }
    in
    (* Previous/next answer relative to the {e host} note, which is why the
       block lives in a note.  Neither ever creates. *)
    let step (what : string) f =
      match Daily_notes.Table.date_of_path table rel_path with
      | None ->
        { label = sprintf "no %s daily note: this note is not one" what; target = None }
      | Some date ->
        (match f table ~exists:(fun p -> file_exists t p) date with
         | None -> { label = sprintf "no %s daily note" what; target = None }
         | Some (_, path) ->
           { label = sprintf "Open %s daily note (%s)" what path
           ; target = Some (path, false)
           })
    in
    (match c with
     | Daily_today -> calendar "today's" today
     | Daily_yesterday -> calendar "yesterday's" (Date.add_days today (-1))
     | Daily_tomorrow -> calendar "tomorrow's" (Date.add_days today 1)
     | Daily_prev -> step "previous" Daily_notes.Table.previous_existing
     | Daily_next -> step "next" Daily_notes.Table.next_existing)
;;

(** The lens for one line: a whole-line range, the resolved label, and the
    command when there is one to run. *)
let lens_of_entry
      (t : t)
      ~(rel_path : string)
      ~(content : string)
      (e : Command_block.entry)
  : CodeLens.t option
  =
  match e.command with
  (* An unknown name gets a diagnostic instead; a lens saying nothing useful
     would only compete with it. *)
  | None -> None
  | Some c ->
    let { label; target } = resolve_command t ~rel_path c in
    let line_start = Lsp_util.line_start_byte content ~line:e.line in
    let range =
      range_of_bytes
        content
        ~first_byte:line_start
        ~last_byte:(line_start + String.length e.text)
    in
    Some
      (CodeLens.create
         ~range
         ?command:
           (Option.map target ~f:(fun (path, create) ->
              Command.create
                ~title:label
                ~command:daily_note_command
                ~arguments:[ `String path; `Bool create ]
                ()))
         ~data:(`String label)
         ())
;;

(** A reference count as a lens above its line: [3 references] over a heading,
    [12 backlinks] over the note, carrying the references themselves so that
    clicking the lens opens them.  The locations come from the same scan that
    produced the number, so the list can never disagree with the count above
    it.  See {!page-"feature-codelens-reference-counts"}. *)
let reference_lenses (t : t) ~(rel_path : string) ~(content : string) : CodeLens.t list =
  if not t.config.code_lens_references
  then []
  else (
    match t.vault with
    | None -> []
    | Some v ->
      Reference_counts.entries
        ~docs:(Oystermark.Vault.docs v)
        ~rel_path
        ~content
        ~range_start_line:0
        ~range_end_line:Int.max_value
        ~count_toc_links:t.config.code_lens_count_toc_links
      |> List.map ~f:(fun (e : Reference_counts.entry) ->
        let at = Position.create ~line:e.line ~character:0 in
        let locations =
          List.map e.refs ~f:(fun (r : Feature.Find_references.reference) ->
            Location.create
              ~uri:(uri_of_rel_path t r.rel_path)
              ~range:
                (range_of_bytes
                   (disk_content t r.rel_path)
                   ~first_byte:r.first_byte
                   ~last_byte:r.last_byte)
            |> Location.yojson_of_t)
        in
        let title = Reference_counts.lens_title e in
        (* The command name is the client's, not the protocol's: there is no
           standard "show me these locations", only a convention VS Code named
           and others implement.  Configured, therefore — and [""] means the
           lens is a label, which is also what an unaware client makes of a
           name it does not know.  A [Command] is still required: a lens shows
           its title through one.  See
           {!page-"feature-codelens-reference-counts".click}. *)
        let command = t.config.code_lens_show_references_command in
        CodeLens.create
          ~range:(Range.create ~start:at ~end_:at)
          ~command:
            (Command.create
               ~title
               ~command
               ?arguments:
                 (if String.is_empty command
                  then None
                  else
                    Some
                      [ DocumentUri.yojson_of_t (uri_of_rel_path t rel_path)
                      ; Position.yojson_of_t at
                      ; `List locations
                      ])
               ())
          ()))
;;

(** Spec: {!page-"feature-command-block".surfaces} for the command-block
    lenses, {!page-"feature-codelens-reference-counts"} for the counts.  [None]
    outside a vault, so a client learns nothing is coming rather than seeing an
    empty list.

    Command lenses come first: they are the note's control panel, and a count
    is an annotation that should not push it down the response. *)
let code_lens (t : t) ~(rel_path : string) : CodeLens.t list option =
  match t.vault with
  | None -> None
  | Some _ ->
    let content = buffer_content t rel_path in
    (Command_block.entries content
     |> List.filter_map ~f:(lens_of_entry t ~rel_path ~content))
    @ reference_lenses t ~rel_path ~content
    |> Option.return
;;

(** The single action for the command-block line under the cursor, if that is
    where the cursor is.  The keyboard route to what the lens offers. *)
let command_block_actions (t : t) ~(rel_path : string) ~(line : int) : CodeAction.t list =
  let content = buffer_content t rel_path in
  match Command_block.entry_at content ~line with
  | None -> []
  | Some { command = None; _ } -> []
  | Some { command = Some c; _ } ->
    (match resolve_command t ~rel_path c with
     | { target = None; _ } -> []
     | { label; target = Some (path, create) } ->
       (* Same bargain as {!daily_note_action}: an action can carry the edit,
          so creation reaches a document even where the command cannot focus
          one.  The lens beside it has only the command — a [CodeLens] carries
          nothing else — and stays as it was. *)
       [ CodeAction.create
           ~title:label
           ~kind:CodeActionKind.Refactor
           ~isPreferred:true
           ?edit:
             (if create then Some (create_note_edit (uri_of_rel_path t path)) else None)
           ~command:
             (Command.create
                ~title:label
                ~command:daily_note_command
                ~arguments:[ `String path; `Bool false; `Bool create ]
                ())
           ()
       ])
;;

(** The action that seeds a note with a panel of its own, at the cursor's line.

    Offered only where there is no block yet, and listing only the commands
    that can run in {e this} note — an ordinary note gets the calendar three,
    a daily note with neighbours gets all five.  Inserting the whole catalogue
    everywhere would hand most notes two lines the lenses immediately report as
    dead.  See {!page-"feature-command-block".insert}. *)
let insert_command_block_actions (t : t) ~(rel_path : string) ~(line : int)
  : CodeAction.t list
  =
  let content = buffer_content t rel_path in
  if Command_block.has_command_block content
  then []
  else (
    match
      List.filter Command_block.all_of_command ~f:(fun c ->
        Option.is_some (resolve_command t ~rel_path c).target)
    with
    (* Nothing runs here — daily notes are off — so there is no panel worth
       writing. *)
    | [] -> []
    | commands ->
      let at = Position.create ~line ~character:0 in
      [ CodeAction.create
          ~title:"Insert oysterlsp command block"
          ~kind:CodeActionKind.Refactor
          ~edit:
            (WorkspaceEdit.create
               ~documentChanges:
                 [ `TextDocumentEdit
                     (TextDocumentEdit.create
                        ~textDocument:
                          (OptionalVersionedTextDocumentIdentifier.create
                             ~uri:(uri_of_rel_path t rel_path)
                             ())
                        ~edits:
                          [ `TextEdit
                              (TextEdit.create
                                 ~range:(Range.create ~start:at ~end_:at)
                                 ~newText:(Command_block.render commands))
                          ])
                 ]
               ())
          ()
      ])
;;

(** The catalogue, offered inside a command block and nowhere else. *)
let command_block_completions (t : t) ~(rel_path : string) ~(line : int)
  : CompletionItem.t list option
  =
  let content = buffer_content t rel_path in
  if not (Command_block.in_command_block content ~line)
  then None
  else
    List.map Command_block.all_of_command ~f:(fun c ->
      let name = Command_block.name_of_command c in
      CompletionItem.create
        ~label:name
        ~kind:CompletionItemKind.Event
        ~detail:(Command_block.doc_of_command c)
          (* What it would do here, today — the same text the lens would show. *)
        ~documentation:(`String (resolve_command t ~rel_path c).label)
        ())
    |> Option.return
;;

(** The note a command-block line {e points at}, when that note is already
    there.  The command's own target, read rather than run.

    A calendar command whose note is missing yields [None]: its lens says
    [Create ...], and go-to-definition may not create anything — a jump that
    wrote a file would be a surprising answer to a navigation request.
    [daily/prev] and [daily/next] never create, so they point wherever they
    would open.  See {!page-"feature-command-block".surfaces}. *)
let command_block_definition (t : t) ~(rel_path : string) ~(line : int) : string option =
  let content = buffer_content t rel_path in
  match Command_block.entry_at content ~line with
  | None | Some { command = None; _ } -> None
  | Some { command = Some c; _ } ->
    (match (resolve_command t ~rel_path c).target with
     | None -> None
     (* [create] is exactly "the note is not there yet". *)
     | Some (_, true) -> None
     | Some (path, false) -> Some path)
;;

(** Spec: {!page-"feature-go-to-definition"}.  A command-block line is tried
    first: it is literal text inside a fence, so the link layer finds nothing
    there, and the note the line names is what a definition means on it.  See
    {!page-"feature-command-block".surfaces}. *)
let definition (t : t) ~(rel_path : string) ~(line : int) ~(character : int)
  : Location.t list option
  =
  match t.vault with
  | None -> None
  | Some v ->
    let location ~path ~line ~character =
      let pos = Position.create ~line ~character in
      [ Location.create
          ~uri:(uri_of_rel_path t path)
          ~range:(Range.create ~start:pos ~end_:pos)
      ]
    in
    (match command_block_definition t ~rel_path ~line with
     | Some path -> Some (location ~path ~line:0 ~character:0)
     | None ->
       (match
          Feature.Go_to_definition.go_to_definition
            ~read_file:(read_file t)
            ~index:v.index
            ~rel_path
            ~content:(buffer_content t rel_path)
            ~line
            ~character
            ()
        with
        | None -> None
        | Some { path; line; character } -> Some (location ~path ~line ~character)))
;;

(** Handle [workspace/executeCommand].  [None] for an unknown command or
    unusable arguments — an editor is free to send either. *)
let execute_command (t : t) ~(command : string) ~(arguments : Yojson.Safe.t list option)
  : open_note option
  =
  match command, arguments with
  (* Without a vault root there is no path to resolve the argument against —
     and nothing offered the command in the first place, disabled or not yet
     initialized. *)
  | _ when Option.is_none t.vault -> None
  | cmd, Some (`String path :: `Bool create :: rest)
    when String.equal cmd daily_note_command
         &&
         match rest with
         | [] | [ `Bool _ ] -> true
         | _ -> false ->
    let uri = uri_of_rel_path t path in
    (* The optional third argument says the caller already handed the client an
       edit that opens this note (see {!create_note_edit}).  Then a failure to
       focus is not worth a message: the reader is looking at the note. *)
    let report_unfocused =
      match rest with
      | [ `Bool opened_by_edit ] -> not opened_by_edit
      | _ -> true
    in
    let create =
      if create && not (file_exists t path)
      then
        Some
          (WorkspaceEdit.create
             ~documentChanges:
               [ `CreateFile
                   (CreateFile.create
                      ~uri
                      ~options:
                        (CreateFileOptions.create
                           ~ignoreIfExists:true
                           ~overwrite:false
                           ())
                      ())
               ]
             ())
      else None
    in
    Some { uri; create; report_unfocused }
  | _ -> None
;;

(* Table of contents
   ==================

   See {!page-"feature-toc"}.  Both actions read {!buffer_content} rather than
   disk: a TOC describes headings that were just typed, and an edit derived
   from a different version of the file would be applied to this one.  See
   {!page-"feature-toc".frame}. *)

let toc_workspace_edit
      (t : t)
      ~(rel_path : string)
      ~(content : string)
      (e : Feature.Toc.edit)
  : WorkspaceEdit.t
  =
  WorkspaceEdit.create
    ~documentChanges:
      [ `TextDocumentEdit
          (TextDocumentEdit.create
             ~textDocument:
               (OptionalVersionedTextDocumentIdentifier.create
                  ~uri:(uri_of_rel_path t rel_path)
                  ())
             ~edits:
               [ `TextEdit
                   (TextEdit.create
                      ~range:
                        (range_of_bytes
                           content
                           ~first_byte:e.first_byte
                           ~last_byte:e.last_byte)
                      ~newText:e.new_text)
               ])
      ]
    ()
;;

(** Offered anywhere outside a region — including in a note that already has
    one elsewhere, and in a note with no headings, which inserts the empty
    region a growing note fills in. *)
let toc_insert_actions (t : t) ~(rel_path : string) ~(line : int) : CodeAction.t list =
  let content = buffer_content t rel_path in
  match Feature.Toc.insertion content ~line with
  | None -> []
  | Some edit ->
    [ CodeAction.create
        ~title:"Insert table of contents"
        ~kind:CodeActionKind.Refactor
        ~edit:(toc_workspace_edit t ~rel_path ~content edit)
        ()
    ]
;;

(** The quick fix for the staleness diagnostic.  A region that is already up
    to date offers nothing: there is no edit to make. *)
let toc_update_actions
      (t : t)
      ~(rel_path : string)
      ~(start_line : int)
      ~(start_character : int)
      ~(end_line : int)
      ~(end_character : int)
  : CodeAction.t list
  =
  let content = buffer_content t rel_path in
  match
    Feature.Toc.update
      content
      ~first_byte:(byte_of_position content ~line:start_line ~character:start_character)
      ~last_byte:(byte_of_position content ~line:end_line ~character:end_character)
  with
  | None -> []
  | Some edit ->
    [ CodeAction.create
        ~title:"Update table of contents"
        ~kind:CodeActionKind.QuickFix
        ~isPreferred:true
        ~edit:(toc_workspace_edit t ~rel_path ~content edit)
        ()
    ]
;;

let code_action
      (t : t)
      ?(only : CodeActionKind.t list option)
      ~(rel_path : string)
      ~(start_line : int)
      ~(start_character : int)
      ~(end_line : int)
      ~(end_character : int)
      ()
  : CodeAction.t list
  =
  (* The daily-note actions below are the one family that needs no vault, only
     a clock — so unlike its neighbours this handler has to refuse the
     rootless case itself, or a disabled server would still fill the menu. *)
  if Option.is_none t.vault
  then []
  else (
    let requested (kind : CodeActionKind.t) =
      match only with
      | None -> true
      | Some kinds -> List.mem kinds kind ~equal:Poly.equal
    in
    let daily =
      if requested CodeActionKind.Refactor
      then (
        (* On a command-block line the panel's own action is the answer, and the
         whole daily-note menu would bury it.  See
         {!page-"feature-command-block".surfaces}. *)
        match command_block_actions t ~rel_path ~line:start_line with
        | [] ->
          daily_note_actions t ~rel_path
          @ daily_note_link_actions
              t
              ~rel_path
              ~line:start_line
              ~character:start_character
          @ insert_command_block_actions t ~rel_path ~line:start_line
          @ toc_insert_actions t ~rel_path ~line:start_line
        | actions -> actions)
      else []
    in
    let toc_fixes =
      if requested CodeActionKind.QuickFix
      then
        toc_update_actions
          t
          ~rel_path
          ~start_line
          ~start_character
          ~end_line
          ~end_character
      else []
    in
    let quick_fixes =
      match t.vault with
      | _ when not (requested CodeActionKind.QuickFix) -> []
      | None -> []
      | Some v ->
        let content = disk_content t rel_path in
        (match
           Feature.Create_unresolved_note.action_at_range
             ~index:v.index
             ~rel_path
             ~content
             ~first_byte:
               (byte_of_position content ~line:start_line ~character:start_character)
             ~last_byte:(byte_of_position content ~line:end_line ~character:end_character)
         with
         | None -> []
         | Some action ->
           let target_uri = uri_of_rel_path t action.rel_path in
           let create =
             `CreateFile
               (CreateFile.create
                  ~uri:target_uri
                  ~options:
                    (CreateFileOptions.create ~ignoreIfExists:false ~overwrite:false ())
                  ())
           in
           let zero = Position.create ~line:0 ~character:0 in
           let initialize =
             `TextDocumentEdit
               (TextDocumentEdit.create
                  ~textDocument:
                    (OptionalVersionedTextDocumentIdentifier.create ~uri:target_uri ())
                  ~edits:
                    [ `TextEdit
                        (TextEdit.create
                           ~range:(Range.create ~start:zero ~end_:zero)
                           ~newText:("# " ^ action.title ^ "\n"))
                    ])
           in
           [ CodeAction.create
               ~title:(sprintf "Create note \"%s\"" action.rel_path)
               ~kind:CodeActionKind.QuickFix
               ~isPreferred:true
               ~edit:(WorkspaceEdit.create ~documentChanges:[ create; initialize ] ())
               ()
           ])
    in
    quick_fixes @ toc_fixes @ daily)
;;

let completion (t : t) ~(rel_path : string) ~(line : int) ~(character : int)
  : CompletionList.t option
  =
  match t.vault with
  | None -> None
  | Some v ->
    (* Inside a command block the note-name and fragment completions make no
     sense: the content there is a command name.  See
     {!page-"feature-command-block".surfaces}. *)
    (match command_block_completions t ~rel_path ~line with
     | Some items -> Some (CompletionList.create ~isIncomplete:false ~items ())
     | None ->
       let content = buffer_content t rel_path in
       let { Feature.Completion.items; replace_from; incomplete } =
         Feature.Completion.complete ~index:v.index ~rel_path ~content ~line ~character ()
       in
       (* One range for the whole response: every item replaces the prefix the
          user has typed.  Left to [insertText], a client picks the replaced
          span by its own word rules, and VS Code's exclude [/] — which is how
          accepting [notes/deep.md] after typing [notes/] yields
          [notes/notes/deep.md].  See
          {!page-"feature-completion-markdown-links".replace_range}. *)
       let range =
         let start_line, start_character =
           Lsp_util.position_of_byte_offset content replace_from
         in
         Range.create
           ~start:(Position.create ~line:start_line ~character:start_character)
           ~end_:(Position.create ~line ~character)
       in
       List.map items ~f:(fun (i : Feature.Completion.item) ->
         let kind =
           match i.kind with
           | Feature.Completion.File -> CompletionItemKind.File
           | Feature.Completion.Reference -> CompletionItemKind.Reference
         in
         let new_text = Option.value i.insert_text ~default:i.label in
         CompletionItem.create
           ~label:i.label
           ?detail:i.detail
           ?filterText:i.filter_text
           ~textEdit:(`TextEdit (TextEdit.create ~range ~newText:new_text))
           ~kind
           ())
       |> fun items -> Some (CompletionList.create ~isIncomplete:incomplete ~items ()))
;;

let inlay_hint (t : t) ~(rel_path : string) ~(start_line : int) ~(end_line : int)
  : InlayHint.t list option
  =
  match t.vault with
  | None -> None
  | Some v ->
    Feature.Inlay_hints.inlay_hints
      ~config:t.config
      ~index:v.index
      ~rel_path
      ~content:(disk_content t rel_path)
      ~range_start_line:start_line
      ~range_end_line:(end_line + 1)
      ()
    |> List.map ~f:(fun (h : Feature.Inlay_hints.hint) ->
      InlayHint.create
        ~position:(Position.create ~line:h.line ~character:h.character)
        ~label:(`String h.label)
        ~kind:InlayHintKind.Parameter
        ~paddingLeft:true
        ())
    |> Option.return
;;
