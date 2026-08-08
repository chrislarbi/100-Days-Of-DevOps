# Day 01 — Create a User with a Non-Interactive Shell

## The real-world problem

To run automated background tasks (like backup agents, logging tools, or application processes), systems need dedicated user accounts. Since these tools don't require humans to log in, the user accounts should have a non-interactive shell. This prevents interactive access, blocking potential attackers from using these service accounts to gain shell access to the system.

## How I approached it

The key requirement is to create a service user `mariyam` on App Server 2 (`stapp02`) with a shell that prevents logging in. The tool to use is `useradd` with the `-s` option to define the shell. Choosing a shell like `/sbin/nologin` (common on RHEL/CentOS) or `/usr/sbin/nologin` (Debian/Ubuntu) will reject login attempts.

## Key concepts

- **Non-interactive shell** — A shell (like `/sbin/nologin` or `/bin/false`) that immediately exits or prints a rejection message when a user tries to log in.
- **Service/system accounts** — User accounts created solely to run applications or agents, rather than for human logins.
- **Principle of least privilege** — Providing only the system access absolutely necessary to perform a task, reducing vulnerability exposure.

## Solution

```bash
# SSH into App Server 2
ssh steve@stapp02

# Create the user with a non-interactive shell
# -s /sbin/nologin -> Sets the shell to nologin to prevent interactive logins
sudo useradd mariyam -s /sbin/nologin
```

## How to verify this actually works

```bash
# Check the user account shell in /etc/passwd
getent passwd mariyam
# Expected output: mariyam:x:1001:1001::/home/mariyam:/sbin/nologin

# Attempt to log in as the user
su - mariyam
# Expected output: "This account is currently not available."
```

## Common mistakes here

- **Using a standard shell** — Creating the user with `/bin/bash` or leaving the shell default, allowing interactive shell access.
- **Path typos** — Specifying a shell path that doesn't exist (e.g., `/bin/nologin` instead of `/sbin/nologin` on RHEL/CentOS systems). Verify the correct path with `command -v nologin` or checking `/etc/shells`.
- **Applying to the wrong host** — Creating the user on App Server 1 or 3 instead of App Server 2.

## What I learned

<!-- Fill this in yourself after completing the task -->
- _How non-interactive shells work to protect system access:_
- _The key differences between /sbin/nologin and /bin/false:_
- _One thing I'll do differently next time:_
