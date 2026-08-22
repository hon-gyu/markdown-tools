(** Read-only queries over a resolved vault snapshot. *)

open Core
module Index = Index

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

let%expect_test "queries distinguish occurrences and edges" =
  let docs =
    List.map
      [ "a.md", "[[b]] [[b]] [[missing]]"; "b.md", "[[a]]"; "c.md", "plain" ]
      ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content)
  in
  let index =
    List.fold docs ~init:Index.empty ~f:(fun index (rel_path, doc) ->
      let file_stat : Index.file_stat = { rel_path; birthtime = None; mtime = None } in
      Index.set_note index (Index.Note.of_doc_exn file_stat doc))
  in
  let docs = Resolve.resolve_docs docs index in
  printf
    "unresolved=%d\n"
    (List.length (unresolved ~index ~docs));
  [%expect {| unresolved=1 |}]
;;
