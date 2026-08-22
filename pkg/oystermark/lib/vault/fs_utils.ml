(** Filesystem operations used while loading a vault. *)

open Core

let ignored_directories = [ ".git"; ".obsidian"; ".oyster"; ".trash"; ".history" ]

(** [walk ~root ()] returns the vault-relative paths below [root]. Directory
    paths end in [/]. Ignored directories and dotfiles are omitted. *)
let rec walk ~(root : string) ?(rel_prefix = "") () : string list =
  let entries =
    try Sys_unix.ls_dir root with
    | _ -> []
  in
  List.concat_map entries ~f:(fun name ->
    if List.mem ignored_directories name ~equal:String.equal
    then []
    else (
      let full_path = Filename.concat root name in
      let rel_path =
        if String.is_empty rel_prefix then name else Filename.concat rel_prefix name
      in
      match Sys_unix.is_directory full_path with
      | `Yes -> (rel_path ^ "/") :: walk ~root:full_path ~rel_prefix:rel_path ()
      | _ -> if String.is_prefix name ~prefix:"." then [] else [ rel_path ]))
;;
