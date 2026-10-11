#!/usr/bin/env bash
# opencode-workflow-kit installer — safe, idempotent, one-shot.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Yulimfish/opencode-workflow-kit/main/install.sh | bash

set -euo pipefail

BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
say() { printf "%s\n" "${BLUE}==>${NC} $*"; }
ok()  { printf "%s\n" "${GREEN}✓${NC} $*"; }
warn(){ printf "%s\n" "${YELLOW}!${NC} $*"; }
die() { printf "%s\n" "${RED}✗${NC} $*" >&2; exit 1; }

CFG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SKILLS_DIR="$CFG_DIR/skills"
AGENTS_DIR="$CFG_DIR/agents"
MANAGED_MANIFEST="$CFG_DIR/.opencode-workflow-kit-managed"
SKILL_MANIFEST="$CFG_DIR/.opencode-workflow-kit-skills"
SKILL_HASH_MANIFEST="$CFG_DIR/.opencode-workflow-kit-skill-hashes"
PLUGIN_MANIFEST="$CFG_DIR/.opencode-workflow-kit-plugins"
GH_USER="Yulimfish"
SKILL_CATALOG_REPO="https://github.com/Yulimfish/opencode-personal-skills.git"

SKILLS=(
  clarify-before-act
  ui-preview-first
  long-term-memory
  memory-graph-ui
  tool-call-discipline
  memory-dream
  swarm-cluster
  post-task-audit
  execution-economy
  screenshot-to-ui
)

skill_stage=""
skill_lock=""
cleanup_skill_sync() {
  if [[ -n "$skill_stage" ]]; then rm -rf "$skill_stage"; fi
  if [[ -n "$skill_lock" ]]; then rmdir "$skill_lock" 2>/dev/null || true; fi
}

manifest_contains_path() {
  local manifest="$1" wanted="$2"
  [[ -f "$manifest" ]] && grep -Fqx -- "$wanted" "$manifest"
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

record_skill_copy() {
  local dest="$1" hash="$2" temp_manifest
  if ! manifest_contains_path "$SKILL_MANIFEST" "$dest"; then
    printf '%s\n' "$dest" >> "$SKILL_MANIFEST"
  fi
  temp_manifest="$SKILL_HASH_MANIFEST.tmp.$$"
  if [[ -f "$SKILL_HASH_MANIFEST" ]]; then
    awk -F '\t' -v path="$dest" '$1 != path { print }' "$SKILL_HASH_MANIFEST" > "$temp_manifest"
  else
    : > "$temp_manifest"
  fi
  printf '%s\t%s\n' "$dest" "$hash" >> "$temp_manifest"
  mv "$temp_manifest" "$SKILL_HASH_MANIFEST"
}

replace_skill_from_catalog() {
  local skill="$1" expected_kind="$2" expected_hash="$3"
  local source="$SKILL_CATALOG_DIR/$1" dest="$SKILLS_DIR/$1"
  local stage backup="" new_hash backup_hash status
  if ! stage=$(mktemp -d "$SKILLS_DIR/.${skill}.new.XXXXXX"); then
    return 1
  fi
  if [[ -z "$stage" || ! -d "$stage" || -L "$stage" ]]; then return 1; fi
  case "$stage" in
    "$SKILLS_DIR/.${skill}.new."*) ;;
    *) return 1 ;;
  esac
  if ! cp -R "$source/." "$stage/"; then
    rm -rf "$stage"
    return 1
  fi
  new_hash=$(skill_tree_hash "$stage") || {
    rm -rf "$stage"
    return 1
  }
  if [[ -e "$dest" ]]; then
    backup="$SKILLS_DIR/.${skill}.old.$$"
    if [[ "$expected_kind" == "absent" || -e "$backup" || -L "$backup" ]] || ! move_no_replace "$dest" "$backup"; then
      rm -rf "$stage"
      return 2
    fi
    if [[ -L "$backup" ]]; then
      status=1
    else
      case "$expected_kind" in
        tree)
          backup_hash=$(skill_tree_hash "$backup") || backup_hash=""
          [[ "$backup_hash" == "$expected_hash" ]] || status=1
          ;;
        legacy)
          legacy_skill_is_clean "$backup" || status=1
          ;;
        *) status=1 ;;
      esac
    fi
    if [[ "${status:-0}" != "0" ]]; then
      if [[ ! -e "$dest" && ! -L "$dest" ]]; then
        move_no_replace "$backup" "$dest" || warn "preserved changed skill at $backup"
      else
        warn "preserved changed skill at $backup because another path now exists"
      fi
      rm -rf "$stage"
      return 2
    fi
  elif [[ "$expected_kind" != "absent" ]]; then
    rm -rf "$stage"
    return 2
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -n "$backup" ]]; then
      warn "preserved prior skill at $backup because another path appeared at $dest"
    fi
    rm -rf "$stage"
    return 2
  fi
  if ! move_no_replace "$stage" "$dest"; then
    if [[ -n "$backup" && ! -e "$dest" && ! -L "$dest" ]]; then move_no_replace "$backup" "$dest" || warn "preserved prior skill at $backup"; fi
    rm -rf "$stage"
    return 2
  fi
  current_hash=$(skill_tree_hash "$dest") || current_hash=""
  if [[ -L "$dest" || "$current_hash" != "$new_hash" ]]; then
    warn "preserved concurrently changed skill at $dest"
    return 2
  fi
  if ! record_skill_copy "$dest" "$new_hash"; then
    warn "installed $skill but failed to record ownership; preserving it at $dest"
    if [[ -n "$backup" ]]; then warn "preserved prior skill at $backup"; fi
    return 1
  fi
  if [[ -n "$backup" ]]; then
    case "$expected_kind" in
      tree)
        backup_hash=$(skill_tree_hash "$backup") || backup_hash=""
        if [[ "$backup_hash" != "$expected_hash" ]]; then
          warn "preserved concurrently changed prior skill at $backup"
          return 0
        fi
        ;;
      legacy)
        if ! legacy_skill_is_clean "$backup"; then
          warn "preserved concurrently changed prior skill at $backup"
          return 0
        fi
        ;;
    esac
    rm -rf "$backup"
  fi
}

