# Manifest-Based Privacy for Docpacks

## Overview

As of this update, docpack manifests now include a `public` field that serves as the **authoritative source of truth** for docpack visibility. This eliminates the need to query databases to determine which docpacks should be visible in the commons.

## Motivation

Previously, privacy/visibility was controlled solely through the database:
- The `docpacks` table has a `public` boolean column
- The commons page queried the database to filter public docpacks
- The manifest itself had no privacy information

**Problem**: This created a dependency on the database as the single source of truth, making it impossible to authoritatively determine visibility by examining just the R2 storage bucket.

**Solution**: Embed privacy information directly in the manifest, making the `.docpack` file self-describing and the R2 bucket queryable for public docpacks without database dependencies.

## Changes Made

### 1. Manifest Schema Updates

Added `public: bool` field to manifest structures:

**Builder** ([builder/src/pipeline/pack.rs:25](builder/src/pipeline/pack.rs#L25)):
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

**Localdoc Reader** ([localdoc/src/models.rs:11](localdoc/src/models.rs#L11)):
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

### 2. Manifest Generation

Updated `create_docpack()` and `create_manifest()` functions to accept and include the `public` parameter ([builder/src/pipeline/pack.rs:77](builder/src/pipeline/pack.rs#L77), [builder/src/pipeline/pack.rs:156](builder/src/pipeline/pack.rs#L156)).

**Default Behavior**: Docpacks default to `public: false` (private) for security.

**Environment Variable Override**: The builder CLI supports `DOCPACK_PUBLIC=true` to create public docpacks when building manually.

### 3. Format Specification

Updated [DOCPACK_FORMAT.md](DOCPACK_FORMAT.md#L52) to document the new field with examples and field descriptions.

### 4. Utilities Created

#### Python Script: `scripts/list-public-docpacks.py`

A utility to query R2 directly for public docpacks by reading manifests:

```bash
# Human-readable output
python3 scripts/list-public-docpacks.py

# JSON output for programmatic use
python3 scripts/list-public-docpacks.py --json
```

This demonstrates:
- Listing all docpacks in R2
- Extracting manifest.json from each .docpack ZIP
- Filtering by `manifest.public === true`
- **Zero database queries required**

#### API Endpoint: `/api/docpacks/public-from-r2`

A new endpoint ([website/src/routes/api/docpacks/public-from-r2/+server.ts](website/src/routes/api/docpacks/public-from-r2/+server.ts)) that queries R2 directly:

```typescript
GET /api/docpacks/public-from-r2
```

Returns:
```json
{
  "docpacks": [...],
  "source": "r2-manifests",
  "message": "Queried directly from R2 manifests - no database dependency"
}
```

## Current Architecture

### Two Sources of Truth (Transitional)

Currently, both sources exist:

1. **Database** (`docpacks.public` column) - Used by `/api/docpacks?public=true`
2. **Manifest** (`manifest.public` field) - Used by `/api/docpacks/public-from-r2`

This allows for:
- Gradual migration
- Testing the new approach
- Fallback to database if needed

### Future Direction

Eventually, you may want to:

1. **Sync on Upload**: When the builder completes, parse the manifest and sync `public` field to database
2. **Single Source**: Deprecate database-based filtering in favor of manifest-based queries
3. **User Control**: Add UI to let users specify privacy when creating jobs
4. **Rebuild Queue**: Create a system to update `public` field in existing docpacks

## Implementation Flow

### Current: Private by Default

1. User triggers docpack build via `/api/jobs/create`
2. RunPod handler calls builder with job parameters
3. Builder generates docpack with `public: false` (default)
4. Handler uploads to R2: `docpacks/{user_id}/{job_id}-{timestamp}.docpack`
5. Handler notifies API at `/api/jobs/complete`
6. API creates database entry with `public: false`

### Future: User-Controlled Privacy

To enable user-controlled privacy:

1. Add `public` field to jobs table (or pass via triggerBuild params)
2. Update `/api/jobs/create` to accept optional `public` parameter
3. Pass to RunPod handler as `input.public`
4. Builder reads from environment or CLI arg: `DOCPACK_PUBLIC=${public}`
5. Manifest includes correct privacy setting
6. API syncs manifest.public to database.public on completion

## Usage Examples

### Query Public Docpacks from R2

```bash
# CLI
python3 scripts/list-public-docpacks.py

# API
curl https://doctown.dev/api/docpacks/public-from-r2
```

### Build Public Docpack (Manual)

```bash
# Set environment variable
export DOCPACK_PUBLIC=true

# Run builder
./doctown-builder https://github.com/user/repo my-public-pack
```

### Check Manifest Privacy (Python)

```python
import zipfile
import json

with zipfile.ZipFile('example.docpack', 'r') as zf:
    manifest = json.loads(zf.read('manifest.json'))
    is_public = manifest.get('public', False)
    print(f"This docpack is {'public' if is_public else 'private'}")
```

## Benefits

1. **Self-Describing Artifacts**: The `.docpack` file contains its own visibility metadata
2. **Database Independence**: Can determine public docpacks by scanning R2 alone
3. **Offline/Local Use**: Tools can respect privacy without database access
4. **Auditability**: The R2 bucket is the authoritative source for what's public
5. **Portability**: Docpacks can be shared with privacy metadata intact

## Migration Considerations

For existing docpacks without the `public` field:

1. **Default Behavior**: Treat missing field as `public: false`
2. **Rebuild**: Trigger rebuilds for docpacks that should be public
3. **Manual Update**: Use a migration script to add `public: false` to existing manifests

## Testing

To test the new functionality:

1. **Create a public docpack**:
   ```bash
   export DOCPACK_PUBLIC=true
   ./doctown-builder test-repo.zip test-pack
   ```

2. **Verify manifest**:
   ```bash
   unzip -p test-pack.docpack manifest.json | jq .public
   # Should output: true
   ```

3. **Query R2**:
   ```bash
   python3 scripts/list-public-docpacks.py
   # Should include your test pack
   ```

4. **Test API**:
   ```bash
   curl http://localhost:5173/api/docpacks/public-from-r2 | jq
   ```

## Files Modified

- [builder/src/pipeline/pack.rs](builder/src/pipeline/pack.rs) - Added `public` field to Manifest
- [builder/src/main.rs](builder/src/main.rs) - Support DOCPACK_PUBLIC env var
- [localdoc/src/models.rs](localdoc/src/models.rs) - Added `public` field to Manifest
- [DOCPACK_FORMAT.md](DOCPACK_FORMAT.md) - Documented `public` field

## Files Created

- [scripts/list-public-docpacks.py](scripts/list-public-docpacks.py) - R2 query utility
- [website/src/routes/api/docpacks/public-from-r2/+server.ts](website/src/routes/api/docpacks/public-from-r2/+server.ts) - R2-based API endpoint
- [MANIFEST_PRIVACY.md](MANIFEST_PRIVACY.md) - This documentation

## Next Steps

1. **Add User Control**: Update job creation UI to let users specify privacy
2. **Sync on Completion**: Parse manifest in `/api/jobs/complete` and sync to database
3. **Migrate Existing**: Create script to update existing docpacks
4. **Switch Commons**: Update commons page to use R2-based endpoint by default
5. **Deprecate Database**: Eventually remove `docpacks.public` column

---

**Questions?** See [DOCPACK_FORMAT.md](DOCPACK_FORMAT.md) for the format specification or examine the implementation in [builder/src/pipeline/pack.rs](builder/src/pipeline/pack.rs).
