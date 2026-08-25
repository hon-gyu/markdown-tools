(** Read odoc documentation into an OysterMark vault.

    odoc has already parsed the doc comments, resolved every cross-reference,
    rendered the signatures and assigned an anchor to each declaration by the
    time it writes a [.odocl] file. This library enters there, at
    [Odoc_document.Types.Document.t] -- the backend-agnostic representation
    that odoc's own HTML, LaTeX and manpage renderers consume -- so the notes
    carry the same information as the HTML, rather than the doc comments alone.

    See {!Notes.of_odocl} for the entry point and {!Render} for how each
    construct is spelled in OysterMark. *)

module Address = Address
module Notes = Notes
module Render = Render
