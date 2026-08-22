(** Link resolution algorithm: resolves link references against a vault index. *)

open Core
module Index = Index

type textloc = Cmarkit.Textloc.t

let sexp_of_textloc = Parse.Textloc_conv.sexp_of_t
let textloc_of_sexp = Parse.Textloc_conv.t_of_sexp

type target =
  | Note of { path : string }
  | File of { path : string }
  | Heading of
      { path : string
      ; heading : string
      ; level : int
      ; slug : string
      ; loc : textloc option [@sexp.option]
      }
  | Block of
      { path : string
      ; block_id : string
      ; loc : textloc option [@sexp.option]
      }
  | Attr of
      { path : string
      ; id : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_file
  | Curr_heading of
      { heading : string
      ; level : int
      ; slug : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_block of
      { block_id : string
      ; loc : textloc option [@sexp.option]
      }
  | Curr_attr of
      { id : string
      ; loc : textloc option [@sexp.option]
      }
  | Unresolved
[@@deriving sexp]

let resolved_key : target Cmarkit.Meta.key = Cmarkit.Meta.key ()

(** Make a wikilink from an already resolved target. *)
let make_wikilink
      ~(target : string option)
      ~(fragment : Cmarkit.Inline.Wikilink.fragment option)
      ~(display : string option)
      ~(embed : bool)
      ~(resolved_target : target)
  : Cmarkit.Inline.t
  =
  let wl = Parse.Common.wikilink_of_fields ~target ~fragment ~display ~embed in
  let meta = Cmarkit.Meta.add resolved_key resolved_target Cmarkit.Meta.none in
  Cmarkit.Inline.Ext_wikilink (wl, meta)
;;

(** Resolve a link reference against the vault index. *)
let resolve (link_ref : Link_ref.t) (curr_file : string) (index : Index.t) : target =
  let current path = Option.is_none link_ref.target && String.equal curr_file path in
  match Index.resolve index curr_file link_ref with
  | Error _ -> Unresolved
  | Ok (Index.Note path) -> if current path then Curr_file else Note { path }
  | Ok (Index.Asset path) -> File { path }
  | Ok (Index.Anchor { note_path = path; anchor }) ->
    let loc = Some anchor.loc in
    (match anchor.value with
     | Index.Heading heading ->
       if current path
       then
         Curr_heading
           { heading = heading.text; level = heading.level; slug = heading.slug; loc }
       else
         Heading
           { path
           ; heading = heading.text
           ; level = heading.level
           ; slug = heading.slug
           ; loc
           }
     | Index.Block { id; kind = Obsidian_caret } ->
       if current path
       then Curr_block { block_id = id; loc }
       else Block { path; block_id = id; loc }
     | Index.Block { id; kind = Djot_attr } | Index.Inline { id } ->
       if current path then Curr_attr { id; loc } else Attr { path; id; loc })
;;

(** Build a [Cmarkit.Mapper.t] that resolves links against the vault index. *)
let resolution_cmarkit_mapper ~(index : Index.t) ~(curr_file : string) : Cmarkit.Mapper.t =
  Cmarkit.Mapper.make
    ~block_ext_default:(fun _m b -> Some b)
    ~inline_ext_default:(fun _m i ->
      match i with
      | Cmarkit.Inline.Ext_wikilink (w, meta) ->
        let link_ref = Link_ref.of_wikilink w in
        let target = resolve link_ref curr_file index in
        let meta' = Cmarkit.Meta.add resolved_key target meta in
        Some (Cmarkit.Inline.Ext_wikilink (w, meta'))
      | other -> Some other)
    ~inline:(fun _m i ->
      match i with
      (* TODO(code-duplication) *)
      | Cmarkit.Inline.Link (link, meta) ->
        let ref_ = Cmarkit.Inline.Link.reference link in
        (match Link_ref.of_cmark_reference ref_ with
         | Some link_ref ->
           let target = resolve link_ref curr_file index in
           let meta' = Cmarkit.Meta.add resolved_key target meta in
           Cmarkit.Mapper.ret (Cmarkit.Inline.Link (link, meta'))
         | None -> Cmarkit.Mapper.default)
      | Cmarkit.Inline.Image (link, meta) ->
        let ref_ = Cmarkit.Inline.Link.reference link in
        (match Link_ref.of_cmark_reference ref_ with
         | Some link_ref ->
           let target = resolve link_ref curr_file index in
           let meta' = Cmarkit.Meta.add resolved_key target meta in
           Cmarkit.Mapper.ret (Cmarkit.Inline.Image (link, meta'))
         | None -> Cmarkit.Mapper.default)
      | _ -> Cmarkit.Mapper.default)
    ()
;;

(** Resolve links in a list of parsed docs against the vault index. *)
let resolve_docs (docs : (string * Cmarkit.Doc.t) list) (index : Index.t)
  : (string * Cmarkit.Doc.t) list
  =
  List.map docs ~f:(fun (rel_path, doc) ->
    let mapper = resolution_cmarkit_mapper ~index ~curr_file:rel_path in
    rel_path, Cmarkit.Mapper.map_doc mapper doc)
;;
