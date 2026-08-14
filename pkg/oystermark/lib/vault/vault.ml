module Index = Index
module Link_ref = Link_ref
module Resolve = Resolve
module Embed = Embed
module Query = Query
module Rename = Rename
open Core

type t =
  { vault_root : string
  ; index : Index.t (** index of all files in the vault *)
  ; vault_meta : Cmarkit.Meta.t (** metadata slot *)
  }

let docs (vault : t) : (string * Cmarkit.Doc.t) list =
  vault.index.notes |> List.map ~f:(fun note -> note.rel_path, note.doc)
;;

(** Replace the note documents while keeping the index as the vault's single
    source of truth. Existing filesystem dates are retained by path. *)
let with_docs (vault : t) (docs : (string * Cmarkit.Doc.t) list) : t =
  let notes =
    List.map docs ~f:(fun (rel_path, doc) ->
      let birthtime, mtime =
        List.find vault.index.notes ~f:(fun note -> String.equal note.rel_path rel_path)
        |> Option.value_map ~default:(None, None) ~f:(fun note ->
          note.birthtime, note.mtime)
      in
      ({ rel_path
       ; birthtime
       ; mtime
       ; doc
       ; headings = Index.extract_headings doc
       ; blocks = Index.extract_block_ids doc
       ; attrs = Index.extract_attr_ids doc
       }
       : Index.note_entry))
  in
  { vault with index = { vault.index with notes } }
;;

(** Build an index from a list of [(rel_path, doc)] pairs
    plus a list of non-md relative paths. *)
let build_index
      ~(md_docs : (string * Cmarkit.Doc.t) list)
      ~(other_files : string list)
      ~(dirs : string list)
  : Index.t
  =
  let md_entries =
    List.map md_docs ~f:(fun (rel_path, doc) ->
      let headings = Index.extract_headings doc in
      let blocks = Index.extract_block_ids doc in
      let attrs = Index.extract_attr_ids doc in
      ({ rel_path
       ; birthtime = None
       ; mtime = None
       ; doc
       ; headings
       ; blocks
       ; attrs
       }
       : Index.note_entry))
  in
  let non_md =
    List.map other_files ~f:(fun rel_path ->
      ({ rel_path; birthtime = None; mtime = None } : Index.non_md_entry))
  in
  { notes = md_entries; files = non_md; dirs }
;;

(** Simple build: read all files not rejected by [exclude], then build the
    index. [exclude] receives vault-relative file paths. *)
let of_root_path
      ?(skip_expand : bool = false)
      ?(locs : bool = true)
      ?(exclude : string -> bool = fun _ -> false)
      (vault_root : string)
  : t
  =
  (* Scan files *)
  let all_files =
    List.filter (Index.list_entries_recursive vault_root ()) ~f:(fun p ->
      not (String.is_suffix p ~suffix:"/") && not (exclude p))
  in
  let (docs : (string * Cmarkit.Doc.t) list) =
    List.filter_map all_files ~f:(fun rel_path ->
      if String.is_suffix rel_path ~suffix:".md"
      then (
        let full_path = Filename.concat vault_root rel_path in
        let content = In_channel.read_all full_path in
        let parsed = Parse.of_string ~locs content in
        Some (rel_path, parsed))
      else None)
  in
  let other_files =
    List.filter all_files ~f:(fun p -> not (String.is_suffix p ~suffix:".md"))
  in
  (* Build index *)
  let index = build_index ~md_docs:docs ~other_files ~dirs:[] in
  (* Resolve *)
  let resolved_docs : (string * Cmarkit.Doc.t) list = Resolve.resolve_docs docs index in
  let index = build_index ~md_docs:resolved_docs ~other_files ~dirs:[] in
  if skip_expand
  then { vault_root; index; vault_meta = Cmarkit.Meta.none }
  else (
    let expanded_docs : (string * Cmarkit.Doc.t) list = Embed.expand_docs resolved_docs in
    let index = build_index ~md_docs:expanded_docs ~other_files ~dirs:[] in
    { vault_root; index; vault_meta = Cmarkit.Meta.none })
;;

(** [of_inmem_files] creates a vault from a list of in-memory files.
  @param files A list of (path, content) pairs representing the files to include in the vault.
*)
let of_inmem_files ?(vault_root = "/tmp_vault") (files : (string * string) list) : t =
  let docs =
    List.map files ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content)
  in
  let index = build_index ~md_docs:docs ~other_files:[] ~dirs:[] in
  let resolved_docs = Resolve.resolve_docs docs index in
  let index = build_index ~md_docs:resolved_docs ~other_files:[] ~dirs:[] in
  { vault_root; index; vault_meta = Cmarkit.Meta.none }
;;
