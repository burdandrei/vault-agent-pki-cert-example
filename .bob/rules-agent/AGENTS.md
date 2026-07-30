# Project Coding Rules (Non-Obvious Only)

- All Vault Agent HCL configs share a `pid_file = "./pidfile"` at the repo root — never add a new config that writes a pidfile to a different path or parallel runs will conflict.
- `.vtmpl` template destination files (e.g., `certs/destination.out`) are written as a raw concatenation of cert + CA + key. The real usable per-type files are produced only by `writeToFile` side effects inside the template. Don't confuse the destination file with an actual usable cert file.
- `writeToFile` append mode requires the literal string `"append"` as a **5th positional argument**, not a named option: `{{ .Cert | writeToFile "path" "" "" "0644" "append" }}`.
- Shell scripts that call `datapower/upload-certs-to-datapower.sh` must be invoked from the **repo root** — the script hard-codes relative paths like `datapower/certs/demo-sscert.pem`.
- DataPower REST Management API requires both a file upload (`PUT /mgmt/filestore/default/cert/<name>`) **and** a crypto object reload (`PUT /mgmt/config/default/CryptoCertificate/<name>`) — uploading the file alone does NOT update the active TLS context.
- Terraform must be applied from the `terraform/` subdirectory; there is no root-level Terraform wrapper.
- `cleanup.sh` recursively deletes all `*.pem` and `*.out` files in the repo — do not place generated files you want to keep in the repo tree.
