#!/usr/bin/env bash
# Craft Suite installer.
#
# With no argument it asks what you want, so nothing is installed by default.
# A novelist is never given the engineering tree, and a developer is never
# given the writing tree.
#
#   bash install.sh                ask what to install
#   bash install.sh --writing      creative writing, 42 skills
#   bash install.sh --documents    professional documents, 7 skills
#   bash install.sh --dev          software engineering, its skills and 25 agents
#   bash install.sh --security     defensive security, 12 skills and 2 agents
#   bash install.sh --research     general research, 5 skills
#   bash install.sh --career       job search and applications, 7 skills
#   bash install.sh --opportunity  ideation, hackathons, business, 9 skills
#   bash install.sh --shared       the 2 cross domain skills only
#   bash install.sh --all          everything, all skills and 26 agents
#   bash install.sh --group a,b    only these categories
#   bash install.sh --skill a,b    only these skills, with their dependencies
#   bash install.sh --list         print every installable skill and exit
#   bash install.sh --agents       the 26 agents only
#   bash install.sh --no-agents    skills without agents
#   bash install.sh --configure    ask for the user specific values only
#   bash install.sh --control-center   start the local Control Center and exit
#   bash install.sh --report       print a usage report from local session data
#   bash install.sh --zip          also build one archive per skill in dist/
#   bash install.sh --remove       uninstall the selected scope
#   bash install.sh --antigravity  install for Google Antigravity CLI (~/.gemini/config)
#   bash install.sh --help         this text
#
# Scope options combine, and combine with --zip and --remove:
#
#   bash install.sh --writing --documents
#   bash install.sh --group genres,quality
#   bash install.sh --dev --zip
#   bash install.sh --writing --remove
#
# Control Center options, valid with --control-center and --report:
#
#   --port N        serve on this port instead of the default
#   --no-browser    start the server without opening a browser
#   --json          print the report as JSON instead of text
#
# Run it without a copy of the repository, if the repository is reachable:
#
#   curl -fsSL https://raw.githubusercontent.com/Handsomeboy990/craft-suite/main/install.sh | bash -s -- --writing
#
# Targets, all overridable:
#
#   CLAUDE_SKILLS_DIR   default ~/.claude/skills
#   CLAUDE_AGENTS_DIR   default ~/.claude/agents
#   CLAUDE_CONFIG_FILE  default ~/.claude/craft.config.yaml
#   CLAUDE_SUITE_REPO   clone source when the script runs on its own
#   CLAUDE_SUITE_CACHE  where that clone lands, default ~/.cache/craft-suite
set -u

ROOT="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '')"
TARGET="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGENT_TARGET="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
RULES_TARGET="${ANTIGRAVITY_RULES_DIR:-$HOME/.gemini/config/rules}"
CONFIG_FILE="${CLAUDE_CONFIG_FILE:-$HOME/.claude/craft.config.yaml}"
REPO_URL="${CLAUDE_SUITE_REPO:-https://github.com/Handsomeboy990/craft-suite.git}"
IS_ANTIGRAVITY="no"

# The suite was called writer-suite until 3.0.0. An existing install keeps its
# answers in the old filenames, so move them once rather than asking again.
# Only when the user has not pointed CLAUDE_CONFIG_FILE somewhere of their own,
# and only when the new name is genuinely absent: never overwrite a real file.
migrate_legacy_config() {
  [ -n "${CLAUDE_CONFIG_FILE:-}" ] && return 0
  case " $* " in *" -h "*|*" --help "*) return 0 ;; esac
  local dir legacy legacy_tasks tasks
  dir="$(dirname "$CONFIG_FILE")"
  legacy="$dir/writer-suite.config.yaml"
  legacy_tasks="$dir/writer-suite-manual-tasks.md"
  tasks="$dir/craft-manual-tasks.md"

  if [ -f "$legacy" ] && [ ! -e "$CONFIG_FILE" ]; then
    mv "$legacy" "$CONFIG_FILE" || return 0
    sed -i.bak 's|Claude Writer Suite configuration|Craft Suite configuration|; s|writer-suite\.config|craft.config|g; s|writer-suite-manual-tasks|craft-manual-tasks|g' "$CONFIG_FILE" 2>/dev/null || true
    rm -f "$CONFIG_FILE.bak"
    printf 'Moved your configuration to %s (the suite is now craft-suite).\n' "$CONFIG_FILE"
  fi

  if [ -f "$legacy_tasks" ] && [ ! -e "$tasks" ]; then
    mv "$legacy_tasks" "$tasks" || return 0
    printf 'Moved your manual task list to %s.\n' "$tasks"
  fi
}

migrate_legacy_config "$@"

# A skill group is a repository relative path holding skill directories.
WRITING_GROUPS="writing/core writing/genres writing/poetry writing/quality"
DOCUMENT_GROUPS="documents/documentation documents/administrative documents/publishing"
ENGINEERING_GROUPS="engineering/dev-skills engineering/delivery-skills engineering/devops-skills"
SECURITY_GROUPS="security/secure-development security/security-assurance"
RESEARCH_GROUPS="research"
CAREER_GROUPS="career"
OPPORTUNITY_GROUPS="opportunity/ideation opportunity/hackathons opportunity/business"
SHARED_GROUPS="shared"

MODE="install"
WANT_WRITING="no"
WANT_DOCUMENTS="no"
WANT_ENGINEERING="no"
WANT_SECURITY="no"
WANT_RESEARCH="no"
WANT_CAREER="no"
WANT_OPPORTUNITY="no"
WANT_SHARED_ONLY="no"
SELECTED_SKILLS=""
SELECTED_GROUPS=""
SCOPE_GIVEN="no"
WITH_AGENTS=""
WITH_SKILLS="yes"
WANT_ALL_AGENTS="no"
CC_ARGS=""

usage() {
  sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'
}

