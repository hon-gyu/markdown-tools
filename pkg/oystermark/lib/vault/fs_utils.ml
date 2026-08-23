(** Filesystem operations used while loading a vault. *)

open Core

let ignored_directories = [ ".git"; ".obsidian"; ".oyster"; ".trash"; ".history" ]

(** [mtime_date path] is the local-time [(year, month, day)] of [path]'s last
    modification, or [None] when [path] cannot be stat'd. *)
let mtime_date (path : string) : (int * int * int) option =
  match Core_unix.stat path with
  | exception _ -> None
  | stat ->
    let tm = Core_unix.localtime stat.st_mtime in
    Some (tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)
;;

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
