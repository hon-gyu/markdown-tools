(** A vault snapshot as a Jinja template context.

    serializes the whole snapshot to JSON so a template engine can compute a
    document from it. E.g. a table of contents over a subtree, an index filtered
    by tag, a list of recently updated notes.

    The exposed JSON namespace is specified in {!page-"template-context"}.

    *)

(** [of_vault vault] is [vault] as a template context.

    [vault] must be loaded with [~skip_expand:true]: an expanded embed repeats
    another note's syntax inside its host, and the context would report links
    the author did not write there. *)
val of_vault : Vault.t -> Yojson.Safe.t