install_catalog_skill() {
  local skill="$1" dest="$SKILLS_DIR/$1" stored_hash current_hash status
  if [[ -L "$dest" ]]; then
    warn "$dest is a symlink — preserving the existing link and target"
    return
  fi
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    if replace_skill_from_catalog "$skill" absent ""; then
      ok "$skill (installed from personal skill catalog)"
    else
      status=$?
      [[ "$status" == "2" ]] && warn "$dest appeared during install — preserving it" || die "failed to install skill: $skill"
    fi
    return
  fi

  if manifest_contains_path "$SKILL_MANIFEST" "$dest" && [[ -e "$dest/.git" ]]; then
    if ! legacy_skill_is_clean "$dest"; then
      warn "$dest has local changes or commits — preserving the legacy checkout"
      return
    fi
    say "migrating clean managed skill: $skill"
    if replace_skill_from_catalog "$skill" legacy ""; then
      ok "$skill (migrated to personal skill catalog)"
    else
      status=$?
      [[ "$status" == "2" ]] && warn "$dest changed during migration — preserving it" || die "failed to migrate skill: $skill"
    fi
    return
  fi

  stored_hash=$(skill_hash_for_path "$dest")
  if [[ -n "$stored_hash" ]]; then
    current_hash=$(skill_tree_hash "$dest") || current_hash=""
    if [[ "$current_hash" != "$stored_hash" ]]; then
      warn "$dest differs from the last managed copy — preserving local changes"
      return
    fi
    say "updating unchanged managed skill: $skill"
    if replace_skill_from_catalog "$skill" tree "$stored_hash"; then
      ok "$skill (updated from personal skill catalog)"
    else
      status=$?
      [[ "$status" == "2" ]] && warn "$dest changed during update — preserving it" || die "failed to update skill: $skill"
    fi
    return
  fi

  if manifest_contains_path "$SKILL_MANIFEST" "$dest"; then
    warn "$dest is a legacy manifest entry without a verifiable catalog fingerprint — preserving it"
  else
    warn "$dest is not managed by this installer — preserving it"
  fi
}

# Agent bundles: repos that ship one or more subagent md files into $AGENTS_DIR.
AGENT_BUNDLES=(
  opencode-swarm-agents
  opencode-tower-workflow
)

# Report-only Dream agent, read-only data interface, and review template.
MEMORY_EVOLUTION_REPO="https://github.com/Yulimfish/opencode-memory-evolution.git"
MEMORY_PLUGIN_REPO="github:Yulimfish/opencode-mem"
MEMORY_PLUGIN_PACKAGE="@yulimfish/opencode-mem"

PLUGINS=(
  opencode-guardrails
  @yulimfish/opencode-tool-search
)

# --- prereq --------------------------------------------------------------
say "checking prerequisites"
command -v git  >/dev/null || die "git not found. Install git first."
command -v npm  >/dev/null || die "npm not found. Install Node.js (>=18) first."
command -v curl >/dev/null || die "curl not found."

# Fetch and validate the complete source before modifying installed skills or manifests.
trap cleanup_skill_sync EXIT
if ! skill_stage=$(mktemp -d); then
  die "failed to create temporary catalog staging directory"
fi
[[ -n "$skill_stage" && -d "$skill_stage" && ! -L "$skill_stage" ]] || die "invalid catalog staging directory"
SKILL_CATALOG_DIR="$skill_stage/catalog"
if ! git clone --depth=1 --quiet "$SKILL_CATALOG_REPO" "$SKILL_CATALOG_DIR"; then
  die "failed to fetch personal skill catalog"
fi
for s in "${SKILLS[@]}"; do
  [[ -f "$SKILL_CATALOG_DIR/$s/SKILL.md" ]] || die "catalog is missing $s/SKILL.md"
done

