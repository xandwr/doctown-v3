# Doctown v3 Implementation Timeline

## Phase 1: Database Foundation (Day 1-2) ✅ COMPLETE

**Goal:** Build the persistence layer everything else depends on.

**Why first?** Every other feature needs to read/write data.

### Tasks

1. **Set up Supabase client in SvelteKit** ✅ DONE
   - Install `@supabase/supabase-js`
   - Create database helper/client (`/website/src/lib/supabase.ts`)
   - Migrate sessions from in-memory to Supabase

2. **Create database schema** ✅ DONE
   - `users` (id, github_id, github_login, avatar_url, access_token)
   - `jobs` (id, user_id, repo, git_ref, status, created_at, updated_at)
   - `docpacks` (id, job_id, name, file_url, public, created_at)
   - `github_installations` (id, user_id, repo_full_name, installation_id)
   - TypeScript types generated (`/website/src/lib/database.types.ts`)

3. **Update auth to use database** ✅ DONE
   - Save users on GitHub OAuth callback
   - Store sessions in Supabase
   - Update `hooks.server.ts` to query DB
   - Helper functions: `upsertUser`, `createSession`, `getSession`, `deleteSession`

---

## Phase 2: Job Creation API (Day 2-3) ✅ COMPLETE

**Goal:** Build the entry point for triggering documentation generation.

**Why second?** You need somewhere to record job requests before processing them.

### Tasks

1. **Create `/api/jobs/create` endpoint** ✅ DONE
   - Accept: `{ repo, git_ref }` in POST body
   - Validate user authentication
   - Generate job ID automatically (UUID)
   - Store job in database with status `pending`
   - Return `{ job_id, status, created_at }` to frontend
   - File: `/website/src/routes/api/jobs/create/+server.ts`

2. **Create `/api/jobs/status/[id]` endpoint** ✅ DONE
   - GET endpoint to poll job status
   - Verify job ownership by user
   - Return complete job information
   - File: `/website/src/routes/api/jobs/status/[id]/+server.ts`

3. **Update dashboard to trigger jobs** ✅ DONE
   - Changed "Create Docpack" button to "Generate Docs"
   - Call `/api/jobs/create` on button click
   - Store returned job ID in UI state
   - Automatic status polling every 5 seconds
   - Stop polling when job reaches `completed` or `failed`
   - Cleanup polling intervals on component unmount
   - Files: `/website/src/routes/dashboard/+page.svelte`, `/website/src/lib/components/RepoModal.svelte`

---

## Phase 3: RunPod Integration (Day 3-4) ✅ COMPLETE

**Goal:** Connect job creation to actual build triggering.

**Why third?** Now that jobs exist in DB, you can trigger builds.

### Tasks

1. **Create RunPod client/helper** ✅ DONE
   - Created `/website/src/lib/runpod.ts`
   - Implemented `triggerBuild()` function with proper types
   - Configured RunPod API authentication
   - Includes error handling and logging

2. **Update `/api/jobs/create` to call RunPod** ✅ DONE
   - Triggers RunPod build after creating job in DB
   - Passes: job_id, repo, git_ref, GitHub access token
   - Updates job status to `building` on success
   - Updates job status to `failed` with error message on failure
   - Non-blocking (background) execution for fast API responses

3. **Create `/api/jobs/status/[id]` endpoint** ✅ DONE (completed in Phase 2)

---

## Phase 4: Builder (Rust) - Minimal Version (Day 4-8) ✅ COMPLETE

**Goal:** Build the smallest thing that produces a .docpack file.

**Why fourth?** RunPod now calls this, need something to respond.

### Tasks

1. **Basic file structure (Day 4-5)** ✅ DONE
   - Accept input params from RunPod via `RUNPOD_INPUT` environment variable
   - Clone Git repo to temp directory using `git2` library
   - Walk file tree with `walkdir`, find source files
   - Extract symbols using tree-sitter parsers (Rust, Python, TypeScript, JavaScript)
   - Implemented in: `/builder/src/git.rs`, `/builder/src/parser.rs`

2. **Minimal docpack output (Day 5-6)** ✅ DONE
   - Create `manifest.json` with repo metadata, language summary, and statistics
   - Create `symbols.json` with extracted symbols (functions, classes, structs, etc.)
   - Generate placeholder documentation for each symbol
   - ZIP everything into .docpack format using `zip` crate
   - Implemented in: `/builder/src/types.rs`, `/builder/src/docpack.rs`

3. **Upload to backend (Day 6-7)** ✅ DONE
   - POST .docpack file to `/api/jobs/complete` using multipart form data
   - Include job_id in request
   - Authenticate with `DOCTOWN_BUILDER_SHARED_SECRET`
   - Implemented in: `/builder/src/uploader.rs`

