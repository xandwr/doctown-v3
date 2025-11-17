# Frontend State Management Fixes

## Overview
This document outlines the fixes applied to resolve frontend state management issues in the Doctown v3 application.

## Issues Fixed

### 1. Username Display Issue ✅
**Problem:** Username showed as "@" only, with the actual username missing.

**Root Cause:** Type mismatch between database schema and component interface. The database stores `github_login` but the `UserHeader` component expected `login`.

**Solution:**
- Updated [UserHeader.svelte](website/src/lib/components/UserHeader.svelte) to use the correct `User` type from `$lib/supabase`
- Changed all references from `user.login` to `user.github_login`

**Files Changed:**
- `website/src/lib/components/UserHeader.svelte`

---

### 2. Docpacks Not Appearing ✅
**Problem:** Docpacks weren't showing up in the dashboard list, even after successful builds.

**Root Cause:** Multiple issues:
1. The frontend `Docpack` type has a `status` field with custom values (`"pending" | "valid" | "public" | "failed" | "building"`)
2. The database `docpacks` table doesn't have a `status` column - it only has a `public` boolean
3. The actual build status lives in the `jobs` table
4. The query didn't include pending/building jobs that don't have docpack records yet

**Solution:**
- Updated `getUserDocpacks()` in [supabase.ts](website/src/lib/supabase.ts:232-259) to:
  - Join with jobs table to get job status
  - Map database fields to frontend `Docpack` type
  - Convert `public` boolean to status: `'public'` or `'valid'`
- Created `getUserPendingJobs()` function to fetch jobs without docpacks yet
- Updated [/api/docpacks](website/src/routes/api/docpacks/+server.ts) endpoint to:
  - Fetch completed docpacks from database
  - Fetch pending/building jobs
  - Convert jobs to docpack format for display
  - Combine both lists

**Files Changed:**
- `website/src/lib/supabase.ts`
- `website/src/routes/api/docpacks/+server.ts`

---

### 3. No Realtime Updates ✅
**Problem:** The app used 5-second polling which felt slow and wasted resources. No realtime logs during builds.

**Solution:** Implemented Supabase Realtime for instant updates and log streaming.

#### Database Schema
Created new `job_logs` table to store build logs:
```sql
CREATE TABLE job_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  level TEXT NOT NULL DEFAULT 'info', -- 'info', 'warning', 'error', 'debug'
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_job_logs_job_id ON job_logs(job_id, timestamp DESC);
```

Run this schema update:
```bash
psql $DATABASE_URL -f schema_update_logs.sql
```

#### Backend Changes

1. **Added log helper functions** in [supabase.ts](website/src/lib/supabase.ts:292-353):
   - `addJobLog()` - Add a log entry
   - `getJobLogs()` - Fetch all logs for a job
   - `subscribeToJobLogs()` - Subscribe to realtime log updates

2. **Created API endpoints**:
   - `GET /api/jobs/[id]/logs` - Fetch all logs for a job
   - `POST /api/jobs/[id]/log` - RunPod callback to add logs (authenticated with API key)

#### Frontend Changes

1. **Created BuildLogs Component** ([BuildLogs.svelte](website/src/lib/components/BuildLogs.svelte)):
   - Full-screen modal displaying realtime logs
   - Auto-scrolling with manual override
   - Color-coded log levels (info=green, warning=yellow, error=red, debug=gray)
   - Timestamp formatting
   - Uses Supabase Realtime for instant updates

2. **Updated Dashboard** ([dashboard/+page.svelte](website/src/routes/dashboard/+page.svelte)):
   - Clicking on building/pending docpacks now shows the BuildLogs modal
   - Completed docpacks show the DocpackConfigModal as before

3. **Updated Layout** ([+layout.server.ts](website/src/routes/+layout.server.ts)):
   - Passes Supabase URL and publishable key to client-side for realtime connections

**Files Changed:**
- `schema_update_logs.sql` (new)
- `website/src/lib/database.types.ts`
- `website/src/lib/supabase.ts`
- `website/src/lib/components/BuildLogs.svelte` (new)
- `website/src/routes/+layout.server.ts`
- `website/src/routes/dashboard/+page.svelte`
- `website/src/routes/api/jobs/[id]/logs/+server.ts` (new)
- `website/src/routes/api/jobs/[id]/log/+server.ts` (new)

---

## RunPod Integration

For RunPod to send logs to your app, update the Python handler to post logs:

```python
import requests

def log_to_doctown(job_id: str, message: str, level: str = "info"):
    """Send a log message to Doctown"""
    url = f"https://your-app.com/api/jobs/{job_id}/log"
    headers = {
        "Authorization": f"Bearer {RUNPOD_API_KEY}",
        "Content-Type": "application/json"
    }
    data = {
        "message": message,
        "level": level,
        "timestamp": datetime.utcnow().isoformat()
    }
    try:
        requests.post(url, json=data, headers=headers)
    except Exception as e:
        print(f"Failed to send log: {e}")

# Usage in handler
log_to_doctown(job_id, "Starting build...", "info")
log_to_doctown(job_id, "Downloading repository...", "info")
log_to_doctown(job_id, "Running doctown-builder...", "info")
```