die() { printf '%s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)   usage; exit 0 ;;
    --list)      MODE="list" ;;
    --remove)    MODE="remove" ;;
    --zip)       MODE="zip" ;;
    --configure) MODE="configure" ;;
    --control-center|--control) MODE="control-center" ;;
    --report)    MODE="report" ;;
    --no-browser) CC_ARGS="$CC_ARGS --no-browser" ;;
    --port=*)    CC_ARGS="$CC_ARGS --port ${1#*=}" ;;
    --port)
      shift
      [ $# -gt 0 ] || die "--port needs a number."
      CC_ARGS="$CC_ARGS --port $1"
      ;;
    --json)      CC_ARGS="$CC_ARGS --json" ;;
    --agy|--antigravity)
      TARGET="${ANTIGRAVITY_SKILLS_DIR:-$HOME/.gemini/config/skills}"
      AGENT_TARGET="${ANTIGRAVITY_AGENTS_DIR:-$HOME/.gemini/config/agents}"
      RULES_TARGET="${ANTIGRAVITY_RULES_DIR:-$HOME/.gemini/config/rules}"
      CONFIG_FILE="${ANTIGRAVITY_CONFIG_FILE:-$HOME/.gemini/config/craft.config.yaml}"
      IS_ANTIGRAVITY="yes"
      ;;
    --writing)     WANT_WRITING="yes";     SCOPE_GIVEN="yes" ;;
    --documents)   WANT_DOCUMENTS="yes";   SCOPE_GIVEN="yes" ;;
    --dev)         WANT_ENGINEERING="yes"; SCOPE_GIVEN="yes" ;;
    --security)    WANT_SECURITY="yes";    SCOPE_GIVEN="yes" ;;
    --research)    WANT_RESEARCH="yes";    SCOPE_GIVEN="yes" ;;
    --career)      WANT_CAREER="yes";      SCOPE_GIVEN="yes" ;;
    --opportunity) WANT_OPPORTUNITY="yes"; SCOPE_GIVEN="yes" ;;
    --shared)      WANT_SHARED_ONLY="yes"; SCOPE_GIVEN="yes" ;;
    --all)
      WANT_WRITING="yes"; WANT_DOCUMENTS="yes"; WANT_ENGINEERING="yes"
      WANT_SECURITY="yes"; WANT_RESEARCH="yes"; WANT_CAREER="yes"
      WANT_OPPORTUNITY="yes"
      SCOPE_GIVEN="yes"
      ;;
    --group=*|--groups=*|--category=*)
      SELECTED_GROUPS="$SELECTED_GROUPS $(printf '%s' "${1#*=}" | tr ',' ' ')"
      SCOPE_GIVEN="yes"
      ;;
    --group|--groups|--category)
      shift
      [ $# -gt 0 ] || die "--group needs at least one category name. See: bash install.sh --list"
      while [ $# -gt 0 ]; do
        case "$1" in --*) break ;; esac
        SELECTED_GROUPS="$SELECTED_GROUPS $(printf '%s' "$1" | tr ',' ' ')"
        shift
      done
      SCOPE_GIVEN="yes"
      continue
      ;;
    --skill=*|--skills=*)
      SELECTED_SKILLS="$SELECTED_SKILLS $(printf '%s' "${1#*=}" | tr ',' ' ')"
      SCOPE_GIVEN="yes"
      ;;
    --skill|--skills)
      shift
      [ $# -gt 0 ] || die "--skill needs at least one skill name. See: bash install.sh --list"
      while [ $# -gt 0 ]; do
        case "$1" in --*) break ;; esac
        SELECTED_SKILLS="$SELECTED_SKILLS $(printf '%s' "$1" | tr ',' ' ')"
        shift
      done
      SCOPE_GIVEN="yes"
      continue
      ;;
    --agents)    WITH_SKILLS="no";  WITH_AGENTS="yes"; WANT_ALL_AGENTS="yes"; SCOPE_GIVEN="yes" ;;
    --no-agents) WITH_AGENTS="no" ;;
    *)
      printf 'Unknown option: %s\n\n' "$1"
      usage
      exit 1
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Locating the skills
# ---------------------------------------------------------------------------

# Piped from the network, the script has no repository next to it. Clone one.
bootstrap() {
  [ -n "$ROOT" ] && [ -d "$ROOT/shared" ] && return 0
  command -v git >/dev/null 2>&1 \
    || die "No skills next to this script, and git is not available to fetch them."
  cache="${CLAUDE_SUITE_CACHE:-$HOME/.cache/craft-suite}"
  if [ -d "$cache/.git" ]; then
    git -C "$cache" pull --ff-only -q 2>/dev/null || true
  else
    printf 'Fetching the skills into %s\n' "$cache"
    git clone -q --depth 1 "$REPO_URL" "$cache" \
      || die "Could not clone $REPO_URL. If the repository is private, clone it yourself and run install.sh from inside it."
  fi
  ROOT="$cache"
  [ -d "$ROOT/shared" ] || die "The clone at $ROOT does not look like this repository."
}

# A category, named either bare (genres) or with its tree (writing/genres).
group_path() {
  local group
  for group in $(all_groups); do
    [ "$group" = "$1" ] && { printf '%s' "$group"; return 0; }
    [ "$(basename "$group")" = "$1" ] && { printf '%s' "$group"; return 0; }
  done
  return 1
}

validate_selected_groups() {
  local name
  for name in ${SELECTED_GROUPS:-}; do
    group_path "$name" >/dev/null \
      || die "Unknown category: $name
Categories: $(for g in $(all_groups); do basename "$g"; done | tr '\n' ' ')"
  done
}

# Called in the main shell: die inside a process substitution would only kill
# the subshell and let the install continue with a silently shorter list.
validate_selected_skills() {
  local name
  for name in ${SELECTED_SKILLS:-}; do
    skill_path "$name" >/dev/null \
      || die "Unknown skill: $name
See the full list with: bash install.sh --list"
  done
}

all_groups() {
  printf '%s %s %s %s %s %s %s %s' \
    "$WRITING_GROUPS" "$DOCUMENT_GROUPS" "$ENGINEERING_GROUPS" \
    "$SECURITY_GROUPS" "$RESEARCH_GROUPS" "$CAREER_GROUPS" \
    "$OPPORTUNITY_GROUPS" "$SHARED_GROUPS"
}

# Absolute path of a skill, whatever tree holds it.
skill_path() {
  local group
  for group in $(all_groups); do
    if [ -d "$ROOT/$group/$1" ]; then
      printf '%s\n' "$ROOT/$group/$1"
      return 0
    fi
  done
  return 1
}

# The skills a skill declares it needs.
deps_of() {
  local path
  path="$(skill_path "$1")" || return 0
  grep -m1 '^  depends_on:' "$path/SKILL.md" 2>/dev/null \
    | sed 's/^  depends_on: *\[//; s/\]$//; s/,/ /g'
}

