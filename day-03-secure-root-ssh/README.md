# Day 03 — Secure Root SSH Access

## The real-world problem

The `root` superuser exists on every Linux server, making it the primary target for automated SSH brute-force attacks. Allowing direct root access via SSH also bypasses personal accountability, as multiple admins logging in as `root` leave no audit trail of who actually logged in. Securing root login forces administrators to log in using their own personal accounts and elevate privileges via `sudo`.

## How I approached it

The security team requires disabling direct SSH root login on all App Servers (`stapp01`, `stapp02`, and `stapp03`). I need to SSH into each server, locate the SSH daemon configuration file `/etc/ssh/sshd_config`, locate the `PermitRootLogin` directive, set it to `no`, and restart the `sshd` service.

## Key concepts

- **`sshd_config`** — The primary configuration file for the OpenSSH daemon, containing rules for authentication, security levels, and network bindings.
- **`PermitRootLogin` directive** — The configuration option that controls whether the root user can establish an SSH session.
- **Audit accountability** — Enforcing user-level logins so audit logs (`/var/log/secure` or `/var/log/auth.log`) clearly link administrative actions to specific individuals.

## Solution

Perform these steps on **all three app servers** (`stapp01`, `stapp02`, `stapp03`):

```bash
# 1. SSH into the app server
ssh tony@stapp01

# 2. Modify the SSH configuration
# Edit /etc/ssh/sshd_config and ensure PermitRootLogin is set to no
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Alternatively, open the file in vi/nano:
# sudo vi /etc/ssh/sshd_config
# Find the line: PermitRootLogin
# Change it to: PermitRootLogin no

# 3. Restart the SSH daemon to apply changes
sudo systemctl restart sshd
```

## How to verify this actually works

```bash
# Attempt to SSH directly as root from the jump host
ssh root@stapp01

# Expected result: Connection refused, Permission denied, or prompted for key/password but rejected even with correct credentials.
# In a secure config, direct root connection will be rejected.
```

## Common mistakes here

- **Forgetting to restart the SSH service** — Modifying the file but failing to run `systemctl restart sshd`, leaving the old configuration active.
- **Locking yourself out** — Editing configurations without having an active fallback session or user with `sudo` privileges configured first.
- **Typo in the directive** — Writing `PermitRootlogin no` (case sensitivity issues) or leaving commented lines active.
- **Applying to only one server** — The security mandate requires this on *all* application servers in the datacenter.

## What I learned

<!-- Fill this in yourself after completing the task -->
- _How SSH authentication policies are parsed and enforced by sshd:_
- _The security benefits of using sudo escalation logs over direct root login:_
- _One thing I'll do differently next time:_
