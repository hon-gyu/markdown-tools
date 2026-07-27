(** Hover: show a preview of the link target's content.

    Spec: {!page-"feature-hover"}. *)

open Core

(** {1:implementation Implementation} *)

(** {2 Content extraction} *)

(** Number of lines in [s], counting a final line that lacks a trailing
    newline.  The empty string has no lines. *)
let count_lines (s : string) : int =
  if String.is_empty s
  then 0
  else
    String.count s ~f:(Char.equal '\n') + if String.is_suffix s ~suffix:"\n" then 0 else 1
;;

(** Render [n] bytes for human consumption: [B], [KB] or [MB]. *)
let human_bytes (n : int) : string =
  if n < 1024
  then sprintf "%d B" n
  else if n < 1024 * 1024
  then sprintf "%d KB" ((n + 512) / 1024)
  else sprintf "%d MB" ((n + (512 * 1024)) / (1024 * 1024))
;;

(** Truncate [s] to at most [max_chars] bytes, snapping to the previous
    newline to avoid cutting mid-word, and appending a notice reporting
    how much of the content is shown.

    The notice measures in {e lines}: that is the unit a reader
    perceives, and the cut lands on a line boundary so the count is
    exact.  The percentage is derived from the very same counts, so the
    two figures can never disagree.

    When one or zero lines are hidden the line counts carry no
    information (the remainder is a single long line, e.g. a wide table
    row), so the notice switches wholesale to bytes rather than mixing
    units.

    The percentage is clamped to \[1, 99\] and rounded down: truncation
    did happen, so the reader is never shown [0%] or [100%].

    Returns [s] unchanged if it is already short enough.

    See {!page-"feature-hover".truncation}. *)
let truncate ~max_chars (s : string) : string =
  if String.length s <= max_chars
  then s
  else (
    (* Snap back to the last newline before the cut point. *)
    let cut =
      match String.rindex_exn (String.prefix s max_chars) '\n' with
      | pos -> pos
      | exception Not_found_s _ -> max_chars
    in
    let shown = String.prefix s cut in
    let pct ~shown ~total = Int.max 1 (Int.min 99 (shown * 100 / Int.max 1 total)) in
    let total_lines = count_lines s in
    let shown_lines = count_lines shown in
    let notice =
      if total_lines - shown_lines <= 1
      then
        sprintf
          "*(truncated: showing %s of %s, %d%%)*"
          (human_bytes (String.length shown))
          (human_bytes (String.length s))
          (pct ~shown:(String.length shown) ~total:(String.length s))
      else
        sprintf
          "*(truncated: showing %d of %d lines, %d%%)*"
          shown_lines
          total_lines
          (pct ~shown:shown_lines ~total:total_lines)
    in
    shown ^ "\n\n" ^ notice)
;;

(** Extract the section of [content] starting at [heading_line] (0-based)
    up to but not including the next heading of equal or higher level.

    [heading_level] is the ATX level (1–6) of the anchor heading.
    Returns the raw lines of the section joined by newlines. *)
let extract_section ~(heading_line : int) ~(heading_level : int) (content : string)
  : string
  =
  let lines = String.split_lines content in
  let lines_arr = Array.of_list lines in
  let n = Array.length lines_arr in
  (* Find where the section ends: next heading at same or higher level. *)
  let end_line =
    let rec find i =
      if i >= n
      then n
      else (
        let line = lines_arr.(i) in
        (* Count leading '#' characters. *)
        let hashes =
          String.lfindi line ~f:(fun _ c -> not (Char.equal c '#'))
          |> Option.value ~default:(String.length line)
        in
        if
          hashes >= 1
          && hashes <= heading_level
          && String.length line > hashes
          && Char.equal line.[hashes] ' '
        then i
        else find (i + 1))
    in
    find (heading_line + 1)
  in
  Array.sub lines_arr ~pos:heading_line ~len:(end_line - heading_line)
  |> Array.to_list
  |> String.concat ~sep:"\n"
;;

(** Extract the paragraph that contains [block_id] from [content].
    Returns the paragraph text (without the trailing [^id] marker)
    or [None] if not found. *)
