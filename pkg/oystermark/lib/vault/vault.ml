module Index = Index
module Fs_utils = Fs_utils
module Link_ref = Link_ref
module Embed = Embed
module Rename = Rename
open Core

type t =
  { vault_root : string
  ; index : Index.t
  ; documents : Cmarkit.Doc.t String.Map.t
  ; vault_meta : Cmarkit.Meta.t
  }

let docs : t -> (string * Cmarkit.Doc.t) list =
  fun vault -> Map.to_alist vault.documents
;;

let find_doc (vault : t) path = Map.find vault.documents path

open struct
  let file_stat ?(birthtime = None) ?(mtime = None) rel_path : Index.file_stat =
    { rel_path; birthtime; mtime }
  ;;
end

let build_index ~(md_docs : (string * Cmarkit.Doc.t) list) ~(other_files : string list)
  : Index.t
  =
  let index =
    List.fold md_docs ~init:Index.empty ~f:(fun index (path, doc) ->
      Index.set_note index (Index.Note.of_doc_exn (file_stat path) doc))
  in
  List.fold other_files ~init:index ~f:(fun index path ->
    Index.set_asset index (Index.Asset.create (file_stat path)))
;;

let set_doc (vault : t) path doc : t =
  let stat =
    Index.find_note vault.index path
    |> Option.value_map ~default:(file_stat path) ~f:Index.Note.file_stat
  in
  { vault with
    index = Index.set_note vault.index (Index.Note.of_doc_exn stat doc)
  ; documents = Map.set vault.documents ~key:path ~data:doc
  }
;;

let remove_path (vault : t) path : t =
  { vault with
    index = Index.remove_asset (Index.remove_note vault.index path) path
  ; documents = Map.remove vault.documents path
  }
;;

(** Construct a vault from transformed documents, retaining the base vault's file dates,
    non-note assets, metadata, and root. *)
let of_docs ~(base : t) (docs : (string * Cmarkit.Doc.t) list) : t =
  let index =
    List.fold docs ~init:Index.empty ~f:(fun index (path, doc) ->
      let stat =
        Index.find_note base.index path
        |> Option.value_map ~default:(file_stat path) ~f:Index.Note.file_stat
      in
      Index.set_note index (Index.Note.of_doc_exn stat doc))
  in
  let index = List.fold (Index.assets base.index) ~init:index ~f:Index.set_asset in
  { base with index; documents = String.Map.of_alist_exn docs }
;;

(** Read, parse, resolve, and by default expand the files beneath [vault_root]. *)
let of_root_path
      ?(skip_expand = false)
      ?(exclude : string -> bool = fun _ -> false)
      (vault_root : string)
  : t
  =
  let entries =
    List.filter (Fs_utils.walk ~root:vault_root ()) ~f:(fun p -> not (exclude p))
  in
  let files = List.filter entries ~f:(fun p -> not (String.is_suffix p ~suffix:"/")) in
  let parsed_docs =
    List.filter_map files ~f:(fun path ->
      if String.is_suffix path ~suffix:".md"
      then
        Some
          ( path
          , Parse.of_string
              ~locs:true
              (In_channel.read_all (Filename.concat vault_root path)) )
      else None)
  in
  let other_files =
    List.filter files ~f:(fun p -> not (String.is_suffix p ~suffix:".md"))
  in
  let index = build_index ~md_docs:parsed_docs ~other_files in
  let vault =
    { vault_root
    ; index
    ; documents = String.Map.of_alist_exn parsed_docs
    ; vault_meta = Cmarkit.Meta.none
    }
  in
  if skip_expand
  then vault
  else of_docs ~base:vault (Embed.expand_docs ~index parsed_docs)
;;

(** Construct a vault from Markdown contents and asset paths without performing IO.
    Links are resolved; embeds are not expanded. *)
let of_files
      ~(vault_root : string)
      ~(md_files : (string * string) list)
      ~(other_files : string list)
  : t
  =
  let parsed_docs =
    List.map md_files ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content)
  in
  let index = build_index ~md_docs:parsed_docs ~other_files in
  { vault_root
  ; index
  ; documents = String.Map.of_alist_exn parsed_docs
  ; vault_meta = Cmarkit.Meta.none
  }
;;