4. **Main entry point** ✅ DONE
   - Orchestrates the full build pipeline (clone → parse → generate → zip → upload)
   - Progress logging for each stage
   - Comprehensive error handling
   - Implemented in: `/builder/src/main.rs`

5. **Add LLM later (Day 8+)** 🔄 TODO
   - Once flow works end-to-end, add OpenAI calls
   - Generate real documentation in batches
   - Skeleton exists in `/builder/src/agent.rs`

### Implementation Details

**Dependencies Added:**
- `git2` - Git repository cloning and operations
- `tree-sitter` + language parsers - Source code parsing
- `walkdir` - File system traversal
- `zip` - Archive creation
- `reqwest` - HTTP client for API uploads
- `anyhow` - Error handling
- `chrono` - Timestamp generation
- `tempfile` - Temporary file/directory management

**Modules Created:**
- `git.rs` - Repository cloning with GitHub token authentication
- `parser.rs` - Multi-language source code analysis with tree-sitter
- `types.rs` - Data structures matching DOCPACK_SPEC.md format
- `docpack.rs` - ZIP archive creation
- `uploader.rs` - HTTP multipart upload to backend
- `main.rs` - Pipeline orchestration

---

## Phase 5: File Upload & Storage (Day 7-9) ✅ COMPLETE

**Goal:** Handle builder uploads and store in R2.

**Why fifth?** Builder needs somewhere to PUT the .docpack.

### Tasks

1. **Create `/api/jobs/complete` endpoint** ✅ DONE
   - Accept multipart form with job_id and .docpack file
   - Verify job exists and is in `building` status
   - Upload file to R2 bucket using AWS S3 SDK
   - Store file URL in `docpacks` table
   - Update job status to `completed`
   - Authenticate requests with `DOCTOWN_BUILDER_SHARED_SECRET`
   - Implemented in: `/website/src/routes/api/jobs/complete/+server.ts`

2. **R2 integration** ✅ DONE
   - Added `@aws-sdk/client-s3` dependency to `package.json`
   - Configured S3 client for Cloudflare R2 compatibility
   - Environment variables: `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`, `BUCKET_S3_ENDPOINT`
   - Auto-generate unique filenames: `{job_id}-{timestamp}.docpack`
   - Extract repository metadata and populate `docpacks` table

3. **Environment configuration** ✅ DONE
   - Added `DOCTOWN_BUILDER_SHARED_SECRET` to `.env.example`
   - Updated for both builder and website environments

4. **Builder Dockerfile** ✅ DONE
   - Implemented multi-stage Docker build for Rust application
   - Stage 1: Compile Rust binary with all dependencies (git2, tree-sitter, reqwest)
   - Stage 2: Minimal runtime image (debian:bookworm-slim) with git and CA certificates
   - Dependency caching optimization: builds dependencies first, then source code
   - Created `.dockerignore` to exclude build artifacts and reduce context size
   - Binary expects `RUNPOD_INPUT` environment variable from RunPod
   - Ready for deployment to RunPod serverless platform

---

## Phase 6: Retrieve & Display (Day 9-10) ✅

**Goal:** Show completed docpacks to users.

**Status:** Complete

### Tasks

1. **Create `/api/docpacks` endpoint** ✅
   - ✅ Created GET endpoint at `/website/src/routes/api/docpacks/+server.ts`
   - ✅ Returns user's docpacks from database (requires auth)
   - ✅ Supports `?public=true` query param for public docpacks (no auth)
   - ✅ Returns metadata + download URLs (file_url from R2)
   - ✅ Uses existing `getUserDocpacks()` and `getPublicDocpacks()` functions

2. **Update dashboard to show completed docpacks** ✅
   - ✅ Added fetch from `/api/docpacks` on mount
   - ✅ Auto-resumes polling for pending/building jobs
   - ✅ Shows download button in DocpackConfigModal for completed docpacks
   - ✅ Download button links directly to R2 file URLs
   - ✅ Displays all docpacks with status badges

3. **Update commons page** ✅
   - ✅ Replaced mock data with API call to `/api/docpacks?public=true`
   - ✅ Added loading state with spinner
   - ✅ Added error handling with user-friendly messages
   - ✅ Maintains responsive grid layout (1/2/3 columns)
   - ✅ Public docpacks visible to all users (no auth required)

### Implementation Details

- **Database functions** already existed in `/lib/supabase.ts`
- **Download functionality** added to DocpackConfigModal component
- **Status handling** properly filters by `status === "valid"` or `status === "public"`
- **Error states** handled gracefully in both dashboard and commons
- **Polling mechanism** integrated to track pending job completion

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