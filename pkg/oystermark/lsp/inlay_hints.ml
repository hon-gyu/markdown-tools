(** Inlay hints: direction arrows on intra-note links.

    Spec: {!page-"feature-inlay-hints-link-direction"}.  This module is the
    place the [textDocument/inlayHint] response is assembled; the arrows
    themselves are {!Link_direction}'s.  Reference counts used to be assembled
    here too, and are now lenses — see
    {!page-"feature-codelens-reference-counts"}. *)

open Core

(** {1:implementation Implementation} *)

(** A single inlay hint: position and label text. *)
type hint =
  { line : int
  ; character : int
  ; label : string
  }
[@@deriving sexp, equal, compare]

(** Compute inlay hints for [rel_path] within the given line range.

    [index] is the vault index the arrows resolve against; omitting it leaves
    them out — a caller with no index has no directions to report.

    See {!page-"feature-inlay-hints-link-direction"}. *)
let inlay_hints
      ?(config : Lsp_config.t = Lsp_config.default)
      ?(index : Oystermark.Vault.Index.t option)
      ~(rel_path : string)
      ~(content : string)
      ~(range_start_line : int)
      ~(range_end_line : int)
      ()
  : hint list
  =
  Trace_core.with_span ~__FILE__ ~__LINE__ "inlay_hints"
  @@ fun _sp ->
  Trace_core.add_data_to_span
    _sp
    [ "rel_path", `String rel_path
    ; "range_start", `Int range_start_line
    ; "range_end", `Int range_end_line
    ];
  (* Computed from [content]: the arrows are about where things are in {e this}
     note, which is what [content] is.
     See {!page-"feature-inlay-hints-link-direction"}. *)
  let result =
    match config.inlay_link_direction, index with
    | false, _ | _, None -> []
    | true, Some index ->
      Link_direction.hints ~index ~rel_path ~content ~range_start_line ~range_end_line ()
      |> List.map ~f:(fun (h : Link_direction.hint) ->
        { line = h.line; character = h.character; label = h.label })
  in
  Trace_core.add_data_to_span _sp [ "num_hints", `Int (List.length result) ];
  result
;;

(** {1:test Test} *)

let%test_module "inlay_hints" =
  (module struct
    (* What the arrows say is {!Link_direction}'s to test; what is checked here
       is the assembly — that the response carries them, and that the two ways
       of having no index or no arrows both come out empty rather than
       raising. *)
    let files =
      [ "moc.md", "- [[#below]]\n\n# Below\n\nBack up [[#Below]].\n"
      ; "plain.md", "# Plain\n\nA link to [[moc]] and nothing inward.\n"
      ]
    ;;

    let index, _docs = Find_references.For_test.make_vault files

    let show ?config ?(index = index) rel_path =
      let content = List.Assoc.find_exn files ~equal:String.equal rel_path in
      inlay_hints
        ?config
        ~index
        ~rel_path
        ~content
        ~range_start_line:0
        ~range_end_line:100
        ()
      |> List.iter ~f:(fun h -> printf "(%d,%d) %s\n" h.line h.character h.label)
    ;;

    let%expect_test "arrows on intra-note links" =
      show "moc.md";
      [%expect
        {|
        (0,12) ↓2
        (4,18) ↑2
        |}]
    ;;

    let%expect_test "a note with no intra-note links" =
      show "plain.md";
      [%expect {| |}]
    ;;

    let%expect_test "switched off" =
      show ~config:{ Lsp_config.default with inlay_link_direction = false } "moc.md";
      [%expect {| |}]
    ;;

    let%expect_test "no index, no arrows" =
      let content = List.Assoc.find_exn files ~equal:String.equal "moc.md" in
      inlay_hints ~rel_path:"moc.md" ~content ~range_start_line:0 ~range_end_line:100 ()
      |> List.length
      |> printf "%d hints\n";
      [%expect {| 0 hints |}]
    ;;
  end)
;;
