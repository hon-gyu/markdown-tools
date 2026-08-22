(** Unified internal link reference extracted from both wikilinks and markdown links, abstracting away source syntax. *)

open Core
open Parse

type fragment =
  | Hash_path of string list
  (** May resolves to headings, or Djot attribute anchors (when length = 1). Non-empty *)
  | Caret_id of string (** Obsidian block id *)
[@@deriving sexp, equal, compare]

(**
  | Target | Fragment | Meaning |
  |---|---|---|
  | `Some target` | `None` | Another note or asset |
  | `Some target` | `Some fragment` | An anchor in another note |
  | `None` | `Some fragment` | An anchor in the current note |
  | `None` | `None` | Current note or normalized empty reference |
*)
type t =
  { target : string option
    (** Authored target name or path. [None] means the current note. *)
  ; fragment : fragment option
  }
[@@deriving sexp, equal, compare]

let to_markdown_link (t : t) : Cmarkit.Inline.Link.t = failwith "TODO"
let to_markdown_link_text (t : t) : string = failwith "TODO"

let of_wikilink (w : Cmarkit.Inline.Wikilink.t) : t =
  let fragment =
    match Cmarkit.Inline.Wikilink.fragment w with
    | None -> None
    | Some (Cmarkit.Inline.Wikilink.Heading hs) -> Some (Hash_path hs)
    | Some (Cmarkit.Inline.Wikilink.Block_ref s) -> Some (Caret_id s)
  in
  { target = Cmarkit.Inline.Wikilink.target w; fragment }
;;

let is_external (s : string) : bool =
  String.is_prefix s ~prefix:"http://"
  || String.is_prefix s ~prefix:"https://"
  || String.is_prefix s ~prefix:"mailto:"
  || String.is_prefix s ~prefix:"ftp://"
;;

let percent_decode (s : string) : string =
  let buf = Buffer.create (String.length s) in
  let len = String.length s in
  let rec loop i =
    if i >= len
    then Buffer.contents buf
    else if Char.equal (String.get s i) '%' && i + 2 < len
    then (
      let hi = String.get s (i + 1) in
      let lo = String.get s (i + 2) in
      match Char.get_hex_digit hi, Char.get_hex_digit lo with
      | Some h, Some l ->
        Buffer.add_char buf (Char.of_int_exn ((h lsl 4) lor l));
        loop (i + 3)
      | _ ->
        Buffer.add_char buf '%';
        loop (i + 1))
    else (
      Buffer.add_char buf (String.get s i);
      loop (i + 1))
  in
  loop 0
;;

let of_cmark_dest (dest : string) : t option =
  let decoded = percent_decode dest in
  if is_external decoded
  then None
  else (
    let wikilink = Cmarkit.Inline.Wikilink.make ~embed:false decoded in
    Some (of_wikilink wikilink))
;;

let of_cmark_reference (ref : Cmarkit.Inline.Link.reference) : t option =
  match ref with
  | `Ref _ ->
    (* TODO: we should support this case? *)
    None
  | `Inline (ld, _ld_meta) ->
    (match Cmarkit.Link_definition.dest ld with
     | None ->
       (* When destination is empty, Obsidian resolves it to a file named "().md". *)
       Some { target = Some "().md"; fragment = None }
     | Some (dest, dest_meta) -> of_cmark_dest dest)
;;
