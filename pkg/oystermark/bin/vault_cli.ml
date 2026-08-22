(** Command-line client for vault queries and renames. *)

open Core
module Vault = Oystermark.Vault

let load root = Vault.of_root_path ~skip_expand:true root

let is_image_target target =
  let target = String.lowercase target in
  List.exists [ ".png"; ".jpg"; ".jpeg"; ".gif"; ".svg"; ".webp" ] ~f:(fun ext ->
    String.is_suffix target ~suffix:ext)
;;

let links index =
  Vault.Index.notes index
  |> List.concat_map ~f:(fun note ->
    let source = Vault.Index.Note.path note in
    Vault.Index.Note.links note
    |> List.map ~f:(fun link ->
      source, link, Vault.Index.resolve index source link.reference))
;;

let kind_name (_, (link : Vault.Index.Link.t), resolution) =
  match link.kind, resolution with
  | Vault.Index.Link.Link, _ -> "link"
  | Embed, Ok (Vault.Index.Note _ | Anchor _) -> "embed"
  | Embed, Ok (Vault.Index.Asset _) -> "image"
  | Embed, Error _ ->
    (match link.reference.target with
     | Some target when is_image_target target -> "image"
     | _ -> "embed")
;;

let destination_name (_, _, resolution) =
  match resolution with
  | Ok target -> Vault.Index.target_path target
  | Error _ -> "<unresolved>"
;;

let line_number (_, (link : Vault.Index.Link.t), _) =
  fst (Cmarkit.Textloc.first_line link.loc)
;;

let print_link ((source, _, _) as occurrence) =
  printf
    "%s:%d\t%s\t%s\n"
    source
    (line_number occurrence)
    (kind_name occurrence)
    (destination_name occurrence)
;;

let (vault_param : string Command.Param.t) = Command.Param.(anon ("vault" %: string))

let unresolved_command =
  Command.basic
    ~summary:"List unresolved links, embeds, and images"
    (let%map_open.Command root = vault_param in
     fun () ->
       let vault = load root in
       links vault.index
       |> List.filter ~f:(fun (_, _, resolution) -> Result.is_error resolution)
       |> List.iter ~f:print_link)
;;

type stats =
  { nodes : int
  ; edges : int
  ; self_links : int
  ; unresolved_links : int
  }

let stats (vault : Vault.t) =
  let links = links vault.index in
  let edges, self_links, unresolved_links =
    List.fold
      links
      ~init:(0, 0, 0)
      ~f:(fun (edges, self_links, unresolved) (source, _, resolution) ->
        match resolution with
        | Error _ -> edges, self_links, unresolved + 1
        | Ok target ->
          let destination = Vault.Index.target_path target in
          ( edges + 1
          , self_links + Bool.to_int (String.equal source destination)
          , unresolved ))
  in
  { nodes = List.length (Vault.Index.notes vault.index)
  ; edges
  ; self_links
  ; unresolved_links
  }
;;

let stats_command =
  Command.basic
    ~summary:"Show vault graph statistics"
    (let%map_open.Command root = vault_param in
     fun () ->
       let stats = stats (load root) in
       printf "nodes\t%d\n" stats.nodes;
       printf "edges\t%d\n" stats.edges;
       printf "self links\t%d\n" stats.self_links;
       printf "unresolved links\t%d\n" stats.unresolved_links)
;;

let resolve_note (vault : Vault.t) note =
  match
    Vault.Index.resolve vault.index "__cli__.md" { target = Some note; fragment = None }
  with
  | Ok (Vault.Index.Note path) -> path
  | _ -> failwithf "note not found: %s" note ()
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
         Vault.Rename.plan
           ~index:vault.index
           ~docs:(Vault.docs vault)
           ~read_file
           target
           ~new_name
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
           ~docs:(Vault.docs vault)
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
    Vault.Index.find_note vault.index path
    |> Option.value_exn ~message:(sprintf "note not found: %s" path)
  in
  let heading =
    Vault.Index.Note.headings entry
    |> List.map ~f:fst
    |> List.find ~f:(fun h -> String.equal h.text heading || String.equal h.slug heading)
    |> Option.value_exn ~message:(sprintf "heading not found in %s: %s" path heading)
  in
  ({ path; subject = Heading { slug = heading.slug } } : Vault.Rename.target)
;;

let command =
  Command.group
    ~summary:"Inspect and rename notes in an OysterMark vault"
    [ "unresolved", unresolved_command
    ; "stats", stats_command
    ; "rename-note", rename_note_command
    ; ( "rename-heading"
      , rename_command
          "heading"
          "Rename a heading and its incoming references"
          heading_target )
    ]
;;

let () = Command_unix.run command
