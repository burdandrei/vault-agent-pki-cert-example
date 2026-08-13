---
name: run-demo
description: Activate when the user says "run the demo", "start the demo", "walk me through the demo", or "/run-demo" — interactively executes the Vault Agent PKI certificate demo step by step, with flow selection (Basic / nginx / HAProxy), confirmations before each phase, and optional teardown at the end.
---

# Vault Agent PKI Demo — Interactive Runner

You are guiding the user through the Vault Agent PKI demo interactively.

**Ground rules for every step:**
- Before executing each command, print a short explanation of what it does and why.
- Run the command with `execute_command` and show the output in chat.
- After each major phase, use `ask_followup_question` to confirm before proceeding. Always offer at least three choices: "Yes, continue", "No, stop here", and one context-appropriate third option (e.g. "Retry", "Skip this step", "Need a moment").
- Never skip ahead — wait for explicit confirmation at each gate.
- If a command fails, explain the error and ask what the user wants to do (retry / skip / abort).
- Some `vault agent` commands without `-exit-after-auth` are **long-running processes** — never run those with `execute_command`. Instead, print the exact command and ask the user to paste it into a separate terminal, then confirm when it is running.

---

## Phase 0 — Prerequisites

**Explain:** "Let me verify the required tools are installed before we start."

Run these three checks with a single `execute_command`:

```bash
echo "=== Prerequisites Check ===" \
  && echo -n "vault:     " && vault version \
  && echo -n "terraform: " && terraform version -no-color 2>&1 | head -1 \
  && echo -n "podman:    " && podman --version
```

If any tool is missing (command not found), stop and tell the user which tool to install and link them to the README prerequisites section. Only continue when all three are present.

Use `ask_followup_question`:
- **Question:** "Prerequisites look good — ready to start Vault?"
- **Suggestion A:** "Yes — let's start Vault"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run the prerequisites check"

---

## Phase 1 — Start Vault Dev Server

**Explain:** "Vault must be running in dev mode for the demo. Dev mode starts a fully in-memory server with a pre-set root token (`root`) — perfect for local testing. The server process is long-running and needs its own terminal."

Ask the user with `ask_followup_question`:
- **Question:** "How would you like to start the Vault dev server?"
- **Suggestion A:** "Start it for me in the background (agent runs `vault server -dev &`)"
- **Suggestion B:** "I'll start it myself — please give me the command to paste in a new terminal"
- **Suggestion C:** "I already have a Vault dev server running — skip ahead and verify it"

**If the user picks A (agent starts it):**

Run with `execute_command`:
```bash
VAULT_DEV_ROOT_TOKEN_ID=root vault server -dev -dev-root-token-id=root -log-level=ERROR > /tmp/vault-dev.log 2>&1 &
echo "Vault dev PID: $!"
sleep 2
```

Then verify it is reachable:
```bash
export VAULT_ADDR='http://127.0.0.1:8200' && export VAULT_TOKEN='root' && vault status
```

**If the user picks B (user starts it themselves):**

Print this block for them to copy:
```
vault server -dev -dev-root-token-id=root -log-level=DEBUG
```
Tell them to open a new terminal, paste the command, and leave it running.
Then use `ask_followup_question`:
- **Question:** "Is Vault running in the new terminal?"
- **Suggestion A:** "Vault is running — continue"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "It failed to start — show me what to check"
Once confirmed, verify with `execute_command`:
```bash
export VAULT_ADDR='http://127.0.0.1:8200' && export VAULT_TOKEN='root' && vault status
```

**If the user picks C (Vault already running):**

Skip starting the server. Go straight to verifying reachability:
```bash
export VAULT_ADDR='http://127.0.0.1:8200' && export VAULT_TOKEN='root' && vault status
```

If `vault status` fails, tell the user Vault does not appear to be reachable and ask them to check whether the dev server is actually running (correct address, correct token) before retrying.