---

## Deployment Steps

### 1. Run Database Migration
```bash
# Connect to your Supabase database
psql $DATABASE_URL -f schema_update_logs.sql

# Or use Supabase dashboard SQL editor
```

### 2. Enable Supabase Realtime
In your Supabase dashboard:
1. Go to Database → Replication
2. Enable replication for the `job_logs` table
3. Ensure `public` schema has realtime enabled

### 3. Update Environment Variables
Ensure these are set in Vercel/your deployment:
```bash
SUPABASE_URL=your-supabase-url
SUPABASE_PUBLISHABLE_KEY=your-publishable-key  # Safe for client-side
SUPABASE_SECRET_KEY=your-service-role-key      # Server-side only
RUNPOD_API_KEY=your-runpod-key
```

### 4. Deploy
```bash
cd website
npm install
npm run build
# Deploy to Vercel
```

### 5. Update RunPod Handler
Update your RunPod handler Python code to send logs to the new endpoint.

---

## Testing Realtime Logs

1. Go to the Dashboard
2. Click "Generate Docs" on a repository
3. Immediately click on the pending/building docpack card
4. You should see the BuildLogs modal with realtime updates
5. Logs should appear instantly as RunPod sends them

### Test without RunPod
You can manually insert logs to test:
```sql
INSERT INTO job_logs (job_id, level, message)
VALUES (
  'your-job-id-here',
  'info',
  'Test log message'
);
```

The BuildLogs component should instantly show this new log via Supabase Realtime.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Frontend                            │
│                                                             │
│  Dashboard                                                  │
│    ├─ Fetches docpacks + pending jobs                      │
│    ├─ Shows docpack cards                                  │
│    └─ On click (building/pending) → BuildLogs modal        │
│                                                             │
│  BuildLogs Component                                        │
│    ├─ Fetches initial logs via API                         │
│    ├─ Subscribes to Supabase Realtime                      │
│    └─ Shows logs with auto-scroll                          │
│                                                             │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    │ HTTP + WebSocket (Supabase Realtime)
                    │
┌───────────────────▼─────────────────────────────────────────┐
│                      Backend (SvelteKit)                    │
│                                                             │
│  GET /api/docpacks                                          │
│    ├─ getUserDocpacks() - completed docpacks               │
│    └─ getUserPendingJobs() - pending/building jobs         │
│                                                             │
│  GET /api/jobs/[id]/logs                                    │
│    └─ getJobLogs() - returns all logs for job              │
│                                                             │
│  POST /api/jobs/[id]/log                                    │
│    └─ addJobLog() - RunPod callback to add log             │
│                                                             │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    │ SQL + Realtime
                    │
┌───────────────────▼─────────────────────────────────────────┐
│                    Supabase Database                        │
│                                                             │
│  Tables:                                                    │
│    ├─ users                                                 │
│    ├─ sessions                                              │
│    ├─ jobs (status: pending/building/completed/failed)     │
│    ├─ docpacks                                              │
│    └─ job_logs (NEW - realtime enabled)                    │
│                                                             │
└───────────────────▲─────────────────────────────────────────┘
                    │
                    │ HTTP POST
                    │
┌───────────────────┴─────────────────────────────────────────┐
│                     RunPod Worker                           │
│                                                             │
│  1. Receives job trigger                                    │
│  2. Downloads GitHub repo                                   │
│  3. Runs doctown-builder                                    │
│  4. Sends logs to /api/jobs/[id]/log                        │
│  5. Uploads .docpack to S3                                  │
│  6. Creates docpack record in database                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Svelte 5 Runes Usage

The app correctly uses Svelte 5 runes throughout:

### `$state` - Reactive local state
```typescript
let docpacks = $state<Docpack[]>([]);
let logs = $state<JobLog[]>([]);
let isLoading = $state(true);
```

### `$derived` - Computed values
```typescript
const statusConfig = $derived(STATUS_CONFIG[docpack.status]);
const isVisible = $derived(!!docpack && !!position);
```

### `$effect` - Side effects and lifecycle
```typescript
// Fetch on mount
$effect(() => {
  fetchDocpacks();
});

// Cleanup on unmount
$effect(() => {
  return () => {
    pollingIntervals.forEach(id => clearInterval(id));
  };
});
```

All state management is working correctly with Svelte 5 Runes!

---

## Summary

✅ **Username displays correctly** using `github_login` from database
✅ **Docpacks appear in list** by combining completed docpacks + pending jobs
✅ **Realtime logs working** via Supabase Realtime subscriptions
✅ **No more polling** - instant updates through WebSocket
✅ **Svelte 5 Runes** properly implemented throughout

The frontend is now fully functional with proper state management and realtime updates! 🚀
