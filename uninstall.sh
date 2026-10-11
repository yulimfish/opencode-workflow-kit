#!/usr/bin/env bash
# opencode-workflow-kit uninstaller
set -euo pipefail

CFG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SKILLS_DIR="$CFG_DIR/skills"
AGENTS_DIR="$CFG_DIR/agents"
MANAGED_MANIFEST="$CFG_DIR/.opencode-workflow-kit-managed"
SKILL_MANIFEST="$CFG_DIR/.opencode-workflow-kit-skills"
SKILL_HASH_MANIFEST="$CFG_DIR/.opencode-workflow-kit-skill-hashes"
PLUGIN_MANIFEST="$CFG_DIR/.opencode-workflow-kit-plugins"
SKILL_LOCK_PATH="$CFG_DIR/.opencode-workflow-kit-skill-operation.lock"
skill_lock=""

path_is_inside_config() {
  local path="$1" base resolved
  base="$(cd -P "$CFG_DIR" 2>/dev/null && pwd)" || return 1
  resolved="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || return 1
  case "$resolved" in
    "$base"/*) return 0 ;;
    *) return 1 ;;
  esac
}

skill_hash_for_path() {
  local wanted="$1"
  [[ -f "$SKILL_HASH_MANIFEST" ]] || return 0
  awk -F '\t' -v wanted="$wanted" '$1 == wanted { hash = $2 } END { if (hash != "") print hash }' "$SKILL_HASH_MANIFEST"
}

skill_tree_hash() {
  local directory="$1" file mode metadata
  [[ -d "$directory" ]] || return 1
  (
    cd "$directory"
    find . -print | LC_ALL=C sort | while IFS= read -r file; do
      if [[ -L "$file" ]]; then
        printf '%s\tsymlink\t%s\n' "$file" "$(readlink "$file")"
      elif [[ -d "$file" ]]; then
        if [[ "${OSTYPE:-}" == darwin* ]]; then mode=$(stat -f '%Lp' "$file"); else mode=$(stat -c '%a' "$file"); fi
        printf '%s\tdir\t%s\n' "$file" "$mode"
      elif [[ -f "$file" ]]; then
        if [[ "${OSTYPE:-}" == darwin* ]]; then mode=$(stat -f '%Lp' "$file"); else mode=$(stat -c '%a' "$file"); fi
        printf '%s\tfile\t%s\t%s\n' "$file" "$mode" "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
      else
        if [[ "${OSTYPE:-}" == darwin* ]]; then metadata=$(stat -f '%HT:%Lp' "$file"); else metadata=$(stat -c '%F:%a' "$file"); fi
        printf '%s\tspecial\t%s\n' "$file" "$metadata"
      fi
    done
  ) | shasum -a 256 | cut -d ' ' -f 1
}

move_no_replace() {
  local source="$1" destination="$2" nested
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    mv -n -h "$source" "$destination" || return 1
  else
    mv -n -T "$source" "$destination" || return 1
  fi
  if [[ -e "$source" || -L "$source" ]]; then return 1; fi
  if [[ -L "$destination" ]]; then return 0; fi
  nested="$destination/${source##*/}"
  if [[ -d "$nested" && ! -L "$nested" ]]; then
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      mv -n -h "$nested" "$source" || return 1
    else
      mv -n -T "$nested" "$source" || return 1
    fi
    return 1
  fi
  [[ -e "$destination" || -L "$destination" ]]
}

