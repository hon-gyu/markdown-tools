(** Loading a vault from the filesystem.

    Separate from {!Vault} so that the pure, in-memory vault API carries no
    Unix dependency: {!Oystermark} links into a js_of_ocaml bundle, and
    [core_unix]'s native stubs have no JavaScript implementation. *)

module Fs_utils = Fs_utils
open Core

(** Read, parse, resolve, and by default expand the files beneath [vault_root].

    [overlay] associates vault-relative [.md] paths with source text to index
    as though those files were on disk. An overlay entry shadows a file of the
    same path beneath [vault_root]. Its purpose is generated notes: a page
    computed from the vault can be indexed alongside the vault that produced
    it, without being written into the source tree first. *)
let of_root_path
      ?(skip_expand = false)
      ?(exclude : string -> bool = fun _ -> false)
      ?(overlay : (string * string) list = [])
      (vault_root : string)
  : Vault.t
  =
  (* [exclude] goes to the walk rather than filtering its result: an excluded
     directory is then never descended into. *)
  let entries = Fs_utils.walk ~root:vault_root ~exclude () in
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
  let overlay_docs =
    List.map overlay ~f:(fun (rel_path, source) ->
      rel_path, Parse.of_string ~locs:true source)
  in
  (* The on-disk entry is dropped rather than shadowed by ordering: [documents]
     below is built with [of_alist_exn], which raises on a duplicate path. *)
  let parsed_docs =
    let overlaid = String.Set.of_list (List.map overlay_docs ~f:fst) in
    List.filter parsed_docs ~f:(fun (path, _) -> not (Set.mem overlaid path))
    @ overlay_docs
  in
  let other_files =
    List.filter files ~f:(fun p -> not (String.is_suffix p ~suffix:".md"))
  in
  let stat_of_path rel_path : Vault.Index.file_stat =
    { rel_path
    ; birthtime = None
    ; mtime = Fs_utils.mtime_date (Filename.concat vault_root rel_path)
    }
  in
  let index = Vault.build_index ~stat_of_path ~md_docs:parsed_docs ~other_files () in
  let vault : Vault.t =
    { vault_root
    ; index
    ; documents = String.Map.of_alist_exn parsed_docs
    ; vault_meta = Cmarkit.Meta.none
    }
  in
  if skip_expand
  then vault
  else Vault.of_docs ~base:vault (Vault.Embed.expand_docs ~index parsed_docs)
;;