If `vault status` succeeds, confirm: "Found a running Vault at `http://127.0.0.1:8200` — proceeding with the existing server."

If `vault status` fails, tell the user Vault does not appear to be reachable and ask them to check whether the dev server is actually running before retrying.

Use `ask_followup_question`:
- **Question:** "Vault is up — ready to set environment variables?"
- **Suggestion A:** "Yes — set environment variables"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run vault status to double-check"

---

## Phase 2 — Export Environment Variables & Copy Token

**Explain:** "We need four environment variables so every subsequent `vault` and `terraform` command knows where Vault lives and how to authenticate. We also copy the dev-mode token file into the repo root so Vault Agent's `echo.hcl` can find it."

Run with `execute_command`:
```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
export VAULT_SKIP_VERIFY='true'
cp ~/.vault-token .vault-token
echo "Token copied. VAULT_ADDR=$VAULT_ADDR  VAULT_TOKEN=$VAULT_TOKEN"
```

Note: `export` statements set the environment for this session. The `.vault-token` file is read by `echo.hcl` at agent startup.

Use `ask_followup_question`:
- **Question:** "Environment ready — proceed to Terraform?"
- **Suggestion A:** "Yes — apply Terraform"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Show me the current environment variables first"

---

## Phase 3 — Apply Terraform

**Explain:** "Terraform provisions all Vault infrastructure: two PKI secrets engines (root + intermediate CA), four PKI roles (`demoissuer`, `nginx`, `haproxy`, `datapower`), ACL policies, token auth backend roles, and a file audit device. This takes about 30 seconds."

Run with `execute_command` (cwd: `terraform`):
```bash
terraform init -no-color && terraform apply -auto-approve -no-color
```
Use `cwd: "terraform"` so Terraform finds its working directory.

After the command finishes, show the output section labelled `Outputs:` to the user and explain what each value means (mount paths, role names, issue paths).

Use `ask_followup_question`:
- **Question:** "Terraform applied — ready to issue scoped tokens?"
- **Suggestion A:** "Yes — issue tokens"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Show me the Terraform outputs again"

---

## Phase 4 — Issue Per-Service Tokens

**Explain:** "Each Vault Agent authenticates with a least-privilege token that only has access to the PKI role it needs. `issue-tokens.sh` mints three tokens and writes them to `.vault-token-nginx`, `.vault-token-haproxy`, and `.vault-token-datapower`. (We only need nginx and haproxy for the flows we're running, but the script issues all three.)"

Run with `execute_command`:
```bash
bash ./issue-tokens.sh
```

Verify the token files were created:
```bash
ls -lh .vault-token-nginx .vault-token-haproxy
```

Ask: "Tokens issued — which flows do you want to run?"

---

## Phase 5 — Choose Flows

Use `ask_followup_question` with `allow_multiple: true`:

- **Question:** "Which flows do you want to run? (select all that apply)"
- **Suggestion A:** "Basic — Vault Agent issues a PKI cert and writes it to certs/"
- **Suggestion B:** "nginx — Vault Agent provisions a TLS cert and auto-reloads nginx on renewal"
- **Suggestion C:** "HAProxy — Vault Agent provisions a TLS cert and sends SIGHUP to HAProxy on renewal"

Record which flows were selected and run only those phases below.

---

## Phase 6A — Basic Flow (run only if selected)

**Explain:** "The Basic flow runs `vault agent` with `-exit-after-auth`, which means the agent authenticates once, renders the certificate template to `certs/cert.pem` (and a combined `certs/destination.out`), then exits. The `exec` block in `echo.hcl` also fires `openssl x509 -noout -dates` on the cert so we see its validity window immediately."

Run with `execute_command`:
```bash
vault agent -config=./echo.hcl -exit-after-auth
```

Then verify the cert:
```bash
openssl x509 -in certs/cert.pem -noout -subject -dates
```