legacy_skill_is_clean() {
  local directory="$1" status upstream ahead
  status=$(git -C "$directory" status --porcelain --untracked-files=all --ignored=matching 2>/dev/null) || return 1
  [[ -z "$status" ]] || return 1
  upstream=$(git -C "$directory" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || return 1
  ahead=$(git -C "$directory" rev-list --count "${upstream}..HEAD" 2>/dev/null) || return 1
  [[ "$ahead" == "0" ]]
}

cleanup_skill_lock() {
  if [[ -n "$skill_lock" ]]; then rmdir "$skill_lock" 2>/dev/null || true; fi
}

if [[ -d "$CFG_DIR" ]]; then
  if ! mkdir "$SKILL_LOCK_PATH" 2>/dev/null; then
    echo "Another workflow-kit install or uninstall is operating on skills." >&2
    exit 1
  fi
  skill_lock="$SKILL_LOCK_PATH"
  trap cleanup_skill_lock EXIT
fi

echo "==> removing skills"
if [[ -f "$SKILL_MANIFEST" ]]; then
  while IFS= read -r dest; do
    [[ -n "$dest" ]] || continue
    if [[ -L "$dest" ]]; then
      echo "  preserved skill symlink: $dest"
      continue
    fi
    [[ -d "$dest" ]] || continue
    if ! path_is_inside_config "$dest"; then
      echo "  preserved unsafe manifest path: $dest"
      continue
    fi
    recorded_hash=$(skill_hash_for_path "$dest")
    if [[ -n "$recorded_hash" ]]; then
      current_hash=$(skill_tree_hash "$dest") || current_hash=""
      if [[ "$current_hash" == "$recorded_hash" ]]; then
        quarantine="${dest}.uninstall.$$"
        if [[ -e "$quarantine" || -L "$quarantine" ]] || ! move_no_replace "$dest" "$quarantine"; then
          echo "  preserved skill; could not safely quarantine: $dest"
          continue
        fi
        if [[ -L "$quarantine" ]]; then current_hash=""; else current_hash=$(skill_tree_hash "$quarantine") || current_hash=""; fi
        if [[ "$current_hash" == "$recorded_hash" ]]; then
          rm -rf "$quarantine"
          echo "  removed $dest"
        elif [[ ! -e "$dest" && ! -L "$dest" ]] && move_no_replace "$quarantine" "$dest"; then
          echo "  preserved concurrently modified skill: $dest"
        else
          echo "  preserved concurrently modified skill at: $quarantine"
        fi
      else
        echo "  preserved modified skill: $dest"
      fi
    elif [[ -e "$dest/.git" ]] && legacy_skill_is_clean "$dest"; then
      quarantine="${dest}.uninstall.$$"
      if [[ -e "$quarantine" || -L "$quarantine" ]] || ! move_no_replace "$dest" "$quarantine"; then
        echo "  preserved legacy skill; could not safely quarantine: $dest"
        continue
      fi
      if [[ ! -L "$quarantine" ]] && legacy_skill_is_clean "$quarantine"; then
        rm -rf "$quarantine"
        echo "  removed $dest"
      elif [[ ! -e "$dest" && ! -L "$dest" ]] && move_no_replace "$quarantine" "$dest"; then
        echo "  preserved concurrently modified legacy skill: $dest"
      else
        echo "  preserved concurrently modified legacy skill at: $quarantine"
      fi
    elif [[ -e "$dest/.git" ]]; then
      echo "  preserved modified skill: $dest"
    else
      echo "  preserved skill without a verifiable fingerprint: $dest"
    fi
  done < "$SKILL_MANIFEST"
  rm -f "$SKILL_MANIFEST"
  rm -f "$SKILL_HASH_MANIFEST"
else
  echo "  no ownership manifest — preserving existing skill checkouts"
fi

echo "==> removing memory evolution helper files (keeping reports and data)"
if [[ -f "$MANAGED_MANIFEST" ]]; then
  while IFS=$'\t' read -r path checksum; do
    [[ -n "$path" && -n "$checksum" && -f "$path" && ! -L "$path" ]] || continue
    if ! path_is_inside_config "$path"; then
      echo "  preserved unsafe manifest path: $path"
      continue
    fi
    current=$(shasum -a 256 "$path" | cut -d ' ' -f 1)
    if [[ "$current" == "$checksum" ]]; then
      rm -f "$path"
      echo "  removed $path"
    else
      echo "  preserved modified file: $path"
    fi
  done < "$MANAGED_MANIFEST"
  rm -f "$MANAGED_MANIFEST"
else
  echo "  no ownership manifest — preserving existing agent/helper files"
fi

echo "==> removing plugins"
cd "$CFG_DIR"
if [[ -s "$PLUGIN_MANIFEST" ]]; then
  OWNED_PLUGINS=()
  while IFS= read -r plugin; do
    [[ -n "$plugin" ]] && OWNED_PLUGINS+=("$plugin")
  done < "$PLUGIN_MANIFEST"
  if ((${#OWNED_PLUGINS[@]})); then
    npm uninstall --silent "${OWNED_PLUGINS[@]}" 2>/dev/null || true
  fi
  rm -f "$PLUGIN_MANIFEST"
else
  echo "  no plugin ownership manifest — preserving installed plugins"
fi

echo "Done. Remember to edit opencode.jsonc to remove plugin entries and restart opencode."
