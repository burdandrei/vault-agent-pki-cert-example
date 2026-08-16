---
name: run-demo
description: Activate when the user says "run the demo", "start the demo", "walk me through the demo", or "/run-demo" — interactively executes the Vault Agent PKI certificate demo step by step, with flow selection (Basic / nginx / HAProxy / DataPower), confirmations before each phase, and optional teardown at the end.
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

Run these checks with a single `execute_command`:

```bash
echo "=== Prerequisites Check ===" \
  && echo -n "vault:     " && vault version \
  && echo -n "terraform: " && terraform version -no-color 2>&1 | head -1 \
  && echo -n "podman:    " && podman --version \
  && echo -n "curl:      " && curl --version | head -1
```

If any tool is missing (command not found), stop and tell the user which tool to install and link them to the README prerequisites section. Note: `curl` is only strictly required for the DataPower flow (used by `upload-certs-to-datapower.sh`), but flag it now so there are no surprises later. Only continue when vault, terraform, and podman are present.

Use `ask_followup_question`:
- **Question:** "Prerequisites look good — ready to begin?"
- **Suggestion A:** "Yes — let's go"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run the prerequisites check"

---

## Phase 1 — Start Vault Dev Server

**Explain:** "Let me check whether a Vault dev server is already reachable before we decide what to do."

First, silently probe Vault with `execute_command`:
```bash
VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='root' vault status -format=json 2>/dev/null \
  && echo "VAULT_RUNNING=yes" || echo "VAULT_RUNNING=no"
```

**If the output contains `VAULT_RUNNING=yes`:**

Confirm to the user: "Found a running Vault dev server at `http://127.0.0.1:8200` — no need to start a new one."

Use `ask_followup_question`:
- **Question:** "Vault is already running — continue with this server?"
- **Suggestion A:** "Yes — use the existing server"
- **Suggestion B:** "No — start a fresh dev server instead"
- **Suggestion C:** "Stop here"

If the user picks B, proceed with the "start a fresh server" path below (kill any existing process first: `pkill -f 'vault server' 2>/dev/null; sleep 1`).

**If the output contains `VAULT_RUNNING=no`:**

**Explain:** "No Vault server found at `http://127.0.0.1:8200`. Dev mode starts a fully in-memory server with a pre-set root token (`root`) — perfect for local testing. The server process is long-running and needs its own terminal."

Use `ask_followup_question`:
- **Question:** "How would you like to start the Vault dev server?"
- **Suggestion A:** "Start it for me in the background"
- **Suggestion B:** "I'll start it myself — give me the command to paste in a new terminal"

**If the user picks A (agent starts it):**

Run with `execute_command`:
```bash
VAULT_DEV_ROOT_TOKEN_ID=root vault server -dev -dev-root-token-id=root -log-level=ERROR > /tmp/vault-dev.log 2>&1 &
echo "Vault dev PID: $!"
sleep 2
```

**If the user picks B (user starts it themselves):**

Print this for them to copy into a new terminal:
```
vault server -dev -dev-root-token-id=root -log-level=DEBUG
```
Then use `ask_followup_question`:
- **Question:** "Is Vault running in the new terminal?"
- **Suggestion A:** "Yes — it's running"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "It failed to start — show me what to check"

---

**After any of the above paths**, verify Vault is reachable with `execute_command`:
```bash
export VAULT_ADDR='http://127.0.0.1:8200' && export VAULT_TOKEN='root' && vault status
```

If `vault status` fails, tell the user Vault is not reachable and ask them to check whether the server is running at the correct address before retrying.

If `vault status` succeeds, confirm: "Vault is up at `http://127.0.0.1:8200`."

Use `ask_followup_question`:
- **Question:** "Vault is up — ready to set environment variables?"
- **Suggestion A:** "Yes — continue"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run vault status to double-check"

---

## Phase 2 — Export Environment Variables

**Explain:** "We need three environment variables so every subsequent `vault` and `terraform` command knows where Vault lives and how to authenticate."

Run with `execute_command`:
```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
export VAULT_SKIP_VERIFY='true'
echo "VAULT_ADDR=$VAULT_ADDR  VAULT_TOKEN=$VAULT_TOKEN"
```

