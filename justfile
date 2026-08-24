# Show this help
default:
    @just --list

doc:
    dune build @doc-private @doc

build:
    dune build

test:
    dune test

# Install git hooks from scripts/pre-commit
setup-hooks:
    git config core.hooksPath scripts/pre-commit

# Spin up dev container
devc-up:
    npx @devcontainers/cli up --workspace-folder .

# Attach to running dev container
devc-attach:
    npx @devcontainers/cli exec --workspace-folder . bash -l

# Kill and remove dev container
devc-down:
    #!/usr/bin/env bash
    id=$(docker ps -q --filter "label=devcontainer.local_folder={{justfile_directory()}}")
    if [ -n "$id" ]; then
        docker rm -f "$id"
    else
        echo "No running dev container found"
    fi

mod lsp "pkg/oystermark/lsp"

import? 'justfile.local'
