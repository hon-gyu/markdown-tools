(** Link resolution algorithm: resolves link references against a vault index. *)

open Core
module Index = Index

type textloc = Cmarkit.Textloc.t

let sexp_of_textloc = Parse.Textloc_conv.sexp_of_t
let textloc_of_sexp = Parse.Textloc_conv.t_of_sexp

type target =
  | Note of { path : string }
  | File of { path : string }
  | Heading of
      { path : string
      ; heading : string
      ; level : int
      ; slug : string
      ; loc : textloc option [@sexp.option]
      }
  | Block of
      { path : string
      ; block_id : string
      ; loc : textloc option [@sexp.option]
      }
  | Attr of
      { path : string
      ; id : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_file
  | Curr_heading of
      { heading : string
      ; level : int
      ; slug : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_block of
      { block_id : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_attr of
      { id : string
      ; loc : textloc option [@sexp.option]
      }
  | Unresolved
[@@deriving sexp]

let resolved_key : target Cmarkit.Meta.key = Cmarkit.Meta.key ()

(** Make a wikilink from an already resolved target. *)
let make_wikilink
      ~(target : string option)
      ~(fragment : Cmarkit.Inline.Wikilink.fragment option)
      ~(display : string option)
      ~(embed : bool)
      ~(resolved_target : target)
  : Cmarkit.Inline.t
  =
  let wl = Parse.Common.wikilink_of_fields ~target ~fragment ~display ~embed in
  let meta = Cmarkit.Meta.add resolved_key resolved_target Cmarkit.Meta.none in
  Cmarkit.Inline.Ext_wikilink (wl, meta)
;;

(** Check if needle components form a (ordered) subsequence of haystack components. *)
let is_path_subsequence ~(haystack : string list) ~(needle : string list) : bool =
  let hay_len = List.length haystack in
  let hay_arr = Array.of_list haystack in
  let rec loop hay_idx needle_rest =
    match needle_rest with
    | [] -> true
    | n :: ns ->
      let rec find i =
        if i >= hay_len
        then false
        else if String.equal hay_arr.(i) n
        then loop (i + 1) ns
        else find (i + 1)
      in
      find hay_idx
  in
  loop 0 needle
;;

let%expect_test "is_path_subsequence" =
  let haystack = [ "foo"; "bar"; "baz"; "qux" ] in
  let n1 = [ "bar"; "baz" ] in
  let n2 = [ "baz"; "bar" ] in
  printf "%b\n" (is_path_subsequence ~haystack ~needle:n1);
  printf "%b\n" (is_path_subsequence ~haystack ~needle:n2);
  [%expect
    {|
    true
    false
    |}]
;;

(** How good a subsequence match is, smaller being better: its depth, then
    whether it sits in the linking note's own folder.

    A bare [ [[note]] ] names no directory, so every [note.md] in the vault
    matches it.  Ranking them is not a preference, it is the difference between
    an answer and whichever answer the filesystem listed first.  See
    {b Ranking Multiple Matches} in [specification/obsidian/link-resolution.md],
    where the order is measured against Obsidian itself: depth wins first, and
    a sibling of the linking note only breaks a tie between equal depths. *)
let match_rank ~(source_dir : string) (rel_path : string) : int * int =
  let depth = List.length (String.split rel_path ~on:'/') in
  let in_source_dir =
    if String.equal (Filename.dirname rel_path) source_dir then 0 else 1
  in
  depth, in_source_dir
;;

(** Resolve a target string to a file entry, as written in [source].

    Exact match on the whole vault-relative path first, then the best
    subsequence match.  Candidates that tie on every rank keep index order —
    arbitrary, as it is in Obsidian, but at least it is the same arbitrary
    answer every time the index is built the same way. *)
let resolve_file ~(source : string) (files : string list) (target_str : string)
  : string option
  =
  let normalize_target s = if String.mem s '.' then s else s ^ ".md" in
  let normalized = normalize_target target_str in
  (* Exact match *)
  match List.find files ~f:(String.equal normalized) with
  | Some _ as result -> result
  | None ->
    (* Subsequence match: split needle into path components *)
    let needle = String.split normalized ~on:'/' in
    let source_dir = Filename.dirname source in
    List.filter files ~f:(fun f ->
      let haystack = String.split f ~on:'/' in
      is_path_subsequence ~haystack ~needle)
    |> List.fold ~init:None ~f:(fun best f ->
      match best with
      | Some b
        when [%compare: int * int] (match_rank ~source_dir b) (match_rank ~source_dir f)
             <= 0 -> best
      | _ -> Some f)
;;

(** Does query component [q] name heading [h]?

    Two spellings reach the same heading: the heading {e text} as written
    ([ [[note#Section One]] ]) and its {e identifier} — the derived slug, or the
    explicit [{#id}] when the heading carries one ([ [[note#section-one]] ]).
    Completion inserts the identifier form, so a link it wrote must resolve.
    See {!page-"feature-go-to-definition".heading_lookup}. *)
type heading_entry =
  { text : string
  ; level : int
  ; slug : string
  ; loc : textloc option
  }

let heading_matches (h : heading_entry) (q : string) : bool =
  String.equal h.text q || String.equal h.slug (Parse.Common.heading_id_of_text q)
;;

(** Resolve a heading query (list of heading texts or ids) against document
    headings.  Finds a subsequence where levels strictly increase
    (backtracking). *)
let resolve_headings (headings : heading_entry list) (query : string list)
  : heading_entry option
  =
  let headings_arr = Array.of_list headings in
  let n_headings = Array.length headings_arr in
  (* Backtracking search: try to match query[qi..] starting from headings[hi..]
     with prev_level constraint. Returns the last matched heading on success. *)
  let rec search hi qi prev_level =
    if qi >= List.length query
    then None (* all matched — but we return from the caller *)
    else if hi >= n_headings
    then None
    else (
      let q = List.nth_exn query qi in
      let h = headings_arr.(hi) in
      if heading_matches h q && h.level > prev_level
      then
        if
          (* This heading matches query[qi] *)
          qi = List.length query - 1
        then Some h (* last query item matched *)
        else (
          (* Try to match remaining query items *)
          match search (hi + 1) (qi + 1) h.level with
          | Some _ as result -> result
          | None ->
            (* Backtrack: skip this heading, try next *)
            search (hi + 1) qi prev_level)
      else search (hi + 1) qi prev_level)
  in
  search 0 0 0
;;

(** Resolve a fragment string against a file's explicit attribute ids
    ([{#id}]). Exact string comparison; first match in document order wins.
    See {!page-"feature-attribute-anchors".resolution}. *)
type attr_entry =
  { id : string
  ; loc : textloc option
  }

let resolve_attr (attrs : attr_entry list) (id : string) : attr_entry option =
  List.find attrs ~f:(fun (a : attr_entry) -> String.equal a.id id)
;;

(** A heading fragment ([#frag]) that matched no heading may still name an
    attribute id, but only when it is a single flat component — a multi-level
    heading query ([#a#b]) can never be an attribute id. *)
let resolve_attr_of_heading_query (attrs : attr_entry list) (hs : string list)
  : attr_entry option
  =
  match hs with
  | [ frag ] -> resolve_attr attrs frag
  | _ -> None
;;

(** Resolve a link reference against the vault index. *)
let resolve (link_ref : Link_ref.t) (curr_file : string) (index : Index.t) : target =
  let current path = Option.is_none link_ref.target && String.equal curr_file path in
  match Index.resolve index curr_file link_ref with
  | Error _ -> Unresolved
  | Ok (Index.Note path) -> if current path then Curr_file else Note { path }
  | Ok (Index.Asset path) -> File { path }
  | Ok (Index.Anchor { note_path = path; anchor }) ->
    let loc = Some anchor.loc in
    (match anchor.value with
     | Index.Heading heading ->
       if current path
       then Curr_heading { heading = heading.text; level = heading.level; slug = heading.slug; loc }
       else Heading { path; heading = heading.text; level = heading.level; slug = heading.slug; loc }
     | Index.Block { id; kind = Obsidian_caret } ->
       if current path then Curr_block { block_id = id; loc } else Block { path; block_id = id; loc }
     | Index.Block { id; kind = Djot_attr } | Index.Inline { id } ->
       if current path then Curr_attr { id; loc } else Attr { path; id; loc })
;;

(** Build a [Cmarkit.Mapper.t] that resolves links against the vault index. *)
let resolution_cmarkit_mapper ~(index : Index.t) ~(curr_file : string) : Cmarkit.Mapper.t =
  Cmarkit.Mapper.make
    ~block_ext_default:(fun _m b -> Some b)
    ~inline_ext_default:(fun _m i ->
      match i with
      | Cmarkit.Inline.Ext_wikilink (w, meta) ->
        let link_ref = Link_ref.of_wikilink w in
        let target = resolve link_ref curr_file index in
        let meta' = Cmarkit.Meta.add resolved_key target meta in
        Some (Cmarkit.Inline.Ext_wikilink (w, meta'))
      | other -> Some other)
    ~inline:(fun _m i ->
      match i with
      (* TODO(code-duplication) *)
      | Cmarkit.Inline.Link (link, meta) ->
        let ref_ = Cmarkit.Inline.Link.reference link in
        (match Link_ref.of_cmark_reference ref_ with
         | Some link_ref ->
           let target = resolve link_ref curr_file index in
           let meta' = Cmarkit.Meta.add resolved_key target meta in
           Cmarkit.Mapper.ret (Cmarkit.Inline.Link (link, meta'))
         | None -> Cmarkit.Mapper.default)
      | Cmarkit.Inline.Image (link, meta) ->
        let ref_ = Cmarkit.Inline.Link.reference link in
        (match Link_ref.of_cmark_reference ref_ with
         | Some link_ref ->
           let target = resolve link_ref curr_file index in
           let meta' = Cmarkit.Meta.add resolved_key target meta in
           Cmarkit.Mapper.ret (Cmarkit.Inline.Image (link, meta'))
         | None -> Cmarkit.Mapper.default)
      | _ -> Cmarkit.Mapper.default)
    ()
;;

(** Resolve links in a list of parsed docs against the vault index. *)
let resolve_docs (docs : (string * Cmarkit.Doc.t) list) (index : Index.t)
  : (string * Cmarkit.Doc.t) list
  =
  List.map docs ~f:(fun (rel_path, doc) ->
    let mapper = resolution_cmarkit_mapper ~index ~curr_file:rel_path in
    rel_path, Cmarkit.Mapper.map_doc mapper doc)
;;

(* The vault of [specification/obsidian/link-resolution.md]'s "Ranking Multiple
   Matches", note for note, so the expectations below can be read against the
   evidence table there — each was measured against Obsidian itself via
   [pkg/oystermark/obsidian-resolver]. [mmm/s7.md] precedes [bbb/s7.md] because
   its folder was created first, which is the order Obsidian broke that tie by
   and the only part of the ranking an author cannot predict. *)
let%expect_test "ranking multiple subsequence matches" =
  let files =
    [ "s1.md"
    ; "s2.md"
    ; "aaa/s5.md"
    ; "mmm/s7.md"
    ; "bbb/s7.md"
    ; "zzz/s6.md"
    ; "notes/probe.md"
    ; "notes/s1.md"
    ; "notes/s3.md"
    ; "notes/s5.md"
    ; "notes/s6.md"
    ; "deep/a/s1.md"
    ; "deep/a/s2.md"
    ; "deep/a/s3.md"
    ; "deep/a/s4.md"
    ; "deep/b/s4.md"
    ]
  in
  let resolve_from source target =
    printf
      "%-14s [[%s]] -> %s\n"
      source
      target
      (match resolve_file ~source files target with
       | Some f -> f
       | None -> "<unresolved>")
  in
  List.iter [ "s1"; "s2"; "s3"; "s4"; "s5"; "s6"; "s7" ] ~f:(fun t ->
    resolve_from "notes/probe.md" t);
  resolve_from "notes/probe.md" "notes/s1";
  resolve_from "notes/probe.md" "deep/a/s1";
  resolve_from "probe-root.md" "s1";
  resolve_from "probe-root.md" "s3";
  [%expect
    {|
    notes/probe.md [[s1]] -> s1.md
    notes/probe.md [[s2]] -> s2.md
    notes/probe.md [[s3]] -> notes/s3.md
    notes/probe.md [[s4]] -> deep/a/s4.md
    notes/probe.md [[s5]] -> notes/s5.md
    notes/probe.md [[s6]] -> notes/s6.md
    notes/probe.md [[s7]] -> mmm/s7.md
    notes/probe.md [[notes/s1]] -> notes/s1.md
    notes/probe.md [[deep/a/s1]] -> deep/a/s1.md
    probe-root.md  [[s1]] -> s1.md
    probe-root.md  [[s3]] -> notes/s3.md
    |}]
;;

(* A heading fragment is accepted in either spelling — the heading text, or the
   identifier (derived slug, or the explicit [{#id}] of [Custom], whose slug is
   [pinned]).  See {!page-"feature-go-to-definition".heading_lookup}. *)
let%expect_test "heading fragment: text and identifier spellings" =
  let headings : heading_entry list =
    [ { text = "Alpha 2"; level = 1; slug = "alpha-2"; loc = None }
    ; { text = "Beta Two"; level = 2; slug = "beta-two"; loc = None }
    ; { text = "Custom"; level = 1; slug = "pinned"; loc = None }
    ]
  in
  let show query =
    printf
      "%-24s -> %s\n"
      (String.concat ~sep:"#" query)
      (match resolve_headings headings query with
       | Some h -> h.slug
       | None -> "<unresolved>")
  in
  List.iter
    ~f:show
    [ [ "Alpha 2" ]
    ; [ "alpha-2" ]
    ; [ "ALPHA 2" ]
    ; [ "Custom" ]
    ; [ "pinned" ]
    ; [ "custom" ]
    ; [ "Alpha 2"; "beta-two" ]
    ; [ "alpha-2"; "Beta Two" ]
    ; [ "nope" ]
    ];
  [%expect
    {|
    Alpha 2                  -> alpha-2
    alpha-2                  -> alpha-2
    ALPHA 2                  -> alpha-2
    Custom                   -> pinned
    pinned                   -> pinned
    custom                   -> <unresolved>
    Alpha 2#beta-two         -> beta-two
    alpha-2#Beta Two         -> beta-two
    nope                     -> <unresolved>
    |}]
;;
