(** Vault-wide rename planning.  This module describes byte edits and file
    moves; clients decide how to apply or encode them. *)

open Core
module Index = Index

(** {1 Rename target} *)

type subject =
  | Note
  | Heading of { slug : string }
  | Block of { id : string }
  | Attr of { id : string }
[@@deriving sexp, equal]

type target =
  { path : string
  ; subject : subject
  }
[@@deriving sexp, equal]

type edit =
  { rel_path : string
  ; first_byte : int
  ; last_byte : int (** Exclusive. *)
  ; new_text : string
  }
[@@deriving sexp, equal, compare]

type change =
  { edits : edit list
  ; rename_file : (string * string) option
  }
[@@deriving sexp, equal]

let valid_note_name s =
  (not (String.is_empty s))
  && (not (String.exists s ~f:(fun c -> Char.equal c '/' || Char.equal c '\\')))
  && not (String.equal s "." || String.equal s "..")
;;

let valid_id s =
  (not (String.is_empty s))
  && String.for_all s ~f:(fun c ->
    Char.is_alphanum c || Char.equal c '-' || Char.equal c '_')
;;

let renamed_note_path ~path ~new_name =
  let new_name =
    if String.is_suffix new_name ~suffix:".md" then new_name else new_name ^ ".md"
  in
  Filename.concat (Filename.dirname path) new_name
;;

let destination_path (_, _, resolution) =
  Result.ok resolution |> Option.map ~f:Index.target_path
;;

let matches { path; subject } ((_, _, resolution) as link) =
  let same_path =
    destination_path link |> Option.value_map ~default:false ~f:(String.equal path)
  in
  same_path
  &&
  match subject, resolution with
  | Note, Ok _ -> true
  | Heading { slug }, Ok (Index.Anchor { anchor = { value = Heading h; _ }; _ }) ->
    String.equal slug h.slug
  | Block { id }, Ok (Index.Anchor { anchor = { value = Block b; _ }; _ }) ->
    String.equal id b.id && Index.equal_referenceable_block_kind b.kind Obsidian_caret
  | Attr { id }, Ok (Index.Anchor { anchor = { value = Block b; _ }; _ }) ->
    String.equal id b.id && Index.equal_referenceable_block_kind b.kind Djot_attr
  | Attr { id }, Ok (Index.Anchor { anchor = { value = Inline a; _ }; _ }) ->
    String.equal id a.id
  | _ -> false
;;

(** {1 Link destination edits} *)

let destination_bounds slice =
  match String.substr_index slice ~pattern:"[[" with
  | Some open_pos ->
    let start = open_pos + 2 in
    let finish =
      String.substr_index ~pos:start slice ~pattern:"]]"
      |> Option.value ~default:(String.length slice)
    in
    let finish =
      String.index_from slice start '|'
      |> Option.filter ~f:(fun p -> p < finish)
      |> Option.value ~default:finish
    in
    Some (`Wikilink, start, finish)
  | None ->
    String.substr_index slice ~pattern:"]("
    |> Option.map ~f:(fun open_pos ->
      let start = open_pos + 2 in
      let rec finish i =
        if
          i >= String.length slice
          || Char.equal slice.[i] ')'
          || Char.is_whitespace slice.[i]
        then i
        else finish (i + 1)
      in
      `Markdown, start, finish start)
;;

