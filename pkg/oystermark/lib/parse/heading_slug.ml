(** Add slug to the metadata of headings.

    {b Deprecated, and no longer wired into {!Oystermark.Parse.of_string}.} The
    parser assigns heading identifiers itself now: [Doc.of_string] is called with
    [~heading_auto_ids:true] and the identifier lives in {!Cmarkit.Block.Heading.id},
    read via {!Common.heading_id}. Nothing stamps {!meta_key} any more, so
    {!sexp_of_meta} prints nothing and {!mk_block_map} is unused.

    It is kept for reference, because it documents what oyster used to mean by a
    heading identifier and the two differ:

    - {!slugify} is GitHub-style — every non-alphanumeric byte becomes [-], runs
      collapse, case is folded — whereas the parser follows CommonMark's
      {!Cmarkit.Inline.id}, which {e drops} punctuation instead: [foo/bar] was
      [foo-bar] and is now [foobar].
    - Deduplication was over one pass of one document, keyed by base slug. The
      parser's is in document order and counts explicit [ {#id} ] attributes as
      taken.

    New code must read {!Common.heading_id}, or {!Common.heading_id_of_text} to
    resolve a fragment written as text. *)

open Core

let meta_key : string Cmarkit.Meta.key = Cmarkit.Meta.key ()

let sexp_of_meta : Common.meta_sexp =
  fun meta ->
  Cmarkit.Meta.find meta_key meta
  |> Option.map ~f:(fun slug -> Sexp.List [ Atom "heading-slug"; Atom slug ])
;;

(** GitHub-style slug: lowercase, non-alphanum to [-], collapse runs, strip edges. *)
let slugify (s : string) : string =
  s
  |> String.lowercase
  |> String.map ~f:(fun c ->
    if Char.is_alphanum c || Char.equal c '-' || Char.equal c '_' then c else '-')
  |> String.split ~on:'-'
  |> List.filter ~f:(fun s -> not (String.is_empty s))
  |> String.concat ~sep:"-"
;;

(** Compute a deduplicated slug. [seen] tracks base slug -> count. *)
let dedup_slug (seen : (string, int) Hashtbl.t) (text : string) : string =
  let base : string = slugify text in
  let count : int = Hashtbl.find seen base |> Option.value ~default:0 in
  Hashtbl.set seen ~key:base ~data:(count + 1);
  if count = 0 then base else sprintf "%s-%d" base count
;;

(** Moved to {!Common.inline_to_plain_text}, which no longer needs an [~ext] for
    wikilinks: [Cmarkit.Inline.to_plain_text] handles
    [Cmarkit.Inline.Ext_wikilink] itself. *)
let inline_to_plain_text = Common.inline_to_plain_text

let mk_block_map () : Cmarkit.Block.t Cmarkit.Mapper.mapper =
  let open Cmarkit.Mapper in
  let slug_seen = Hashtbl.create (module String) in
  fun (m : t) (b : Cmarkit.Block.t) ->
    match b with
    | Cmarkit.Block.Heading (h, meta) ->
      let orig_inline = Cmarkit.Block.Heading.inline h in
      let mapped_inline =
        Cmarkit.Mapper.map_inline m orig_inline |> Option.value ~default:orig_inline
      in
      let text = inline_to_plain_text mapped_inline in
      let slug = dedup_slug slug_seen text in
      let meta' = Cmarkit.Meta.add meta_key slug meta in
      let h' =
        Cmarkit.Block.Heading.make
          ?id:(Cmarkit.Block.Heading.id h)
          ~layout:(Cmarkit.Block.Heading.layout h)
          ~level:(Cmarkit.Block.Heading.level h)
          mapped_inline
      in
      ret (Cmarkit.Block.Heading (h', meta'))
    | _ -> Cmarkit.Mapper.default
;;
