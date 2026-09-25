#!/usr/bin/env python3
"""Craft Suite to Antigravity CLI subagent adapter and generator.

Parses all 26 canonical agent definitions in agents/*/*.md and:
1. Generates native Antigravity declarative agent files (.md with YAML frontmatter)
   in the format: name, description, model, tools list
   Target: ~/.gemini/config/agents/<name>.md (or .agents/agents/<name>.md per project)
2. Generates a workspace rule for the agy CLI orchestration protocol
3. Provides a JSON manifest of all 26 agent definitions

Antigravity declarative agent format (from official docs):
  ---
  name: <unique-identifier>
  description: <what it does and when>
  model: flash          # optional: flash_lite, flash, pro
  tools:
    - view_file
    - replace_file_content
    - run_command
  ---
  # Markdown body = system instructions
"""

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Craft Suite tool names -> Antigravity tool names
# Based on Antigravity CLI tool registry (view_file, replace_file_content, run_command,
# grep_search, find_by_name, write_to_file, define_subagent, invoke_subagent, etc.)
CRAFT_TO_AGY_TOOLS = {
    "Read": "view_file",
    "Grep": "grep_search",
    "Glob": "find_by_name",
    "Bash": "run_command",
    "Write": "write_to_file",
    "Edit": "replace_file_content",
    "Agent": "invoke_subagent",
}

# Recommended model tiers based on engineering/dev-skills/model-routing
MODEL_TIERS = {
    # Strongest reasoning: architecture, principal review, security audit, delivery lifecycle
    "delivery-orchestrator": "pro",
    "principal-engineer": "pro",
    "software-architect": "pro",
    "security-engineer": "pro",

    # Balanced: domain engineering, implementations, diagnostics, performance
    "backend-engineer": "flash",
    "database-engineer": "flash",
    "frontend-engineer": "flash",
    "site-template-engineer": "flash",
    "ui-ux-engineer": "flash",
    "performance-engineer": "flash",
    "devops-engineer": "flash",
    "incident-responder": "flash",
    "release-engineer": "flash",
    "qa-engineer": "flash",
    "playwright-engineer": "flash",
    "documentation-engineer": "flash",
    "requirements-analyst": "flash",
    "checkup": "flash",
    "pr-reviewer": "flash",

    # Fast: verification, compliance, diff checks, pattern research, passive audit
    "compliance-verifier": "flash_lite",
    "final-verifier": "flash_lite",
    "pr-author": "flash_lite",
    "source-of-truth": "flash_lite",
    "design-verification": "flash_lite",
    "design-research": "flash_lite",
    "web-auditor": "flash_lite",
}

# Workspace isolation mode: branch for active code modification, inherit for review/audit
WORKSPACE_MODES = {
    "frontend-engineer": "branch",
    "backend-engineer": "branch",
    "database-engineer": "branch",
    "performance-engineer": "branch",
    "site-template-engineer": "branch",
    "ui-ux-engineer": "branch",
    "qa-engineer": "branch",
    "playwright-engineer": "branch",
    "security-engineer": "branch",
    "devops-engineer": "branch",
    "incident-responder": "branch",
    "documentation-engineer": "branch",
}


def parse_agent_file(filepath):
    """Parse an agent markdown file extracting YAML frontmatter and body."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    match = re.match(r"^---\n(.*?)\n---\n(.*)$", content, re.DOTALL)
    if not match:
        raise ValueError(f"Invalid agent file format: {filepath}")

    frontmatter_raw, body = match.group(1), match.group(2).strip()

    metadata = {}
    for line in frontmatter_raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            key, val = line.split(":", 1)
            metadata[key.strip()] = val.strip()

    name = metadata.get("name", "")
    description = metadata.get("description", "")
    tools_str = metadata.get("tools", "")
    tools = [t.strip() for t in tools_str.split(",") if t.strip()]

    # Antigravity permissions
    has_write = any(t in ["Write", "Edit", "Bash"] for t in tools)
    is_orchestrator = name in ["delivery-orchestrator", "principal-engineer"]

    model = MODEL_TIERS.get(name, "flash")
    workspace = WORKSPACE_MODES.get(name, "inherit")

    return {
        "name": name,
        "description": description,
        "tools": tools,
        "enable_write_tools": has_write,
        "enable_subagent_tools": is_orchestrator,
        "enable_mcp_tools": False,
        "recommended_model": model,
        "workspace_mode": workspace,
        "system_prompt": body,
        "source_path": os.path.relpath(filepath, ROOT),
    }


def load_all_agents():
    """Load all 26 canonical agent definitions."""
    pattern = os.path.join(ROOT, "agents", "*", "*.md")
    files = sorted(glob.glob(pattern))
    agents = []
    for fp in files:
        base = os.path.basename(fp)
        if base in ["README.md", "handoff-protocol.md"]:
            continue
        agents.append(parse_agent_file(fp))
    return agents


def format_table(agents):
    """Format agents as a readable markdown table."""
    lines = [
        "| Agent Name | Model | Write Tools | Subagent Tools | Workspace | Description |",
        "|---|---|---|---|---|---|",
    ]
    for a in agents:
        write_flag = "Yes" if a["enable_write_tools"] else "No"
        sub_flag = "Yes" if a["enable_subagent_tools"] else "No"
        desc = (a["description"][:65] + "...") if len(a["description"]) > 65 else a["description"]
        lines.append(f"| `{a['name']}` | `{a['recommended_model']}` | {write_flag} | {sub_flag} | `{a['workspace_mode']}` | {desc} |")
    return "\n".join(lines)


def generate_rule_content(agents):
    """Generate Antigravity workspace rule for subagents."""
    table = format_table(agents)
    return f"""# Craft Suite Subagent Protocol for Antigravity CLI

