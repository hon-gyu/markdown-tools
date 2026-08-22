(** What the vault walk lists.
    Impl: {!Oystermark.Vault.Fs_utils.walk}.

    The tree is built at run time rather than checked in under [data/]: dune
    does not copy dot-directories into the build tree, and dot-directories are
    the whole point of this test. *)

open Core

(** Build [files] under a fresh temporary root, list the vault's entries, and
    clean up. *)
let list_entries (files : string list) : string list =
  let root = Core_unix.mkdtemp "/tmp/oystermark-vault-walk-" in
  List.iter files ~f:(fun rel ->
    let full = Filename.concat root rel in
    Core_unix.mkdir_p (Filename.dirname full);
    Out_channel.write_all full ~data:"# Note\n");
  Exn.protect
    ~f:(fun () -> Oystermark.Vault.Fs_utils.walk ~root () |> List.sort ~compare:String.compare)
    ~finally:(fun () ->
      let (_ : Core_unix.Exit_or_signal.t) =
        Core_unix.system (sprintf "rm -rf %s" (Filename.quote root))
      in
      ())
;;

(* A directory whose name begins with a [.] is one the author named that way,
   and the notes inside it are notes. Only the directories that hold tooling
   state are skipped, by name. *)
let%expect_test "dot-directories are notes; tooling directories are not" =
  list_entries
    [ "top.md"
    ; ".a/b.md"
    ; ".a/c.md"
    ; ".a/nested/d.md"
    ; ".git/config"
    ; ".obsidian/app.json"
    ; ".obsidian/plugins/thing/main.js"
    ; ".oyster/cache.json"
    ; ".trash/deleted.md"
    ; ".DS_Store"
    ]
  |> List.iter ~f:print_endline;
  [%expect
    {|
    .a/
    .a/b.md
    .a/c.md
    .a/nested/
    .a/nested/d.md
    top.md
    |}]
;;