Explain the output — the `notBefore` / `notAfter` fields confirm the cert was freshly issued by the intermediate CA. Point out the short TTL (set to 72 h max by the `demoissuer` role) which is what drives automatic renewal in a long-running agent session.

Use `ask_followup_question`:
- **Question:** "Basic flow complete — what would you like to do next?"
- **Suggestion A:** "Continue to the next selected flow (or teardown if none remain)"
- **Suggestion B:** "Stop here"
- **Suggestion C:** "Re-run openssl to inspect the cert again"

---

## Phase 6B — nginx Flow (run only if selected)

### Step 1 — Issue Initial Certificate

**Explain:** "We need the cert on disk before the nginx container starts, so we run the agent once with `-exit-after-auth`. The `exec` block (which calls `nginx/reload-nginx.sh`) will fail because the container isn't running yet — that's expected and safe."

Run with `execute_command`:
```bash
vault agent -config=./nginx.hcl -exit-after-auth
```

Verify:
```bash
ls -lh certs/nginx-cert.pem certs/nginx-privkey.pem
openssl x509 -in certs/nginx-cert.pem -noout -subject -dates
```

### Step 2 — Start nginx Container

**Explain:** "The script starts an `nginx:alpine` container via Podman, mounts the config and the `certs/` directory read-only, and exposes HTTP on `8080` (redirect only) and HTTPS on `8443`."

Run with `execute_command`:
```bash
bash nginx/start-nginx.sh
```

Then check the container is up:
```bash
podman ps --filter name=nginx-vault --format "{{.Names}}  {{.Status}}"
```

Optionally verify TLS:
```bash
curl -sk https://localhost:8443 | head -5
```

### Step 3 — Continuous Renewal Agent

**Explain:** "`vault agent -config=./nginx.hcl` (without `-exit-after-auth`) runs indefinitely. It watches the cert TTL and re-issues before expiry, then calls `nginx/reload-nginx.sh` — which sends `nginx -s reload` inside the container — so nginx picks up the new cert with zero downtime. This is a long-running process and must run in a separate terminal."

Print this command for the user to copy:
```
vault agent -log-level debug -config=./nginx.hcl
```

Use `ask_followup_question`:
- **Question:** "Is Vault Agent for nginx running in a separate terminal?"
- **Suggestion A:** "Yes — it's running, continue"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "Run it for me in the background instead"

**If the user picks C (run in background):** run with `execute_command`:
```bash
vault agent -log-level debug -config=./nginx.hcl > /tmp/vault-agent-nginx.log 2>&1 &
echo "Vault Agent nginx PID: $!"
sleep 3 && tail -5 /tmp/vault-agent-nginx.log
```

After confirmation (A or C), verify the cert one more time:
```bash
openssl x509 -in certs/nginx-cert.pem -noout -subject -dates
```

Use `ask_followup_question`:
- **Question:** "nginx flow complete — what would you like to do next?"
- **Suggestion A:** "Continue to the next selected flow (or teardown)"
- **Suggestion B:** "Stop here"
- **Suggestion C:** "Verify the cert and TLS endpoint one more time"

---

## Phase 6C — HAProxy Flow (run only if selected)

### Step 1 — Issue Initial Certificate

**Explain:** "Same pattern as nginx: we seed the cert files with a one-shot agent run before starting the container. HAProxy needs the private key and cert concatenated into a single bundle file, which `reload-haproxy.sh` handles on every renewal — but we do it manually for the first run."

Run with `execute_command`:
```bash
vault agent -config=./haproxy.hcl -exit-after-auth
```

Verify:
```bash
ls -lh certs/haproxy-cert.pem certs/haproxy-privkey.pem
openssl x509 -in certs/haproxy-cert.pem -noout -subject -dates
```

### Step 2 — Assemble the Initial Bundle

**Explain:** "HAProxy requires its TLS file to contain the private key first, then the certificate chain. We concatenate them now so the container has a valid bundle on startup."