This rule governs how the primary Antigravity agent discovers, defines, and invokes
the twenty-six specialized Craft Suite subagents using Antigravity runtime tools.

## 1. Discovery and Invocation Model

Antigravity CLI provides native subagent lifecycle tools:
- `define_subagent`: Registers a specialized agent role with its system prompt and tool capabilities.
- `invoke_subagent`: Dispatches one or more subagents in parallel with role, prompt, model tier, and workspace isolation.
- `manage_subagents`: Inspects or cancels running subagent tasks.
- `send_message`: Communicates with active or idle subagents.

When a complex or specialized task arrives, the primary agent should NOT attempt to solve
every aspect in a single flat context. Instead, it defines and delegates to the appropriate
specialist subagent.

## 2. Delegation Procedure

1. **Identify the Specialist**: Locate the agent matching the task in the catalog below.
2. **Define the Subagent**: If not already defined in the current session, call `define_subagent`:
   ```python
   define_subagent(
       name="<agent-name>",
       description="<agent-description>",
       enable_write_tools=<enable_write_tools>,
       enable_subagent_tools=<enable_subagent_tools>,
       enable_mcp_tools=False,
       system_prompt="<system_prompt from agents/*/<agent-name>.md>"
   )
   ```
3. **Invoke the Subagent**: Dispatch the work using `invoke_subagent`:
   ```python
   invoke_subagent(
       Subagents=[
           {{
               "TypeName": "<agent-name>",
               "Role": "<Human Readable Role>",
               "Prompt": "<Actionable task specification>",
               "Model": "<recommended_model>",
               "Workspace": "<workspace_mode>"
           }}
       ]
   )
   ```
4. **Handoff and Verification**: Inspect the returned durable artifact and run the mandatory gates.

## 3. Subagent Catalog (26 Roles)

{table}

## 4. Workspace Isolation Rules

- Use `Workspace: "branch"` whenever the subagent performs code modifications, database schema edits, or aggressive refactoring. This keeps the primary branch clean until verification passes.
- Use `Workspace: "inherit"` for read-only audits, compliance checks, research, and test execution against existing code.
"""


def generate_agy_agent_file(agent):
    """Generate a native Antigravity declarative agent .md file for one agent.

    The format follows the Antigravity CLI declarative agent specification:
    ---
    name: <name>
    description: <description>
    model: <flash_lite|flash|pro>
    tools:
      - view_file
      - run_command
    ---
    # Markdown body = system instructions
    """
    craft_tools = agent["tools"]
    # Map Craft Suite tool names to Antigravity tool names; skip unknowns
    agy_tools = []
    for t in craft_tools:
        mapped = CRAFT_TO_AGY_TOOLS.get(t)
        if mapped and mapped not in agy_tools:
            agy_tools.append(mapped)
    # Orchestrators also get subagent management tools
    if agent["name"] in ["delivery-orchestrator", "principal-engineer"]:
        for extra in ["define_subagent", "invoke_subagent", "manage_subagents", "send_message"]:
            if extra not in agy_tools:
                agy_tools.append(extra)

    tools_yaml = "\n".join(f"  - {t}" for t in agy_tools)
    model = agent["recommended_model"]
    body = agent["system_prompt"]

    return f"""---
name: {agent['name']}
description: {agent['description']}
model: {model}
tools:
{tools_yaml}
---
{body}
"""


def install_agy_agents(agents, target_dir):
    """Write all 26 native Antigravity agent .md files to target_dir."""
    os.makedirs(target_dir, exist_ok=True)
    count = 0
    for agent in agents:
        content = generate_agy_agent_file(agent)
        out_path = os.path.join(target_dir, f"{agent['name']}.md")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(content)
        count += 1
    return count


def main():
    default_agy_agents_dir = os.path.expanduser("~/.gemini/config/agents")

    parser = argparse.ArgumentParser(description="Craft Suite Antigravity Subagents Adapter")
    parser.add_argument("--list", action="store_true", help="List all 26 agents and Antigravity mapping")
    parser.add_argument("--json", action="store_true", help="Dump all agent definitions as JSON")
    parser.add_argument("--get", type=str, metavar="NAME", help="Get the native Antigravity .md for a specific agent")
    parser.add_argument("--generate-rule", action="store_true", help="Print the Antigravity orchestration rule markdown")
    parser.add_argument("--write-rule", type=str, metavar="FILE", help="Write Antigravity orchestration rule to FILE")
    parser.add_argument(
        "--install-agents",
        nargs="?",
        const=default_agy_agents_dir,
        metavar="DIR",
        help=f"Write all 26 native Antigravity agent files to DIR (default: {default_agy_agents_dir})",
    )

    args = parser.parse_args()
    agents = load_all_agents()

    if args.list:
        print(f"Loaded {len(agents)} agents from Craft Suite:")
        print(format_table(agents))
    elif args.json:
        print(json.dumps(agents, indent=2))
    elif args.get:
        target = next((a for a in agents if a["name"] == args.get), None)
        if not target:
            print(f"Error: Agent '{args.get}' not found.", file=sys.stderr)
            sys.exit(1)
        print(generate_agy_agent_file(target), end="")
    elif args.generate_rule:
        print(generate_rule_content(agents))
    elif args.write_rule:
        content = generate_rule_content(agents)
        os.makedirs(os.path.dirname(os.path.abspath(args.write_rule)), exist_ok=True)
        with open(args.write_rule, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Rule written to {args.write_rule}")
    elif args.install_agents is not None:
        count = install_agy_agents(agents, args.install_agents)
        print(f"{count} Antigravity agent files installed in {args.install_agents}")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
