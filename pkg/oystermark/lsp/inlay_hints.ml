(** Inlay hints: reference counts next to headings and at top of file, plus
    direction arrows on intra-note links.

    Spec: {!page-"feature-inlay-hints"} for the counts,
    {!page-"feature-inlay-hints-link-direction"} for the arrows — two
    independently switchable features sharing one response, and nothing else.
    Uses {!Find_references} for counting over pre-resolved vault docs and
    {!Link_direction} for the arrows. *)

open Core

(** {1:implementation Implementation} *)

(** A single inlay hint: position and label text. *)
type hint =
  { line : int
  ; character : int
  ; label : string
  }
[@@deriving sexp, equal, compare]

(** Format a reference count as a label string.
    Returns [None] for count 0 (no hint emitted). *)
let format_count (n : int) : string option =
  if n = 0 then None else if n = 1 then Some "1 ref" else Some (sprintf "%d refs" n)
;;

(** Find all headings in [content] within the line range [\[range_start_line,
    range_end_line)].  Returns [(line, end_character, slug)] triples. *)
let headings_in_range
      ~(content : string)
      ~(range_start_line : int)
      ~(range_end_line : int)
  : (int * int * string) list
  =
  let lines = String.split_lines content in
  List.filter_mapi lines ~f:(fun i line_str ->
    if i < range_start_line || i >= range_end_line
    then None
    else (
      match Hover.heading_level_of_line line_str with
      | None -> None
      | Some _ ->
        let text =
          String.lstrip line_str ~drop:(fun c -> Char.equal c '#')
          |> String.lstrip ~drop:(fun c -> Char.equal c ' ')
        in
        let slug = Oystermark.Parse.Common.heading_id_of_text text in
        let end_char = String.length line_str in
        Some (i, end_char, slug)))
;;

(** Compute inlay hints for [rel_path] within the given line range.

    [docs] is the list of pre-resolved vault documents (with
    {!Oystermark.Vault.Resolve.resolved_key} metadata attached); [index] is
    the vault index the link arrows resolve against, and omitting it leaves
    them out — a caller that has no index has no directions to report.

    See {!page-"feature-inlay-hints"} and
    {!page-"feature-inlay-hints-link-direction"}. *)
let inlay_hints
      ?(config : Lsp_config.t = Lsp_config.default)
      ?(index : Oystermark.Vault.Index.t option)
      ~(docs : (string * Cmarkit.Doc.t) list)
      ~(rel_path : string)
      ~(content : string)
      ~(range_start_line : int)
      ~(range_end_line : int)
      ()
  : hint list
  =
  Trace_core.with_span ~__FILE__ ~__LINE__ "inlay_hints"
  @@ fun _sp ->
  Trace_core.add_data_to_span
    _sp
    [ "rel_path", `String rel_path
    ; "range_start", `Int range_start_line
    ; "range_end", `Int range_end_line
    ];
  let hints = ref [] in
  (* File-level hint at (0, 0) if range includes line 0. *)
  if range_start_line <= 0 && range_end_line > 0
  then (
    let count = Find_references.count_file_refs ~docs ~path:rel_path in
    match format_count count with
    | None -> ()
    | Some label -> hints := { line = 0; character = 0; label } :: !hints);
  (* Per-heading hints. *)
  let headings = headings_in_range ~content ~range_start_line ~range_end_line in
  List.iter headings ~f:(fun (line, end_char, slug) ->
    let count = Find_references.count_heading_refs ~docs ~path:rel_path ~slug in
    match format_count count with
    | None -> ()
    | Some label -> hints := { line; character = end_char; label } :: !hints);
  (* Link-direction arrows.  Computed from [content] rather than from [docs]:
     they are about where things are in {e this} note, which is what [content]
     is, while [docs] is what the vault says about every note.
     See {!page-"feature-inlay-hints-link-direction"}. *)
  let direction_hints =
    match config.inlay_link_direction, index with
    | false, _ | _, None -> []
    | true, Some index ->
      Link_direction.hints ~index ~rel_path ~content ~range_start_line ~range_end_line ()
      |> List.map ~f:(fun (h : Link_direction.hint) ->
        { line = h.line; character = h.character; label = h.label })
  in
  (* One response, so one order: by position, whichever feature produced it. *)
  let result =
    List.rev !hints @ direction_hints
    |> List.stable_sort ~compare:(fun a b ->
      [%compare: int * int] (a.line, a.character) (b.line, b.character))
  in
  Trace_core.add_data_to_span _sp [ "num_hints", `Int (List.length result) ];
  result
;;

(** {1:test Test} *)

let%test_module "format_count" =
  (module struct
    let%expect_test "zero" =
      print_s [%sexp (format_count 0 : string option)];
      [%expect {| () |}]
    ;;

    let%expect_test "one" =
      print_s [%sexp (format_count 1 : string option)];
      [%expect {| ("1 ref") |}]
    ;;

    let%expect_test "many" =
      print_s [%sexp (format_count 5 : string option)];
      [%expect {| ("5 refs") |}]
    ;;
  end)
;;

let%test_module "inlay_hints" =
  (module struct
    let files =
      [ "note-a.md", "# Alpha\n\n## Section One\n\nBody text ^block1\n"
      ; "note-b.md", "# Beta\n\nLink to [[note-a]] here.\n"
      ; ( "note-c.md"
        , "# Gamma\n\nSee [[note-a#Section One]].\n\nAlso [[note-a#^block1]].\n" )
      ]
    ;;

    let _index, docs = Find_references.For_test.make_vault files

    let show ~rel_path ~content ~range_start_line ~range_end_line =
      let hints =
        inlay_hints ~docs ~rel_path ~content ~range_start_line ~range_end_line ()
      in
      List.iter hints ~f:(fun h -> printf "(%d,%d) %s\n" h.line h.character h.label)
    ;;

    let%expect_test "file with incoming refs" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-a.md" in
      show ~rel_path:"note-a.md" ~content ~range_start_line:0 ~range_end_line:10;
      [%expect
        {|
        (0,0) 3 refs
        (2,14) 1 ref
        |}]
    ;;

    let%expect_test "file with no refs" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-b.md" in
      show ~rel_path:"note-b.md" ~content ~range_start_line:0 ~range_end_line:10;
      [%expect {| |}]
    ;;

    let%expect_test "partial range excludes file-level hint" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-a.md" in
      show ~rel_path:"note-a.md" ~content ~range_start_line:2 ~range_end_line:5;
      [%expect {| (2,14) 1 ref |}]
    ;;
  end)
;;