Note: `export` statements set the environment for this session only.

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

**Explain:** "Each Vault Agent authenticates with a least-privilege token that only has access to the PKI role it needs. `issue-tokens.sh` mints three tokens and writes them to `.vault-token-nginx`, `.vault-token-haproxy`, and `.vault-token-datapower` — one per service, and all three may be needed depending on which flows you select."

Run with `execute_command`:
```bash
bash ./issue-tokens.sh
```

Verify the token files were created:
```bash
ls -lh .vault-token-nginx .vault-token-haproxy .vault-token-datapower
```

Use `ask_followup_question`:
- **Question:** "Tokens issued — which flows do you want to run?"
- **Suggestion A:** "Continue to flow selection"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run ls to verify the token files"

---

## Phase 5 — Choose Flows

Use `ask_followup_question` with `allow_multiple: true`:

- **Question:** "Which flows do you want to run? (select all that apply)"
- **Suggestion A:** "Basic — Vault Agent issues a PKI cert and writes it to certs/"
- **Suggestion B:** "nginx — Vault Agent provisions a TLS cert and auto-reloads nginx on renewal"
- **Suggestion C:** "HAProxy — Vault Agent provisions a TLS cert and sends SIGHUP to HAProxy on renewal"
- **Suggestion D:** "DataPower — Vault Agent provisions TLS certs, starts the IBM DataPower container, and auto-uploads renewed certs via the REST Management API"

Record which flows were selected and run only those phases below.

---

## Phase 6A — Basic Flow (run only if selected)

**Explain:** "The Basic flow uses `echo.hcl`, which authenticates via a token file at `.vault-token` in the repo root. Vault dev mode writes the root token to `~/.vault-token` — we copy it here so the agent can find it. Then we run the agent with `-exit-after-auth`: it authenticates once, renders the certificate template to `certs/cert.pem` (and a combined `certs/destination.out`), then exits. The `exec` block in `echo.hcl` also fires `openssl x509 -noout -dates` on the cert so we see its validity window immediately."

Run with `execute_command`:
```bash
cp ~/.vault-token .vault-token
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

After confirmation (A or C), verify the cert by reading it directly from the live TLS handshake on `localhost:8443`:
```bash
echo "" | openssl s_client -connect localhost:8443 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

Use `ask_followup_question`:
- **Question:** "nginx flow complete — what would you like to do next?"
- **Suggestion A:** "Continue to the next selected flow (or teardown)"
- **Suggestion B:** "Stop here"
- **Suggestion C:** "Verify the cert and TLS endpoint one more time"
- **Suggestion D:** "Wait for the cert to rotate and verify the new one live"