install_managed() {
  local source="$1" target="$2"
  if [[ -e "$target" ]]; then
    if cmp -s "$source" "$target"; then
      warn "$target already exists unchanged — leaving it in place"
    else
      warn "$target already exists — leaving the local file untouched"
    fi
    return 1
  fi
  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
  printf '%s\t%s\n' "$target" "$(shasum -a 256 "$target" | cut -d ' ' -f 1)" >> "$MANAGED_MANIFEST"
  return 0
}

# --- dirs ----------------------------------------------------------------
say "preparing $CFG_DIR"
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"
if ! mkdir "$CFG_DIR/.opencode-workflow-kit-skill-operation.lock" 2>/dev/null; then
  die "another workflow-kit install or uninstall is operating on skills"
fi
skill_lock="$CFG_DIR/.opencode-workflow-kit-skill-operation.lock"
touch "$MANAGED_MANIFEST" "$SKILL_MANIFEST" "$PLUGIN_MANIFEST"
ok "config dir ready"

# --- skills --------------------------------------------------------------
for s in "${SKILLS[@]}"; do
  install_catalog_skill "$s"
done
cleanup_skill_sync
trap - EXIT

# --- memory evolution -----------------------------------------------------
tmp=$(mktemp -d)
say "installing memory evolution assets"
git clone --depth=1 --quiet "$MEMORY_EVOLUTION_REPO" "$tmp/opencode-memory-evolution"
install_managed "$tmp/opencode-memory-evolution/agents/memory-dream.md" "$AGENTS_DIR/memory-dream.md" || true
install_managed "$tmp/opencode-memory-evolution/bin/dreamctl" "$CFG_DIR/memory/bin/dreamctl" && chmod +x "$CFG_DIR/memory/bin/dreamctl" || true
install_managed "$tmp/opencode-memory-evolution/templates/dream/TEMPLATE.md" "$CFG_DIR/memory/dream/TEMPLATE.md" || true
rm -rf "$tmp"
ok "memory evolution assets installed (database untouched)"

# --- agent bundles -------------------------------------------------------
for b in "${AGENT_BUNDLES[@]}"; do
  tmp=$(mktemp -d)
  say "installing agent bundle: $b"
  git clone --depth=1 --quiet "https://github.com/$GH_USER/$b.git" "$tmp/$b"
  if [[ -d "$tmp/$b/agents" ]]; then
    # Copy without overwriting hand-edited local agent md files unnamed by us.
    for f in "$tmp/$b/agents"/*.md; do
      install_managed "$f" "$AGENTS_DIR/$(basename "$f")" || true
    done
    ok "$b (agent md files copied to $AGENTS_DIR)"
  else
    warn "$b has no agents/ dir — skipped"
  fi
  rm -rf "$tmp"
done

# --- plugins -------------------------------------------------------------
say "installing plugins via npm (cwd=$CFG_DIR)"
cd "$CFG_DIR"
if [[ ! -f package.json ]]; then
  npm init -y >/dev/null
  # opencode plugins are loaded by string ID; type=module makes ESM plugins work.
  node -e 'const f="package.json";const p=require("./"+f);p.type="module";require("fs").writeFileSync(f,JSON.stringify(p,null,2))'
fi
for plugin in "${PLUGINS[@]}"; do
  if ! npm ls --depth=0 "$plugin" >/dev/null 2>&1; then
    printf '%s\n' "$plugin" >> "$PLUGIN_MANIFEST"
  fi
done
if ! npm ls --depth=0 "$MEMORY_PLUGIN_PACKAGE" >/dev/null 2>&1; then
  printf '%s\n' "$MEMORY_PLUGIN_PACKAGE" >> "$PLUGIN_MANIFEST"
fi
npm install --silent "${PLUGINS[@]}" "$MEMORY_PLUGIN_REPO"
ok "plugins installed"

# --- next steps ----------------------------------------------------------
cat <<EOF

${GREEN}All done!${NC}

Next steps:

1. Add plugins to ${YELLOW}$CFG_DIR/opencode.jsonc${NC}:

   {
     "plugin": [
       "opencode-guardrails",
       "@yulimfish/opencode-tool-search",
        "./node_modules/@yulimfish/opencode-mem/dist/plugin.js"
     ]
   }

2. Add memory config to ${YELLOW}$CFG_DIR/opencode-mem.jsonc${NC}
   (embedding backend: Alibaba Cloud Model Studio / MaaS, qwen3.7-text-embedding):

   {
     "embeddingApiUrl": "https://<your-endpoint>.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
     "embeddingApiKey": "<YOUR_API_KEY>",
     "embeddingModel": "qwen3.7-text-embedding",
     "embeddingDimensions": 1024
   }

3. Restart opencode. Look for:
      [guardrails] armed
      [opencode-mem] loaded …

4. Optional: create the OpenChamber nightly Dream task from:
   https://github.com/$GH_USER/opencode-memory-evolution/blob/main/examples/openchamber-dream-schedule.json

Full docs: https://github.com/$GH_USER/opencode-workflow-kit
EOF
