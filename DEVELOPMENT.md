# Development Guide

This guide covers the technical architecture, file formats, features, and development details for Doctown.

## Table of contents

- [Docpack format specification](#docpack-format-specification)
- [Manual editing feature](#manual-editing-feature)
- [Privacy and manifest system](#privacy-and-manifest-system)
- [Bucket cleanup automation](#bucket-cleanup-automation)
- [Architecture overview](#architecture-overview)

---

## Docpack format specification

**Version:** 1  
**Extension:** `.docpack`  
**Format:** ZIP archive containing structured JSON files

A docpack is a portable, self-contained documentation bundle generated from a source code repository. It includes the extracted symbol graph, AI-generated documentation, and optional source snapshots.

### Directory structure

```
/
  manifest.json
  symbols.json
  docs/
    <doc_id>.json
  source/                  (optional)
    <project source tree>
```

All files are UTF-8 encoded JSON or text.

### `manifest.json`

Top-level metadata describing the docpack, the project it was generated from, and generation context.

```json
{
  "docpack_format": 1,
  "project": {
    "name": "example-project",
    "version": "0.1.0",
    "repo": "https://github.com/user/example-project",
    "commit": "a1b2c3d4"
  },
  "generated_at": "2025-11-16T04:32:17Z",
  "language_summary": {
    "rust_files": 12,
    "other_files": 3
  },
  "stats": {
    "symbols_extracted": 128,
    "docs_generated": 128
  },
  "public": false
}
```

**Fields:**
- `docpack_format` – Version of the docpack format specification
- `project` – Project metadata including name, version, repository URL, and commit hash
- `generated_at` – ISO 8601 timestamp of when the docpack was generated
- `language_summary` – Count of files by language/type
- `stats` – Counts of extracted symbols and generated documentation
- `public` – Boolean indicating if this docpack is public (defaults to `false`)

### `symbols.json`

Array of symbol records extracted from source using AST analysis. Each symbol links to a doc entry via `doc_id`.

```json
[
  {
    "id": "example::parser::parse_file",
    "kind": "function",
    "file": "src/parser.rs",
    "line": 143,
    "signature": "pub fn parse_file(path: &str) -> Result<FileAst>",
    "doc_id": "doc_0001"
  },
  {
    "id": "example::ast::Node",
    "kind": "struct",
    "file": "src/ast.rs",
    "line": 21,
    "fields": ["kind", "span", "children"],
    "doc_id": "doc_0002"
  }
]
```

This file contains **no AI-generated content**. It is the ground-truth structural representation of the codebase.

### `docs/<doc_id>.json`

AI-generated documentation for a single symbol. Each file corresponds to one symbol defined in `symbols.json`.

```json
{
  "symbol": "example::parser::parse_file",
  "summary": "Parses a file from disk and produces its abstract syntax tree.",
  "description": "Reads the file at the given path, tokenizes its contents, and constructs a validated AST structure...",
  "parameters": [
    {
      "name": "path",
      "type": "&str",
      "description": "The filesystem path of the file to parse."
    }
  ],
  "returns": "Result<FileAst>",
  "example": "let ast = parse_file(\"input.rs\")?;",
  "notes": [
    "Assumes UTF-8 input.",
    "For ephemeral strings, use parse_string()."
  ]
}
```

This structured output is stable and LLM-validated.

### `source/` (optional)

A snapshot of the source repository at the time the docpack was created. Recommended contents:
- Entire project directory
- Source files (`.rs`, `.ts`, `.py`, etc.)
- Configuration files (`Cargo.toml`, `package.json`, etc.)

Binary files may be omitted at generator discretion.

### Packaging

To create a `.docpack`:

1. Create the directory structure
2. Write all JSON files
3. Optionally write the source tree
4. Zip the directory
5. Rename with `.docpack` extension

Example:
```bash
zip -r project.docpack manifest.json symbols.json docs/ source/
```

---

## Manual editing feature

The manual editing feature allows docpack owners to make custom edits to all portions of symbol entries in their generated docpacks. While AI generates the initial documentation, users have full control to refine, correct, or enhance any aspect.

### What can be edited

Users can manually edit all portions of a symbol entry:

**Symbol metadata:**
- `kind` – The symbol type (function, struct, enum, etc.)
- `signature` – The full signature/declaration

**Documentation fields:**
- `summary` – Brief one-line description
- `description` – Detailed explanation
- `parameters` – Array of parameter objects with name, type, and description
- `returns` – Return value description
- `example` – Code example demonstrating usage
- `notes` – Array of additional notes and caveats

### Persistence

- Edits are stored in the `symbol_edits` database table
- Each user can have one set of edits per symbol per docpack
- Edits are applied on-the-fly when viewing the docpack
- Original AI-generated content is preserved
- Users can revert individual edits at any time

### Database schema

```sql
CREATE TABLE symbol_edits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  docpack_id UUID NOT NULL REFERENCES docpacks(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  symbol_id TEXT NOT NULL,
  
  -- Editable symbol fields
  signature TEXT,
  kind TEXT,
  
  -- Editable documentation fields
  summary TEXT,
  description TEXT,
  parameters JSONB,
  returns TEXT,
  example TEXT,
  notes JSONB,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(docpack_id, user_id, symbol_id)
);
```

### API endpoints

#### `GET /api/docpacks/[id]/edits`
Fetch all edits for a docpack by the current user.

**Response:** `Record<symbol_id, SymbolEdit>`

#### `POST /api/docpacks/[id]/edits`
Save or update a symbol edit.

**Request body:**
```json
{
  "symbol_id": "string",
  "signature": "string (optional)",
  "kind": "string (optional)",
  "summary": "string (optional)",
  "description": "string (optional)",
  "parameters": "array (optional)",
  "returns": "string (optional)",
  "example": "string (optional)",
  "notes": "array (optional)"
}
```

#### `DELETE /api/docpacks/[id]/edits`
Remove an edit (revert to original).

**Request body:**
```json
{
  "symbol_id": "string"
}
```

#### `POST /api/docpacks/[id]/export`
Export docpack with all user edits applied.

**Response:**
```json
{
  "success": true,
  "download_url": "string",
  "edits_applied": 123
}
```

### Usage

**Viewing edits:**
- Symbols with edits show an "Edited" badge
- Header displays total edit count
- All displayed content reflects edits automatically

**Making edits:**
1. Navigate to your docpack and select a symbol
2. Click "Edit" button
3. Modify any fields
4. Click "Save" to persist changes

**Reverting edits:**
1. Open edit mode for a symbol with existing edits
2. Click "Revert" button
3. Confirm the action

**Exporting:**
1. Make edits to one or more symbols
2. Click "Export Edited" in the header
3. Download the new `.docpack` file with all edits applied

### Implementation details

**Edit merging:**
```typescript
const getMergedSymbol = (symbol: DocpackSymbol): DocpackSymbol => {
  const edit = edits[symbol.id];
  if (!edit) return symbol;
  return {
    ...symbol,
    signature: edit.signature ?? symbol.signature,
    kind: edit.kind ?? symbol.kind,
  };
};
```

Only fields that are explicitly edited are overridden.

**Export process:**
1. Download original docpack from storage
2. Load as ZIP archive
3. Parse `symbols.json` and all `docs/*.json` files
4. Apply user edits to matching symbols and docs
5. Repackage as ZIP
6. Upload to storage with `-edited` suffix
7. Return download URL

---

## Privacy and manifest system

As of this update, docpack manifests include a `public` field that serves as the **authoritative source of truth** for docpack visibility. This eliminates the need to query databases to determine which docpacks should be visible in the commons.

### Motivation

Previously, privacy was controlled solely through the database (`docpacks.public` column). This created a dependency on the database as the single source of truth, making it impossible to authoritatively determine visibility by examining just the R2 storage bucket.

**Solution:** Embed privacy information directly in the manifest, making the `.docpack` file self-describing and the R2 bucket queryable for public docpacks without database dependencies.

### Manifest changes

Added `public: bool` field to manifest structures:

**Builder** (`builder/src/pipeline/pack.rs`):
```rust
pub struct Manifest {
    pub docpack_format: u32,
    pub project: ProjectInfo,
    pub generated_at: String,
    pub language_summary: HashMap<String, usize>,
    pub stats: Stats,
    pub public: bool,  // ← NEW FIELD
}
```

**Localdoc** (`localdoc/src/models.rs`):
```rust
pub struct Manifest {
    pub docpack_format: u32,
    pub project: ProjectInfo,
    pub generated_at: String,
    pub language_summary: HashMap<String, u32>,
    pub stats: Stats,
    pub public: bool,  // ← NEW FIELD
}
```

### Default behavior

Docpacks default to `public: false` (private) for security. The builder CLI supports `DOCPACK_PUBLIC=true` environment variable to create public docpacks when building manually.

### Utilities

#### Python script: `scripts/list-public-docpacks.py`

Query R2 directly for public docpacks by reading manifests:

```bash
# Human-readable output
python3 scripts/list-public-docpacks.py

# JSON output
python3 scripts/list-public-docpacks.py --json
```

This demonstrates:
- Listing all docpacks in R2
- Extracting manifest.json from each `.docpack` ZIP
- Filtering by `manifest.public === true`
- **Zero database queries required**

#### API endpoint: `/api/docpacks/public-from-r2`

Returns:
```json
{
  "docpacks": [...],
  "source": "r2-manifests",
  "message": "Queried directly from R2 manifests - no database dependency"
}
```

### Current architecture

Two sources exist during transition:

1. **Database** (`docpacks.public` column) – Used by `/api/docpacks?public=true`
2. **Manifest** (`manifest.public` field) – Used by `/api/docpacks/public-from-r2`

### Future direction

1. **Sync on Upload** – When builder completes, parse manifest and sync `public` field to database
2. **Single Source** – Deprecate database-based filtering in favor of manifest-based queries
3. **User Control** – Add UI to let users specify privacy when creating jobs
4. **Rebuild Queue** – Create system to update `public` field in existing docpacks

### Benefits

1. **Self-describing artifacts** – The `.docpack` file contains its own visibility metadata
2. **Database independence** – Can determine public docpacks by scanning R2 alone
3. **Offline/local use** – Tools can respect privacy without database access
4. **Auditability** – The R2 bucket is the authoritative source for what's public
5. **Portability** – Docpacks can be shared with privacy metadata intact

---

## Bucket cleanup automation

Automated cleanup system for orphaned docpack files in the R2 bucket. When docpacks are deleted from the database, their corresponding `.docpack` files remain in R2. The cleanup mechanism periodically scans the bucket and removes unreferenced files.

### Manual cleanup

**Endpoint:** `POST /api/admin/cleanup-bucket`

**Authentication:** Requires `Bearer {DOCTOWN_BUILDER_SHARED_SECRET}` header

**Query parameters:**
- `dry_run=true` – Lists files that would be deleted without actually deleting

**Usage:**
```bash
# Dry run - see what would be deleted
curl -X POST "https://www.doctown.dev/api/admin/cleanup-bucket?dry_run=true" \
  -H "Authorization: Bearer YOUR_SECRET"

# Actual cleanup
curl -X POST "https://www.doctown.dev/api/admin/cleanup-bucket" \
  -H "Authorization: Bearer YOUR_SECRET"
```

**Response:**
```json
{
  "message": "Cleanup completed - deleted 5 orphaned files",
  "dry_run": false,
  "orphaned_files": ["docpacks/user1/old-file.docpack"],
  "deleted": ["docpacks/user1/old-file.docpack"],
  "kept": 10,
  "total_in_bucket": 15,
  "total_in_database": 10
}
```

### Automated cleanup (cron)

**Endpoint:** `GET /api/cron/cleanup-bucket`

**Schedule:** Daily at 3:00 AM UTC

**Authentication:** Uses `CRON_SECRET` or falls back to `DOCTOWN_BUILDER_SHARED_SECRET`

**Vercel configuration:**
```json
{
  "crons": [
    {
      "path": "/api/cron/cleanup-bucket",
      "schedule": "0 3 * * *"
    }
  ]
}
```

### How it works

1. Fetches all docpack records from database (`file_url` column)
2. Extracts file paths from URLs
3. Lists all files in R2 bucket under `docpacks/` prefix
4. Compares bucket files against database records
5. Deletes orphaned files

### File path formats

Handles multiple URL formats:
- Direct R2: `https://...r2.cloudflarestorage.com/bucket/docpacks/user_id/file.docpack`
- Proxy: `https://www.doctown.dev/api/docpacks/download?path=docpacks/user_id/file.docpack`

All normalized to: `docpacks/{user_id}/{filename}.docpack`

### Safety features

1. **Dry run mode** – Test before deleting
2. **Database verification** – Only deletes files not in database
3. **File type filtering** – Only processes `.docpack` files
4. **Error logging** – Failed deletions logged but don't stop the process
5. **Authentication** – Requires admin secret

### Environment variables

Required:
- `BUCKET_ACCESS_KEY_ID` – R2 API token access key
- `BUCKET_SECRET_ACCESS_KEY` – R2 API token secret key
- `BUCKET_S3_ENDPOINT` – Cloudflare R2 endpoint URL
- `BUCKET_NAME` – Bucket name (defaults to "doctown-central")
- `DOCTOWN_BUILDER_SHARED_SECRET` – Admin authentication secret

Optional:
- `CRON_SECRET` – Separate secret for cron (defaults to builder secret)

### Monitoring

**Vercel dashboard:**
- View cron job execution history
- Check logs for errors
- Monitor execution time

**Manual monitoring:**
```bash
curl -X POST "https://www.doctown.dev/api/admin/cleanup-bucket?dry_run=true" \
  -H "Authorization: Bearer YOUR_SECRET"
```

---

## Architecture overview

### Pipeline flow

```
User → GitHub repo → RunPod → Builder → R2 → Website → User
```

1. **User triggers build** – Via website dashboard
2. **Job created** – Stored in Supabase with pending status
3. **RunPod invoked** – Builder handler receives job via API
4. **Source fetched** – GitHub repo cloned or zip downloaded
5. **Symbols extracted** – Tree-sitter parses source files
6. **Docs generated** – OpenAI API generates documentation
7. **Docpack created** – ZIP archive with manifest, symbols, docs
8. **Uploaded to R2** – Stored in user's folder
9. **Job completed** – Database updated with file URL
10. **User notified** – Real-time update via webhook/polling

### Database schema

**Key tables:**
- `users` – GitHub OAuth users
- `jobs` – Build jobs with status and logs
- `docpacks` – Generated docpacks with metadata
- `subscriptions` – Stripe subscription records
- `symbol_edits` – User edits to AI-generated docs

### Real-time features

**Build streaming:**
- RunPod handler streams logs
- Website polls job status endpoint
- Progress updates in real-time

**Status tracking:**
- Pending → In Progress → Completed/Failed
- Detailed error logs on failure

### Storage structure

```
doctown-central/
└── docpacks/
    └── {user_id}/
        ├── {job_id}-{timestamp}.docpack
        ├── {job_id}-{timestamp}-edited.docpack
        └── ...
```

### Security

- **Row-level security** – Users can only access their own data
- **Webhook verification** – Stripe webhook signature validation
- **API authentication** – Shared secrets for admin endpoints
- **OAuth scopes** – Minimal GitHub permissions

### Performance optimizations

- **Parallel doc generation** – Multiple OpenAI requests concurrently
- **Incremental parsing** – Only parse changed files (future)
- **CDN caching** – R2 with Cloudflare edge caching
- **Database indexing** – Optimized queries for common operations

### Error handling

- **Graceful degradation** – Partial results on errors
- **Retry logic** – Automatic retries for transient failures
- **Error logging** – Detailed logs for debugging
- **User feedback** – Clear error messages in UI

---

## Contributing

When contributing to Doctown:

1. Follow the existing code style
2. Write tests for new features
3. Update documentation
4. Ensure all tests pass
5. Submit a pull request with clear description

### Development workflow

```bash
# 1. Make changes
# 2. Test locally
npm run dev  # Website
cargo test   # Builder/localdoc

# 3. Format code
npm run format
cargo fmt

# 4. Run linters
npm run lint
cargo clippy

# 5. Commit and push
git add .
git commit -m "Description of changes"
git push
```

### Testing checklist

- [ ] Manual testing in development environment
- [ ] Stripe webhook testing (use test mode)
- [ ] GitHub OAuth flow testing
- [ ] Build pipeline testing (use test repos)
- [ ] Export functionality testing
- [ ] Mobile/responsive testing
- [ ] Accessibility testing

---

For setup instructions, see [`SETUP.md`](SETUP.md).
