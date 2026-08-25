type note =
  { path : string
  ; body : string
  }

let of_document (doc : Odoc_document.Types.Document.t) =
  match doc with
  | Source_page _ -> []
  | Page page ->
    let rec walk acc = function
      | [] -> List.rev acc
      | page :: queued ->
        let rendered = Render.page page in
        walk
          ({ path = rendered.path; body = rendered.body } :: acc)
          (queued @ rendered.subpages)
    in
    walk [] [ page ]
;;

let of_odocl file =
  match Odoc_odoc.Odoc_file.load file with
  | Error _ -> Error (Fpath.to_string file ^ ": cannot be loaded")
  | Ok { content = Unit_content unit_; _ } ->
    Ok
      (of_document
         (Odoc_document.Renderer.document_of_compilation_unit ~syntax:OCaml unit_))
  | Ok { content = Page_content page; _ } ->
    Ok (of_document (Odoc_document.Renderer.document_of_page ~syntax:OCaml page))
  | Ok { content = Impl_content _ | Asset_content _; _ } -> Ok []
;;

let write ~dir note =
  let path = Filename.concat dir (note.path ^ ".md") in
  let rec mkdirs d =
    if not (Sys.file_exists d)
    then (
      mkdirs (Filename.dirname d);
      Sys.mkdir d 0o755)
  in
  mkdirs (Filename.dirname path);
  let out = open_out path in
  Fun.protect ~finally:(fun () -> close_out out) (fun () -> output_string out note.body)
;;
