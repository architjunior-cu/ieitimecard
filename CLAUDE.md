# CLAUDE.md — Time Tracker

Invariants every session must respect. Read this before touching anything.

## What this app is

A Supabase-backed employee time clock and PTO tracker for a construction
company, deployed to Netlify as static files. There is no build step and no
server of our own.

| File | What it is |
|---|---|
| `index.html` | The **entire** UI and all client logic — markup, CSS, and one large inline `<script>`. ~68KB. |
| `config.js` | `SUPABASE_URL` and the `sb_publishable_` key. Loaded by `index.html`. |
| `schema.sql` | The database definition (tables, RLS policies, triggers). |
| `netlify.toml` | Publish config and redirects. Security headers go here. |
| `manifest.json` | PWA manifest. |
| `audit/` | The production-readiness review: `00_START_HERE.md` (findings + order of work), `01_hardening_v2.sql` (the migration), `02_client_patches.md` (function-by-function client replacements), `03_invite-employee.ts` (Edge Functions), `netlify.toml` (headers/CSP). |

Tables: `profiles`, `time_entries`, `breaks`, `task_segments`, `tasks`,
`pto_requests`, `cost_codes` (plus `audit_log` and the `entry_hours` view once
the migration runs).

**This app holds live payroll data for real employees.** FLSA record-retention
applies (29 CFR 516 — two years for time records, three for payroll). Treat
`time_entries`, `breaks`, and `pto_requests` as records you do not get to lose.

---

## The core architectural rule

**The client is never trusted to supply identity or timestamps.**

Every mutation goes through a `SECURITY DEFINER` Postgres RPC that derives
identity from `auth.uid()` and time from `now()`. The `authenticated` role has
**SELECT only** on the business tables; there is no INSERT/UPDATE/DELETE grant
to fall back on, so a direct write returns `42501`.

Exceptions, deliberately: `cost_codes` keeps direct insert/update/delete, and
`tasks` (the personal to-do list) keeps direct writes under column grants that
prevent an employee from setting someone else's `emp_id`.

The RPC surface *is* the API contract. If this ever moves behind a dedicated API
service, that service implements the same verbs and the client swaps transport.

### Never do this

Never introduce a `.from(table).insert(...)`, `.update(...)`, or `.delete(...)`
call on:

- `profiles`
- `time_entries`
- `breaks`
- `task_segments`
- `pto_requests`

Use the RPCs. The full list (see `audit/01_hardening_v2.sql`):

`clock_in`, `clock_out`, `start_break`, `end_break`, `switch_task`,
`submit_pto`, `decide_pto`, `admin_set_pto_allocation`, `admin_update_profile`,
`admin_deactivate_employee`, `admin_reactivate_employee`, `admin_clock_in_for`,
`admin_clock_out_for`, `admin_toggle_break_for`, `admin_create_entry`,
`admin_update_entry`, `admin_delete_entry`.

If a needed operation has no RPC, add one to the migration — do not reach around
it with a direct table write.

---

## Escaping

**Never interpolate database text into `innerHTML` without escaping.** Use
`esc()`.

```js
function esc(v){
  if(v===null||v===undefined)return '';
  return String(v)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
```

The original `escapeHtml` crashes on null and leaves `'` unescaped; it is kept
only as an alias. The live XSS path is an employee typing markup into "What are
you working on?", which then executes in the **admin's** session the moment the
admin opens All Time Entries. `audit/02_client_patches.md` Patch 1 has the table
of every interpolation site.

`costLabelFromVal()` escapes its own return value — do not wrap its call sites
in `esc()` as well, or you double-escape.

---

## PTO semantics

`profiles.pto_hours` is an **annual allocation, not a running balance.**

```
remaining = pto_hours − sum(hours of all non-rejected requests in that calendar year)
```

**Never decrement `pto_hours` on approval.** Doing so double-counts every
approval and slowly zeroes out everyone's balance. `submit_pto` derives the
balance server-side using this same model; `admin_set_pto_allocation` is the
only thing that changes the column.

### Status values

Exactly: `pending`, `approved`, `rejected`, `cancelled`. Enforced by a CHECK
constraint.

`statusBadge()` maps `'rejected'` to the CSS class `badge-denied`, which is why
the UI reads "denied". **The stored value is `'rejected'`. Do not "fix" this to
`'denied'`** — it is a class name, not a status, and changing the written value
violates the constraint and breaks every existing row.

---

## Secrets

The `sb_publishable_` key in `config.js` is public by design and correct to
commit.

**The `service_role` / `sb_secret_` key must never appear in any file served to
the browser** — not `config.js`, not `index.html`, not anything under the
publish root. It belongs only in Edge Function environment variables. If one is
ever found in git history, rotate it; removing the commit is not enough.

---

## Destructive operations

**Do not run destructive Supabase CLI commands without asking first**, including
but not limited to:

- `supabase db reset`
- `supabase db push` against a linked remote project
- any `drop table` / `truncate` / unqualified `delete`

This app has live payroll data. Migrations get reviewed and applied
deliberately, not as a side effect of a task.

Related: employees are **deactivated, never deleted.** The FK on
`time_entries.emp_id` is `ON DELETE RESTRICT` after the migration precisely so a
profile delete fails loudly instead of cascading away someone's entire work
history. Use `admin_deactivate_employee` plus the `ban-employee` Edge Function.

---

## Ordering constraint

`adminAddEmployee()` currently depends on `sb.auth.signUp()`, so **do not
disable public signup in Supabase until `invite-employee` is deployed and Patch
3 is applied.** Flipping that toggle first breaks employee creation.

---

## Current state

Remediation progress. Update these as work lands.

**Today**
- [ ] Deploy `invite-employee` Edge Function (`audit/03_invite-employee.ts`)
- [ ] Patch 3 — `adminAddEmployee()` → Edge Function; `adminRemoveEmployee()` → deactivate
- [ ] Disable "Allow new users to sign up" in Supabase (only after the two above)
- [ ] Audit Authentication → Users; check `profiles` for unexpected `is_admin = true`

**This week**
- [ ] Run `audit/01_hardening_v2.sql` + its Section 9 verification
- [ ] Patch 1 — escape everything (`esc()` at all sites)
- [ ] Patch 2 — route all writes through the RPCs
- [ ] Deploy the new `netlify.toml` (security headers + CSP)
- [ ] Re-enable "Confirm email"; force password reset for temp-password accounts
- [ ] Run Section 9(d) console checks as a real non-admin user; confirm each fails

**Next**
- [ ] Decide break-pay policy in writing, then Patch 4 (break deduction)
- [ ] Patch 5 — timezone-correct date filters
- [ ] Patch 6 — surface truncated result sets
- [ ] Patch 7 — skip re-render on `TOKEN_REFRESHED`
- [ ] Patch 8 — pin CDN scripts + SRI (or self-host)
- [ ] Patch 9 — subscribe to realtime only for admins
- [ ] PWA icons in `manifest.json`; `start_url` → `/`
- [ ] `close-stale-shifts` via `pg_cron`

**Then**
- [ ] `cost_code` → FK to `cost_codes(id)`
- [ ] Rounding and overtime as one shared SQL function
- [ ] Payroll export
- [ ] Offline queue
- [ ] Database backups on, restore tested
- [ ] Failure-case tests around each RPC (these carry the security properties)
