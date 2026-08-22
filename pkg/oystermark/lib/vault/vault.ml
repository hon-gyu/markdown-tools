module Index = Index
module Fs_utils = Fs_utils
module Link_ref = Link_ref
module Resolve = Resolve
module Embed = Embed
module Rename = Rename
open Core

type t =
  { vault_root : string
  ; index : Index.t
  ; vault_meta : Cmarkit.Meta.t
  }

let docs vault =
  Index.notes vault.index |> List.map ~f:(fun note -> Index.Note.path note, Index.Note.doc note)

let file_stat ?(birthtime = None) ?(mtime = None) rel_path : Index.file_stat =
  { rel_path; birthtime; mtime }

let build_index ~md_docs ~other_files =
  let index =
    List.fold md_docs ~init:Index.empty ~f:(fun index (path, doc) ->
      Index.set_note index (Index.Note.of_doc_exn (file_stat path) doc))
  in
  List.fold other_files ~init:index ~f:(fun index path ->
    Index.set_asset index (Index.Asset.create (file_stat path)))

(** Replace note documents while retaining file dates and non-note assets. *)
let with_docs vault docs =
  let index =
    List.fold docs ~init:Index.empty ~f:(fun index (path, doc) ->
      let stat =
        Index.find_note vault.index path
        |> Option.value_map ~default:(file_stat path) ~f:Index.Note.file_stat
      in
      Index.set_note index (Index.Note.of_doc_exn stat doc))
  in
  let index = List.fold (Index.assets vault.index) ~init:index ~f:Index.set_asset in
  { vault with index }

let of_root_path ?(skip_expand = false) ?(locs = true) ?(exclude = fun _ -> false) vault_root =
  (* CR: should we remove ~locs altogether? *)
  if not locs then invalid_arg "Vault.of_root_path: Vault.Index requires source locations";
  let entries = List.filter (Fs_utils.walk ~root:vault_root ()) ~f:(fun p -> not (exclude p)) in
  let files = List.filter entries ~f:(fun p -> not (String.is_suffix p ~suffix:"/")) in
  let parsed_docs =
    List.filter_map files ~f:(fun path ->
      if String.is_suffix path ~suffix:".md"
      then Some (path, Parse.of_string ~locs:true (In_channel.read_all (Filename.concat vault_root path)))
      else None)
  in
  let other_files = List.filter files ~f:(fun p -> not (String.is_suffix p ~suffix:".md")) in
  let index = build_index ~md_docs:parsed_docs ~other_files in
  let resolved_docs = Resolve.resolve_docs parsed_docs index in
  let index = build_index ~md_docs:resolved_docs ~other_files in
  let vault = { vault_root; index; vault_meta = Cmarkit.Meta.none } in
  if skip_expand then vault else with_docs vault (Embed.expand_docs resolved_docs)

let of_inmem_files ?(vault_root = "/tmp_vault") files =
  let parsed_docs = List.map files ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content) in
  let index = build_index ~md_docs:parsed_docs ~other_files:[] in
  let resolved_docs = Resolve.resolve_docs parsed_docs index in
  { vault_root
  ; index = build_index ~md_docs:resolved_docs ~other_files:[]
  ; vault_meta = Cmarkit.Meta.none
  }
