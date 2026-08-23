(** Addressing a code block by its djot attribute id, and reading its text.
    Impl: {!Oystermark.Parse.Extract.code_of_block}. Spec:
    {!page-"template-context-example"}.

    This is what [oyster block] is built on: a build system extracts one block
    by id and pipes it to an interpreter. *)

open Core
module Extract = Oystermark.Parse.Extract

let blocks_of_string (s : string) : Cmarkit.Block.t list =
  match Cmarkit.Doc.block (Oystermark.Parse.of_string ~locs:true s) with
  | Cmarkit.Block.Blocks (blocks, _) -> blocks
  | block -> [ block ]
;;

(** Print what [oyster block] would print for [id], or the error it would
    report. *)
let extract (s : string) (id : string) =
  let blocks = blocks_of_string s in
  match Extract.get_block_by_attr_id blocks id with
  | None -> printf "<no block with id %s>\n" id
  | Some block ->
    (match Extract.code_of_block block with
     | None -> printf "<block %s is not a code block>\n" id
     | Some code ->
       printf
         "lang=%s\n%s\n"
         (Option.value (Extract.info_string_of_block block) ~default:"<none>")
         code)
;;

let%expect_test "the id selects the block, not its position" =
  extract
    {|
```python
print("first")
```

{#wanted}
```python
print("second")
```

```python
print("third")
```
|}
    "wanted";
  [%expect
    {|
    lang=python
    print("second")
    |}]
;;

let%expect_test "a code block keeps its indentation and blank lines" =
  extract
    {|
{#script}
```python
def f():
    if True:

        return 1
```
|}
    "script";
  [%expect
    {|
    lang=python
    def f():
        if True:

            return 1
    |}]
;;

let%expect_test "an unknown id, and an id on something that is not code" =
  let doc =
    {|
{#prose}
Just a paragraph.

{#code}
```sh
echo hi
```
|}
  in
  extract doc "missing";
  extract doc "prose";
  extract doc "code";
  [%expect
    {|
    <no block with id missing>
    <block prose is not a code block>
    lang=sh
    echo hi
    |}]
;;

let%expect_test "a fence with no info string has no language to assert on" =
  extract
    {|
{#bare}
```
some text
```
|}
    "bare";
  [%expect
    {|
    lang=<none>
    some text
    |}]
;;
