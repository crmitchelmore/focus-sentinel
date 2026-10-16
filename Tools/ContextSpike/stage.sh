#!/bin/zsh
# Opens every corpus window in the background: documents from a neutral folder (so a path does
# not name this repository) and one new Safari window per web page. `unstage.sh` closes them.
set -euo pipefail
cd "${0:A:h}"
DOCS=/tmp/Sam/Documents
mkdir -p $DOCS
cp -f stage/* $DOCS/
python3 - "$DOCS" <<'PY' | while IFS=$'\t' read -r kind app target; do
import json, sys, os
docs = sys.argv[1]
for w in json.load(open("corpus.json"))["windows"]:
    if w.get("url"):
        print("url", w["app"], w["url"], sep="\t")
    elif w["open"].startswith("stage/"):
        print("file", w["app"], os.path.join(docs, w["open"][6:]), sep="\t")
    else:
        print("file", w["app"], os.path.abspath(w["open"]), sep="\t")
PY
  if [[ $kind == url ]]; then
    osascript -e "tell application \"Safari\" to make new document with properties {URL:\"$target\"}" >/dev/null
  else
    open -g -a "$app" "$target"
  fi
  sleep 1
done
echo "staged; give pages ~20 s to load before capture"