let reference_edit ~read_file { subject; _ } ~new_name (source, (link : Index.Link.t), _) =
  let first_byte = Cmarkit.Textloc.first_byte link.loc in
  let last_byte = Cmarkit.Textloc.last_byte link.loc in
  read_file source
  |> Option.bind ~f:(fun content ->
    let len = last_byte - first_byte + 1 in
    if first_byte < 0 || len <= 0 || first_byte + len > String.length content
    then None
    else (
      let slice = String.sub content ~pos:first_byte ~len in
      destination_bounds slice
      |> Option.bind ~f:(fun (style, start, stop) ->
        let destination = String.sub slice ~pos:start ~len:(stop - start) in
        match subject with
        | Note ->
          let target_stop =
            Option.value
              (String.index destination '#')
              ~default:(String.length destination)
          in
          let old_target = String.prefix destination target_stop in
          let basename =
            if String.is_suffix old_target ~suffix:".md"
            then
              if String.is_suffix new_name ~suffix:".md"
              then new_name
              else new_name ^ ".md"
            else
              Option.value (String.chop_suffix new_name ~suffix:".md") ~default:new_name
          in
          let replacement =
            match Filename.dirname old_target with
            | "." -> basename
            | dir -> Filename.concat dir basename
          in
          let replacement =
            match style with
            | `Wikilink -> replacement
            | `Markdown -> String.substr_replace_all replacement ~pattern:" " ~with_:"%20"
          in
          Some
            { rel_path = source
            ; first_byte = first_byte + start
            ; last_byte = first_byte + start + target_stop
            ; new_text = replacement
            }
        | Heading _ | Block _ | Attr _ ->
          String.index destination '#'
          |> Option.map ~f:(fun hash ->
            let marker_length =
              match subject with
              | Block _ -> 1
              | Note | Heading _ | Attr _ -> 0
            in
            let replacement =
              match style with
              | `Wikilink -> new_name
              | `Markdown -> String.substr_replace_all new_name ~pattern:" " ~with_:"%20"
            in
            { rel_path = source
            ; first_byte = first_byte + start + hash + 1 + marker_length
            ; last_byte = first_byte + stop
            ; new_text = replacement
            }))))
;;

(** {1 Definition edits} *)

let line_bounds content line =
  let rec loop pos current =
    if current = line
    then (
      let stop =
        Option.value (String.index_from content pos '\n') ~default:(String.length content)
      in
      Some (pos, stop))
    else (
      match String.index_from content pos '\n' with
      | None -> None
      | Some newline -> loop (newline + 1) (current + 1))
  in
  loop 0 0
;;

let attr_id_offset ~(id : string) line =
  let is_id_char c = Char.is_alphanum c || Char.equal c '-' || Char.equal c '_' in
  let rec scan i =
    if i >= String.length line
    then None
    else if Char.equal line.[i] '{'
    then (
      match String.index_from line i '}' with
      | None -> None
      | Some close ->
        let body = String.sub line ~pos:(i + 1) ~len:(close - i - 1) in
        (match Parse.Cb_attribute.of_string body with
         | Some { id = Some found; _ } when String.equal found id ->
           let pattern = "#" ^ id in
           let rec seek from =
             match String.substr_index body ~pos:from ~pattern with
             | None -> scan (close + 1)
             | Some p ->
               let after = p + String.length pattern in
               if after >= String.length body || not (is_id_char body.[after])
               then Some (i + 1 + p + 1)
               else seek (p + 1)
           in
           seek 0
         | _ -> scan (close + 1)))
    else scan (i + 1)
  in
  scan 0
;;

let definition_edit ~index ~read_file { path; subject } ~new_name =
  Index.find_note index path
  |> Option.bind ~f:(fun note ->
    let loc =
      match subject with
      | Note -> None
      | Heading { slug } ->
        Index.Note.anchors note
        |> List.find_map ~f:(fun anchor ->
          match anchor.value with
          | Index.Heading heading when String.equal heading.slug slug -> Some anchor.loc
          | _ -> None)
      | Block { id } ->
        Index.Note.anchors note
        |> List.find_map ~f:(fun anchor ->
          match anchor.value with
          | Index.Block { id = found; kind = Obsidian_caret } when String.equal found id
            -> Some anchor.loc
          | _ -> None)
      | Attr { id } ->
        Index.Note.anchors note
        |> List.find_map ~f:(fun anchor ->
          match anchor.value with
          | (Index.Block { id = found; kind = Djot_attr } | Inline { id = found })
            when String.equal found id -> Some anchor.loc
          | _ -> None)
    in
    loc
    |> Option.bind ~f:(fun loc ->
      read_file path
      |> Option.bind ~f:(fun content ->
        let source_line =
          match subject with
          | Block _ -> fst (Cmarkit.Textloc.last_line loc) - 1
          | Note | Heading _ | Attr _ -> fst (Cmarkit.Textloc.first_line loc) - 1
        in
        line_bounds content source_line
        |> Option.bind ~f:(fun (start, stop) ->
          let line = String.sub content ~pos:start ~len:(stop - start) in
          match subject with
          | Note -> None
          | Heading _ ->
            let hashes =
              String.length line
              - String.length (String.lstrip line ~drop:(Char.equal '#'))
            in
            let rec skip i =
              if i < String.length line && Char.equal line.[i] ' '
              then skip (i + 1)
              else i
            in
            let text_start = skip hashes in
            let text_stop =
              String.substr_index line ~pos:text_start ~pattern:" {"
              |> Option.value ~default:(String.length line)
            in
            Some
              { rel_path = path
              ; first_byte = start + text_start
              ; last_byte = start + text_stop
              ; new_text = new_name
              }
          | Block { id } ->
            String.substr_index line ~pattern:("^" ^ id)
            |> Option.map ~f:(fun pos ->
              { rel_path = path
              ; first_byte = start + pos + 1
              ; last_byte = start + pos + 1 + String.length id
              ; new_text = new_name
              })
          | Attr { id } ->
            attr_id_offset ~id line
            |> Option.map ~f:(fun pos ->
              { rel_path = path
              ; first_byte = start + pos
              ; last_byte = start + pos + String.length id
              ; new_text = new_name
              })))))
