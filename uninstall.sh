#!/usr/bin/env bash
# opencode-workflow-kit uninstaller
set -euo pipefail

CFG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SKILLS_DIR="$CFG_DIR/skills"
AGENTS_DIR="$CFG_DIR/agents"
MANAGED_MANIFEST="$CFG_DIR/.opencode-workflow-kit-managed"
SKILL_MANIFEST="$CFG_DIR/.opencode-workflow-kit-skills"
PLUGIN_MANIFEST="$CFG_DIR/.opencode-workflow-kit-plugins"

path_is_inside_config() {
  local path="$1" base resolved
  base="$(cd -P "$CFG_DIR" 2>/dev/null && pwd)" || return 1
  resolved="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || return 1
  case "$resolved" in
    "$base"/*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "==> removing skills"
if [[ -f "$SKILL_MANIFEST" ]]; then
  while IFS= read -r dest; do
    [[ -n "$dest" && -d "$dest" ]] || continue
    if ! path_is_inside_config "$dest"; then
      echo "  preserved unsafe manifest path: $dest"
      continue
    fi
    if [[ -n "$(git -C "$dest" status --porcelain 2>/dev/null)" ]]; then
      echo "  preserved modified skill: $dest"
    else
      rm -rf "$dest"
      echo "  removed $dest"
    fi
  done < "$SKILL_MANIFEST"
  rm -f "$SKILL_MANIFEST"
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