Run with `execute_command`:
```bash
cat certs/haproxy-privkey.pem certs/haproxy-cert.pem > certs/haproxy-bundle.pem
ls -lh certs/haproxy-bundle.pem
```

### Step 3 — Start HAProxy Container

**Explain:** "The script starts an `haproxy:alpine` container via Podman, mounts the config and `certs/` read-only, and exposes HTTP on `8090` and HTTPS on `8453`."

Run with `execute_command`:
```bash
bash haproxy/start-haproxy.sh
```

Check the container:
```bash
podman ps --filter name=haproxy-vault --format "{{.Names}}  {{.Status}}"
```

Optionally verify TLS:
```bash
curl -sk https://localhost:8453 | head -5
```

### Step 4 — Continuous Renewal Agent

**Explain:** "`vault agent -config=./haproxy.hcl` runs indefinitely. On each cert renewal it calls `haproxy/reload-haproxy.sh`, which rebuilds `certs/haproxy-bundle.pem` and sends `SIGHUP` to the `haproxy-vault` container for a graceful reload. This is a long-running process and must run in a separate terminal."

Print this command for the user to copy:
```
vault agent -config=./haproxy.hcl
```

Use `ask_followup_question`:
- **Question:** "Is Vault Agent for HAProxy running in a separate terminal?"
- **Suggestion A:** "Yes — it's running, continue"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "Run it for me in the background instead"

**If the user picks C (run in background):** run with `execute_command`:
```bash
vault agent -config=./haproxy.hcl > /tmp/vault-agent-haproxy.log 2>&1 &
echo "Vault Agent HAProxy PID: $!"
sleep 3 && tail -5 /tmp/vault-agent-haproxy.log
```

After confirmation (A or C):
```bash
openssl x509 -in certs/haproxy-cert.pem -noout -subject -dates
```

Use `ask_followup_question`:
- **Question:** "HAProxy flow complete — what would you like to do next?"
- **Suggestion A:** "Proceed to teardown"
- **Suggestion B:** "Stop here, leave everything running"
- **Suggestion C:** "Verify the cert and TLS endpoint one more time"

---

## Phase 7 — Teardown (optional)

Use `ask_followup_question`:
- **Question:** "All selected flows are complete. Do you want to tear down the Vault infrastructure?"
- **Suggestion A:** "Yes — run terraform destroy and clean up generated files"
- **Suggestion B:** "No — leave everything running for now"

**If yes:**

**Explain:** "First stop the Vault Agent processes and containers if they are running (you can Ctrl-C those terminals now). Then we destroy the Vault resources managed by Terraform and delete generated cert files."

Use `ask_followup_question`:
- **Question:** "Have you stopped the Vault Agent terminals and containers?"
- **Suggestion A:** "Yes, all stopped — run terraform destroy"
- **Suggestion B:** "Need a moment"
- **Suggestion C:** "Show me the commands to stop them"

**If the user picks C:** print:
```
# Kill background agents (if started in background):
kill $(cat ./pidfile 2>/dev/null) 2>/dev/null
pkill -f 'vault agent' 2>/dev/null

# Stop containers:
podman stop nginx-vault haproxy-vault 2>/dev/null
```
Then re-ask the confirmation question.

Once confirmed, run with `execute_command` (cwd: `terraform`):
```bash
terraform destroy -auto-approve -no-color
```

Then clean up token files and cert/out files:
```bash
rm -f .vault-token-nginx .vault-token-haproxy .vault-token-datapower
bash ./cleanup.sh
```

**Explain what was removed:** Terraform destroyed the PKI engines, roles, policies, and token auth backend roles from Vault. `cleanup.sh` deleted all generated `.pem` and `.out` files. The `.vault-token` (root dev token copy) is also gone.

Print a final summary:
```
✓ Vault infrastructure destroyed
✓ Generated cert files removed
✓ Token files removed
Demo complete.
```
