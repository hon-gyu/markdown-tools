(** Read-only queries over a resolved vault snapshot. *)

open Core

type kind =
  | Link
  | Embed
  | Image
[@@deriving sexp, equal, compare]

type link =
  { source : string
  ; destination : Resolve.target
  ; reference : Link_ref.t
  ; kind : kind
  ; first_byte : int
  ; last_byte : int
  }
[@@deriving sexp]

let is_image_target : string -> bool =
  fun target ->
  let target = String.lowercase target in
  List.exists [ ".png"; ".jpg"; ".jpeg"; ".gif"; ".svg"; ".webp" ] ~f:(fun ext ->
    String.is_suffix target ~suffix:ext)
;;

let collect ~(index : Index.t) ~(source : string) (doc : Cmarkit.Doc.t) : link list =
  let add acc reference kind meta =
    let loc = Cmarkit.Meta.textloc meta in
    if Cmarkit.Textloc.is_none loc
    then acc
    else
      { source
      ; destination = Resolve.resolve reference source index
      ; reference
      ; kind
      ; first_byte = Cmarkit.Textloc.first_byte loc
      ; last_byte = Cmarkit.Textloc.last_byte loc
      }
      :: acc
  in
  let folder =
    Cmarkit.Folder.make
      ~inline_ext_default:(fun _f acc -> function
         | Cmarkit.Inline.Ext_wikilink (wl, meta) ->
           let reference = Link_ref.of_wikilink wl in
           let kind =
             if Cmarkit.Inline.Wikilink.embed wl
             then (
               match reference.target with
               | Some target when is_image_target target -> Image
               | _ -> Embed)
             else Link
           in
           add acc reference kind meta
         | _ -> acc)
      ~block_ext_default:(fun _f acc _ -> acc)
      ~inline:(fun _f acc inline ->
        match inline with
        | Cmarkit.Inline.Link (link, meta) | Cmarkit.Inline.Image (link, meta) ->
          (match Link_ref.of_cmark_reference (Cmarkit.Inline.Link.reference link) with
           | None -> Cmarkit.Folder.default
           | Some reference ->
             let kind =
               match inline with
               | Cmarkit.Inline.Image _ ->
                 (match reference.target with
                  | Some target when String.is_suffix target ~suffix:".md" -> Embed
                  | _ -> Image)
               | _ -> Link
             in
             Cmarkit.Folder.ret (add acc reference kind meta))
        | _ -> Cmarkit.Folder.default)
      ()
  in
  List.rev (Cmarkit.Folder.fold_doc folder [] doc)
;;

type stats =
  { notes : int
  ; resolved_link_occurrences : int
  ; unique_edges : int
  ; unresolved_links : int
  }
[@@deriving sexp]

let destination_path ~source = function
  | Resolve.Note { path }
  | File { path }
  | Heading { path; _ }
  | Block { path; _ }
  | Attr { path; _ } -> Some path
  | Curr_file | Curr_heading _ | Curr_block _ | Curr_attr _ -> Some source
  | Unresolved -> None
;;

let all ~(index : Index.t) ~(docs : (string * Cmarkit.Doc.t) list) : link list =
  List.concat_map docs ~f:(fun (source, doc) -> collect ~index ~source doc)
;;

let unresolved ~index ~docs =
  List.filter (all ~index ~docs) ~f:(fun link ->
    match link.destination with
    | Resolve.Unresolved -> true
    | _ -> false)
;;

let outgoing ~index ~docs ~note =
  List.filter (all ~index ~docs) ~f:(fun l -> String.equal l.source note)
;;

let incoming ~index ~docs ~note =
  List.filter (all ~index ~docs) ~f:(fun l ->
    destination_path ~source:l.source l.destination
    |> Option.value_map ~default:false ~f:(String.equal note))
;;

let stats ~index ~docs =
  let links = all ~index ~docs in
  let resolved =
    List.filter_map links ~f:(fun l ->
      destination_path ~source:l.source l.destination
      |> Option.map ~f:(fun destination -> l.source, destination))
  in
  { notes = List.length docs
  ; resolved_link_occurrences = List.length resolved
  ; unique_edges =
      List.dedup_and_sort resolved ~compare:[%compare: string * string] |> List.length
  ; unresolved_links = List.length links - List.length resolved
  }
;;

let%expect_test "queries distinguish occurrences and edges" =
  let docs =
    List.map
      [ "a.md", "[[b]] [[b]] [[missing]]"; "b.md", "[[a]]"; "c.md", "plain" ]
      ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content)
  in
  let index =
    let files =
      List.map docs ~f:(fun (rel_path, doc) ->
        ({ Index.rel_path
         ; headings = Index.extract_headings doc
         ; blocks = Index.extract_block_ids doc
         ; attrs = Index.extract_attr_ids doc
         }
         : Index.file_entry))
    in
    ({ files; dirs = [] } : Index.t)
  in
  let docs = Resolve.resolve_docs docs index in
  print_s [%sexp (stats ~index ~docs : stats)];
  printf
    "incoming-b=%d outgoing-a=%d unresolved=%d\n"
    (List.length (incoming ~index ~docs ~note:"b.md"))
    (List.length (outgoing ~index ~docs ~note:"a.md"))
    (List.length (unresolved ~index ~docs));
  [%expect
    {|
    ((notes 3) (resolved_link_occurrences 3) (unique_edges 2)
     (unresolved_links 1))
    incoming-b=2 outgoing-a=3 unresolved=1
    |}]
;;
