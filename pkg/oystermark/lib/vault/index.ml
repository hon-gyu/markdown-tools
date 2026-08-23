(* A unified vault index API, centralizing all relevant queries / operations

  - provide a unified vault API, centralizing all relevant queries / operations
  - downstream client code: LSP, oyster-publish (not in this repo yet), vault_cli (oyster)
  - compact, persistent snapshots that clients can update one file at a time
*)

open Core
open Parse

type loc = Cmarkit.Textloc.t

let sexp_of_loc = Textloc_conv.sexp_of_t
let loc_of_sexp = Textloc_conv.t_of_sexp
let compare_loc = Textloc_conv.compare
let equal_loc a b = Int.equal (compare_loc a b) 0

(**
- non-emtpy
- vault-relative
- separated by [/]
- free of leading [./]
- no empty components
- no [.] or [..] components
- case-preserving
- no Unicode normalization
*)
module Path = struct
  type t = string

  let sexp_of_t = String.sexp_of_t
  let t_of_sexp = String.t_of_sexp

  let of_string : string -> (t, Error.t) result =
    fun s ->
    let cs = String.split s ~on:'/' in
    if String.is_empty s
    then Error (Error.of_string "vault path must not be empty")
    else if String.is_prefix s ~prefix:"/"
    then Error (Error.of_string "vault path must be relative")
    else if
      List.exists cs ~f:(fun c ->
        String.is_empty c || String.equal c "." || String.equal c "..")
    then Error (Error.of_string "vault path contains an empty, . or .. component")
    else Ok s
  ;;

  let to_string : t -> string = Fun.id
  let dirname : t -> t option = fun t -> Option.map (String.rsplit2 t ~on:'/') ~f:fst
  let basename : t -> string = Filename.basename
  let compare : t -> t -> int = String.compare
  let equal : t -> t -> bool = String.equal
end

type heading =
  { text : string
  ; level : int
  ; slug : string
    (** The identifier the parser gave the heading. See {!Parse.Common.heading_id}. *)
  }
[@@deriving sexp, equal, compare]

type referenceable_block_kind =
  | Djot_attr
  | Obsidian_caret
[@@deriving sexp, equal, compare]

(** Block other than heading, made referenceable because of either djot attribute or Obsidian caret.  *)
type block =
  { id : string
  ; kind : referenceable_block_kind
  }
[@@deriving sexp, equal, compare]