**If the user picks C:** re-run:
```bash
echo "" | openssl s_client -connect localhost:8443 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

**If the user picks D:** capture the current fingerprint from the live TLS handshake on `localhost:8443`, then poll until it changes:
```bash
old=$(echo "" | openssl s_client -connect localhost:8443 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
echo "Current fingerprint: $old"
echo "Waiting for rotation (checking every 10s, up to 3 min)..."
for i in $(seq 1 18); do
  sleep 10
  new=$(echo "" | openssl s_client -connect localhost:8443 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
  echo "[$i/18] $new"
  [ "$new" != "$old" ] && echo "Cert rotated!" && break
done
echo "" | openssl s_client -connect localhost:8443 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```
Point out the new `notBefore` and changed fingerprint as live proof that Vault Agent renewed the cert and nginx picked it up with zero downtime.

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

After confirmation (A or C), verify the cert by reading it directly from the live TLS handshake on `localhost:8453`:
```bash
echo "" | openssl s_client -connect localhost:8453 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

Use `ask_followup_question`:
- **Question:** "HAProxy flow complete — what would you like to do next?"
- **Suggestion A:** "Continue to the next selected flow (or teardown)"
- **Suggestion B:** "Stop here, leave everything running"
- **Suggestion C:** "Verify the cert and TLS endpoint one more time"
- **Suggestion D:** "Wait for the cert to rotate and verify the new one live"

**If the user picks C:** re-run:
```bash
echo "" | openssl s_client -connect localhost:8453 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

**If the user picks D:** capture the current fingerprint from the live TLS handshake on `localhost:8453`, then poll until it changes:
```bash
old=$(echo "" | openssl s_client -connect localhost:8453 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
echo "Current fingerprint: $old"
echo "Waiting for rotation (checking every 10s, up to 3 min)..."
for i in $(seq 1 18); do
  sleep 10
  new=$(echo "" | openssl s_client -connect localhost:8453 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
  echo "[$i/18] $new"
  [ "$new" != "$old" ] && echo "Cert rotated!" && break
done
echo "" | openssl s_client -connect localhost:8453 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```
Point out the new `notBefore` and changed fingerprint as live proof that Vault Agent renewed the cert and HAProxy picked it up gracefully.

---

## Phase 6D — DataPower Flow (run only if selected)

### Step 1 — Issue Initial Certificates

**Explain:** "`datapower-init.hcl` is a one-shot config that renders three certificate templates (`dp-webgui.vtmpl`, `dp-ui.vtmpl`, `dp-demo.vtmpl`) into `datapower/certs/` and exits. We need these files on disk before the container starts, otherwise DataPower's TLS contexts have nothing to load."

Run with `execute_command`:
```bash
vault agent -config=./datapower-init.hcl -exit-after-auth
```

Verify the cert files were written:
```bash
ls -lh datapower/certs/
openssl x509 -in datapower/certs/demo-sscert.pem -noout -subject -dates
```

Use `ask_followup_question`:
- **Question:** "Initial DataPower certs are on disk — ready to start the container?"
- **Suggestion A:** "Yes — start DataPower"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Re-run openssl to inspect a cert"

### Step 2 — Start the DataPower Container

**Explain:** "`start-datapower.sh` launches `icr.io/cpopen/datapower/datapower-limited:11.0.0.1` via Podman with `--privileged`, mounts `datapower/certs/` into `cert:///` inside the container, and exposes four ports. **This is a long-running, interactive process** — it must run in a separate terminal, and it must be started from the `datapower/` directory (the script hard-codes relative paths)."

Print this for the user to copy into a new terminal:
```
cd datapower && bash ./start-datapower.sh
```

Tell them: "Open a new terminal, `cd` into the `datapower/` subdirectory, and run that command. DataPower takes 30–60 seconds to fully boot."

| Endpoint | URL |
|---|---|
| Web UI | `https://localhost:9090` |
| SOMA API (SOAP) | `https://localhost:5550` |
| REST Management API | `https://localhost:5554` |
| Demo TLS service | `https://localhost:8043` |

Default credentials: `admin` / `admin`.

Use `ask_followup_question`:
- **Question:** "Is the DataPower container starting in the other terminal?"
- **Suggestion A:** "Yes — it's booting, I'll wait for it"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "It failed to start — help me diagnose"

**If the user picks C:** run `podman logs my-datapower 2>&1 | tail -30` and explain the output.

### Step 3 — Wait for DataPower to Be Ready

**Explain:** "DataPower's REST Management API becomes reachable once the runtime is initialised. We poll it until it responds."

Run with `execute_command` (retry up to 12 times, 5-second gap = 60 s max):
```bash
for i in $(seq 1 12); do
  echo "Attempt $i/12..."
  code=$(curl -sk -u admin:admin https://localhost:5554/mgmt/filestore/default/cert/ \
    -o /dev/null -w "%{http_code}")
  echo "HTTP $code"
  [ "$code" = "200" ] && echo "DataPower REST API is up!" && break
  sleep 5
done
```

If the loop exhausts all 12 attempts without a 200, tell the user DataPower is still booting or unreachable and ask them to check the container terminal for errors before retrying.

Use `ask_followup_question`:
- **Question:** "DataPower is up — ready to start the continuous renewal agent?"
- **Suggestion A:** "Yes — start the renewal agent"
- **Suggestion B:** "No, stop here"
- **Suggestion C:** "Verify the cert filestore via curl first"

**If the user picks C:** run:
```bash
curl -sk -u admin:admin https://localhost:5554/mgmt/filestore/default/cert/
```
Show the output and explain that the cert files listed there are what DataPower's TLS contexts are currently using.

### Step 4 — Continuous Renewal Agent

**Explain:** "`vault agent -config=./datapower.hcl` runs indefinitely. It watches the TTL of the demo cert rendered by `templates/dp-demo-1m.vtmpl` and re-issues it before expiry. After each renewal it calls `datapower/upload-certs-to-datapower.sh`, which: (1) uploads the new `demo-sscert.pem` and `demo-privkey.pem` to the DataPower cert filestore via PUT, (2) reloads the `CryptoCertificate/demo` and `CryptoKey/demo` config objects so the running TLS context picks up the new material — uploading the file alone is not enough. This is a long-running process and must run in a separate terminal."

**Important:** `upload-certs-to-datapower.sh` uses relative paths (`datapower/certs/demo-sscert.pem`) so the agent **must be run from the repo root** — never from the `datapower/` subdirectory.

Print this command for the user to copy:
```
vault agent -config=./datapower.hcl
```

Use `ask_followup_question`:
- **Question:** "Is Vault Agent for DataPower running in a separate terminal?"
- **Suggestion A:** "Yes — it's running, continue"
- **Suggestion B:** "Not yet, give me a moment"
- **Suggestion C:** "Run it for me in the background instead"

**If the user picks C (run in background):** run with `execute_command`:
```bash
vault agent -config=./datapower.hcl > /tmp/vault-agent-datapower.log 2>&1 &
echo "Vault Agent DataPower PID: $!"
sleep 5 && tail -10 /tmp/vault-agent-datapower.log
```

After confirmation (A or C), verify the cert DataPower is actively serving by reading it directly from the TLS handshake on the demo service port (`8043`):
```bash
echo "" | openssl s_client -connect localhost:8043 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

Explain the output:
- **Subject** confirms it's the `demo.datapower.hashicorp.ibm` leaf cert issued by Vault.
- **Issuer** should be `CN=vault.hashicorp.ibm Intermediate CA` — the `pki_int` engine.
- **Dates** reveal the short TTL (`dp-demo-1m.vtmpl` uses ~90 seconds) — watch the `notBefore` advance on successive runs to confirm the agent is rotating the cert automatically.
- **Fingerprint** can be compared across renewals to confirm a new cert was issued.

Use `ask_followup_question`:
- **Question:** "DataPower flow complete — what would you like to do next?"
- **Suggestion A:** "Continue to the next selected flow (or teardown)"
- **Suggestion B:** "Stop here, leave everything running"
- **Suggestion C:** "Re-run the TLS handshake check to see if the cert has already rotated"
- **Suggestion D:** "Wait for the next rotation and verify it live"

**If the user picks C:** re-run the same `openssl s_client` command and compare the `notBefore` and fingerprint against the previous output to confirm rotation already happened.

**If the user picks D:** capture the current fingerprint from the live TLS handshake on `localhost:8043`, then poll until it changes (~90s TTL so this is fast):
```bash
old=$(echo "" | openssl s_client -connect localhost:8043 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
echo "Current fingerprint: $old"
echo "Waiting for rotation (checking every 10s, up to 3 min — ~90s TTL so this should be quick)..."
for i in $(seq 1 18); do
  sleep 10
  new=$(echo "" | openssl s_client -connect localhost:8043 -showcerts 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
  echo "[$i/18] $new"
  [ "$new" != "$old" ] && echo "Cert rotated on DataPower!" && break
done
echo "" | openssl s_client -connect localhost:8043 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```
Point out the new `notBefore` and changed fingerprint as live proof that Vault Agent rotated the cert and DataPower picked it up automatically via the REST Management API reload.

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
# Kill individual agents by their pidfile (or use pkill to stop all at once):
kill $(cat ./pidfile-nginx 2>/dev/null) 2>/dev/null
kill $(cat ./pidfile-haproxy 2>/dev/null) 2>/dev/null
kill $(cat ./pidfile-datapower 2>/dev/null) 2>/dev/null
# — or, to stop everything in one shot:
pkill -f 'vault agent' 2>/dev/null

# Stop containers (DataPower may take ~15 s to stop gracefully):
podman stop nginx-vault haproxy-vault my-datapower 2>/dev/null
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
