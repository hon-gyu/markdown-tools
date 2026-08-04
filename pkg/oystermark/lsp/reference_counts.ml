(** How many links land on a note and on each of its headings, and where that
    number belongs.

    Rendered as a lens above the line: see
    {!page-"feature-codelens-reference-counts"}.  Counting over the vault is
    {!Find_references}'s; what is here is which lines are worth counting for,
    and what the number is called once counted. *)

open Core

(** {1:implementation Implementation} *)

(** What a count is about: the note as a whole, or one heading in it. *)
type target =
  | File
  | Heading of { slug : string }
[@@deriving sexp, equal, compare]

(** What points at one line, and where the number goes.  [end_character] is
    the byte length of the line, where an inlay hint sits; a lens uses the line
    alone.

    The references are carried, not just counted: a lens hands them to the
    client so that clicking it can show them, and re-scanning the vault to
    answer a click the count already scanned for would be a second answer that
    could disagree with the first.  See
    {!page-"feature-codelens-reference-counts".click}. *)
type entry =
  { line : int
  ; end_character : int
  ; refs : Find_references.reference list
  ; target : target
  }
[@@deriving sexp, equal, compare]

let count (e : entry) : int = List.length e.refs

(** The headings of [content] within the line range [\[range_start_line,
    range_end_line)], as [(line, end_character, slug)] triples.

    Both which lines are headings and what each one's slug is come from
    {!Anchors}, i.e. from the parser: a [#] inside a fenced code block gets no
    lens, and a heading with an authored [ \{#id\} ] is counted under the id
    references actually name.  See {!page-"feature-index"}. *)
let headings_in_range
      ~(content : string)
      ~(range_start_line : int)
      ~(range_end_line : int)
  : (int * int * string) list
  =
  let lines = Array.of_list (String.split_lines content) in
  Anchors.of_content content
  |> List.filter_map ~f:(fun (a : Anchors.t) ->
    match a.kind with
    | Anchors.Block | Attr -> None
    | Heading _ ->
      if a.first_line < range_start_line || a.first_line >= range_end_line
      then None
      else (
        let end_char =
          if a.first_line < Array.length lines
          then String.length lines.(a.first_line)
          else 0
        in
        Some (a.first_line, end_char, a.id)))
;;

(** Every count worth showing for [rel_path], in line order: the whole-note
    count at line 0, then one per heading that something points at.

    A count of zero produces no entry.  Both renderings would rather say
    nothing than annotate every heading in the vault with a nought — and the
    zero case is the common one.  [docs] is the pre-resolved vault. *)
let entries
      ~(docs : (string * Cmarkit.Doc.t) list)
      ~(rel_path : string)
      ~(content : string)
      ~(range_start_line : int)
      ~(range_end_line : int)
  : entry list
  =
  let file =
    if range_start_line <= 0 && range_end_line > 0
    then (
      match Find_references.scan_vault ~docs (Path_only { path = rel_path }) with
      | [] -> []
      | refs -> [ { line = 0; end_character = 0; refs; target = File } ])
    else []
  in
  let headings =
    headings_in_range ~content ~range_start_line ~range_end_line
    |> List.filter_map ~f:(fun (line, end_character, slug) ->
      match Find_references.scan_vault ~docs (Path_heading { path = rel_path; slug }) with
      | [] -> None
      | refs -> Some { line; end_character; refs; target = Heading { slug } })
  in
  file @ headings
;;

(** {2 Wording} *)

(** The lens title: what every other language server writing this feature
    says, near enough — [3 references] on a heading, and [12 backlinks] for the
    note, which is the word a note-taker uses for the same thing.
    See {!page-"feature-codelens-reference-counts".wording}. *)
let lens_title (e : entry) : string =
  let n = count e in
  match e.target with
  | File -> if n = 1 then "1 backlink" else sprintf "%d backlinks" n
  | Heading _ -> if n = 1 then "1 reference" else sprintf "%d references" n
;;

(** {1:test Test} *)

let%test_module "reference_counts" =
  (module struct
    let files =
      [ ( "note-a.md"
        , "# Alpha\n\n## Section One\n\nBody text ^block1\n\n## Untouched\n\nEnd.\n" )
      ; "note-b.md", "# Beta\n\nLink to [[note-a]] here.\n"
      ; ( "note-c.md"
        , "# Gamma\n\nSee [[note-a#Section One]].\n\nAlso [[note-a#^block1]].\n" )
      ]
    ;;

    let _index, docs = Find_references.For_test.make_vault files

    let show ?(range_start_line = 0) ?(range_end_line = 100) rel_path =
      let content = List.Assoc.find_exn files ~equal:String.equal rel_path in
      entries ~docs ~rel_path ~content ~range_start_line ~range_end_line
      |> List.iter ~f:(fun e -> printf "line %d: %s\n" e.line (lens_title e))
    ;;

    (* Both wordings of the same counts, side by side.  [## Untouched] is
       absent: nothing points at it, so neither rendering says anything. *)
    let%expect_test "counts and their two wordings" =
      show "note-a.md";
      [%expect
        {|
        line 0: 3 backlinks
        line 2: 1 reference
        |}]
    ;;

    let%expect_test "a note nothing points at" =
      show "note-b.md";
      [%expect {| |}]
    ;;

    (* The range is the client's visible window: line 0 outside it takes the
       whole-note count with it. *)
    let%expect_test "partial range" =
      show ~range_start_line:2 ~range_end_line:5 "note-a.md";
      [%expect {| line 2: 1 reference |}]
    ;;

    let%expect_test "singular and plural" =
      let show_both count =
        let refs =
          List.init count ~f:(fun i ->
            { Find_references.rel_path = "x.md"; first_byte = i; last_byte = i })
        in
        let e = { line = 0; end_character = 0; refs; target = File } in
        let h = { e with target = Heading { slug = "s" } } in
        printf "%d: %s / %s\n" count (lens_title e) (lens_title h)
      in
      show_both 1;
      show_both 2;
      [%expect
        {|
        1: 1 backlink / 1 reference
        2: 2 backlinks / 2 references
        |}]
    ;;
  end)
;;