# Transitive closure. Installing thriller without writing-constitution and
# novel-architect would install something that refuses to run.
resolve_with_deps() {
  local pending=("$@") seen=() name dep found
  while [ ${#pending[@]} -gt 0 ]; do
    name="${pending[0]}"
    pending=("${pending[@]:1}")
    found=no
    for dep in ${seen[@]+"${seen[@]}"}; do
      [ "$dep" = "$name" ] && found=yes && break
    done
    [ "$found" = "yes" ] && continue
    skill_path "$name" >/dev/null \
      || die "Unknown skill: $name. Run: bash install.sh --list"
    seen+=("$name")
    for dep in $(deps_of "$name"); do
      [ -n "$dep" ] && pending+=("$dep")
    done
  done
  printf '%s\n' ${seen[@]+"${seen[@]}"}
}

active_groups() {
  local groups="" name
  for name in ${SELECTED_GROUPS:-}; do
    groups="$groups $(group_path "$name")"
  done
  [ "$WANT_WRITING" = "yes" ]     && groups="$groups $WRITING_GROUPS"
  [ "$WANT_DOCUMENTS" = "yes" ]   && groups="$groups $DOCUMENT_GROUPS"
  [ "$WANT_ENGINEERING" = "yes" ] && groups="$groups $ENGINEERING_GROUPS"
  [ "$WANT_SECURITY" = "yes" ]    && groups="$groups $SECURITY_GROUPS"
  [ "$WANT_RESEARCH" = "yes" ]    && groups="$groups $RESEARCH_GROUPS"
  [ "$WANT_CAREER" = "yes" ]      && groups="$groups $CAREER_GROUPS"
  [ "$WANT_OPPORTUNITY" = "yes" ] && groups="$groups $OPPORTUNITY_GROUPS"
  # The cross domain pair belongs to every scope: every tree calls it.
  [ -n "$groups" ] && groups="$groups $SHARED_GROUPS"
  # deduplicate, since --group shared --writing would list it twice
  groups="$(printf '%s\n' $groups | awk '!seen[$0]++' | tr '\n' ' ')"
  [ "$WANT_SHARED_ONLY" = "yes" ] && groups="$SHARED_GROUPS"
  printf '%s' "$groups"
}

# What the selection names directly: the skills given to --skill, plus every
# skill in the chosen categories and trees. No dependency is added here, which
# is what removal needs: removing a tree must never take a skill another tree
# still depends on.
selected_skill_dirs_direct() {
  local name group skill
  {
    if [ -n "${SELECTED_SKILLS// /}" ]; then
      for name in $SELECTED_SKILLS; do
        skill_path "$name"
      done
      # A named selection still gets the cross domain pair, for the same
      # reason every tree does: everything calls it.
      for name in self-critique project-brief; do
        skill_path "$name"
      done
    fi
    for group in $(active_groups); do
      for skill in "$ROOT/$group"/*/; do
        # The trailing slash is stripped so this path is spelled exactly as
        # skill_path spells it above. The deduplication below compares strings,
        # and without this the cross domain pair arrives twice when --skill and
        # --group are combined, which the installer would then report as two
        # more skills than it installed.
        [ -d "$skill" ] && printf '%s\n' "${skill%/}"
      done
    done
  } | awk '!seen[$0]++'
}

# Every skill directory that has to be on disk for the selection to work: the
# direct selection plus the transitive closure of what those skills declare.
# The closure runs for a tree and a category too, not only for --skill: the
# security tree declares `security-audit`, which lives in the engineering tree,
# and installing the dependent without its dependency installs something that
# refuses to run.
selected_skill_dirs() {
  local dir name names=""
  while IFS= read -r dir; do
    [ -n "$dir" ] && names="$names $(basename "$dir")"
  done < <(selected_skill_dirs_direct)
  [ -n "${names// /}" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] && skill_path "$name"
  done < <(resolve_with_deps $names) | awk '!seen[$0]++'
}

# Removal never takes the cross domain pair unless it was asked for on its
# own, or everything was, so removing one tree never breaks another.
removing_everything() {
  [ "$WANT_WRITING" = "yes" ] && [ "$WANT_DOCUMENTS" = "yes" ] \
    && [ "$WANT_ENGINEERING" = "yes" ] && [ "$WANT_SECURITY" = "yes" ] \
    && [ "$WANT_RESEARCH" = "yes" ] && [ "$WANT_CAREER" = "yes" ] \
    && [ "$WANT_OPPORTUNITY" = "yes" ] && return 0
  [ "$WANT_SHARED_ONLY" = "yes" ] && return 0
  return 1
}

removable_skill_dirs() {
  local skill name
  # A named removal takes only what was named. Its dependencies are shared
  # with other skills, and removing writing-constitution because someone
  # dropped haiku would break the rest of the tree.
  if [ -n "${SELECTED_SKILLS// /}" ] && [ -z "${SELECTED_GROUPS// /}" ]; then
    for name in $SELECTED_SKILLS; do
      skill_path "$name"
    done
    return 0
  fi
  while IFS= read -r skill; do
    name="$(basename "$skill")"
    case "$name" in
      self-critique|project-brief)
        removing_everything || continue
        ;;
    esac
    printf '%s\n' "$skill"
  done < <(selected_skill_dirs_direct)
}

# Which domain scopes carry a given agent, so a domain's plugin is
# self-contained. An agent's home is its group's domain: every agent belongs to
# the engineering domain except the two security-group agents. `security-engineer`
# is shared, because the engineering delivery flow dispatches it; `web-auditor`
# is a security-only tool with no role in the engineering sequence. A domain with
# no agent of its own (writing, documents, research, career, opportunity) simply
# matches nothing here.
agent_domains() {
  case "$1" in
    web-auditor)        printf 'security' ;;
    security-engineer)  printf 'engineering security' ;;
    *)                  printf 'engineering' ;;
  esac
}

# True when the given domain name is a wanted scope.
domain_wanted() {
  case "$1" in
    engineering) [ "$WANT_ENGINEERING" = "yes" ] ;;
    security)    [ "$WANT_SECURITY" = "yes" ] ;;
    *) return 1 ;;
  esac
}

# Agents are single files, grouped by kind of work under agents/<group>/.
# README and the handoff protocol are documentation, not agent definitions,
# and are not installed. Installation is flat: only the basename matters. Each
# agent is emitted when its own domain is wanted, so a domain's plugin carries
# exactly its agents; `--agents` installs the whole roster regardless of scope.
agents() {
  local agent name domain
  for agent in "$ROOT/agents"/*/*.md; do
    [ -f "$agent" ] || continue
    name="$(basename "$agent" .md)"
    case "$name" in
      README|handoff-protocol) continue ;;
    esac
    if [ "$WANT_ALL_AGENTS" = "yes" ]; then
      printf '%s\n' "$agent"
      continue
    fi
    for domain in $(agent_domains "$name"); do
      if domain_wanted "$domain"; then
        printf '%s\n' "$agent"
        break
      fi
    done
  done
}

count_in() {
  local group total=0 skill
  for group in $1; do
    for skill in "$ROOT/$group"/*/; do
      [ -d "$skill" ] && total=$((total + 1))
    done
  done
  printf '%s' "$total"
}

# ---------------------------------------------------------------------------
# Choosing what to install
# ---------------------------------------------------------------------------

list_skills() {
  local group name desc
  for group in $(all_groups); do
    printf '\n%s\n' "$group"
    for skill in "$ROOT/$group"/*/; do
      [ -d "$skill" ] || continue
      name="$(basename "$skill")"
      desc="$(grep -m1 '^description:' "$skill/SKILL.md" | cut -c14- | cut -c1-72)"
      printf '  %-26s %s\n' "$name" "$desc"
    done
  done
  printf '\nInstall a subset:\n  bash install.sh --skill <name>,<name>\n'
  printf 'Dependencies are added automatically.\n'
}

# Reads from the terminal even when the script itself arrived on stdin, as it
# does under curl | bash. /dev/tty can exist as a path and still refuse to
# open, so the open is attempted rather than the path tested.
TTY_FD=""
open_tty() {
  [ -n "$TTY_FD" ] && return 0
  if [ -t 0 ]; then TTY_FD=0; return 0; fi
  if { exec 3</dev/tty; } 2>/dev/null; then TTY_FD=3; return 0; fi
  return 1
}

ask_tty() {
  local prompt="$1" answer=""
  open_tty || return 1
  printf '%s' "$prompt" >&2
  if [ "$TTY_FD" = "0" ]; then
    IFS= read -r answer || return 1
  else
    IFS= read -r -u 3 answer || return 1
  fi
  printf '%s' "$answer"
}

no_terminal() {
  die "install.sh asks what to install, and no terminal is available.
Pass a scope instead:
  bash install.sh --writing      creative writing
  bash install.sh --documents    professional documents
  bash install.sh --dev          software engineering
  bash install.sh --all          everything
  bash install.sh --skill <name> one skill and its dependencies
  bash install.sh --list         see every skill first"
}

interactive_select() {
  local writing documents engineering security research career opportunity
  local total answer picked

  open_tty || no_terminal

  writing="$(count_in "$WRITING_GROUPS")"
  documents="$(count_in "$DOCUMENT_GROUPS")"
  engineering="$(count_in "$ENGINEERING_GROUPS")"
  security="$(count_in "$SECURITY_GROUPS")"
  research="$(count_in "$RESEARCH_GROUPS")"
  career="$(count_in "$CAREER_GROUPS")"
  opportunity="$(count_in "$OPPORTUNITY_GROUPS")"
  total=$((writing + documents + engineering + security + research \
    + career + opportunity + $(count_in "$SHARED_GROUPS")))

  {
    printf '\nCraft Suite\n\n'
    printf 'Nothing is installed until you choose. Pick what you actually do.\n\n'
    printf '   1) Creative writing        %2s skills   novels, poetry, screenplay, editing\n' "$writing"
    printf '   2) Professional documents  %2s skills   guides, manuals, reports, letters, PDF\n' "$documents"
    printf '   3) Software engineering    %2s skills   plus 25 agents\n' "$engineering"
    printf '   4) Cybersecurity           %2s skills   threat models, audits, hardening\n' "$security"
    printf '   5) Research                %2s skills   sources, verification, synthesis\n' "$research"
    printf '   6) Career                  %2s skills   job search, CV, interviews\n' "$career"
    printf '   7) Opportunity             %2s skills   ideation, hackathons, business\n' "$opportunity"
    printf '   8) Everything             %3s skills   plus 26 agents\n' "$total"
    printf '   9) Individual skills, chosen by name\n'
    printf '  10) One or more categories, for example genres only\n\n'
    printf 'Every choice also installs the 2 cross domain skills, self-critique and\n'
    printf 'project-brief, because every tree calls them.\n\n'
    printf 'Several numbers may be given, separated by spaces. For example: 1 2\n'
  } >&2

  answer="$(ask_tty 'Choice [1]: ')" || no_terminal
  [ -n "$answer" ] || answer="1"

  for picked in $answer; do
    case "$picked" in
      1) WANT_WRITING="yes" ;;
      2) WANT_DOCUMENTS="yes" ;;
      3) WANT_ENGINEERING="yes" ;;
      4) WANT_SECURITY="yes" ;;
      5) WANT_RESEARCH="yes" ;;
      6) WANT_CAREER="yes" ;;
      7) WANT_OPPORTUNITY="yes" ;;
      8) WANT_WRITING="yes"; WANT_DOCUMENTS="yes"; WANT_ENGINEERING="yes"
         WANT_SECURITY="yes"; WANT_RESEARCH="yes"; WANT_CAREER="yes"
         WANT_OPPORTUNITY="yes" ;;
      9) select_individual_skills ;;
      10) select_categories ;;
      *) die "Not one of the offered choices: $picked" ;;
    esac
  done

  if [ "$WANT_WRITING" = "no" ] && [ "$WANT_DOCUMENTS" = "no" ] \
     && [ "$WANT_ENGINEERING" = "no" ] && [ "$WANT_SECURITY" = "no" ] \
     && [ "$WANT_RESEARCH" = "no" ] && [ "$WANT_CAREER" = "no" ] \
     && [ "$WANT_OPPORTUNITY" = "no" ] && [ "$WANT_SHARED_ONLY" = "no" ] \
     && [ -z "${SELECTED_SKILLS// /}" ] && [ -z "${SELECTED_GROUPS// /}" ]; then
    die "Nothing selected. Nothing installed."
  fi
}

