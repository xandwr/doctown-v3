# Doctown v3 Implementation Timeline

## Phase 1: Database Foundation (Day 1-2)

**Goal:** Build the persistence layer everything else depends on.

**Why first?** Every other feature needs to read/write data.

### Tasks

1. **Set up Supabase client in SvelteKit** - DONE
   - Install `@supabase/supabase-js`
   - Create database helper/client
   - Migrate sessions from in-memory to Supabase

2. **Create database schema** - DONE
   - `users` (id, github_id, github_login, avatar_url, access_token)
   - `jobs` (id, user_id, repo, git_ref, status, created_at, updated_at)
   - `docpacks` (id, job_id, name, file_url, public, created_at)
   - `github_installations` (id, user_id, repo_full_name, installation_id)

3. **Update auth to use database** - DONE (partially)
   - Save users on GitHub OAuth callback
   - Store sessions in Supabase
   - Update `hooks.server.ts` to query DB

---

## Phase 2: Job Creation API (Day 2-3)

**Goal:** Build the entry point for triggering documentation generation.

**Why second?** You need somewhere to record job requests before processing them.

### Tasks

1. **Create `/api/jobs/create` endpoint**
   - Accept: `{ repo, git_ref, user_id }`
   - Generate job ID
   - Store job in database with status `pending`
   - Return job ID to frontend

2. **Update dashboard to trigger jobs**
   - Add "Generate Docs" button
   - Call `/api/jobs/create` on click
   - Show job status polling

---

## Phase 3: RunPod Integration (Day 3-4)

**Goal:** Connect job creation to actual build triggering.

**Why third?** Now that jobs exist in DB, you can trigger builds.

### Tasks

1. **Create RunPod client/helper**
   ```typescript
   // /website/src/lib/runpod.ts
   export async function triggerBuild(params: {
     job_id: string;
     repo: string;
     git_ref: string;
     token: string;
   })
   ```

2. **Update `/api/jobs/create` to call RunPod**
   - After creating job in DB, trigger RunPod
   - Pass: job_id, repo, git_ref, GitHub token
   - Update job status to `building`

3. **Create `/api/jobs/status/:id` endpoint**
   - Poll job status from database
   - Frontend can check if job is complete

---

## Phase 4: Builder (Rust) - Minimal Version (Day 4-8)

**Goal:** Build the smallest thing that produces a .docpack file.

**Why fourth?** RunPod now calls this, need something to respond.

**Start simple - don't try to build everything at once!**

### Tasks

1. **Basic file structure (Day 4-5)**
   - Accept input params from RunPod
   - Clone Git repo to temp directory
   - Walk file tree, find source files
   - Extract basic metadata (no LLM yet)

2. **Minimal docpack output (Day 5-6)**
   - Create `manifest.json` with repo metadata
   - Create `symbols.json` with basic file/function list
   - Skip LLM documentation for now (just placeholders)
   - ZIP everything into .docpack format

3. **Upload to backend (Day 6-7)**
   - POST .docpack file to `/api/jobs/complete`
   - Include job_id in request

4. **Add LLM later (Day 8+)**
   - Once flow works end-to-end, add OpenAI calls
   - Generate real documentation in batches

---

## Phase 5: File Upload & Storage (Day 7-9)

**Goal:** Handle builder uploads and store in R2.

**Why fifth?** Builder needs somewhere to PUT the .docpack.

### Tasks

1. **Create `/api/jobs/complete` endpoint**
   - Accept multipart form with job_id and .docpack file
   - Verify job exists and is in `building` status
   - Upload file to R2 bucket
   - Store file URL in `docpacks` table
   - Update job status to `completed`

2. **R2 upload helper**
   ```typescript
   // /website/src/lib/r2.ts
   export async function uploadDocpack(
     file: File,
     jobId: string
   ): Promise<string> // Returns R2 URL
   ```

---

## Phase 6: Retrieve & Display (Day 9-10)

**Goal:** Show completed docpacks to users.

### Tasks

1. **Create `/api/docpacks` endpoint**
   - List user's docpacks from database
   - Return metadata + download URLs

2. **Update dashboard to show completed docpacks**
   - Fetch from `/api/docpacks`
   - Show list with download buttons
   - Link to R2 file URLs

3. **Update commons page (if public)**
   - Query public docpacks
   - Replace mock data with real data

---

## Phase 7: GitHub Webhook (Optional for MVP) (Day 10-11)

**Goal:** Auto-trigger on push events.

**Why last?** Manual trigger works for MVP; this is automation.

### Tasks

1. **Create `/api/github/webhook` endpoint**
   - Verify GitHub signature
   - Parse push events
   - Check if installation exists for repo
   - Create job automatically

2. **Test with GitHub webhook deliveries**

---

## Summary

**MVP (Manual Trigger):** Days 1-10 (~2 weeks)
**Full Auto (Webhooks):** Day 11+

### Key Principles

1. **Build end-to-end first, then add features**
   - Skip LLM documentation initially - use placeholders
   - Skip GitHub webhooks - manual trigger works
   - Skip payment gates - add Stripe later

2. **Test each phase before moving on**
   - Phase 1: Can you store/retrieve users?
   - Phase 2: Can you create a job?
   - Phase 3: Does RunPod get called?
   - Phase 4: Does builder produce a .docpack?
   - Phase 5: Does file reach R2?
   - Phase 6: Can you download it?

3. **Keep builder simple initially**
   - Don't parse with tree-sitter yet - use simple regex
   - Don't call LLM - use placeholder docs
   - Just prove the pipeline works