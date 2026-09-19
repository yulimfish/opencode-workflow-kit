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
PLUGIN_MANIFEST="$CFG_DIR/.opencode-workflow-kit-plugins"
GH_USER="Yulimfish"

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

# Agent bundles: repos that ship one or more subagent md files into $AGENTS_DIR.
AGENT_BUNDLES=(
  opencode-swarm-agents
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
touch "$MANAGED_MANIFEST" "$SKILL_MANIFEST" "$PLUGIN_MANIFEST"
ok "config dir ready"

# --- skills --------------------------------------------------------------
for s in "${SKILLS[@]}"; do
  dest="$SKILLS_DIR/$s"
  repo="https://github.com/$GH_USER/opencode-skill-$s.git"
  if [[ -d "$dest/.git" ]]; then
    say "updating skill: $s"
    if git -C "$dest" pull --ff-only --quiet; then
      ok "$s (updated)"
    else
      warn "$s pull failed — keeping the local copy; verify it manually"
    fi
    continue
  else
    say "installing skill: $s"
    if [[ -e "$dest" ]]; then
      warn "$dest exists but is not a git checkout — moving to $dest.bak.$(date +%s)"
      mv "$dest" "$dest.bak.$(date +%s)"
    fi
    git clone --depth=1 --quiet "$repo" "$dest"
    printf '%s\n' "$dest" >> "$SKILL_MANIFEST"
  fi
  ok "$s (installed)"
done

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