(** Inline, made referenceable because of attached djot attribute id ([ {#id} ]). *)
type inline = { id : string } [@@deriving sexp, equal, compare]

type file_stat =
  { rel_path : Path.t
  ; birthtime : (int * int * int) option (** created date YYYY/MM/DD, when available *)
  ; mtime : (int * int * int) option (** modified date YYYY/MM/DD, when available *)
  }

type anchor_value =
  | Heading of heading
  | Block of block
  | Inline of inline
[@@deriving sexp, equal, compare]

(** Construct a vault-qualified reference to [anchor] in [target_path] *)
let link_ref_of_anchor ~(tgt_path : Path.t) (anchor : anchor_value) : Link_ref.t =
  match anchor with
  | Heading h ->
    { Link_ref.target = Some tgt_path; fragment = Some (Hash_path [ h.slug ]) }
  | Block { id; kind = Obsidian_caret } ->
    { Link_ref.target = Some tgt_path; fragment = Some (Caret_id id) }
  | Block { id; kind = Djot_attr } | Inline { id } ->
    { Link_ref.target = Some tgt_path; fragment = Some (Hash_path [ id ]) }
;;

module Anchor = struct
  type t =
    { value : anchor_value
    ; loc : loc (** non-none loc *)
    }
  [@@deriving sexp, equal, compare]
end

(** Authored link; a note can compute this without an index  *)
module Link = struct
  (** How the authored syntax uses its target. Whether an embed transcludes a
      note or displays an asset is determined after resolution. *)
  type kind =
    | Link
    | Embed
  [@@deriving sexp, equal, compare]

  type t =
    { reference : Link_ref.t
    ; kind : kind
    ; loc : loc (** Non-none loc *)
    }
  [@@deriving sexp, equal, compare]
end

let loc_of_meta meta =
  let loc = Cmarkit.Meta.textloc meta in
  if Cmarkit.Textloc.is_none loc then None else Some loc
;;

module Note = struct
  type t =
    { file_stat : file_stat
    ; anchors : Anchor.t list
    ; links : Link.t list
    }

  (** @return [Error] if the document is not parsed with source locations enabled (missing location information) *)
  let of_doc (file_stat : file_stat) (doc : Cmarkit.Doc.t) : (t, string) result =
    let missing_loc = ref false in
    let anchors = ref [] in
    let links = ref [] in
    let with_loc meta f =
      match loc_of_meta meta with
      | Some loc -> f loc
      | None -> missing_loc := true
    in
    let add_anchor value meta =
      with_loc meta (fun loc -> anchors := { Anchor.value; loc } :: !anchors)
    in
    let add_link reference kind meta =
      with_loc meta (fun loc -> links := { Link.reference; kind; loc } :: !links)
    in
    let add_attr ~inline attr meta =
      Option.iter (Cmarkit.Attribute.id attr) ~f:(fun id ->
        add_anchor (if inline then Inline { id } else Block { id; kind = Djot_attr }) meta)
    in
    let folder =
      Cmarkit.Folder.make
        ~block:(fun f acc b ->
          match b with
          | Cmarkit.Block.Heading (h, meta) ->
            let text = Common.inline_to_plain_text (Cmarkit.Block.Heading.inline h) in
            let slug =
              Common.heading_id h
              |> Option.value_exn
                   ~message:"heading missing identifier; parse with Oystermark.Parse"
            in
            add_anchor
              (Heading { text; level = Cmarkit.Block.Heading.level h; slug })
              meta;
            Cmarkit.Folder.default
          | Cmarkit.Block.Paragraph (_, meta) ->
            Option.iter (Cmarkit.Block.Block_id.find meta) ~f:(fun id ->
              add_anchor
                (Block { id = Cmarkit.Block.Block_id.id id; kind = Obsidian_caret })
                meta);
            Cmarkit.Folder.default
          | Cmarkit.Block.Ext_keyed ((_label, body), meta) ->
            Option.iter (Cmarkit.Block.Block_id.find meta) ~f:(fun id ->
              add_anchor
                (Block { id = Cmarkit.Block.Block_id.id id; kind = Obsidian_caret })
                meta);
            Cmarkit.Folder.ret (Cmarkit.Folder.fold_block f acc body)
          | Cmarkit.Block.Ext_attributes (a, meta) ->
            add_attr ~inline:false (Cmarkit.Block.Attributes.attributes a) meta;
            Cmarkit.Folder.ret
              (Cmarkit.Folder.fold_block f acc (Cmarkit.Block.Attributes.block a))
          | _ -> Cmarkit.Folder.default)
        ~inline:(fun f acc i ->
          match i with
          | Cmarkit.Inline.Ext_wikilink (w, meta) ->
            add_link
              (Link_ref.of_wikilink w)
              (if Cmarkit.Inline.Wikilink.embed w then Link.Embed else Link.Link)
              meta;
            Cmarkit.Folder.default
          | Cmarkit.Inline.Link (l, meta) ->
            Option.iter
              (Link_ref.of_cmark_reference (Cmarkit.Inline.Link.reference l))
              ~f:(fun r -> add_link r Link.Link meta);
            Cmarkit.Folder.default
          | Cmarkit.Inline.Image (l, meta) ->
            Option.iter
              (Link_ref.of_cmark_reference (Cmarkit.Inline.Link.reference l))
              ~f:(fun r -> add_link r Link.Embed meta);
            Cmarkit.Folder.default
          | Cmarkit.Inline.Ext_attributes (a, meta) ->
            add_attr ~inline:true (Cmarkit.Inline.Attributes.attributes a) meta;
            Cmarkit.Folder.ret
              (Cmarkit.Folder.fold_inline f acc (Cmarkit.Inline.Attributes.inline a))
          | _ -> Cmarkit.Folder.default)
        ~inline_ext_default:(fun _ acc _ -> acc)
        ~block_ext_default:(fun _ acc _ -> acc)
        ()
    in
    ignore (Cmarkit.Folder.fold_doc folder () doc : unit);
    if !missing_loc
    then Error "document is missing source locations"
    else Ok { file_stat; anchors = List.rev !anchors; links = List.rev !links }
  ;;

  let of_doc_exn (file_stat : file_stat) (doc : Cmarkit.Doc.t) : t =
    Result.ok_or_failwith (of_doc file_stat doc)
  ;;

  let path : t -> Path.t = fun note -> note.file_stat.rel_path
  let file_stat : t -> file_stat = fun note -> note.file_stat

  (** all authored anchor occurrence (including duplicates) in document order *)
  let anchors (note : t) : Anchor.t list = note.anchors

  let headings (note : t) : (heading * loc) list =
    anchors note
    |> List.filter_map ~f:(fun anchor ->
      match anchor.value with
      | Heading heading -> Some (heading, anchor.loc)
      | Block _ | Inline _ -> None)
  ;;

  (** All link references in a note, returned in document order.
      - includes both resolved and unresolved links
      - includes both markdown and wiki links
      - does not include external links (HTTP/mail link)
  *)
  let links (note : t) : Link.t list = note.links
end

(** Non-note assets (images, etc.) *)
module Asset = struct
  type t = { file_stat : file_stat }

  let create (file_stat : file_stat) : t = { file_stat }
  let path (asset : t) : Path.t = asset.file_stat.rel_path
end

type target =
  | Note of Path.t
  | Asset of Path.t
  | Anchor of
      { note_path : Path.t
      ; anchor : Anchor.t
      }
[@@deriving sexp, equal, compare]

type resolution_error =
  | Missing_path
  | Missing_anchor of Path.t
  (** the base path exists and the fragment does not resolve, whether that base target is a note or asset *)

(** Result of resolving an authored reference. *)
type resolution = (target, resolution_error) result

(** An authored link viewed through a resolved target  *)
type backlink =
  { source : Path.t
  ; link : Link.t
  }

let target_path : target -> Path.t = function
  | Note path | Asset path -> path
  | Anchor { note_path; _ } -> note_path
;;

type t =
  { notes_by_path : Note.t String.Map.t
  ; assets_by_path : Asset.t String.Map.t
  }

let empty : t = { notes_by_path = String.Map.empty; assets_by_path = String.Map.empty }

(** Insert or replace the note at its canonical path, removing any asset at the same path.

- atomically update its anchors and outgoing occurrences;
- update all reverse-reference queries affected by the change;
- return a new index snapshot;
- leave the old snapshot valid and unchanged.

The result of any update sequence is observationally equivalent to rebuilding the index
from its resulting notes and assets.
 *)
let set_note : t -> Note.t -> t =
  fun t n ->
  let p = Note.path n in
  { notes_by_path = Map.set t.notes_by_path ~key:p ~data:n
  ; assets_by_path = Map.remove t.assets_by_path p
  }
;;

(** remove a note from the index. no-op when absent *)
let remove_note : t -> Path.t -> t =
  fun t p -> { t with notes_by_path = Map.remove t.notes_by_path p }
;;

(** Insert or replace the asset at its canonical path, removing any note at the same path. *)
let set_asset : t -> Asset.t -> t =
  fun t a ->
  let p = Asset.path a in
  { notes_by_path = Map.remove t.notes_by_path p
  ; assets_by_path = Map.set t.assets_by_path ~key:p ~data:a
  }
;;

let remove_asset : t -> Path.t -> t =
  fun t p -> { t with assets_by_path = Map.remove t.assets_by_path p }
;;

let note_of_path : t -> Path.t -> Note.t option = fun t p -> Map.find t.notes_by_path p

(** Returned in ascending canonical path order. *)
let notes (index : t) : Note.t list = Map.data index.notes_by_path

(** Returned in ascending canonical path order. *)
let assets (index : t) : Asset.t list = Map.data index.assets_by_path

let find_note (index : t) (path : Path.t) : Note.t option =
  Map.find index.notes_by_path path
;;

let find_asset (index : t) (path : Path.t) : Asset.t option =
  Map.find index.assets_by_path path
;;

module Resolve_ = struct
  let normalize_relative_target ~source target =
    if not (String.is_prefix target ~prefix:"./" || String.is_prefix target ~prefix:"../")
    then target
    else
      Filename.concat (Filename.dirname source) target
      |> String.split ~on:'/'
      |> List.fold ~init:[] ~f:(fun acc component ->
        match component, acc with
        | ".", _ | "", _ -> acc
        | "..", _ :: rest -> rest
        | "..", [] -> []
        | component, _ -> component :: acc)
      |> List.rev
      |> String.concat ~sep:"/"
  ;;

  let is_path_subsequence ~haystack ~needle =
    let rec loop hs = function
      | [] -> true
      | n :: ns ->
        (match List.drop_while hs ~f:(fun h -> not (String.equal h n)) with
         | [] -> false
         | _ :: hs -> loop hs ns)
    in
    loop haystack needle
  ;;

  let match_rank ~source_dir p =
    ( List.length (String.split p ~on:'/')
    , if String.equal (Filename.dirname p) source_dir then 0 else 1 )
  ;;

  let resolve_path index ~source target =
    let target = normalize_relative_target ~source target in
    let normalized = if String.mem target '.' then target else target ^ ".md" in
    let paths = Map.keys index.notes_by_path @ Map.keys index.assets_by_path in
    match List.find paths ~f:(String.equal normalized) with
    | Some p -> Some p
    | None ->
      let needle = String.split normalized ~on:'/' in
      let source_dir = Filename.dirname source in
      List.filter paths ~f:(fun p ->
        is_path_subsequence ~haystack:(String.split p ~on:'/') ~needle)
      |> List.min_elt ~compare:(fun a b ->
        [%compare: int * int] (match_rank ~source_dir a) (match_rank ~source_dir b))
  ;;

  let heading_matches h q =
    String.equal h.text q || String.equal h.slug (Common.heading_id_of_text q)
  ;;

  let resolve_heading anchors query =
    let hs =
      List.filter_map anchors ~f:(fun a ->
        match a.Anchor.value with
        | Heading h -> Some (h, a)
        | _ -> None)
      |> Array.of_list
    in
    let qs = Array.of_list query in
    let rec search hi qi prev =
      if hi >= Array.length hs || qi >= Array.length qs
      then None
      else (
        let h, a = hs.(hi) in
        if heading_matches h qs.(qi) && h.level > prev
        then
          if qi = Array.length qs - 1
          then Some a
          else
            Option.first_some (search (hi + 1) (qi + 1) h.level) (search (hi + 1) qi prev)
        else search (hi + 1) qi prev)
    in
    if Array.is_empty qs then None else search 0 0 0
  ;;

  let resolve_fragment note = function
    | Link_ref.Hash_path hs ->
      Option.first_some
        (resolve_heading (Note.anchors note) hs)
        (match hs with
         | [ id ] ->
           List.find (Note.anchors note) ~f:(fun a ->
             match a.value with
             | Block { id = x; kind = Djot_attr } | Inline { id = x } -> String.equal x id
             | _ -> false)
         | _ -> None)
    | Link_ref.Caret_id id ->
      List.find (Note.anchors note) ~f:(fun a ->
        match a.value with
        | Block { id = x; kind = Obsidian_caret } -> String.equal x id
        | _ -> false)
  ;;
end

open Resolve_

(** Resolve an authored reference related to a [source] note.

  On duplicated anchors, the first one in document order is returned.

  @param ref The link reference to resolve.
  @param source The path of the note containing the link reference. It doesn't need to be present in the index.
*)
let resolve (index : t) (source : Path.t) (ref : Link_ref.t) : resolution =
  let path =
    match ref.Link_ref.target with
    | None -> Some source
    | Some t -> resolve_path index ~source t
  in
  match path with
  | None -> Error Missing_path
  | Some p ->
    (match ref.fragment with
     | None ->
       if Map.mem index.notes_by_path p
       then Ok (Note p)
       else if Map.mem index.assets_by_path p
       then Ok (Asset p)
       else Error Missing_path
     | Some f ->
       (match find_note index p with
        | None -> Error (Missing_anchor p)
        | Some n ->
          Option.value_map
            (resolve_fragment n f)
            ~default:(Error (Missing_anchor p))
            ~f:(fun anchor -> Ok (Anchor { note_path = p; anchor }))))
;;

let unresolved_links (index : t) (note_path : Path.t) : (Link.t * resolution_error) list =
  let path = note_path in
  Option.value_map (find_note index path) ~default:[] ~f:(fun n ->
    List.filter_map (Note.links n) ~f:(fun l ->
      match resolve index path l.reference with
      | Ok _ -> None
      | Error e -> Some (l, e)))
;;

let all_backlinks index =
  List.concat_map (notes index) ~f:(fun note ->
    Note.links note
    |> List.filter_map ~f:(fun link ->
      match resolve index (Note.path note) link.reference with
      | Error _ -> None
      | Ok target -> Some (target, { source = Note.path note; link })))
;;

(**
  @param include_anchors If true, also includes edge pointing to any anchor owned by the note
  @return incoming links {b to} a note of [tgt_path], in document order
*)
let backlinks_of_note ?(include_anchors : bool = false) (index : t) (tgt_path : Path.t)
  : backlink list
  =
  let tgt = tgt_path in
  List.filter_map (all_backlinks index) ~f:(fun (target, b) ->
    match target with
    | Note p when Path.equal p tgt -> Some b
    | Anchor { note_path; _ } when include_anchors && Path.equal note_path tgt -> Some b
    | _ -> None)
;;

(** @return incoming links {b to} [target], in document order *)
let backlinks_of_target (index : t) (target : target) : backlink list =
  let wanted = target in
  List.filter_map (all_backlinks index) ~f:(fun (target, b) ->
    if equal_target target wanted then Some b else None)
;;

(** A note is orphaned when no successfully resolved ordinary link or embed from a different
note targets either the note or one of its anchors. *)
let is_orphan (index : t) (note_path : Path.t) : bool =
  let path = note_path in
  not
    (List.exists (backlinks_of_note ~include_anchors:true index path) ~f:(fun b ->
       (not (Path.equal b.source path))
       &&
       match b.link.kind with
       | Link.Link | Embed -> true))
;;

(** Returned in ascending canonical path order. *)
let orphans (index : t) : Path.t list =
  List.filter (Map.keys index.notes_by_path) ~f:(is_orphan index)
;;
