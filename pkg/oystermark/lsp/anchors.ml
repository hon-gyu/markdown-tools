(** Where a note's anchors are, according to the parser.

    Four features need the same thing — {i is there a heading with this slug,
    and where does its section end?}, {i what anchor is the cursor sitting
    on?} — and each used to answer it by reading lines: count the leading
    [#]s, slugify what follows, look for a trailing [ ^id], match a [\{#id\}]
    line. That is a second implementation of Markdown, and it drifts from the
    one that decides what the note actually is: it finds headings inside
    fenced code blocks, and it derives a slug from the heading's text, so a
    heading carrying an authored [ \{#id\} ] or a parser-deduplicated
    [heading-1] cannot be found at all.

    This module is the single parser-based answer, built on the same
    extractors the vault index uses. Nothing here inspects a character of
    Markdown syntax.

    See {!page-"feature-index"}, and {!page-"feature-attribute-anchors"} for
    what an anchor {e is}. *)

open Core

(** {1 Anchors} *)

type kind =
  | Heading of int (** ATX level, 1–6. *)
  | Block (** A [ ^id] caret marker. *)
  | Attr (** An explicit [ \{#id\} ], block-level or inline. *)
[@@deriving sexp, equal, compare]

(** One located anchor.

    [id] is what a [#fragment] must name to reach it: for a heading that is
    the identifier {e the parser assigned} — an authored [ \{#id\} ] included,
    and deduplicated with [-1], [-2] — not a slug re-derived from the text.

    [first_line] and [last_line] are the anchor's own extent, 0-based. An
    attribute anchor starts at the [ \{#id\} ] line and runs through the block
    it attributes; a caret id spans its whole paragraph. *)
type t =
  { kind : kind
  ; id : string
  ; text : string (** The heading's text; [""] for the other kinds. *)
  ; first_line : int
  ; last_line : int (** Inclusive. *)
  ; first_byte : int
  ; last_byte : int (** Exclusive. *)
  }
[@@deriving sexp, equal, compare]

(** The line the id is {e written} on — where a rename edits and a definition
    jump should land. For a caret id that is the paragraph's last line, since
    the [ ^id] closes it; for the others it is where the anchor starts. *)
let write_line (a : t) : int =
  match a.kind with
  | Heading _ | Attr -> a.first_line
  | Block -> a.last_line
;;

let of_loc (loc : Cmarkit.Textloc.t option) : (int * int * int * int) option =
  match loc with
  | Some tl when not (Cmarkit.Textloc.is_none tl) ->
    Some
      ( fst (Cmarkit.Textloc.first_line tl) - 1
      , fst (Cmarkit.Textloc.last_line tl) - 1
      , Cmarkit.Textloc.first_byte tl
      , Cmarkit.Textloc.last_byte tl + 1 )
  | _ -> None
;;

(** Every anchor of [doc], in source order.  Anchors the parser could not
    locate are dropped: without a position there is nothing to answer with.
    An attribute anchor's location covers its [ \{#id\} ] line as well as the
    block it attributes: the parser spans the specifier, so nothing here has
    to guess where it was written. *)
let of_doc (doc : Cmarkit.Doc.t) : t list =
  let headings =
    Oystermark.Vault.Index.extract_headings doc
    |> List.filter_map ~f:(fun (h : Oystermark.Vault.Index.heading_entry) ->
      of_loc h.loc
      |> Option.map ~f:(fun (first_line, last_line, first_byte, last_byte) ->
        { kind = Heading h.level
        ; id = h.slug
        ; text = h.text
        ; first_line
        ; last_line
        ; first_byte
        ; last_byte
        }))
  in
  let blocks =
    Oystermark.Vault.Index.extract_block_ids doc
    |> List.filter_map ~f:(fun (b : Oystermark.Vault.Index.block_entry) ->
      of_loc b.loc
      |> Option.map ~f:(fun (first_line, last_line, first_byte, last_byte) ->
        { kind = Block
        ; id = b.id
        ; text = ""
        ; first_line
        ; last_line
        ; first_byte
        ; last_byte
        }))
  in
  let attrs =
    Oystermark.Vault.Index.extract_attr_ids doc
    |> List.filter_map ~f:(fun (a : Oystermark.Vault.Index.attr_entry) ->
      of_loc a.loc
      |> Option.map ~f:(fun (first_line, last_line, first_byte, last_byte) ->
        { kind = Attr
        ; id = a.id
        ; text = ""
        ; first_line
        ; last_line
        ; first_byte
        ; last_byte
        }))
  in
  List.sort
    (headings @ blocks @ attrs)
    ~compare:(fun a b ->
      match Int.compare a.first_byte b.first_byte with
      | 0 -> Int.compare a.last_byte b.last_byte
      | c -> c)
;;

let of_content (content : string) : t list = of_doc (Lsp_util.parse_doc content)

(** {1 Lookup} *)

(** The anchor of [kind] carrying [id].  Heading slugs, caret ids and
    attribute ids share one namespace per file, so [kind] is what
    distinguishes [ [[note#foo]] ] meaning the heading from the caret id —
    the caller knows which it resolved to. *)
let find (ts : t list) ~(id : string) ~(is_kind : kind -> bool) : t option =
  List.find ts ~f:(fun a -> is_kind a.kind && String.equal a.id id)
;;

let find_heading (ts : t list) ~(slug : string) : t option =
  find ts ~id:slug ~is_kind:(function
    | Heading _ -> true
    | Block | Attr -> false)
;;

(** The anchor the cursor is on, [None] when the line holds none.

    Line-granular rather than byte-granular on purpose: asking the reader to
    put the cursor exactly on a [ ^id] would be a worse question than "which
    line are you on".  A heading and an attribute answer anywhere in their own
    extent — for an attribute that is its [ \{#id\} ] line and the block it
    attributes, both of which are that anchor.  A caret id answers only on the
    line it is written on: its paragraph is ordinary prose that happens to end
    with a marker, not an anchor throughout.

    Headings come first, then caret ids, then attributes — the order fragments
    resolve in.  See {!page-"feature-find-references".activation}. *)
let at_line (ts : t list) ~(line : int) : t option =
  let covers (a : t) =
    match a.kind with
    | Heading _ | Attr -> a.first_line <= line && line <= a.last_line
    | Block -> a.last_line = line
  in
  let on_line k = List.find ts ~f:(fun a -> covers a && k a.kind) in
  List.find_map
    [ (function
        | Heading _ -> true
        | _ -> false)
    ; (function
        | Block -> true
        | _ -> false)
    ; (function
        | Attr -> true
        | _ -> false)
    ]
    ~f:on_line
;;

(** {1 Slices}

    Both return raw source rather than a re-rendered AST: a preview should
    show what the file says, and the byte ranges come from the parser
    anyway. *)

(** The section [a] heads: from its own first byte up to the next heading of
    equal or higher level, or the end of [content].  [""] for a non-heading. *)
let section (ts : t list) (content : string) (a : t) : string =
  match a.kind with
  | Block | Attr -> ""
  | Heading level ->
    let stop =
      List.find_map ts ~f:(fun b ->
        match b.kind with
        | Heading l when l <= level && b.first_byte > a.first_byte -> Some b.first_byte
        | _ -> None)
    in
    String.sub
      content
      ~pos:a.first_byte
      ~len:(Option.value stop ~default:(String.length content) - a.first_byte)
    |> String.rstrip
;;

(** The paragraph [a] marks, [ ^id] marker included — this is source, and the
    marker is part of what the file says.  [""] for a non-caret anchor. *)
let block_text (content : string) (a : t) : string =
  match a.kind with
  | Heading _ | Attr -> ""
  | Block ->
    String.sub content ~pos:a.first_byte ~len:(a.last_byte - a.first_byte)
    |> String.rstrip
;;

(* Tests
   ======

   Recognition is the parser's, so what is worth pinning is the cases a
   line-based reading gets wrong. *)

let%test_module "of_content" =
  (module struct
    let show content =
      List.iter (of_content content) ~f:(fun a -> print_s [%sexp (a : t)])
    ;;

    let%expect_test "headings, caret ids and attributes together" =
      show "# Alpha\n\nBody ^b1\n\nThe [key]{#kt} span.\n";
      [%expect
        {|
        ((kind (Heading 1)) (id alpha) (text Alpha) (first_line 0) (last_line 0)
         (first_byte 0) (last_byte 7))
        ((kind Block) (id b1) (text "") (first_line 2) (last_line 2) (first_byte 9)
         (last_byte 17))
        ((kind Attr) (id kt) (text "") (first_line 4) (last_line 4) (first_byte 23)
         (last_byte 33))
        |}]
    ;;

    (* The identifier is the parser's, so an authored anchor is findable by
       the id the author wrote — a slug re-derived from the text would be
       [introduction] and match nothing. *)
    let%expect_test "authored heading id" =
      show "{#intro}\n# Introduction\n";
      [%expect
        {|
        ((kind Attr) (id intro) (text "") (first_line 0) (last_line 1) (first_byte 0)
         (last_byte 23))
        ((kind (Heading 1)) (id intro) (text Introduction) (first_line 1)
         (last_line 1) (first_byte 9) (last_byte 23))
        |}]
    ;;

    let%expect_test "duplicate heading texts are deduplicated" =
      show "# Same\n\n# Same\n";
      [%expect
        {|
        ((kind (Heading 1)) (id same) (text Same) (first_line 0) (last_line 0)
         (first_byte 0) (last_byte 6))
        ((kind (Heading 1)) (id same-1) (text Same) (first_line 2) (last_line 2)
         (first_byte 8) (last_byte 14))
        |}]
    ;;

    let%expect_test "a heading inside a code block is not a heading" =
      show "```\n# Not a heading\n```\n";
      [%expect {| |}]
    ;;

    let%expect_test "a heading inside a div is one" =
      show "::: warning\n# Inside\n:::\n";
      [%expect
        {|
        ((kind (Heading 1)) (id inside) (text Inside) (first_line 1) (last_line 1)
         (first_byte 12) (last_byte 20))
        |}]
    ;;
  end)
;;

let%test_module "section" =
  (module struct
    let show ~slug content =
      let ts = of_content content in
      match find_heading ts ~slug with
      | None -> print_endline "<not found>"
      | Some a -> print_string (section ts content a)
    ;;

    let%expect_test "runs to the next heading of equal or higher level" =
      show
        ~slug:"beta"
        "# Alpha\n\n## Beta\n\ntext\n\n### Gamma\n\nmore\n\n## Delta\n\nend\n";
      [%expect
        {|
        ## Beta

        text

        ### Gamma

        more
        |}]
    ;;

    let%expect_test "a hash inside a code block does not end the section" =
      show ~slug:"alpha" "# Alpha\n\n```\n# not a heading\n```\n\ntail\n\n# Beta\n";
      [%expect
        {|
        # Alpha

        ```
        # not a heading
        ```

        tail
        |}]
    ;;

    let%expect_test "authored id" =
      show ~slug:"intro" "{#intro}\n# Introduction\n\nbody\n\n# Next\n";
      [%expect
        {|
        # Introduction

        body
        |}]
    ;;
  end)
;;

let%test_module "block_text" =
  (module struct
    let show ~id content =
      let ts = of_content content in
      match find ts ~id ~is_kind:(Poly.equal Block) with
      | None -> print_endline "<not found>"
      | Some a -> print_string (block_text content a)
    ;;

    let%expect_test "the whole paragraph, marker included" =
      show ~id:"abc" "# H\n\nFirst line\nsecond line ^abc\n\nafter\n";
      [%expect
        {|
        First line
        second line ^abc
        |}]
    ;;

    let%expect_test "unknown id" =
      show ~id:"nope" "text ^abc\n";
      [%expect {| <not found> |}]
    ;;
  end)
;;

let%test_module "at_line" =
  (module struct
    let show content ~line =
      match at_line (of_content content) ~line with
      | None -> print_endline "<none>"
      | Some a -> print_s [%sexp (a : t)]
    ;;

    let%expect_test "on a heading" =
      show "# Alpha\n\ntext ^b\n" ~line:0;
      [%expect
        {|
        ((kind (Heading 1)) (id alpha) (text Alpha) (first_line 0) (last_line 0)
         (first_byte 0) (last_byte 7))
        |}]
    ;;

    (* The caret is on the paragraph's last line, which is where the reader
       sees it — not on the line the paragraph started. *)
    let%expect_test "on the caret line of a multi-line paragraph" =
      show "one\ntwo ^b\n" ~line:1;
      [%expect
        {|
        ((kind Block) (id b) (text "") (first_line 0) (last_line 1) (first_byte 0)
         (last_byte 10))
        |}]
    ;;

    let%expect_test "on the first line of that paragraph" =
      show "one\ntwo ^b\n" ~line:0;
      [%expect {| <none> |}]
    ;;

    let%expect_test "on an inline attribute's line" =
      show "The [key]{#kt} span.\n" ~line:0;
      [%expect
        {|
        ((kind Attr) (id kt) (text "") (first_line 0) (last_line 0) (first_byte 4)
         (last_byte 14))
        |}]
    ;;

    let%expect_test "on a plain line" =
      show "# Alpha\n\njust prose\n" ~line:2;
      [%expect {| <none> |}]
    ;;
  end)
;;
