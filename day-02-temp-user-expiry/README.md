# Day 02 — Temporary User Setup with Expiry

## The real-world problem

When contractors, external developers, or temporary auditors are granted server access, their accounts often remain active long after their contract ends. This creates a severe security risk. To prevent this, temporary accounts should have an automatic, system-enforced expiration date built in from day one.

## How I approached it

We need to create a temporary user `rose` on App Server 2 (`stapp02`) with an account expiry date of `2024-02-17`. The `useradd` command provides the `-e` flag to set the account expiry date using the format `YYYY-MM-DD`. Once created, we can inspect account settings using the `chage` (change age) command.

## Key concepts

- **Account Expiry** — A Linux security feature that automatically disables a user account once a specific calendar date is reached.
- **`chage` command** — A utility used to inspect and modify user password and account expiry policies.
- **Lifecycle Management** — The process of managing the creation, maintenance, and decommissioning of user identities securely.

## Solution

```bash
# SSH into App Server 2
ssh steve@stapp02

# Create the user with an explicit expiry date
# -e 2024-02-17 -> sets the account expiration date (YYYY-MM-DD)
sudo useradd -e 2024-02-17 rose
```

## How to verify this actually works

```bash
# Inspect the password aging and account expiry details
sudo chage -l rose

# Expected output should show:
# Account expires : Feb 17, 2024
```

## Common mistakes here

- **Using the wrong date format** — Passing non-standard date formats (e.g. `MM-DD-YYYY`) which may be rejected or interpreted incorrectly.
- **Typo in username** — Creating the account with mixed case (e.g., `Rose`) instead of lowercase `rose` as per standard protocol.
- **Confusing password expiry with account expiry** — Adjusting password expiration rules instead of locking the entire user account.

## What I learned

<!-- Fill this in yourself after completing the task -->
- _How Linux handles account aging and lockouts automatically:_
- _The difference between account expiration (chage -E) and password expiration (chage -M):_
- _One thing I'll do differently next time:_
