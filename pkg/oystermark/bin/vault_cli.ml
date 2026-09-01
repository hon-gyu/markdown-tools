(** Command-line client for vault queries and renames. *)

open Core
module Parse = Oystermark.Parse
module Vault = Oystermark.Vault

let load root = Vault_fs.of_root_path ~skip_expand:true root

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

(** Emit the vault as a Jinja template context on stdout.

    Rendering is left to a Jinja engine invoked by the build system, so that
    this executable stays a pure query over a snapshot and gains no runtime
    dependency on a template binary. See {!page-"template-context"}. *)
let context_command =
  Command.basic
    ~summary:"Print the vault as a JSON template context"
    (let%map_open.Command root = vault_param
     and compact =
       flag "-compact" no_arg ~doc:" emit one line instead of indented JSON"
     in
     fun () ->
       let json = Oystermark.Context.of_vault (load root) in
       print_endline
         (if compact
          then Yojson.Safe.to_string json
          else Yojson.Safe.pretty_to_string json))
;;

(* Site build
   ========== *)

(** Render every template in the vault to a page, in the vault's own namespace.

    A template is a file named [<page>.md.jinja], and renders to [<page>.md].
    Every template is rendered against a context holding the whole vault,
    including the pages other templates produce: a template may describe a page
    in terms of generated pages, to any depth.

    Rendering repeats until a pass changes no page. Generated pages are indexed
    from memory and reach the filesystem, under [-o], only once that fixed
    point is found; the vault itself is never written to. Templates with no
    fixed point are an error, after [-max-passes] passes, naming the pages that
    would not settle. *)

(* Render order matters here and cannot be read off the templates: a Jinja
   expression selects notes at run time, so which pages a template consumes is
   not a static property of its source. Iterating to a fixed point is what buys
   us an order without asking templates to declare one. *)
let build_command =
  let template_suffix = ".md.jinja" in
  let page_of_template template =
    String.chop_suffix_exn template ~suffix:template_suffix ^ ".md"
  in
  (* [minijinja-cli] reads the context from a file rather than stdin: writing
     it to the child while reading the child's output risks a deadlock on a
     context larger than a pipe buffer. *)
  let render ~engine ~root ~context_paths template =
    let process =
      Core_unix.create_process
        ~prog:engine
        ~args:("--format=json" :: Filename.concat root template :: context_paths)
    in
    Core_unix.close process.stdin;
    let read fd = In_channel.input_all (Core_unix.in_channel_of_descr fd) in
    let rendered = read process.stdout in
    let errors = read process.stderr in
    Core_unix.close process.stdout;
    Core_unix.close process.stderr;
    match Core_unix.waitpid process.pid with
    | Ok () -> rendered
    | Error _ -> failwithf "%s: %s failed\n%s" template engine errors ()
  in
  Command.basic
    ~summary:"Render the vault's Jinja templates to pages"
    (let%map_open.Command root = vault_param
     and out = flag "-o" (required string) ~doc:"DIR write rendered pages under DIR"
     and engine =
       flag
         "-engine"
         (optional_with_default "minijinja-cli" string)
         ~doc:"PROG Jinja engine to invoke (default: minijinja-cli)"
     and max_passes =
       flag
         "-max-passes"
         (optional_with_default 10 int)
         ~doc:"N give up after N passes without a fixed point (default: 10)"
     and extra_context =
       flag
         "-context"
         (listed string)
         ~doc:
           "FILE merge FILE into the template context, after the vault's own (repeatable)"
     in
     fun () ->
       let templates =
         Vault_fs.Fs_utils.walk ~root ()
         |> List.filter ~f:(String.is_suffix ~suffix:template_suffix)
         |> List.sort ~compare:String.compare
       in
       let context_dir =
         Core_unix.mkdtemp (Filename.concat Filename.temp_dir_name "oyster-build")
       in
       let context_path = Filename.concat context_dir "context.json" in
       let render_pass overlay =
         let vault = Vault_fs.of_root_path ~skip_expand:true ~overlay root in
         Out_channel.write_all
           context_path
           ~data:(Yojson.Safe.to_string (Oystermark.Context.of_vault vault));
         List.map templates ~f:(fun template ->
           ( page_of_template template
           , render ~engine ~root ~context_paths:(context_path :: extra_context) template
           ))
       in
       let rec settle pass overlay =
         let rendered = render_pass overlay in
         if [%equal: (string * string) list] rendered overlay
         then rendered
         else if pass >= max_passes
         then (
           let previous = String.Map.of_alist_exn overlay in
           let unsettled =
             List.filter_map rendered ~f:(fun (page, contents) ->
               match Map.find previous page with
               | Some before when String.equal before contents -> None
               | _ -> Some page)
           in
           failwithf
             "no fixed point after %d passes; still changing: %s"
             max_passes
             (String.concat ~sep:", " unsettled)
             ())
         else settle (pass + 1) rendered
       in
       let pages =
         Exn.protect
           ~f:(fun () -> settle 1 [])
           ~finally:(fun () ->
             Core_unix.remove context_path;
             Core_unix.rmdir context_dir)
       in
       List.iter pages ~f:(fun (page, contents) ->
         let destination = Filename.concat out page in
         Core_unix.mkdir_p (Filename.dirname destination);
         Out_channel.write_all destination ~data:contents))
;;

