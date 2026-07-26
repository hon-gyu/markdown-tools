(** Daily notes: date formats, path computation, and recognition.

    The pure layer of {!page-"feature-daily-notes"}: everything here is a
    function of a settings record and a date. Nothing reads the clock — "today"
    is always passed in — so results are deterministic and testable.

    Spec: {!page-"feature-daily-notes"}. *)

open Core

(** {1:format Date format}

    A subset of the moment.js tokens, per
    {!page-"feature-daily-notes".format}. *)

module Format = struct
  (** One element of a parsed format string. *)
  type piece =
    | Year4 (** [YYYY] *)
    | Year2 (** [YY] *)
    | Month2 (** [MM] *)
    | Month (** [M] *)
    | Month_abbr (** [MMM] *)
    | Month_name (** [MMMM] *)
    | Day2 (** [DD] *)
    | Day (** [D] *)
    | Day_ordinal (** [Do] *)
    | Weekday_abbr (** [ddd] *)
    | Weekday_name (** [dddd] *)
    | Literal of string
  [@@deriving sexp_of]

  type t =
    { pieces : piece list
    ; source : string (** The format as written, for round-tripping settings. *)
    }
  [@@deriving sexp_of]

  (** Recognized tokens, longest first so that [MMMM] is not read as [MMM]
      followed by a stray [M]. *)
  let tokens =
    [ "MMMM", Month_name
    ; "dddd", Weekday_name
    ; "YYYY", Year4
    ; "MMM", Month_abbr
    ; "ddd", Weekday_abbr
    ; "YY", Year2
    ; "MM", Month2
    ; "DD", Day2
    ; "Do", Day_ordinal
    ; "M", Month
    ; "D", Day
    ]
  ;;

  (* Characters a path component may not contain.  ['/'] is absent on purpose:
     a format may nest the note in folders.  Mirrors the validation Obsidian's
     settings tab applies. *)
  let illegal_chars = [ '*'; '"'; '\\'; '<'; '>'; ':'; '|'; '?' ]

  let matches_token (s : string) ~(pos : int) : (string * piece) option =
    List.find tokens ~f:(fun (tok, _) ->
      String.length tok <= String.length s - pos
      && String.equal tok (String.sub s ~pos ~len:(String.length tok)))
  ;;

  (** Split [s] into pieces.  Errors on an unsupported alphabetic token rather
      than treating it as a literal: silently naming the wrong file is the one
      outcome worth failing over. *)
  let parse_pieces (s : string) : (piece list, string) Result.t =
    let len = String.length s in
    let rec loop pos acc =
      if pos >= len
      then Ok (List.rev acc)
      else (
        match s.[pos] with
        (* [ ... ] is literal text. *)
        | '[' ->
          (match String.index_from s pos ']' with
           | None -> Error "unterminated [ in format"
           | Some close ->
             let text = String.sub s ~pos:(pos + 1) ~len:(close - pos - 1) in
             loop (close + 1) (Literal text :: acc))
        | c ->
          (match matches_token s ~pos with
           | Some (tok, piece) -> loop (pos + String.length tok) (piece :: acc)
           | None ->
             if Char.is_alpha c
             then Error (sprintf "unsupported format token %C" c)
             else loop (pos + 1) (Literal (String.of_char c) :: acc)))
    in
    loop 0 []
  ;;

  let month_names =
    [| "January"
     ; "February"
     ; "March"
     ; "April"
     ; "May"
     ; "June"
     ; "July"
     ; "August"
     ; "September"
     ; "October"
     ; "November"
     ; "December"
    |]
  ;;

  let weekday_names =
    [| "Sunday"; "Monday"; "Tuesday"; "Wednesday"; "Thursday"; "Friday"; "Saturday" |]
  ;;

  (** English ordinal suffix: [1st], [2nd], [3rd], [4th], and the [11th]–[13th]
      exception. *)
  let ordinal (n : int) : string =
    let suffix =
      if n % 100 >= 11 && n % 100 <= 13
      then "th"
      else (
        match n % 10 with
        | 1 -> "st"
        | 2 -> "nd"
        | 3 -> "rd"
        | _ -> "th")
    in
    Int.to_string n ^ suffix
  ;;

  let render_piece (piece : piece) (date : Date.t) : string =
    let month = Month.to_int (Date.month date) in
    let day = Date.day date in
    let year = Date.year date in
    match piece with
    | Year4 -> sprintf "%04d" year
    | Year2 -> sprintf "%02d" (year % 100)
    | Month2 -> sprintf "%02d" month
    | Month -> Int.to_string month
    | Month_abbr -> String.sub month_names.(month - 1) ~pos:0 ~len:3
    | Month_name -> month_names.(month - 1)
    | Day2 -> sprintf "%02d" day
    | Day -> Int.to_string day
    | Day_ordinal -> ordinal day
    | Weekday_abbr ->
      String.sub weekday_names.(Day_of_week.to_int (Date.day_of_week date)) ~pos:0 ~len:3
    | Weekday_name -> weekday_names.(Day_of_week.to_int (Date.day_of_week date))
    | Literal s -> s
  ;;

  let render_pieces (pieces : piece list) (date : Date.t) : string =
    String.concat (List.map pieces ~f:(fun p -> render_piece p date))
  ;;

  (** A reference date used to check what a format produces.  Every field
      differs from every other, so a rendering mistake shows up as a wrong
      component rather than a coincidence. *)
  let probe_date = Date.create_exn ~y:2026 ~m:Month.Jul ~d:6

  (** [of_string s] validates [s] as a daily-note format.  Rejects, per
      {!page-"feature-daily-notes".format}: unsupported tokens, a leading [/],
      an empty result, and text illegal in a path. *)
  let of_string (s : string) : (t, string) Result.t =
    if String.is_prefix s ~prefix:"/"
    then Error "format must not start with /"
    else (
      match parse_pieces s with
      | Error _ as e -> e
      | Ok pieces ->
        let rendered = String.strip (render_pieces pieces probe_date) in
        if String.is_empty rendered
        then Error "format produces an empty name"
        else (
          match
            String.find rendered ~f:(fun c -> List.mem illegal_chars c ~equal:Char.equal)
          with
          | Some c -> Error (sprintf "format produces %C, illegal in a path" c)
          | None -> Ok { pieces; source = s }))
  ;;

  let to_string (t : t) : string = t.source

  (** The note name for [date] — the path without the [.md] suffix.  Trimmed,
      as Obsidian trims. *)
  let render (t : t) (date : Date.t) : string = String.strip (render_pieces t.pieces date)
