#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
out=src/lib/oystermark

version=$(sed -n 's/^(version \(.*\))$/\1/p' "$root/dune-project")
if [ -z "$version" ]; then
  echo "no (version ...) stanza in $root/dune-project" >&2
  exit 1
fi
commit=$(git -C "$root" rev-parse --short HEAD)

dune build --root "$root" pkg/oystermark/js/oystermark_js.bc.js
cp -f "$root/_build/default/pkg/oystermark/js/oystermark_js.bc.js" "$out/oystermark.cjs"
chmod u+w "$out/oystermark.cjs"

sha=$(shasum -a 256 "$out/oystermark.cjs" | cut -d" " -f1)

cat > "$out/oystermark.version.json" <<JSON
{
  "oystermark": "$version",
  "commit": "$commit",
  "bundleSha256": "$sha"
}
JSON

echo "vendored oystermark $version ($commit)"
