# Key Rotation

Procedures for rotating encryption keys and secrets in this repository.

## Age Key Rotation

Rotate the age encryption key when: a team member leaves, key compromise is suspected, or on schedule.

### Add a new key (expand recipients)

```bash
# Generate new age keypair
age-keygen -o new-key.txt
# Note the public key: age1...

# Add the new public key to .sops.yaml (comma-separated in the age: field)
# Then re-encrypt all files with the updated recipient list:
sops updatekeys secrets/production.env
sops updatekeys clusters/production/hosts.enc.yaml
```

### Remove an old key (revoke access)

1. Remove the public key from `.sops.yaml`
2. Re-encrypt all files:
   ```bash
   sops updatekeys secrets/production.env
   sops updatekeys clusters/production/hosts.enc.yaml
   ```
3. The removed key can no longer decrypt future versions of these files
4. **Important:** if the removed key was compromised, also rotate all secret values (see below)

## Secret Rotation

### Edit a single secret

```bash
# Opens your $EDITOR with decrypted values; re-encrypts on save
sops secrets/production.env
```

### Rotate all secrets after a compromise

If the age private key was compromised, all encrypted values are potentially exposed. Rotate everything:

1. Rotate the age key (see above)
2. Rotate all credential values:
   - **Database passwords:** Change in `production.env`, then run `frameworks cluster provision --only infrastructure` to apply
   - **API keys (Stripe, Cloudflare, etc.):** Regenerate in each provider's dashboard, update in `production.env`
   - **Auto-generated secrets (JWT_SECRET, SERVICE_TOKEN, etc.):** Generate new values with `openssl rand -hex 32`, update in `production.env`
   - **Ethereum private key (X402_GAS_WALLET_PRIVKEY):** Generate new wallet, transfer funds, update key
3. Re-provision all services: `frameworks cluster provision`

### Rotate host IPs

```bash
sops clusters/production/hosts.enc.yaml
# Edit the IPs, save — file is re-encrypted automatically
```

## Recovery

If the primary age key is lost but a recovery key exists:

1. Decrypt using the recovery key: `SOPS_AGE_KEY_FILE=/path/to/recovery-key.txt sops -d secrets/production.env`
2. Generate a new primary key: `age-keygen -o new-primary.txt`
3. Update `.sops.yaml` with the new primary public key (replacing the lost one)
4. Re-encrypt all files: `sops updatekeys secrets/production.env && sops updatekeys clusters/production/hosts.enc.yaml`

## Adding a Team Member

1. Have them generate an age keypair: `age-keygen`
2. Add their public key to `.sops.yaml` (comma-separated)
3. Re-encrypt: `sops updatekeys` on all encrypted files
4. They can now decrypt with their private key
