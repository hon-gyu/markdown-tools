(** Filesystem operations used while loading a vault. *)

open Core

(** Directories never walked, by name: build outputs and dependency trees,
    whose contents are not notes and whose size dwarfs the vault's.  Tooling
    state ([.git], [.obsidian], [.trash]) needs no entry here — a leading dot
    is enough. *)
let ignored_directories = [ "node_modules"; "_build"; "target"; "dist" ]

(* Exclusion patterns
   ================== *)

(** Vault-relative path patterns, in the shape [.gitignore] made familiar.

    A pattern containing no [/] matches a file or directory of that name
    anywhere in the vault; one that does is anchored at the vault root. Within
    a component, [*] matches any run of characters and [?] any single one;
    [**] as a whole component matches any number of components. A pattern that
    matches a directory excludes its whole subtree, so a trailing [/] is
    accepted and carries no extra meaning. *)
module Exclude = struct
  type segment =
    | Any_depth (** [**] *)
    | Component of string (** One component's glob. *)

  type t = segment list

  (** [None] when the pattern names nothing — [""], ["/"], ["."]. Excluding on
      such a pattern would exclude the vault. *)
  let of_pattern (pattern : string) : t option =
    let pattern = String.chop_suffix_if_exists pattern ~suffix:"/" in
    let anchored = String.contains pattern '/' in
    let segments =
      String.split pattern ~on:'/'
      |> List.filter ~f:(fun c -> not (String.is_empty c || String.equal c "."))
      |> List.map ~f:(function
        | "**" -> Any_depth
        | component -> Component component)
    in
    if List.is_empty segments
    then None
    else Some (if anchored then segments else Any_depth :: segments)
  ;;

  let matches_component (glob : string) (name : string) : bool =
    let glob_len = String.length glob
    and name_len = String.length name in
    let rec go i j =
      if i >= glob_len
      then j >= name_len
      else (
        match glob.[i] with
        | '*' -> go (i + 1) j || (j < name_len && go i (j + 1))
        | '?' -> j < name_len && go (i + 1) (j + 1)
        | c -> j < name_len && Char.equal name.[j] c && go (i + 1) (j + 1))
    in
    go 0 0
  ;;

  (** An exhausted pattern matches whatever components remain: the pattern
      named a directory, and the exclusion carries to its subtree. *)
  let rec matches_segments (segments : t) (components : string list) : bool =
    match segments with
    | [] -> true
    | Any_depth :: rest ->
      matches_segments rest components
      ||
        (match components with
        | [] -> false
        | _ :: tl -> matches_segments segments tl)
    | Component glob :: rest ->
      (match components with
       | [] -> false
       | hd :: tl -> matches_component glob hd && matches_segments rest tl)
  ;;

  let matches (t : t) (path : string) : bool =
    String.chop_suffix_if_exists path ~suffix:"/"
    |> String.split ~on:'/'
    |> matches_segments t
  ;;

  (** [of_patterns patterns] is the predicate {!walk} takes: whether any
      pattern claims this vault-relative path.  Patterns naming nothing are
      dropped, so an empty list — and a list of only those — excludes
      nothing. *)
  let of_patterns (patterns : string list) : string -> bool =
    match List.filter_map patterns ~f:of_pattern with
    | [] -> fun _ -> false
    | ts -> fun path -> List.exists ts ~f:(fun t -> matches t path)
  ;;
end

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
    paths end in [/].  {!ignored_directories}, dot-directories, dotfiles, and
    everything [exclude] claims are omitted; an excluded directory is not
    descended into, so the cost of a tree left out is one [stat]. *)
let rec walk
          ~(root : string)
          ?(exclude : string -> bool = fun _ -> false)
          ?(rel_prefix = "")
          ()
  : string list
  =
  let entries =
    try Sys_unix.ls_dir root with
    | _ -> []
  in
  List.concat_map entries ~f:(fun name ->
    if
      List.mem ignored_directories name ~equal:String.equal
      || String.is_prefix name ~prefix:"."
    then []
    else (
      let full_path = Filename.concat root name in
      let rel_path =
        if String.is_empty rel_prefix then name else Filename.concat rel_prefix name
      in
      match Sys_unix.is_directory full_path with
      | `Yes ->
        if exclude (rel_path ^ "/")
        then []
        else (rel_path ^ "/") :: walk ~root:full_path ~exclude ~rel_prefix:rel_path ()
      | _ -> if exclude rel_path then [] else [ rel_path ]))
;;