(** Query the blocks of a note.

    The filters are sugar over one traversal: every flag narrows the same list
    of {!Oystermark.Parse.Extract.located} records, and [-json] prints those
    records so a filter this command does not implement can be written in jq.

    Default output is the block's source, verbatim. *)
let block_command =
  Command.basic
    ~summary:"Print blocks of a note, filtered by heading, kind, id or position"
    (let%map_open.Command note = anon ("NOTE" %: string)
     and under =
       flag
         "-under"
         (optional string)
         ~doc:"SLUG only blocks under the heading with this id or text"
     and direct = flag "-direct" no_arg ~doc:" with -under, exclude nested subsections"
     and kind = flag "-kind" (optional string) ~doc:"KIND only blocks of this kind"
     and lang =
       flag
         "-lang"
         (optional string)
         ~doc:"INFO only code blocks whose info string is exactly INFO"
     and id = flag "-id" (optional string) ~doc:"ID only the block with this {#id}"
     and caret_id =
       flag "-caret-id" (optional string) ~doc:"ID only the block with this ^id"
     and nth = flag "-nth" (optional int) ~doc:"N keep only the Nth match, 1-based"
     and content =
       flag "-content" no_arg ~doc:" print what the container holds, not its source"
     and json = flag "-json" no_arg ~doc:" print the matching blocks as JSON" in
     fun () ->
       let die fmt =
         ksprintf
           (fun s ->
              prerr_endline s;
              exit 1)
           fmt
       in
       let source = In_channel.read_all note in
       let doc = Parse.of_string ~locs:true source in
       let defs = Cmarkit.Doc.defs doc in
       let blocks =
         match Cmarkit.Doc.block doc with
         | Cmarkit.Block.Blocks (blocks, _) -> blocks
         | block -> [ block ]
       in
       let matches =
         Parse.Extract.walk blocks
         |> List.filter ~f:(fun (located : Parse.Extract.located) ->
           let keeps_under =
             match under with
             | None -> true
             | Some wanted ->
               let wanted = Parse.Common.heading_id_of_text wanted in
               if direct
               then (
                 match List.last located.heading_path with
                 | Some innermost -> String.equal innermost wanted
                 | None -> false)
               else List.mem located.heading_path wanted ~equal:String.equal
           in
           let matches_option option actual =
             match option with
             | None -> true
             | Some wanted ->
               (match actual with
                | Some actual -> String.equal actual wanted
                | None -> false)
           in
           keeps_under
           && matches_option kind (Some (Parse.Extract.kind_of_block located.block))
           && matches_option lang (Parse.Extract.info_string_of_block located.block)
           && matches_option id located.attr_id
           && matches_option caret_id (Parse.Extract.caret_id_of_block located.block))
       in
       let matches =
         match nth with
         | None -> matches
         | Some n ->
           (match List.nth matches (n - 1) with
            | Some located -> [ located ]
            | None -> [])
       in
       if List.is_empty matches then die "%s: no block matches" note;
       let content_of located =
         match Parse.Extract.content_string ~defs located with
         | Ok content -> content
         | Error kind -> die "%s: a %s has no contents to print" note kind
       in
       let source_of (located : Parse.Extract.located) =
         let textloc = Cmarkit.Meta.textloc (Parse.Extract.meta_of_block located.block) in
         if Cmarkit.Textloc.is_none textloc
         then die "%s: block %d has no location; parse with locations" note located.index
         else (
           let first = Cmarkit.Textloc.first_byte textloc in
           let last = Cmarkit.Textloc.last_byte textloc in
           String.sub source ~pos:first ~len:(last - first + 1))
       in
       if json
       then (
         let json_of (located : Parse.Extract.located) =
           let textloc =
             Cmarkit.Meta.textloc (Parse.Extract.meta_of_block located.block)
           in
           let string_or_null = function
             | Some s -> `String s
             | None -> `Null
           in
           `Assoc
             [ "index", `Int located.index
             ; "kind", `String (Parse.Extract.kind_of_block located.block)
             ; "info", string_or_null (Parse.Extract.info_string_of_block located.block)
             ; "attr_id", string_or_null located.attr_id
             ; "caret_id", string_or_null (Parse.Extract.caret_id_of_block located.block)
             ; ( "heading_path"
               , `List (List.map located.heading_path ~f:(fun s -> `String s)) )
             ; ( "heading_text"
               , `List (List.map located.heading_text ~f:(fun s -> `String s)) )
             ; ( "loc"
               , `Assoc
                   [ "first_line", `Int (fst (Cmarkit.Textloc.first_line textloc))
                   ; "last_line", `Int (fst (Cmarkit.Textloc.last_line textloc))
                   ; "first_byte", `Int (Cmarkit.Textloc.first_byte textloc)
                   ; "last_byte", `Int (Cmarkit.Textloc.last_byte textloc)
                   ] )
             ; "text", `String (source_of located)
             ; ( "content"
               , match Parse.Extract.content_string ~defs located with
                 | Ok content -> `String content
                 | Error _ -> `Null )
             ]
         in
         print_endline
           (Yojson.Safe.pretty_to_string (`List (List.map matches ~f:json_of))))
       else
         List.map matches ~f:(fun located ->
           if content then content_of located else source_of located)
         |> String.concat ~sep:"\n\n"
         |> print_endline)
;;

let command =
  Command.group
    ~summary:"Inspect and rename notes in an OysterMark vault"
    [ "unresolved", unresolved_command
    ; "stats", stats_command
    ; "context", context_command
    ; "build", build_command
    ; "block", block_command
    ; "rename-note", rename_note_command
    ; ( "rename-heading"
      , rename_command
          "heading"
          "Rename a heading and its incoming references"
          heading_target )
    ]
;;

let () =
  let version = Oystermark.Version.to_string () in
  (* [build_info] defaults to a placeholder sexp that [oyster version] prints
     verbatim; give it something readable instead. *)
  Command_unix.run ~version ~build_info:("oystermark " ^ version) command
;;
