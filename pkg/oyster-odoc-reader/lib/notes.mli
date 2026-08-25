(** Converting a compiled odoc file into notes. *)

type note =
  { path : string (** vault-relative, without the [.md] extension *)
  ; body : string
  }

(** [of_odocl file] is every note held by the linked odoc file [file]: the page
    it describes, and, recursively, the expansions that become notes of their
    own. A module's submodules are reached this way, so one [.odocl] yields one
    note per odoc page. *)
val of_odocl : Fpath.t -> (note list, string) result

(** [write ~dir note] writes [note] beneath [dir], creating the directories its
    path names. *)
val write : dir:string -> note -> unit