;;

(** {1 Change planning} *)

let resolved_links_of_docs index docs =
  List.concat_map docs ~f:(fun (source, doc) ->
    let file_stat =
      Index.find_note index source
      |> Option.value_map
           ~default:
             ({ rel_path = source; birthtime = None; mtime = None } : Index.file_stat)
           ~f:Index.Note.file_stat
    in
    Index.Note.of_doc_exn file_stat doc
    |> Index.Note.links
    |> List.map ~f:(fun link -> source, link, Index.resolve index source link.reference))
;;

let plan ~index ~docs ~read_file ({ path; subject } as target) ~new_name =
  let valid =
    match subject with
    | Note -> valid_note_name new_name
    | Heading _ -> not (String.is_empty (String.strip new_name))
    | Block _ | Attr _ -> valid_id new_name
  in
  if not valid
  then Error "invalid new name"
  else (
    let edits =
      resolved_links_of_docs index docs
      |> List.filter ~f:(matches target)
      |> List.filter_map ~f:(reference_edit ~read_file target ~new_name)
    in
    let definition, rename_file =
      match subject with
      | Note -> [], Some (path, renamed_note_path ~path ~new_name)
      | Heading _ | Block _ | Attr _ ->
        Option.to_list (definition_edit ~index ~read_file target ~new_name), None
    in
    Ok { edits = List.sort (definition @ edits) ~compare:compare_edit; rename_file })
;;

let%expect_test "plan note and heading renames" =
  let files =
    [ "a.md", "# Alpha\n\nBody\n"; "b.md", "[[a]] [[a#Alpha|label]] [x](a.md#Alpha)\n" ]
  in
  let md_docs =
    List.map files ~f:(fun (path, content) -> path, Parse.of_string ~locs:true content)
  in
  let index =
    List.fold md_docs ~init:Index.empty ~f:(fun index (rel_path, doc) ->
      let file_stat : Index.file_stat = { rel_path; birthtime = None; mtime = None } in
      Index.set_note index (Index.Note.of_doc_exn file_stat doc))
  in
  let read_file path = List.Assoc.find files ~equal:String.equal path in
  let show target new_name =
    match plan ~index ~docs:md_docs ~read_file target ~new_name with
    | Error error -> printf "error: %s\n" error
    | Ok change -> print_s [%sexp (change : change)]
  in
  show { path = "a.md"; subject = Note } "renamed";
  show { path = "a.md"; subject = Heading { slug = "alpha" } } "New title";
  [%expect
    {|
    ((edits
      (((rel_path b.md) (first_byte 2) (last_byte 3) (new_text renamed))
       ((rel_path b.md) (first_byte 8) (last_byte 9) (new_text renamed))
       ((rel_path b.md) (first_byte 28) (last_byte 32) (new_text renamed.md))))
     (rename_file ((a.md ./renamed.md))))
    ((edits
      (((rel_path a.md) (first_byte 2) (last_byte 7) (new_text "New title"))
       ((rel_path b.md) (first_byte 10) (last_byte 15) (new_text "New title"))
       ((rel_path b.md) (first_byte 33) (last_byte 38) (new_text New%20title))))
     (rename_file ()))
    |}]
;;
