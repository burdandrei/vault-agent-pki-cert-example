# Interactive Demo Skill — Plan

## Top-Level Overview

Create a Bob skill (`run-demo`) that walks the user through the three "easy" flows (Basic, nginx, HAProxy) interactively inside the Bob chat. The skill will:

- Explain what each step does before executing it
- Run each command via `execute_command` and surface the output
- Ask the user for confirmation before proceeding to the next step
- Cover prerequisites → Vault start → Terraform apply → token issuance → selected flows in sequence

**Key UX decisions (confirmed with user):**
- Vault dev server: skill asks if the user wants the agent to start it (backgrounded via `&`) or if they will start it themselves in a separate terminal
- No teardown between flows — teardown is only offered at the very end
- Flow selection: `ask_followup_question` with `allow_multiple: true` lets the user pick any subset of Basic / nginx / HAProxy before execution begins

The skill is a new file at `.bob/skills/run-demo.md` following the Bob skill format.

---

## Sub-Tasks

### Sub-Task 1 — Discover the Bob skill format

**Intent**: Understand exactly what frontmatter, sections, and conventions a `.bob/skills/*.md` file must contain, so the skill is valid and will load correctly.

**Expected Outcomes**
- Know the required frontmatter fields (name, description, etc.)
- Know how skill instructions are structured

**Todo List**
1. Use `use_skill` with `skill_name: "create-skill"` to load the authoring guide
2. Inspect any existing skill file in `.bob/skills/` if one exists

**Relevant Context**
- `.bob/skills/` directory (check if it exists and contains examples)

**Status**: [ ] pending

---

### Sub-Task 2 — Read all relevant repo files

**Intent**: Ground the skill's step-by-step instructions in the actual commands, file paths, and sequencing used by the repo.

**Expected Outcomes**
- Exact commands for each flow phase confirmed from source files
- File paths for templates, certs, and configs confirmed
- Edge-cases (e.g. nginx must be started from repo root, HAProxy bundle assembly) captured

**Todo List**
1. Read [`nginx/start-nginx.sh`](nginx/start-nginx.sh), [`nginx/reload-nginx.sh`](nginx/reload-nginx.sh), [`nginx/nginx.conf`](nginx/nginx.conf)
2. Read [`haproxy/start-haproxy.sh`](haproxy/start-haproxy.sh), [`haproxy/reload-haproxy.sh`](haproxy/reload-haproxy.sh), [`haproxy/haproxy.cfg`](haproxy/haproxy.cfg)
3. Read [`echo.hcl`](echo.hcl), [`nginx.hcl`](nginx.hcl), [`haproxy.hcl`](haproxy.hcl)
4. Read [`issue-tokens.sh`](issue-tokens.sh), [`cleanup.sh`](cleanup.sh)
5. Read terraform outputs (confirm paths and role names)

**Relevant Context**
- README.md (already read)
- AGENTS.md non-obvious patterns section

**Status**: [ ] pending

---

### Sub-Task 3 — Author the `run-demo` skill file

**Intent**: Write `.bob/skills/run-demo.md` — the interactive skill that guides the user through the demo end-to-end.

**Expected Outcomes**
- Skill file is valid (correct frontmatter, activatable by name `run-demo`)
- Skill instructs the agent to: explain → execute → show output → ask confirmation before each step
- Covers all phases in order:
  1. Prerequisites check (Vault, Terraform, Podman available via `which`)
  2. **Vault dev server**: `ask_followup_question` — "Should I start `vault server -dev` for you (background), or will you start it yourself?" → if yes, run it backgrounded; then verify Vault is reachable with `vault status`
  3. Export env vars + copy `.vault-token` file (agent executes `export` and `cp` commands)
  4. `terraform apply` (with explanation of what Terraform provisions)
  5. `issue-tokens.sh` (with explanation of scoped tokens)
  6. **Flow selection**: `ask_followup_question` with `allow_multiple: true` — options: Basic / nginx / HAProxy
  7. **Basic flow** (if selected) — `vault agent -config=./echo.hcl -exit-after-auth`, verify cert with `openssl`
  8. **nginx flow** (if selected) — init cert (`-exit-after-auth`), start container, instruct user to run continuous agent in separate terminal, verify cert
  9. **HAProxy flow** (if selected) — init cert (`-exit-after-auth`), assemble bundle, start container, instruct user to run continuous agent in separate terminal, verify cert
  10. **Teardown** (single optional phase at the end) — offer `terraform destroy` + manual token file cleanup
- Each phase is wrapped in: explanation → `execute_command` → output shown → `ask_followup_question` "Continue?"
- Skill handles the "blocking process" problem: `vault agent` without `-exit-after-auth` is long-running; skill instructs the user to run those in a separate terminal and confirms when ready

**Todo List**
1. Design the skill's phase list and the exact wording for each explanation
2. Write the skill file with valid frontmatter and full step instructions
3. Verify the file is syntactically valid YAML frontmatter + Markdown

**Relevant Context**
- `.bob/skills/run-demo.md` — new file to create
- Skill authoring guide (loaded in Sub-Task 1)
- All commands confirmed in Sub-Task 2

**Status**: [ ] pending

---

### Sub-Task 4 — Smoke-test the skill activation

**Intent**: Confirm the skill loads without errors by activating it in the current session.

**Expected Outcomes**
- `use_skill "run-demo"` resolves and prints skill instructions with no errors
- The phase list and confirmations are coherent

**Todo List**
1. Activate the skill with `use_skill "run-demo"`
2. Review the printed instructions for correctness and completeness
3. Fix any issues found

**Relevant Context**
- `.bob/skills/run-demo.md`

**Status**: [ ] pending

---

## Key Design Decisions

| Decision | Choice |
|---|---|
| Flows covered | Basic, nginx, HAProxy (no DataPower) |
| Flow selection | `ask_followup_question` with `allow_multiple: true` before execution begins |
| Command execution | `execute_command` (agent runs commands automatically) |
| Vault dev server | User chooses: agent starts it backgrounded OR user runs it themselves |
| Long-running agents | Instructed to open a separate terminal; skill does NOT block on `vault agent` continuous mode |
| Confirmation gate | `ask_followup_question` "Ready to proceed?" before each major phase |
| Teardown | Single optional phase at the end only — no teardown between flows |

## Non-Goals

- DataPower flow
- Modifying any existing HCL, template, or script files
- Automating the long-running `vault agent` processes (those are terminal-resident by nature)
