# Time Tracker — Cloud Setup Guide

This is the hosted version of your time tracker. It uses **Supabase** (free database +
login) and **Netlify** (free hosting). Follow these steps in order.

---

## Step 1 — Create Supabase (database + login)

1. Go to https://supabase.com and click **Start your project** (sign in with GitHub or email).
2. Click **New project**.
   - Name: `time-tracker`
   - Database password: pick something strong (save it — you may need it later)
   - Region: choose the one closest to you (e.g. East US)
   - Wait ~1–2 min for it to build.
3. In the left sidebar, click **SQL Editor → New query**.
4. Paste the **entire contents of `schema.sql`** (in this folder) and click **Run**.
   - This creates the tables, security rules, and sample cost codes.
5. Turn off email confirmation (so employees can log in right away):
   - Go to **Authentication → Providers → Email**
   - Toggle **"Confirm email"** OFF, then **Save**.

### Make yourself the admin
6. In the left sidebar, go to **Authentication → Users → Add user → Create new user**.
   - Email: your email
   - Password: your chosen password
   - (leave "auto confirm" checked)
7. Go to **Table Editor → profiles**. Find your row (your email's name part) and
   set **is_admin = true**.
   - If there's no row yet, go to **SQL Editor** and run:
     ```sql
     update profiles set is_admin = true where id = (select id from auth.users where email = 'YOUR@EMAIL.com');
     ```

### Get your API keys
8. Go to **Project Settings → API**.
   - Copy the **Project URL** (looks like `https://xxxx.supabase.co`)
   - Copy the **anon / public** key (NOT the secret key)

---

## Step 2 — Plug keys into config.js

Open `config.js` in this folder and replace:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY-HERE';
```

with your real URL and anon key. Save.

---

## Step 3 — Deploy to Netlify (free hosting)

**Option A — drag & drop (easiest, no install):**
1. Go to https://app.netlify.com and sign up (GitHub or email).
2. In Netlify, click **Sites → "Add new site" → "Deploy manually"**.
3. Drag this entire `time-tracker-cloud` folder onto the drop zone.
4. Netlify gives you a URL like `https://your-site.netlify.app`. That's your app!

**Option B — custom domain (optional):**
- Netlify → your site → **Domain settings** → add your domain (~$12/yr from a registrar
  like Namecheap/Cloudflare).

---

## Step 4 — Add employees

1. Open your Netlify URL and log in as the admin (the user you made `is_admin`).
2. You'll land on the **Admin Panel**.
3. Under **Employees**, add each person: name, department, email, temp password.
   - Tell each employee their email + password.
4. Optionally add your own cost codes (the sample ones are already loaded).

Employees log in at the same URL with their email + password and clock in/out.

---

## Adding it to a phone's home screen (feels like an app)

- **iPhone:** open the URL in Safari → Share → **Add to Home Screen**.
- **Android:** open in Chrome → menu → **Add to Home screen**.

---

## Files in this folder

| File | Purpose |
|---|---|
| `index.html` | The entire app (UI + logic) |
| `config.js` | Your Supabase URL + anon key (edit this) |
| `schema.sql` | Database tables + security (run once in Supabase) |
| `netlify.toml` | Netlify routing config |
| `manifest.json` | PWA manifest (for home-screen install) |