select_categories() {
  local answer group
  {
    printf '\nCategories:\n\n'
    for group in $(all_groups); do
      printf '  %-16s %2s skills   %s\n' \
        "$(basename "$group")" "$(count_in "$group")" "$group"
    done
  } >&2
  answer="$(ask_tty '
Category names, separated by spaces: ')" || no_terminal
  [ -n "${answer// /}" ] || die "No category named. Nothing installed."
  SELECTED_GROUPS="$SELECTED_GROUPS $answer"
}

select_individual_skills() {
  local answer
  list_skills >&2
  answer="$(ask_tty '
Skill names, separated by spaces: ')" || no_terminal
  [ -n "${answer// /}" ] || die "No skill named. Nothing installed."
  SELECTED_SKILLS="$SELECTED_SKILLS $answer"
}

# Agents install with the domain that owns them: engineering carries its
# delivery team, security carries its own auditors. A cherry-picked skill list
# is not a domain install, so it brings no agents unless --agents is explicit.
resolve_agents() {
  [ -n "$WITH_AGENTS" ] && return 0
  # Only the domains that actually ship agents. --research used to be listed
  # here, and since no agent belongs to the research domain it produced an
  # empty agents directory and a "0 agents installed" line.
  if [ -z "${SELECTED_SKILLS// /}" ] \
     && { [ "$WANT_ENGINEERING" = "yes" ] \
       || [ "$WANT_SECURITY" = "yes" ]; }; then
    WITH_AGENTS="yes"
  else
    WITH_AGENTS="no"
  fi
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Current value of section.key in the configuration file, empty when absent.
config_get() {
  [ -f "$CONFIG_FILE" ] || return 0
  awk -v section="$1:" -v key="  $2:" '
    $0 == section { inside = 1; next }
    /^[a-z]/ { inside = 0 }
    inside && index($0, key) == 1 {
      value = substr($0, length(key) + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$CONFIG_FILE"
}

# The sections --configure asks about and therefore rewrites. Anything else in
# the file was put there by hand and is none of the installer's business.
MANAGED_SECTIONS="identity delegation git language engineering documents"

# --configure rewrites the configuration file, and a plain redirect would drop
# every section it does not ask about: model_routing and career are documented
# in config/craft.config.example.yaml and are edited by hand, so re-running the
# installer used to silently delete them. This returns those sections verbatim,
# to be re-emitted after the managed ones. It must be called before the
# redirect opens the file, since opening it for writing truncates it.
preserved_sections() {
  [ -f "$CONFIG_FILE" ] || return 0
  awk -v managed=" $MANAGED_SECTIONS " '
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
      name = $0
      sub(/:.*$/, "", name)
      keep = (index(managed, " " name " ") == 0)
      if (keep) blank = 1
    }
    !keep { next }
    $0 == "" { blank = 1; next }
    { if (blank) { print ""; blank = 0 } print }
  ' "$CONFIG_FILE"
}

# Every field --configure writes, as section:key. The writer at the end of
# configure() emits exactly this list, so a field missing here would be written
# empty on any run that does not ask its question.
MANAGED_FIELDS="
identity:author_name identity:author_email identity:organization
delegation:commits delegation:branches delegation:push
delegation:pull_requests delegation:release_tags delegation:deployments
delegation:database_operations delegation:dependency_changes
git:commit_convention git:branch_convention git:default_branch
git:protected_branches
language:documentation language:creative_output language:document_output
engineering:package_manager engineering:deployment_platform
engineering:database
documents:pdf_engine documents:page_size documents:date_format
"

# Seeds the in memory answers from the file before the first question, so a run
# writes back the fields it did not ask about. Without this, --dev --configure
# after --all --configure erased every documents and creative writing answer:
# those questions are asked only under their own scope, and an unasked field
# reached the writer empty.
load_existing_config() {
  local field section key value
  for field in $MANAGED_FIELDS; do
    section="${field%%:*}"
    key="${field##*:}"
    value="$(config_get "$section" "$key")"
    [ -n "$value" ] && eval "CFG_${section}_${key}=\"\$value\""
  done
  return 0
}

# A credential must never reach this file.
looks_like_secret() {
  printf '%s' "$1" | grep -Eiq 'key|token|secret|password|passwd|credential'
}

# An author must be a person, not the tool that typed for them.
looks_like_a_tool() {
  printf '%s' "$1" | grep -Eiq '(^|[^a-z])(ai|bot|gpt|llm|claude|chatgpt|openai|anthropic|copilot|assistant|generated|generator)([^a-z]|$)'
}

valid_email() {
  printf '%s' "$1" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
}

in_list() {
  needle="$1"; shift
  for candidate in "$@"; do
    [ "$needle" = "$candidate" ] && return 0
  done
  return 1
}

# ask <section> <key> <prompt> <required:yes|no> <fallback> [allowed...]
ask() {
  local section="$1" key="$2" prompt="$3" required="$4" fallback="$5"
  shift 5
  local allowed="$*"
  local current answer

  if looks_like_secret "$key"; then
    printf '  refused: %s.%s looks like a credential and is not stored here\n' \
      "$section" "$key"
    return 0
  fi

  current="$(config_get "$section" "$key")"
  [ -n "$current" ] || current="$fallback"

  while true; do
    if [ -n "$current" ]; then
      printf '  %s [%s]: ' "$prompt" "$current"
    elif [ "$required" = "yes" ]; then
      printf '  %s (required): ' "$prompt"
    else
      printf '  %s (optional, enter to skip): ' "$prompt"
    fi
    IFS= read -r answer || answer=""
    [ -n "$answer" ] || answer="$current"

    if [ -z "$answer" ] && [ "$required" = "yes" ]; then
      printf '    this field has no default, and no value is invented for you\n'
      continue
    fi
    if [ -n "$allowed" ] && [ -n "$answer" ] && ! in_list "$answer" $allowed; then
      printf '    accepted values: %s\n' "$allowed"
      continue
    fi
    if [ "$key" = "author_email" ] && [ -n "$answer" ] && ! valid_email "$answer"; then
      printf '    not an email address\n'
      continue
    fi
    if { [ "$key" = "author_name" ] || [ "$key" = "author_email" ]; } \
       && [ -n "$answer" ] && looks_like_a_tool "$answer"; then
      printf '    an author is a person, not a tool; history has to stay auditable\n'
      continue
    fi
    break
  done

  eval "CFG_${section}_${key}=\"\$answer\""
}

value_of() {
  eval "printf '%s' \"\${CFG_$1_$2:-}\""
}

# choose <section> <key> <prompt> <recommended_index> <label|value> ...
# Numbered menu. The recommended option is marked and pre-selected, so the
# usual answer is the enter key.
choose() {
  local section="$1" key="$2" prompt="$3" recommended="$4"
  shift 4
  local labels=() values=() pair i
  for pair in "$@"; do
    labels+=("${pair%%|*}")
    values+=("${pair##*|}")
  done

  local current default_index="$recommended"
  current="$(config_get "$section" "$key")"
  for i in "${!values[@]}"; do
    [ "${values[$i]}" = "$current" ] && default_index=$((i + 1))
  done

  printf '\n  %s\n' "$prompt"
  for i in "${!labels[@]}"; do
    if [ $((i + 1)) -eq "$recommended" ]; then
      printf '    %d) %s   (recommended)\n' "$((i + 1))" "${labels[$i]}"
    else
      printf '    %d) %s\n' "$((i + 1))" "${labels[$i]}"
    fi
  done

  local answer
  while true; do
    printf '  Choice [%d]: ' "$default_index"
    IFS= read -r answer || answer=""
    [ -n "$answer" ] || answer="$default_index"
    case "$answer" in
      *[!0-9]*|'') printf '    enter a number between 1 and %d\n' "${#values[@]}"; continue ;;
    esac
    if [ "$answer" -ge 1 ] && [ "$answer" -le "${#values[@]}" ]; then
      eval "CFG_${section}_${key}=\"\${values[\$((answer - 1))]}\""
      return 0
    fi
    printf '    enter a number between 1 and %d\n' "${#values[@]}"
  done
}

configure() {
  if [ ! -t 0 ]; then
    printf 'Configuration needs a terminal.\n'
    printf 'Non interactive alternative: copy config/craft.config.example.yaml\n'
    printf 'to %s and edit it.\n' "$CONFIG_FILE"
    exit 1
  fi

  printf 'Craft Suite configuration\n'
  printf 'File: %s\n\n' "$CONFIG_FILE"
  printf 'Every question has a recommended answer, already selected.\n'
  printf 'Press enter to accept it. Values in brackets are what is stored now.\n'
  printf 'Answer no to anything you would rather do yourself: the agent will\n'
  printf 'stop at that boundary and list the step for you instead.\n'
  printf 'Never put a secret here. Field reference: config/README.md\n'

  load_existing_config

  local need_engineering="$WANT_ENGINEERING"
  local need_writing="$WANT_WRITING"
  local need_documents="$WANT_DOCUMENTS"

  if [ "$need_engineering" = "yes" ]; then
    printf '\n--- Identity, used on every commit ---\n'
    ask identity author_name  "Author name"  yes ""
    ask identity author_email "Author email" yes ""

    printf '\n--- What the agent may do on your repository ---\n'
    printf 'Each no is a step that moves to your manual task list.\n'

    choose delegation commits "May the agent create commits?" 1 \
      "Yes, atomic commits following the convention below|yes" \
      "Yes, but stage only and let me write the message|stage-only" \
      "No, I commit myself|no"

    choose delegation branches "May the agent create branches?" 1 \
      "Yes, following the branch convention below|yes" \
      "No, I create branches and tell it which one to use|no"

    choose delegation push "May the agent push?" 2 \
      "Yes, including the default branch|yes" \
      "Yes, but never to a protected branch|branch-only" \
      "No, I push myself|no"

    choose delegation pull_requests "May the agent open pull requests?" 1 \
      "Yes, with the full description|yes" \
      "Yes, but as a draft only|draft" \
      "No, I open them myself|no"

    choose git protected_branches "Which branches are protected, so nothing reaches them without a pull request?" 1 \
      "The default branch only|default" \
      "The default branch and any release branch|default+release" \
      "None, direct pushes are allowed|none"

    choose delegation release_tags "May the agent create version tags and releases?" 2 \
      "Yes|yes" \
      "No, I tag and release myself|no"

    choose delegation deployments "May the agent deploy?" 3 \
      "Yes, to any environment|yes" \
      "Yes, but never to production|non-production" \
      "No, it prepares and I deploy|no"

    choose delegation database_operations "May the agent run migrations and data operations on a live database?" 3 \
      "Yes|yes" \
      "Yes, but never on production|non-production" \
      "No, it writes the migration and I run it|no"

    choose delegation dependency_changes "May the agent add or upgrade dependencies?" 2 \
      "Yes|yes" \
      "Yes, but it must justify each one first|with-justification" \
      "No|no"

    printf '\n--- Version control conventions ---\n'
    choose git commit_convention "Commit message convention" 1 \
      "Conventional, feat: add user profile endpoint|conventional" \
      "Plain imperative, Add user profile endpoint|plain"

    choose git branch_convention "Branch naming" 1 \
      "type/short-kebab-description, for example feat/team-invitations|type/short-kebab-description" \
      "username/description|username/description" \
      "ticket-id-description, for example PROJ-142-invitations|ticket-id-description"

    ask git default_branch "Default branch" no main

    printf '\n--- Engineering defaults ---\n'
    printf 'Empty means detect it from the project, which is what the skills do anyway.\n'
    ask engineering package_manager     "Preferred package manager"   no ""
    ask engineering deployment_platform "Preferred deployment target" no ""
    ask engineering database            "Preferred database"          no ""

    choose language documentation "Language of the technical documentation the agent writes" 1 \
      "English|english" "French|french" "Spanish|spanish" \
      "German|german" "Portuguese|portuguese" "Italian|italian"
  fi

  if [ "$need_writing" = "yes" ]; then
    printf '\n--- Creative writing ---\n'
    choose language creative_output "Default output language for fiction and poetry" 1 \
      "French, the craft these skills encode|french" \
      "English|english" "Spanish|spanish" \
      "German|german" "Portuguese|portuguese" "Italian|italian"
  fi

  if [ "$need_documents" = "yes" ]; then
    printf '\n--- Professional documents ---\n'
    ask identity organization "Organisation name on covers and letterheads" no ""

    choose language document_output "Default output language for documents, override it per recipient" 1 \
      "English|english" "French|french" "Spanish|spanish" \
      "German|german" "Portuguese|portuguese" "Italian|italian"

    choose documents pdf_engine "PDF engine" 1 \
      "Choose per document, then verify it is installed|" \
      "Headless Chromium|chromium" "WeasyPrint|weasyprint" \
      "Typst|typst" "LaTeX|latex"

    choose documents page_size "Page size" 1 "A4|A4" "US Letter|Letter"

    choose documents date_format "Date format" 1 \
      "ISO, 2026-08-11|iso" "French, 11 aout 2026|fr" "US, August 11, 2026|us"
  fi

  mkdir -p "$(dirname "$CONFIG_FILE")"
  local carried
  carried="$(preserved_sections)"
  {
    printf '# Craft Suite configuration\n'
    printf '# Written by install.sh --configure. Never store a secret here.\n'
    printf '# Field reference: config/README.md\n\n'
    printf 'identity:\n'
    printf '  author_name: "%s"\n'  "$(value_of identity author_name)"
    printf '  author_email: "%s"\n' "$(value_of identity author_email)"
    printf '  organization: "%s"\n' "$(value_of identity organization)"
    printf '\ndelegation:\n'
    printf '  commits: %s\n'             "$(value_of delegation commits)"
    printf '  branches: %s\n'            "$(value_of delegation branches)"
    printf '  push: %s\n'                "$(value_of delegation push)"
    printf '  pull_requests: %s\n'       "$(value_of delegation pull_requests)"
    printf '  release_tags: %s\n'        "$(value_of delegation release_tags)"
    printf '  deployments: %s\n'         "$(value_of delegation deployments)"
    printf '  database_operations: %s\n' "$(value_of delegation database_operations)"
    printf '  dependency_changes: %s\n'  "$(value_of delegation dependency_changes)"
    printf '\ngit:\n'
    printf '  commit_convention: %s\n'   "$(value_of git commit_convention)"
    printf '  branch_convention: "%s"\n' "$(value_of git branch_convention)"
    printf '  default_branch: %s\n'      "$(value_of git default_branch)"
    printf '  protected_branches: %s\n'  "$(value_of git protected_branches)"
    printf '\nlanguage:\n'
    printf '  skill: english\n'
    printf '  documentation: %s\n'    "$(value_of language documentation)"
    printf '  creative_output: %s\n'  "$(value_of language creative_output)"
    printf '  document_output: %s\n'  "$(value_of language document_output)"
    printf '\nengineering:\n'
    printf '  package_manager: "%s"\n'     "$(value_of engineering package_manager)"
    printf '  deployment_platform: "%s"\n' "$(value_of engineering deployment_platform)"
    printf '  database: "%s"\n'            "$(value_of engineering database)"
    printf '\ndocuments:\n'
    printf '  pdf_engine: "%s"\n' "$(value_of documents pdf_engine)"
    printf '  page_size: %s\n'    "$(value_of documents page_size)"
    printf '  date_format: %s\n'  "$(value_of documents date_format)"
    if [ -n "$carried" ]; then printf '%s\n' "$carried"; fi
  } > "$CONFIG_FILE"

  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
  printf '\nWritten: %s\n' "$CONFIG_FILE"

  write_manual_tasks
}

# Everything the agent was told not to do becomes a step somebody has to
# perform. This file is that list, with the commands, so nothing is silently
# left undone.
write_manual_tasks() {
  local file="${CLAUDE_MANUAL_TASKS_FILE:-$(dirname "$CONFIG_FILE")/craft-manual-tasks.md}"
  local branch commits push prs tags deploys dbops deps protected count=0
  branch="$(value_of git default_branch)";      [ -n "$branch" ] || branch=main
  commits="$(value_of delegation commits)"
  push="$(value_of delegation push)"
  prs="$(value_of delegation pull_requests)"
  tags="$(value_of delegation release_tags)"
  deploys="$(value_of delegation deployments)"
  dbops="$(value_of delegation database_operations)"
  deps="$(value_of delegation dependency_changes)"
  protected="$(value_of git protected_branches)"

  {
    printf '# Your manual steps\n\n'
    printf 'Generated by `bash install.sh --configure` on %s.\n\n' "$(date +%Y-%m-%d)"
    printf 'These are the actions you asked to keep. The agent will stop at each\n'
    printf 'boundary, hand you what it prepared, and name the step rather than\n'
    printf 'performing it. Re-run `--configure` to change any of them.\n\n'
    printf '## What you kept\n\n'

    case "$commits" in
      stage-only)
        count=$((count + 1))
        printf '### Commits\n\n'
        printf 'The agent stages the change and gives you the message it would have used.\n\n'
        printf '```bash\ngit diff --staged     # read it before committing\ngit commit\n```\n\n'
        ;;
      no)
        count=$((count + 1))
        printf '### Commits\n\n'
        printf 'The agent leaves the working tree ready and lists the atomic commits it\n'
        printf 'would have made, in order, with a message for each.\n\n'
        printf '```bash\ngit status\ngit diff\ngit add -p\ngit commit\n```\n\n'
        ;;
    esac

    [ "$(value_of delegation branches)" = "no" ] && {
      count=$((count + 1))
      printf '### Branches\n\n'
      printf 'Create the branch before asking for work, and tell the agent its name.\n\n'
      printf '```bash\ngit switch -c <type>/<short-description>\n```\n\n'
    }

    case "$push" in
      branch-only)
        count=$((count + 1))
        printf '### Pushing to a protected branch\n\n'
        printf 'The agent pushes feature branches only. Anything reaching `%s` is yours.\n\n' "$branch"
        ;;
      no)
        count=$((count + 1))
        printf '### Pushing\n\n'
        printf 'The agent commits locally and stops. Every push is yours.\n\n'
        printf '```bash\ngit log --oneline origin/%s..HEAD    # review first\ngit push -u origin HEAD\n```\n\n' "$branch"
        ;;
    esac

    case "$prs" in
      draft)
        count=$((count + 1))
        printf '### Marking a pull request ready\n\n'
        printf 'The agent opens drafts. Reviewing and marking ready is yours.\n\n'
        ;;
      no)
        count=$((count + 1))
        printf '### Pull requests\n\n'
        printf 'The agent writes the description into the branch and stops. Open it yourself.\n\n'
        printf '```bash\ngh pr create --fill\n```\n\n'
        ;;
    esac

    [ "$tags" = "no" ] && {
      count=$((count + 1))
      printf '### Tags and releases\n\n'
      printf 'The agent prepares the changelog and the version number, then stops.\n\n'
      printf '```bash\ngit tag -a v<x.y.z> -m "<summary>"\ngit push origin v<x.y.z>\n```\n\n'
    }

    case "$deploys" in
      non-production)
        count=$((count + 1))
        printf '### Production deployment\n\n'
        printf 'The agent deploys to non production environments and verifies them.\n'
        printf 'Promotion to production is yours, and so is running\n'
        printf '`production-verification` afterwards.\n\n'
        ;;
      no)
        count=$((count + 1))
        printf '### Deployment\n\n'
        printf 'The agent prepares the artefact, the migrations and the environment\n'
        printf 'variable list, then stops. Every deployment is yours.\n\n'
        ;;
    esac

    case "$dbops" in
      non-production)
        count=$((count + 1))
        printf '### Production database operations\n\n'
        printf 'The agent runs migrations outside production only. Production runs are\n'
        printf 'yours, after the row count check the migration note gives you.\n\n'
        ;;
      no)
        count=$((count + 1))
        printf '### Database operations\n\n'
        printf 'The agent writes the migration and the rollback, and states what each\n'
        printf 'one locks and for how long. Running them is yours.\n\n'
      ;;
    esac

    case "$deps" in
      with-justification)
        count=$((count + 1))
        printf '### Approving dependencies\n\n'
        printf 'The agent proposes each dependency with the twelve point evaluation from\n'
        printf '`dependency-selection`. Approval is yours before it installs anything.\n\n'
        ;;
      no)
        count=$((count + 1))
        printf '### Dependencies\n\n'
        printf 'The agent names what it needs and why, and writes the code against it.\n'
        printf 'Installing is yours.\n\n'
        printf '```bash\n<your package manager> add <package>\n```\n\n'
        ;;
    esac

    if [ "$count" -eq 0 ]; then
      printf 'Nothing. You delegated every step, so the agent carries the work from\n'
      printf 'the first commit to the verified deployment.\n\n'
      printf 'Two things are never delegated, whatever this file says:\n\n'
      printf '- A destructive operation is always counted and confirmed first.\n'
      printf '- A secret is never committed, and a leaked one is reported for\n'
      printf '  rotation rather than quietly removed.\n\n'
    fi

    printf '## Branch protection\n\n'
    case "$protected" in
      none)
        printf 'You allowed direct pushes. If you later protect `%s`, re-run\n' "$branch"
        printf '`--configure` so the agent switches to the pull request path.\n\n'
        ;;
      default)
        printf '`%s` is protected: nothing reaches it without a pull request.\n' "$branch"
        printf 'The agent never pushes to it directly, and never force pushes a shared\n'
        printf 'branch.\n\n'
        ;;
      default+release)
        printf '`%s` and the release branches are protected: nothing reaches them\n' "$branch"
        printf 'without a pull request. The agent never pushes to them directly.\n\n'
        ;;
    esac
    printf 'If protection is not configured on the host yet:\n\n'
    printf '```bash\ngh api -X PUT repos/{owner}/{repo}/branches/%s/protection \\\n' "$branch"
    printf '  -f required_pull_request_reviews.required_approving_review_count=1\n```\n\n'

    printf '## Files that must never be committed\n\n'
    printf 'Your responsibility as much as the agent'"'"'s. Verify the ignore file covers:\n\n'
    printf '```\n.env and .env.*\nprivate keys, certificates, credential files\nlocal agent and editor configuration\n```\n\n'
    printf 'A secret already committed is not fixed by deleting it. Rotate it.\n\n'
    printf '## Changing any of this\n\n'
    printf '```bash\nbash install.sh --configure\n```\n\n'
    printf 'Answers are pre-filled with what you chose. This file is rewritten.\n'
  } > "$file"

  printf 'Written: %s\n' "$file"
  printf 'Read it: it lists the steps you kept, with their commands.\n'
}

