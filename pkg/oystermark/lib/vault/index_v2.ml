(* v2 goal (this file and together with adapted vault.ml):
  - provide a unified vault API, centralizing all relevant queries / operations
  - downstream client code: LSP, oyster-publish (not in this repo yet), vault_cli (oyster)
  - prep for adding incremental calculation using [Incremental] (not now, but v2 should aim for supporting it starting from day one)
    - this should improve performance for LSP (for both memory usage and speed)

- some lsp features should move to here and make the lsp a thinner wrapper
*)

open Core
open Parse

let todo = failwith "todo"

type loc = Cmarkit.Textloc.t

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

  let of_string : string -> (t, error) result = todo
  let to_string : t -> string = todo
  let dirname : t -> t option = todo
  let basename : t -> string = todo

  let compare : t -> t -> int = todo
  let equal : t -> t -> bool = todo
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
type inline = { id : string }
[@@deriving sexp, equal, compare]

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
let link_ref_of_anchor ~(tgt_path : Path.t) (anchor : anchor_value) : Link_ref.t = todo

module Anchor = struct
  type t =
    { value : anchor_value
    ; loc : loc (** non-none loc *)
    }
    [@@deriving sexp, equal, compare]
end

(** Authored link; a note can compute this without an index  *)
module Link = struct
  type kind =
    | Link
    | Embed
    | Image

  type t =
    { reference : Link_ref.t
    ; kind : kind
    ; loc : loc (** Non-none loc *)
    }
    [@@deriving sexp, equal, compare]
end

module Note = struct
  type t =
    { file_stat : file_stat
    ; doc : Cmarkit.Doc.t
    ; anchors : Anchor.t list
    ; links: Link.t list
    }

  (** @return [Error] if the document is not parsed with source locations enabled (missing location information) *)
  let of_doc (file_stat : file_stat) (doc : Cmarkit.Doc.t) : (t, string) result = todo

  let of_doc_exn (file_stat : file_stat) (doc : Cmarkit.Doc.t) : t = todo

  let path : t -> Path.t = fun note -> note.file_stat.rel_path

  let file_stat : t -> file_stat = fun note -> note.file_stat

  (** all authored anchor occurrence (including duplicates) in document order *)
  let anchors (note : t) : Anchor.t list = todo

  let headings (note : t) : (heading * loc) list = anchors note |> List.filter_map ~f:todo

  (** All link references in a note, returned in document order.
      - includes both resolved and unresolved links
      - includes both markdown and wiki links
      - does not include external links (HTTP/mail link)
  *)
  let links (note : t) : Link.t list = todo

  let doc (note : t) : Cmarkit.Doc.t = todo
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
  | Missing_anchor of Path.t (** the base path exists and the fragment does not resolve, whether that base target is a note or asset *)

(** Result of resolving an authored reference. *)
type resolution = (target, resolution_error) result

(** An authored link viewed through a resolved target  *)
type backlink =
  { source : Path.t
  ; link : Link.t
  }

let target_path : target -> Path.t = todo

type t

let empty : t = todo

(** Insert or replace the note at its canonical path, removing any asset at the same path.

- atomically update its anchors and outgoing occurrences;
- update all reverse-reference queries affected by the change;
- return a new index snapshot;
- leave the old snapshot valid and unchanged.

The result of any update sequence is observationally equivalent to rebuilding the index
from its resulting notes and assets.
 *)
let set_note : t -> Note.t -> t = todo

(* remove a note from the index. no-op when absent *)
let remove_note : t -> Path.t -> t = todo

(** Insert or replace the asset at its canonical path, removing any note at the same path. *)
let set_asset : t -> Asset.t -> t = todo
let remove_asset : t -> Path.t   -> t = todo

let note_of_path : t -> Path.t -> Note.t option = todo

(** Returned in ascending canonical path order. *)
let notes (index : t) : Note.t list = todo
(** Returned in ascending canonical path order. *)
let assets (index : t) : Asset.t list = todo
let find_note (index : t) (path : Path.t) : Note.t option = todo
let find_asset (index : t) (path : Path.t) : Asset.t option = todo

(** Resolve an authored reference related to a [source] note.

  On duplicated anchors, the first one in document order is returned.

  @param ref The link reference to resolve.
  @param source The path of the note containing the link reference. It doesn't need to be present in the index.
*)
let resolve (index : t) (source : Path.t) (ref : Link_ref.t) : resolution =
  (* TASK: this aims to replace the existing Resolve.resolve. We want to make [Resolve] mostly a module providing utilities  *)
  todo
;;

let unresolved_links (index : t) (note_path : Path.t) : (Link.t * resolution_error) list = todo

(**
  @param include_anchors If true, also includes edge pointing to any anchor owned by the note
  @return incoming links {b to} a note of [tgt_path], in document order
*)
let backlinks_of_note ?(include_anchors : bool = false) (index : t) (tgt_path : Path.t) : backlink list = todo

(** @return incoming links {b to} [target], in document order *)
let backlinks_of_target (index : t) (target : target) : backlink list = todo


(** A note is orphaned when no successfully resolved ordinary link or embed from a different
note targets either the note or one of its anchors. *)
let is_orphan (index : t) (note_path : Path.t) : bool = todo

(** Returned in ascending canonical path order. *)
let orphans (index : t) : Path.t list = todo