let extract_block ~(block_id : string) (content : string) : string option =
  (* A block ID appears as " ^id" at the end of a paragraph's last line. *)
  let marker = " ^" ^ block_id in
  let lines = String.split_lines content in
  (* Walk backwards through lines to find the marker, then collect the
     paragraph (consecutive non-blank lines ending at the marker line). *)
  let lines_arr = Array.of_list lines in
  let n = Array.length lines_arr in
  let find_marker () =
    let rec loop i =
      if i >= n
      then None
      else if String.is_suffix lines_arr.(i) ~suffix:marker
      then Some i
      else loop (i + 1)
    in
    loop 0
  in
  match find_marker () with
  | None -> None
  | Some marker_line ->
    (* Walk backwards to find the start of the paragraph. *)
    let start =
      let rec loop i =
        if i < 0 || String.is_empty (String.strip lines_arr.(i))
        then i + 1
        else loop (i - 1)
      in
      loop (marker_line - 1)
    in
    let para_lines =
      Array.sub lines_arr ~pos:start ~len:(marker_line - start + 1) |> Array.to_list
    in
    Some (String.concat ~sep:"\n" para_lines)
;;

(** Extract the block carrying attribute id [{#id}] from [content] and render it
    back to CommonMark.  Content-based (robust to unsaved edits), reusing
    {!Oystermark.Parse.Extract.get_block_by_attr_id}.  [None] if not found.
    See {!page-"feature-attribute-anchors"}. *)
let extract_attr_block ~(id : string) (content : string) : string option =
  let doc = Lsp_util.parse_doc content in
  Oystermark.Parse.Extract.get_block_by_attr_id [ Cmarkit.Doc.block doc ] id
  |> Option.map ~f:(fun b ->
    Oystermark.Parse.commonmark_of_doc (Cmarkit.Doc.make b) |> String.strip)
;;

(** {2 Heading-level parsing} *)

(** Return the ATX heading level (1–6) of [line], or [None]. *)
let heading_level_of_line (line : string) : int option =
  let hashes =
    String.lfindi line ~f:(fun _ c -> not (Char.equal c '#'))
    |> Option.value ~default:(String.length line)
  in
  if
    hashes >= 1
    && hashes <= 6
    && String.length line > hashes
    && Char.equal line.[hashes] ' '
  then Some hashes
  else None
;;

(** Find the 0-based line number and ATX level of the heading whose slug
    matches [slug] in [content].  Returns [None] if not found. *)
let find_heading_in_content ~(slug : string) (content : string) : (int * int) option =
  let lines = String.split_lines content in
  List.findi lines ~f:(fun _i line ->
    match heading_level_of_line line with
    | None -> false
    | Some _ ->
      (* Strip leading '#'s and space, then slugify. *)
      let text =
        String.lstrip line ~drop:(fun c -> Char.equal c '#')
        |> String.lstrip ~drop:(fun c -> Char.equal c ' ')
      in
      String.equal (Oystermark.Parse.Common.heading_id_of_text text) slug)
  |> Option.map ~f:(fun (i, line) ->
    let level = heading_level_of_line line |> Option.value_exn in
    i, level)
;;

(** {2 Formatting} *)

(** Build the hover string: path header, separator, then body.
    If [body] is empty, shows [*(empty)*] instead. *)
let format_hover ~(path : string) (body : string) : string =
  let header = "*Path*:" ^ path in
  if String.is_empty (String.strip body)
  then header ^ "\n\n*(empty)*"
  else header ^ "\n\n" ^ body
;;

(** {2 Main computation} *)

(** Compute hover content for the link at the given position.

    Returns [(markdown_string, first_byte, last_byte)] or [None] if
    there is no recognisable, readable link at the cursor.

    See {!page-"feature-hover"}. *)
let hover
      ?(config : Lsp_config.t = Lsp_config.default)
      ~(index : Oystermark.Vault.Index.t)
      ~(rel_path : string)
      ~(content : string)
      ~(line : int)
      ~(character : int)
      ~(read_file : string -> string option)
      ()
  : (string * int * int) option
  =
  Trace_core.with_span ~__FILE__ ~__LINE__ "hover"
  @@ fun _sp ->
  Trace_core.add_data_to_span
    _sp
    [ "rel_path", `String rel_path; "line", `Int line; "character", `Int character ];
  let offset = Lsp_util.byte_offset_of_position content ~line ~character in
  let doc = Lsp_util.parse_doc content in
  let links = Link_collect.collect_links doc in
  match Link_collect.find_at_offset links offset with
  | None -> None
  | Some link_ref ->
    let ll =
      List.find_exn links ~f:(fun ll -> ll.first_byte <= offset && offset <= ll.last_byte)
    in
    let target = Oystermark.Vault.Resolve.resolve link_ref rel_path index in
    (* Determine which file to read and which portion to extract. *)
    let result_opt =
      match target with
      | Oystermark.Vault.Resolve.Unresolved -> None
      | Note { path } | File { path } ->
        (match read_file path with
         | None -> None
         | Some file_content ->
           let body =
             match link_ref.fragment with
             | Some (Oystermark.Vault.Link_ref.Heading hs) ->
               (* Fragment present but resolve fell back — try to find section. *)
               let slug =
                 String.concat
                   ~sep:"-"
                   (List.map hs ~f:Oystermark.Parse.Common.heading_id_of_text)
               in
               (match find_heading_in_content ~slug file_content with
                | Some (hline, hlevel) ->
                  extract_section ~heading_line:hline ~heading_level:hlevel file_content
                | None -> file_content)
             | Some (Block_ref bid) ->
               (match extract_block ~block_id:bid file_content with
                | Some p -> p
                | None -> file_content)
             | None -> file_content
           in
           Some (path, body))
      | Heading { path; slug; _ } ->
        (match read_file path with
         | None -> None
         | Some file_content ->
           let body =
             match find_heading_in_content ~slug file_content with
             | Some (hline, hlevel) ->
               extract_section ~heading_line:hline ~heading_level:hlevel file_content
             | None -> file_content
           in
           Some (path, body))
      | Block { path; block_id } ->
        (match read_file path with
         | None -> None
         | Some file_content ->
           let body =
             match extract_block ~block_id file_content with
             | Some p -> p
             | None -> file_content
           in
           Some (path, body))
      | Attr { path; id; _ } ->
        (match read_file path with
         | None -> None
         | Some file_content ->
           let body =
             Option.value (extract_attr_block ~id file_content) ~default:file_content
           in
           Some (path, body))
      | Curr_file ->
        let body =
          match link_ref.fragment with
          | Some (Oystermark.Vault.Link_ref.Heading hs) ->
            let slug =
              String.concat
                ~sep:"-"
                (List.map hs ~f:Oystermark.Parse.Common.heading_id_of_text)
            in
            (match find_heading_in_content ~slug content with
             | Some (hline, hlevel) ->
               extract_section ~heading_line:hline ~heading_level:hlevel content
             | None -> content)
          | Some (Block_ref bid) ->
            (match extract_block ~block_id:bid content with
             | Some p -> p
             | None -> content)
          | None -> content
        in
        Some (rel_path, body)
      | Curr_heading { slug; _ } ->
        let body =
          match find_heading_in_content ~slug content with
          | Some (hline, hlevel) ->
            extract_section ~heading_line:hline ~heading_level:hlevel content
          | None -> content
        in
        Some (rel_path, body)
      | Curr_block { block_id } ->
        let body =
          match extract_block ~block_id content with
          | Some p -> p
          | None -> content
        in
        Some (rel_path, body)
      | Curr_attr { id; _ } ->
        let body = Option.value (extract_attr_block ~id content) ~default:content in
        Some (rel_path, body)
    in
    (* The budget applies to the body only: the path header is short,
       always useful, and must survive however small the budget is. *)
    Option.map result_opt ~f:(fun (path, body) ->
      let text = format_hover ~path (truncate ~max_chars:config.hover_max_chars body) in
      Trace_core.add_data_to_span _sp [ "content_bytes", `Int (String.length text) ];
      text, ll.first_byte, ll.last_byte)
;;

(** {1:test Test} *)

let%test_module "truncate" =
  (module struct
    let%expect_test "short string unchanged" =
      print_string (truncate ~max_chars:100 "hello\nworld");
      [%expect
        {|
        hello
        world
        |}]
    ;;

    let%expect_test "truncates at newline, reporting lines and percentage" =
      let s = "line one\nline two\nline three" in
      print_string (truncate ~max_chars:15 s);
      [%expect
        {|
        line one

        *(truncated: showing 1 of 3 lines, 33%)* |}]
    ;;

    (* The remainder is a single long line, so line counts would say
       "1 of 2, 50%" while hiding almost everything.  Report bytes. *)
    let%expect_test "single long remainder reports bytes" =
      let s = "head\n" ^ String.make 4000 'x' in
      print_string (truncate ~max_chars:100 s);
      [%expect
        {|
        head

        *(truncated: showing 4 B of 4 KB, 1%)* |}]
    ;;

    (* No newline at all: nothing to snap back to, cut at the budget. *)
    let%expect_test "no newline reports bytes" =
      print_string (truncate ~max_chars:10 (String.make 40 'y'));
      [%expect
        {|
        yyyyyyyyyy

        *(truncated: showing 10 B of 40 B, 25%)* |}]
    ;;

    (* Truncation happened, so neither 0% nor 100% may be reported:
       a sliver of a huge note is 1%, and all-but-a-sliver is 99%. *)
    let%expect_test "percentage is clamped away from the extremes" =
      let notice s = List.last_exn (String.split_lines s) in
      let many =
        List.init 500 ~f:(fun i -> sprintf "line %d" i) |> String.concat ~sep:"\n"
      in
      print_endline (notice (truncate ~max_chars:20 many));
      let one_line = String.make 10_000 'z' in
      print_endline (notice (truncate ~max_chars:9_999 one_line));
      [%expect
        {|
        *(truncated: showing 2 of 500 lines, 1%)*
        *(truncated: showing 10 KB of 10 KB, 99%)*
        |}]
    ;;
  end)
;;

let%test_module "extract_section" =
  (module struct
    let content =
      "# Title\n\nIntro.\n\n## Section One\n\nBody one.\n\n## Section Two\n\nBody two.\n"
    ;;

    let%expect_test "extracts first section" =
      print_string (extract_section ~heading_line:4 ~heading_level:2 content);
      [%expect
        {|
        ## Section One

        Body one.
         |}]
    ;;

    let%expect_test "top-level heading stops at next h1" =
      print_string (extract_section ~heading_line:0 ~heading_level:1 content);
      [%expect
        {|
        # Title

        Intro.

        ## Section One

        Body one.

        ## Section Two

        Body two.
        |}]
    ;;
  end)
;;

let%test_module "extract_block" =
  (module struct
    let content = "First para.\n\nSecond para ^abc\n\nThird para.\n"

    let%expect_test "finds block" =
      print_s [%sexp (extract_block ~block_id:"abc" content : string option)];
      [%expect {| ("Second para ^abc") |}]
    ;;

    let%expect_test "missing block returns None" =
      print_s [%sexp (extract_block ~block_id:"nope" content : string option)];
      [%expect {| () |}]
    ;;
  end)
;;

let%test_module "format_hover" =
  (module struct
    let%expect_test "with content" =
      print_string (format_hover ~path:"dir/note.md" "# Hello\n\nWorld.\n");
      [%expect
        {|
        *Path*:dir/note.md

        # Hello

        World.
        |}]
    ;;

    let%expect_test "empty content" =
      print_string (format_hover ~path:"dir/empty.md" "");
      [%expect
        {|
        *Path*:dir/empty.md

        *(empty)*
        |}]
    ;;

    let%expect_test "whitespace-only content" =
      print_string (format_hover ~path:"dir/blank.md" "  \n\n  ");
      [%expect
        {|
        *Path*:dir/blank.md

        *(empty)*
        |}]
    ;;
  end)
;;

let%test_module "hover" =
  (module struct
    let files =
      [ ( "note-a.md"
        , "# Alpha\n\n## Section One\n\nBody text. ^block1\n\n## Section Two\n\nMore.\n" )
      ; "note-b.md", "# Beta\n\nSee [[note-a]].\n"
      ; "note-c.md", "# Gamma\n\nSee [[note-a#Section One]].\n"
      ; "note-d.md", "# Delta\n\nSee [[note-a#^block1]].\n"
      ; "note-e.md", "# Epsilon\n\nSelf [[#Epsilon]].\n"
      ; "empty.md", ""
      ; "note-f.md", "# Zeta\n\nSee [[empty]].\n"
      ; "note-g.md", "# Eta\n\nThe [key term]{#kt} matters here.\n"
      ; "note-h.md", "# Theta\n\nSee [[note-g#kt]].\n"
      ]
    ;;

    let make_index files =
      let md_docs =
        List.filter_map files ~f:(fun (rel_path, content) ->
          if String.is_suffix rel_path ~suffix:".md"
          then Some (rel_path, Oystermark.Parse.of_string content)
          else None)
      in
      Oystermark.Vault.build_index ~md_docs ~other_files:[] ~dirs:[]
    ;;

    let index = make_index files
    let read_file rp = List.Assoc.find files ~equal:String.equal rp

    let show ~rel_path ~content ~line ~character =
      match hover ~index ~rel_path ~content ~line ~character ~read_file () with
      | None -> print_endline "<none>"
      | Some (text, fb, lb) -> printf "[%d-%d]\n%s\n" fb lb text
    ;;

    let%expect_test "plain note link" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-b.md" in
      show ~rel_path:"note-b.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [12-21]
        *Path*:note-a.md

        # Alpha

        ## Section One

        Body text. ^block1

        ## Section Two

        More.
        |}]
    ;;

    let%expect_test "heading fragment" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-c.md" in
      show ~rel_path:"note-c.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [13-34]
        *Path*:note-a.md

        ## Section One

        Body text. ^block1
        |}]
    ;;

    let%expect_test "block fragment" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-d.md" in
      show ~rel_path:"note-d.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [13-30]
        *Path*:note-a.md

        Body text. ^block1
        |}]
    ;;

    let%expect_test "self-referencing heading" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-e.md" in
      show ~rel_path:"note-e.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [16-27]
        *Path*:note-e.md

        # Epsilon

        Self [[#Epsilon]].
        |}]
    ;;

    (* Hovering a link to an inline attribute anchor shows the containing
       block. See {!page-"feature-attribute-anchors"}. *)
    let%expect_test "attribute-anchor fragment" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-h.md" in
      show ~rel_path:"note-h.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [13-25]
        *Path*:note-g.md

        The key term{#kt} matters here.
        |}]
    ;;

    let%expect_test "empty target note" =
      let content = List.Assoc.find_exn files ~equal:String.equal "note-f.md" in
      show ~rel_path:"note-f.md" ~content ~line:2 ~character:8;
      [%expect
        {|
        [12-20]
        *Path*:empty.md

        *(empty)*
        |}]
    ;;

    let%expect_test "unresolved link returns none" =
      let content = "See [[missing]]." in
      show ~rel_path:"note-b.md" ~content ~line:0 ~character:6;
      [%expect {| <none> |}]
    ;;

    let%expect_test "cursor outside link returns none" =
      let content = "See [[note-a]]." in
      show ~rel_path:"note-b.md" ~content ~line:0 ~character:0;
      [%expect {| <none> |}]
    ;;

    let%expect_test "truncation" =
      let config = { Lsp_config.default with hover_max_chars = 30 } in
      let content = List.Assoc.find_exn files ~equal:String.equal "note-b.md" in
      (match
         hover
           ~config
           ~index
           ~rel_path:"note-b.md"
           ~content
           ~line:2
           ~character:8
           ~read_file
           ()
       with
       | None -> print_endline "<none>"
       | Some (text, _, _) -> print_string text);
      [%expect
        {|
        *Path*:note-a.md

        # Alpha

        ## Section One


        *(truncated: showing 3 of 9 lines, 33%)*
        |}]
    ;;
  end)
;;