# Reports what the installed skills still need. Never guesses a value.
report_configuration_state() {
  # Only the engineering tree commits, so only it needs an identity.
  [ "$WANT_ENGINEERING" = "yes" ] || return 0

  if [ ! -f "$CONFIG_FILE" ]; then
    printf 'Configuration missing: %s\n' "$CONFIG_FILE"
    printf 'git-workflow stops without an author identity. Run: bash install.sh --configure\n'
    return 0
  fi
  local name email
  name="$(config_get identity author_name)"
  email="$(config_get identity author_email)"
  if [ -z "$name" ] || [ -z "$email" ]; then
    printf 'Configuration incomplete in %s:\n' "$CONFIG_FILE"
    [ -n "$name" ]  || printf '  identity.author_name is empty\n'
    [ -n "$email" ] || printf '  identity.author_email is empty\n'
    printf 'Run: bash install.sh --configure\n'
  fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

bootstrap

if [ "$MODE" = "control-center" ]; then
  # The Control Center is optional and self-contained: it reads local session
  # data and serves a single page. It needs nothing installed to run.
  command -v python3 >/dev/null \
    || die "The Control Center needs python3, which was not found on the PATH."
  [ -f "$ROOT/control-center/server.py" ] \
    || die "control-center/server.py not found beside the installer."
  # shellcheck disable=SC2086
  exec python3 "$ROOT/control-center/server.py" $CC_ARGS
fi

if [ "$MODE" = "report" ]; then
  command -v python3 >/dev/null \
    || die "The usage report needs python3, which was not found on the PATH."
  [ -f "$ROOT/control-center/reader.py" ] \
    || die "control-center/reader.py not found beside the installer."
  # shellcheck disable=SC2086
  exec python3 "$ROOT/control-center/reader.py" --report $CC_ARGS
fi

if [ "$MODE" = "list" ]; then
  list_skills
  exit 0
fi

if [ "$MODE" = "configure" ]; then
  # Configure asks about the trees that are installed, so infer them from the
  # target directory rather than making the user restate a scope.
  if [ "$SCOPE_GIVEN" = "no" ]; then
    [ -d "$TARGET/writing-constitution" ] && WANT_WRITING="yes"
    [ -d "$TARGET/document-core" ]        && WANT_DOCUMENTS="yes"
    [ -d "$TARGET/engineering-core" ]     && WANT_ENGINEERING="yes"
    if [ "$WANT_WRITING" = "no" ] && [ "$WANT_DOCUMENTS" = "no" ] \
       && [ "$WANT_ENGINEERING" = "no" ]; then
      WANT_WRITING="yes"; WANT_DOCUMENTS="yes"; WANT_ENGINEERING="yes"
    fi
  fi
  configure
  exit 0
fi

# No scope on the command line means ask. Never install everything by default:
# a developer should not receive a novelist's toolkit, and the reverse.
if [ "$SCOPE_GIVEN" = "no" ]; then
  interactive_select
fi

# After the prompt as well as before it: a name typed at the prompt is as
# likely to be wrong as one typed on the command line.
validate_selected_skills
validate_selected_groups

resolve_agents

if [ "$MODE" = "remove" ]; then
  count=0
  if [ "$WITH_SKILLS" = "yes" ]; then
    while IFS= read -r skill; do
      [ -n "$skill" ] || continue
      name="$(basename "$skill")"
      if [ -d "$TARGET/$name" ]; then
        rm -rf "${TARGET:?}/$name"
        count=$((count + 1))
      fi
    done < <(removable_skill_dirs)
    printf '%s skills removed from %s\n' "$count" "$TARGET"
    removing_everything \
      || printf 'Cross domain skills kept: another tree may still use them.\n'
  fi
  if [ "$WITH_AGENTS" = "yes" ]; then
    acount=0
    while IFS= read -r agent; do
      name="$(basename "$agent")"
      if [ -f "$AGENT_TARGET/$name" ]; then
        rm -f "${AGENT_TARGET:?}/$name"
        acount=$((acount + 1))
      fi
    done < <(agents)
    printf '%s agents removed from %s\n' "$acount" "$AGENT_TARGET"
  fi
  printf 'Configuration left untouched: %s\n' "$CONFIG_FILE"
  exit 0
fi

bash "$ROOT/tests/validate-structure.sh" >/dev/null 2>&1 || {
  printf 'Structure invalid, installation stopped. Run tests/validate-structure.sh for the detail.\n'
  exit 1
}

# Copies one skill directory without the artefacts a reader's own machine leaves
# beside it. A skill whose examples are a runnable project acquires a
# node_modules, a build directory and runtime state on the machine of whoever
# ran it. None of that is the skill: the build output would multiply an install
# a thousandfold, and the runtime state would carry that operator's password
# hash, sessions and received messages into every later install. The example
# content file is kept, because it is the worked example.
copy_skill() {
  local source="$1" destination="$2"
  mkdir -p "$destination"
  ( cd "$source" && tar -cf - \
      --exclude='node_modules' \
      --exclude='.next' \
      --exclude='out' \
      --exclude='*.tsbuildinfo' \
      --exclude='next-env.d.ts' \
      --exclude='package-lock.json' \
      --exclude='uploads' \
      --exclude='admin.json' \
      --exclude='sessions.json' \
      --exclude='messages.json' \
      --exclude='subscriptions.json' \
      --exclude='rate-limits.json' \
      . ) | ( cd "$destination" && tar -xf - )
}

if [ "$WITH_SKILLS" = "yes" ]; then
  mkdir -p "$TARGET"
  count=0
  added=""
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    name="$(basename "$skill")"
    rm -rf "${TARGET:?}/$name"
    copy_skill "$skill" "$TARGET/$name"
    count=$((count + 1))
    added="$added $name"
  done < <(selected_skill_dirs)
  printf '%s skills installed in %s\n' "$count" "$TARGET"
  # A named selection is short enough to show, and showing it is how the user
  # learns that dependencies were pulled in.
  if [ -n "${SELECTED_SKILLS// /}" ] && [ -z "${SELECTED_GROUPS// /}" ]; then
    printf 'Installed:%s\n' "$added"
  fi
fi

if [ "$WITH_AGENTS" = "yes" ]; then
  acount=0
  # The directory is created only when there is something to put in it, so a
  # scope that carries no agent leaves no empty directory behind.
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    mkdir -p "$AGENT_TARGET"
    cp "$agent" "$AGENT_TARGET/$(basename "$agent")"
    acount=$((acount + 1))
  done < <(agents)
  [ "$acount" -gt 0 ] \
    && printf '%s agents installed in %s\n' "$acount" "$AGENT_TARGET"
  if [ "$IS_ANTIGRAVITY" = "yes" ]; then
    mkdir -p "$RULES_TARGET"
    python3 "$ROOT/bin/craft-subagents.py" --write-rule "$RULES_TARGET/craft-subagents.md" >/dev/null 2>&1 || true
    python3 "$ROOT/bin/craft-subagents.py" --install-agents "$AGENT_TARGET" >/dev/null 2>&1 || true
    printf 'Antigravity agent files installed at %s\n' "$AGENT_TARGET"
    printf 'Antigravity subagents rule installed at %s/craft-subagents.md\n' "$RULES_TARGET"
  fi
fi

if [ "$MODE" = "zip" ]; then
  command -v zip >/dev/null || { printf 'zip not found, archives not built.\n'; exit 0; }
  mkdir -p "$ROOT/dist"
  rm -f "$ROOT"/dist/*.zip
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    name="$(basename "$skill")"
    parent="$(dirname "$skill")"
    ( cd "$parent" && zip -rq "$ROOT/dist/$name.zip" "$name" )
  done < <(selected_skill_dirs)
  printf '%s archives built in dist/\n' "$(ls "$ROOT"/dist/*.zip 2>/dev/null | wc -l)"
fi

report_configuration_state