end

(** {1 Settings}

    See {!page-"feature-daily-notes"}. Sourced from LSP
    [initializationOptions]; this module only consumes the resolved record. *)

type settings =
  { format : Format.t
  ; folder : string option (** [None] is the vault root. *)
  ; template : string option
    (** Carried but unused: template support is stubbed, per
        {!page-"feature-daily-notes".limitations}. *)
  }

let default_format = Format.of_string "YYYY-MM-DD" |> Result.ok_or_failwith
let default_settings = { format = default_format; folder = None; template = None }

(** [path_of_date settings date] is the vault-relative path of [date]'s note.
    The format may contain [/], so the result may name folders that do not
    exist yet. *)
let path_of_date (settings : settings) (date : Date.t) : string =
  let name = Format.render settings.format date ^ ".md" in
  match settings.folder with
  | None | Some "" -> name
  | Some folder -> Filename.concat (String.rstrip folder ~drop:(Char.equal '/')) name
;;

(** {1:recognition Recognition}

    Path-to-date is the inverse of {!path_of_date}, obtained by generating
    every date in a window and tabulating what it renders to, rather than by
    parsing.  The table cannot disagree with the formatter — which a
    hand-written strict parser could.  See
    {!page-"feature-daily-notes".recognition}. *)

module Table = struct
  type t =
    { by_path : Date.t String.Table.t
    ; dates : Date.t array (** Ascending; the window, for prev/next scans. *)
    ; settings : settings
    }

  let default_window_years = 5

  (** [create settings ~today] tabulates [today ± window_years].  When a format
      lacks a day token, several dates render to one path; the earliest wins,
      which keeps recognition deterministic. *)
  let create
        ?(window_years = default_window_years)
        (settings : settings)
        ~(today : Date.t)
    : t
    =
    let first = Date.add_years today (-window_years) in
    let last = Date.add_years today window_years in
    let dates =
      let rec loop d acc =
        if Date.(d > last) then acc else loop (Date.add_days d 1) (d :: acc)
      in
      loop first [] |> List.rev |> Array.of_list
    in
    let by_path = String.Table.create () in
    Array.iter dates ~f:(fun d ->
      let path = path_of_date settings d in
      match Hashtbl.find by_path path with
      | Some _ -> ()
      | None -> Hashtbl.set by_path ~key:path ~data:d);
    { by_path; dates; settings }
  ;;

  (** [date_of_path t path] is the date [path] names, or [None] when it is not
      a daily note.  A note dated outside the window is not recognized; see
      {!page-"feature-daily-notes".recognition}. *)
  let date_of_path (t : t) (path : string) : Date.t option = Hashtbl.find t.by_path path

  let is_daily_note (t : t) (path : string) : bool = Option.is_some (date_of_path t path)

  (** [previous_existing t ~exists date] is the latest daily note strictly
      before [date] whose file exists, with its path.  Never creates anything —
      this is Obsidian's [daily-notes:goto-prev]. *)
  let previous_existing (t : t) ~(exists : string -> bool) (date : Date.t)
    : (Date.t * string) option
    =
    Array.fold_until
      t.dates
      ~init:None
      ~f:(fun acc d ->
        if Date.(d >= date)
        then Stop acc
        else (
          let path = path_of_date t.settings d in
          if exists path then Continue (Some (d, path)) else Continue acc))
      ~finish:Fn.id
  ;;

  (** [next_existing t ~exists date] is the earliest daily note strictly after
      [date] whose file exists. *)
  let next_existing (t : t) ~(exists : string -> bool) (date : Date.t)
    : (Date.t * string) option
    =
    Array.find_map t.dates ~f:(fun d ->
      if Date.(d <= date)
      then None
      else (
        let path = path_of_date t.settings d in
        if exists path then Some (d, path) else None))
  ;;
end

(** {1:test Test} *)

let%test_module "daily_notes" =
  (module struct
    let fmt_exn s = Format.of_string s |> Result.ok_or_failwith
    let date y m d = Date.create_exn ~y ~m:(Month.of_int_exn m) ~d

    (** {2 Formatting}

        See {!page-"feature-daily-notes".format}. *)

    let%expect_test "supported tokens" =
      let d = date 2026 7 6 in
      List.iter
        [ "YYYY-MM-DD"
        ; "YYYY/MM/YYYY-MM-DD"
        ; "YY-M-D"
        ; "MMMM D, YYYY"
        ; "MMM D"
        ; "dddd"
        ; "ddd"
        ; "Do MMMM YYYY"
        ; "[Daily] YYYY-MM-DD"
        ; "YYYY-MM-DD [note]"
        ]
        ~f:(fun f -> printf "%-22s -> %s\n" f (Format.render (fmt_exn f) d));
      [%expect
        {|
        YYYY-MM-DD             -> 2026-07-06
        YYYY/MM/YYYY-MM-DD     -> 2026/07/2026-07-06
        YY-M-D                 -> 26-7-6
        MMMM D, YYYY           -> July 6, 2026
        MMM D                  -> Jul 6
        dddd                   -> Monday
        ddd                    -> Mon
        Do MMMM YYYY           -> 6th July 2026
        [Daily] YYYY-MM-DD     -> Daily 2026-07-06
        YYYY-MM-DD [note]      -> 2026-07-06 note
        |}]
    ;;

    let%expect_test "ordinals" =
      List.iter [ 1; 2; 3; 4; 11; 12; 13; 21; 22; 23; 31 ] ~f:(fun n ->
        printf "%s " (Format.ordinal n));
      [%expect {| 1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 31st |}]
    ;;

    (** {2 Rejection}

        An unsupported format disables the feature rather than naming a wrong
        file. *)

    let%expect_test "rejected formats" =
      List.iter
        [ "YYYY-ww" (* week token: does not identify a day *)
        ; "YYYY-MM-DD HH:mm" (* time tokens, and [:] is path-illegal *)
        ; "/YYYY-MM-DD"
        ; "YYYY[-MM-DD"
        ; "gggg"
        ]
        ~f:(fun f ->
          match Format.of_string f with
          | Ok _ -> printf "%-18s -> accepted\n" f
          | Error e -> printf "%-18s -> rejected: %s\n" f e);
      [%expect
        {|
        YYYY-ww            -> rejected: unsupported format token 'w'
        YYYY-MM-DD HH:mm   -> rejected: unsupported format token 'H'
        /YYYY-MM-DD        -> rejected: format must not start with /
        YYYY[-MM-DD        -> rejected: unterminated [ in format
        gggg               -> rejected: unsupported format token 'g'
        |}]
    ;;

    (** {2 Paths} *)

    let%expect_test "path_of_date" =
      let d = date 2026 7 6 in
      let show ?folder f =
        let s = { default_settings with format = fmt_exn f; folder } in
        printf
          "%-20s folder=%-8s -> %s\n"
          f
          (Option.value folder ~default:"-")
          (path_of_date s d)
      in
      show "YYYY-MM-DD";
      show "YYYY-MM-DD" ~folder:"journal";
      show "YYYY-MM-DD" ~folder:"journal/";
      show "YYYY/MM/YYYY-MM-DD" ~folder:"journal";
      show "MMMM D, YYYY" ~folder:"journal/daily";
      [%expect
        {|
        YYYY-MM-DD           folder=-        -> 2026-07-06.md
        YYYY-MM-DD           folder=journal  -> journal/2026-07-06.md
        YYYY-MM-DD           folder=journal/ -> journal/2026-07-06.md
        YYYY/MM/YYYY-MM-DD   folder=journal  -> journal/2026/07/2026-07-06.md
        MMMM D, YYYY         folder=journal/daily -> journal/daily/July 6, 2026.md
        |}]
    ;;

    (** {2 Recognition}

        See {!page-"feature-daily-notes".recognition}. *)

    let today = date 2026 7 26

    let table ?(folder : string option) (f : string) : Table.t =
      Table.create
        ~window_years:1
        { default_settings with format = fmt_exn f; folder }
        ~today
    ;;

    let%expect_test "date_of_path" =
      let t = table ~folder:"journal" "YYYY/MM/YYYY-MM-DD" in
      List.iter
        [ "journal/2026/07/2026-07-06.md"
        ; "journal/2026/07/2026-07-06" (* no extension *)
        ; "2026/07/2026-07-06.md" (* outside the folder *)
        ; "journal/2026/07/not-a-date.md"
        ; "journal/1999/01/1999-01-01.md" (* outside the window *)
        ]
        ~f:(fun p ->
          match Table.date_of_path t p with
          | Some d -> printf "%-32s -> %s\n" p (Date.to_string d)
          | None -> printf "%-32s -> not a daily note\n" p);
      [%expect
        {|
        journal/2026/07/2026-07-06.md    -> 2026-07-06
        journal/2026/07/2026-07-06       -> not a daily note
        2026/07/2026-07-06.md            -> not a daily note
        journal/2026/07/not-a-date.md    -> not a daily note
        journal/1999/01/1999-01-01.md    -> not a daily note
        |}]
    ;;

    (* Round-trip: rendering a date and recognizing the result must return the
       same date, for every date in the window and every supported format.
       This is the obligation that lets recognition skip a strict parser. *)
    let%test_unit "round-trip: path_of_date then date_of_path" =
      List.iter
        [ "YYYY-MM-DD"
        ; "YYYY/MM/YYYY-MM-DD"
        ; "MMMM D, YYYY"
        ; "Do MMM YY"
        ; "[d] YYYY-MM-DD"
        ]
        ~f:(fun f ->
          let t = table f in
          Array.iter t.Table.dates ~f:(fun d ->
            let path = path_of_date t.Table.settings d in
            [%test_result: Date.t option]
              ~message:(sprintf "format %s, date %s" f (Date.to_string d))
              (Table.date_of_path t path)
              ~expect:(Some d)))
    ;;

    (* A format with no day token maps a whole month to one note; the earliest
       date in the month wins, so recognition stays deterministic. *)
    let%expect_test "format without a day token" =
      let t = table "YYYY-MM" in
      print_s [%sexp (Table.date_of_path t "2026-07.md" : Date.t option)];
      [%expect {| (2026-07-01) |}]
    ;;

    (** {2 Previous / next existing}

        Calendar-independent: these skip gaps and never create. *)

    let%expect_test "previous and next skip gaps" =
      let t = table "YYYY-MM-DD" in
      let existing =
        String.Set.of_list [ "2026-07-03.md"; "2026-07-10.md"; "2026-07-26.md" ]
      in
      let exists p = Set.mem existing p in
      let show label = function
        | Some (d, p) -> printf "%-24s -> %s (%s)\n" label (Date.to_string d) p
        | None -> printf "%-24s -> none\n" label
      in
      show "prev of 07-10" (Table.previous_existing t ~exists (date 2026 7 10));
      show "next of 07-10" (Table.next_existing t ~exists (date 2026 7 10));
      show "prev of 07-03" (Table.previous_existing t ~exists (date 2026 7 3));
      show "next of 07-26" (Table.next_existing t ~exists (date 2026 7 26));
      show "prev of 07-05 (gap)" (Table.previous_existing t ~exists (date 2026 7 5));
      [%expect
        {|
        prev of 07-10            -> 2026-07-03 (2026-07-03.md)
        next of 07-10            -> 2026-07-26 (2026-07-26.md)
        prev of 07-03            -> none
        next of 07-26            -> none
        prev of 07-05 (gap)      -> 2026-07-03 (2026-07-03.md)
        |}]
    ;;

    let%expect_test "is_daily_note" =
      let t = table ~folder:"journal" "YYYY-MM-DD" in
      printf
        "%b %b\n"
        (Table.is_daily_note t "journal/2026-07-26.md")
        (Table.is_daily_note t "notes/idea.md");
      [%expect {| true false |}]
    ;;
  end)
;;
