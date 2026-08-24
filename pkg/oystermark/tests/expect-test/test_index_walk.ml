(** What the vault walk lists.
    Impl: {!Oystermark.Vault.Fs_utils.walk}.

    The tree is built at run time rather than checked in under [data/]: dune
    does not copy dot-directories into the build tree, and dot-directories are
    the whole point of this test. *)

open Core

(** Build [files] under a fresh temporary root, list the vault's entries, and
    clean up. *)
let list_entries ?(exclude = []) (files : string list) : string list =
  let root = Core_unix.mkdtemp "/tmp/oystermark-vault-walk-" in
  List.iter files ~f:(fun rel ->
    let full = Filename.concat root rel in
    Core_unix.mkdir_p (Filename.dirname full);
    Out_channel.write_all full ~data:"# Note\n");
  Exn.protect
    ~f:(fun () ->
      Oystermark.Vault.Fs_utils.walk
        ~root
        ~exclude:(Oystermark.Vault.Fs_utils.Exclude.of_patterns exclude)
        ()
      |> List.sort ~compare:String.compare)
    ~finally:(fun () ->
      let (_ : Core_unix.Exit_or_signal.t) =
        Core_unix.system (sprintf "rm -rf %s" (Filename.quote root))
      in
      ())
;;

(* A leading dot marks a directory as tooling state rather than notes — an
   editor's, a version control system's, a language's — and there are far more
   of those than a list could name. A vault that keeps notes under one loses
   them from the index; the exclusion is by rule because guessing which dot is
   which is worse than the rule. *)
let%expect_test "dot-directories are not notes" =
  list_entries
    [ "top.md"
    ; ".a/b.md"
    ; ".a/nested/d.md"
    ; ".git/config"
    ; ".obsidian/app.json"
    ; ".oyster/cache.json"
    ; ".trash/deleted.md"
    ; ".DS_Store"
    ]
  |> List.iter ~f:print_endline;
  [%expect {| top.md |}]
;;

(* Build outputs and dependency trees hold no notes and dwarf the vault that
   contains them: a workspace with a [node_modules] indexes more Markdown from
   its dependencies than from itself. *)
let%expect_test "build and dependency directories are not notes" =
  list_entries
    [ "top.md"
    ; "node_modules/pkg/README.md"
    ; "_build/default/doc.md"
    ; "target/debug/notes.md"
    ; "dist/bundle.md"
    ; "notes/deep.md"
    ]
  |> List.iter ~f:print_endline;
  [%expect
    {|
    notes/
    notes/deep.md
    top.md
    |}]
;;

(* What the walk leaves out by rule is fixed; what a vault leaves out is its
   own business. See {!Oystermark.Vault.Fs_utils.Exclude}. *)
let%expect_test "configured patterns" =
  let files =
    [ "top.md"
    ; "drafts/one.md"
    ; "notes/drafts/two.md"
    ; "notes/keep.md"
    ; "archive/2020/old.md"
    ; "scratch.tmp.md"
    ]
  in
  let show exclude =
    printf "%s\n" (String.concat ~sep:" " exclude);
    List.iter (list_entries ~exclude files) ~f:(printf "  %s\n")
  in
  (* Unanchored: every [drafts], at any depth, and its subtree with it. *)
  show [ "drafts" ];
  (* Anchored at the vault root: the other [drafts] stays. *)
  show [ "/drafts" ];
  (* Globs match within one component; [**] spans components. *)
  show [ "*.tmp.md"; "archive/**/old.md" ];
  (* A pattern naming nothing excludes nothing — it must not excise the
     vault. *)
  show [ "/"; "." ];
  [%expect
    {|
    drafts
      archive/
      archive/2020/
      archive/2020/old.md
      notes/
      notes/keep.md
      scratch.tmp.md
      top.md
    /drafts
      archive/
      archive/2020/
      archive/2020/old.md
      notes/
      notes/drafts/
      notes/drafts/two.md
      notes/keep.md
      scratch.tmp.md
      top.md
    *.tmp.md archive/**/old.md
      archive/
      archive/2020/
      drafts/
      drafts/one.md
      notes/
      notes/drafts/
      notes/drafts/two.md
      notes/keep.md
      top.md
    / .
      archive/
      archive/2020/
      archive/2020/old.md
      drafts/
      drafts/one.md
      notes/
      notes/drafts/
      notes/drafts/two.md
      notes/keep.md
      scratch.tmp.md
      top.md
    |}]
;;
