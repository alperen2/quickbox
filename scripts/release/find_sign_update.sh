#!/usr/bin/env bash
set -euo pipefail

if command -v sign_update >/dev/null 2>&1; then
  command -v sign_update
  exit 0
fi

search_roots=(
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Caches/org.swift.swiftpm"
)

preferred_patterns=(
  "*/Sparkle/bin/sign_update"
  "*/bin/sign_update"
  "*/sign_update"
)

for root in "${search_roots[@]}"; do
  [[ -d "$root" ]] || continue

  for pattern in "${preferred_patterns[@]}"; do
    while IFS= read -r candidate; do
      [[ "$candidate" == *"/old_dsa_scripts/"* ]] && continue
      if [[ -x "$candidate" ]]; then
        echo "$candidate"
        exit 0
      fi
    done < <(find "$root" -type f -path "$pattern" 2>/dev/null | sort)
  done
done

echo "Unable to locate sign_update. Build the project once or set SIGN_UPDATE_BIN explicitly." >&2
exit 1
