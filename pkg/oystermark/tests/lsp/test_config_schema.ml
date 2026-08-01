(** Spec: {!page-"feature-configuration".schema_file}.
    Impl: [lsp/oysterlsp.schema.json] and {!Lsp_lib.Config}.

    The published schema is a second statement of what the parser accepts, and
    two statements drift. These tests make drift fail: the schema's keys and
    {!Lsp_lib.Config.known_keys} must agree, and every key in that inventory
    must be one the parser really knows — a name in a list proves nothing on
    its own. *)

open Core
module Config = Lsp_lib.Config

let schema_path = "../../lsp/oysterlsp.schema.json"
let schema () : Yojson.Safe.t = Yojson.Safe.from_string (In_channel.read_all schema_path)

(** Every dotted leaf key the schema declares, [$schema] aside: it is an
    editor association rather than a setting, and {!Config.known_keys} does not
    list it. *)
let schema_keys () : string list =
  let properties (j : Yojson.Safe.t) =
    match j with
    | `Assoc fields ->
      (match List.Assoc.find fields "properties" ~equal:String.equal with
       | Some (`Assoc props) -> props
       | _ -> [])
    | _ -> []
  in
  properties (schema ())
  |> List.concat_map ~f:(fun (section, sub) ->
    match properties sub with
    | [] -> if String.equal section "$schema" then [] else [ section ]
    | leaves -> List.map leaves ~f:(fun (leaf, _) -> section ^ "." ^ leaf))
  |> List.sort ~compare:String.compare
;;

(* A key in the schema that the parser does not accept would be advertised
   completion for a setting that does nothing; a key the parser accepts but
   the schema omits would be flagged as invalid in the user's editor. Both
   directions are failures, so compare the sets. *)
let%expect_test "the schema and the parser accept the same keys" =
  let inventory = List.sort Config.known_keys ~compare:String.compare in
  let schema = schema_keys () in
  let missing =
    List.filter inventory ~f:(fun k -> not (List.mem schema k ~equal:String.equal))
  in
  let extra =
    List.filter schema ~f:(fun k -> not (List.mem inventory k ~equal:String.equal))
  in
  printf "in the parser, not the schema: %s\n" (String.concat ~sep:", " missing);
  printf "in the schema, not the parser: %s\n" (String.concat ~sep:", " extra);
  [%expect
    {|
    in the parser, not the schema:
    in the schema, not the parser:
    |}]
;;

(* [known_keys] is hand-written beside a hand-written parser, so it could
   name a key that no longer exists. Feeding each key a value of deliberately
   wrong type distinguishes the two failures the parser reports: a key it
   knows complains about the value, an unknown one complains about the key. *)
let%expect_test "every inventoried key is one the parser knows" =
  List.iter Config.known_keys ~f:(fun key ->
    let json =
      match String.split key ~on:'.' with
      | [ section; leaf ] -> `Assoc [ section, `Assoc [ leaf, `List [] ] ]
      | _ -> `Assoc [ key, `List [] ]
    in
    let _, warnings = Config.parse json in
    let unknown =
      List.exists warnings ~f:(fun w -> String.is_substring w ~substring:"unknown key")
    in
    if unknown then printf "%s: not known to the parser\n" key);
  [%expect {| |}]
;;

(* The URL is written twice — as the schema's own [$id] and as the value
   [--print-default-config] emits — and an emitted association pointing
   somewhere the schema does not claim to be is a broken association. It must
   also be a raw URL: a github.com/blob link serves HTML, which a JSON
   language server cannot read. *)
let%expect_test "the emitted association matches the schema's own $id" =
  let id =
    match schema () with
    | `Assoc fields ->
      (match List.Assoc.find fields "$id" ~equal:String.equal with
       | Some (`String s) -> s
       | _ -> "<none>")
    | _ -> "<none>"
  in
  printf "same: %b\n" (String.equal id Config.schema_url);
  printf
    "raw host: %b\n"
    (String.is_prefix id ~prefix:"https://raw.githubusercontent.com/");
  [%expect
    {|
    same: true
    raw host: true
    |}]
;;

(* The association line the schema exists to be reached by must not itself be
   reported as a stray setting. *)
let%expect_test "$schema is accepted and is not a setting" =
  let config, warnings =
    Config.parse
      (`Assoc
          [ "$schema", `String "https://oystermark.dev/oysterlsp.schema.json"
          ; "hover", `Assoc [ "maxChars", `Int 40 ]
          ])
  in
  printf "warnings: %d\n" (List.length warnings);
  printf "maxChars: %d\n" (Config.resolve config).hover_max_chars;
  [%expect
    {|
    warnings: 0
    maxChars: 40
    |}]
;;

(* What [--print-default-config] hands over has to be a file this server
   accepts: defaults in, defaults out, no warnings. *)
let%expect_test "the emitted default config round-trips" =
  let json = Config.to_json Config.default in
  let parsed, warnings = Config.parse json in
  printf "warnings: %s\n" (String.concat ~sep:"; " warnings);
  printf "same as default: %b\n" (Config.equal (Config.resolve parsed) Config.default);
  [%expect
    {|
    warnings:
    same as default: true
    |}]
;;
