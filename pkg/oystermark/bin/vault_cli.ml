(** Command-line client for vault queries and renames. *)

open Core
module Vault = Oystermark.Vault

let load root = Vault.of_root_path ~skip_expand:true root

let kind_name = function
  | Vault.Query.Link -> "link"
  | Embed -> "embed"
  | Image -> "image"
;;

let destination_name ~source target =
  match Vault.Query.destination_path ~source target with
  | Some path -> path
  | None -> "<unresolved>"
;;

let line_number root (link : Vault.Query.link) =
  let content = In_channel.read_all (Filename.concat root link.source) in
  1
  + String.fold
      (String.prefix content (Int.min link.first_byte (String.length content)))
      ~init:0
      ~f:(fun n c -> if Char.equal c '\n' then n + 1 else n)
;;

let print_link root (link : Vault.Query.link) =
  printf
    "%s:%d\t%s\t%s\n"
    link.source
    (line_number root link)
    (kind_name link.kind)
    (destination_name ~source:link.source link.destination)
;;

let vault_param = Command.Param.(anon ("vault" %: string))

let unresolved_command =
  Command.basic
    ~summary:"List unresolved links, embeds, and images"
    (let%map_open.Command root = vault_param in
     fun () ->
       let vault = load root in
       Vault.Query.unresolved ~index:vault.index ~docs:vault.docs
       |> List.iter ~f:(print_link root))
;;

let stats_command =
  Command.basic
    ~summary:"Show vault graph statistics"
    (let%map_open.Command root = vault_param in
     fun () ->
       let vault = load root in
       let stats = Vault.Query.stats ~index:vault.index ~docs:vault.docs in
       printf "notes\t%d\n" stats.notes;
       printf "resolved link occurrences\t%d\n" stats.resolved_link_occurrences;
       printf "unique directed edges\t%d\n" stats.unique_edges;
       printf "unresolved links\t%d\n" stats.unresolved_links)
;;

let resolve_note (vault : Vault.t) note =
  match
    Vault.Resolve.resolve
      { Vault.Link_ref.target = Some note; fragment = None }
      ""
      vault.index
  with
  | Vault.Resolve.Note { path } -> path
  | _ -> failwithf "note not found: %s" note ()
;;

let links_command =
  Command.basic
    ~summary:"List incoming and outgoing links of a note"
    (let%map_open.Command root = vault_param
     and note = anon ("note" %: string)
     and incoming = flag "--incoming" no_arg ~doc:" Show incoming links only"
     and outgoing = flag "--outgoing" no_arg ~doc:" Show outgoing links only" in
     fun () ->
       if incoming && outgoing
       then failwith "choose at most one of --incoming and --outgoing";
       let vault = load root in
       let note = resolve_note vault note in
       let show label links =
         printf "%s (%d)\n" label (List.length links);
         List.iter links ~f:(print_link root)
       in
       if not outgoing
       then
         show "incoming" (Vault.Query.incoming ~index:vault.index ~docs:vault.docs ~note);
       if not incoming
       then
         show "outgoing" (Vault.Query.outgoing ~index:vault.index ~docs:vault.docs ~note))
;;

let apply_edits content edits =
  List.sort edits ~compare:(fun (a : Vault.Rename.edit) b ->
    Int.descending a.first_byte b.first_byte)
  |> List.fold ~init:content ~f:(fun content edit ->
    String.prefix content edit.first_byte
    ^ edit.new_text
    ^ String.drop_prefix content edit.last_byte)
;;

let apply_change root (change : Vault.Rename.change) =
  Option.iter change.rename_file ~f:(fun (_old_path, new_path) ->
    let new_path = Filename.concat root new_path in
    match Sys_unix.file_exists new_path with
    | `No -> ()
    | `Yes | `Unknown -> failwithf "refusing to overwrite %s" new_path ());
  List.group change.edits ~break:(fun a b -> not (String.equal a.rel_path b.rel_path))
  |> List.iter ~f:(fun edits ->
    let rel_path = (List.hd_exn edits).rel_path in
    let path = Filename.concat root rel_path in
    let content = In_channel.read_all path in
    Out_channel.write_all path ~data:(apply_edits content edits));
  Option.iter change.rename_file ~f:(fun (old_path, new_path) ->
    let old_path = Filename.concat root old_path in
    let new_path = Filename.concat root new_path in
    Core_unix.rename ~src:old_path ~dst:new_path)
;;

let print_change (change : Vault.Rename.change) =
  List.iter change.edits ~f:(fun edit ->
    printf "%s:%d-%d -> %S\n" edit.rel_path edit.first_byte edit.last_byte edit.new_text);
  Option.iter change.rename_file ~f:(fun (old_path, new_path) ->
    printf "rename %s -> %s\n" old_path new_path)
;;

let rename_command target_name summary make_target =
  Command.basic
    ~summary
    (let%map_open.Command root = vault_param
     and note = anon ("note" %: string)
     and target = anon (target_name %: string)
     and new_name = anon ("new-name" %: string)
     and apply = flag "--apply" no_arg ~doc:" Apply the displayed change to disk" in
     fun () ->
       let vault = load root in
       let path = resolve_note vault note in
       let read_file rel_path =
         try Some (In_channel.read_all (Filename.concat root rel_path)) with
         | _ -> None
       in
       let target = make_target vault path target in
       match
         Vault.Rename.plan ~index:vault.index ~docs:vault.docs ~read_file target ~new_name
       with
       | Error message -> failwith message
       | Ok change ->
         print_change change;
         if apply
         then apply_change root change
         else printf "dry run; pass --apply to write\n")
;;

let rename_note_command =
  Command.basic
    ~summary:"Rename a note and its incoming references"
    (let%map_open.Command root = vault_param
     and note = anon ("note" %: string)
     and new_name = anon ("new-name" %: string)
     and apply = flag "--apply" no_arg ~doc:" Apply the displayed change to disk" in
     fun () ->
       let vault = load root in
       let path = resolve_note vault note in
       let read_file rel_path =
         try Some (In_channel.read_all (Filename.concat root rel_path)) with
         | _ -> None
       in
       match
         Vault.Rename.plan
           ~index:vault.index
           ~docs:vault.docs
           ~read_file
           ({ path; subject = Note } : Vault.Rename.target)
           ~new_name
       with
       | Error message -> failwith message
       | Ok change ->
         print_change change;
         if apply
         then apply_change root change
         else printf "dry run; pass --apply to write\n")
;;

let heading_target (vault : Vault.t) path heading =
  let entry =
    List.find_exn vault.index.files ~f:(fun entry -> String.equal entry.rel_path path)
  in
  let heading =
    List.find entry.headings ~f:(fun h ->
      String.equal h.text heading || String.equal h.slug heading)
    |> Option.value_exn ~message:(sprintf "heading not found in %s: %s" path heading)
  in
  ({ path; subject = Heading { slug = heading.slug } } : Vault.Rename.target)
;;

let command =
  Command.group
    ~summary:"Inspect and rename notes in an OysterMark vault"
    [ "unresolved", unresolved_command
    ; "stats", stats_command
    ; "links", links_command
    ; "rename-note", rename_note_command
    ; ( "rename-heading"
      , rename_command
          "heading"
          "Rename a heading and its incoming references"
          heading_target )
    ]
;;

let () = Command_unix.run command
