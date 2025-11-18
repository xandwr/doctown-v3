# Bucket Cleanup Mechanism

This document describes the automated cleanup system for orphaned docpack files in the R2 bucket.

## Overview

When docpacks are deleted from the Supabase database, their corresponding `.docpack` files remain in the R2 bucket. Over time, this can lead to unnecessary storage costs and clutter. The cleanup mechanism periodically scans the bucket and removes files that are no longer referenced in the database.

## How It Works

### 1. Manual Cleanup (Admin Endpoint)

**Endpoint:** `POST /api/admin/cleanup-bucket`

**Authentication:** Requires `Bearer {DOCTOWN_BUILDER_SHARED_SECRET}` header

**Query Parameters:**
- `dry_run=true` - Lists files that would be deleted without actually deleting them

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
  "orphaned_files": ["docpacks/user1/old-file.docpack", ...],
  "deleted": ["docpacks/user1/old-file.docpack", ...],
  "kept": 10,
  "total_in_bucket": 15,
  "total_in_database": 10
}
```

### 2. Automated Cleanup (Cron Job)

**Endpoint:** `GET /api/cron/cleanup-bucket`

**Schedule:** Runs daily at 3:00 AM UTC (configured in `vercel.json`)

**Authentication:** Uses `CRON_SECRET` or falls back to `DOCTOWN_BUILDER_SHARED_SECRET`

**Vercel Configuration:**
The cron job is configured in `vercel.json`:
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

## Environment Variables

Required environment variables:
- `BUCKET_ACCESS_KEY_ID` - R2 API token access key
- `BUCKET_SECRET_ACCESS_KEY` - R2 API token secret key
- `BUCKET_S3_ENDPOINT` - Cloudflare R2 endpoint URL
- `BUCKET_NAME` - Bucket name (defaults to "doctown-central")
- `DOCTOWN_BUILDER_SHARED_SECRET` - Admin authentication secret

Optional:
- `CRON_SECRET` - Separate secret for cron authentication (defaults to builder secret)

## Deployment

### Vercel

1. Push the code with `vercel.json` to your repository
2. Vercel will automatically detect and set up the cron job
3. The cron job will run according to the schedule (daily at 3 AM UTC)
4. View cron logs in the Vercel dashboard under "Cron Jobs"

### Manual Testing

Before deploying, test the cleanup mechanism:

```bash
# 1. Test dry run locally
curl -X POST "http://localhost:5173/api/admin/cleanup-bucket?dry_run=true" \
  -H "Authorization: Bearer your-secret"

# 2. Check the output to verify correct files would be deleted

# 3. Run actual cleanup if dry run looks good
curl -X POST "http://localhost:5173/api/admin/cleanup-bucket" \
  -H "Authorization: Bearer your-secret"
```

## How Files are Identified

The cleanup process:

1. **Fetches all docpack records** from the database (`file_url` column)
2. **Extracts file paths** from URLs (format: `docpacks/{user_id}/{filename}.docpack`)
3. **Lists all files** in the R2 bucket under `docpacks/` prefix
4. **Compares** bucket files against database records
5. **Deletes orphaned files** that exist in the bucket but not in the database

### File Path Formats

The system handles multiple URL formats:

- Direct R2 URLs: `https://...r2.cloudflarestorage.com/bucket/docpacks/user_id/file.docpack`
- Proxy URLs: `https://www.doctown.dev/api/docpacks/download?path=docpacks/user_id/file.docpack`

All are normalized to the path format: `docpacks/{user_id}/{filename}.docpack`

## Safety Features

1. **Dry run mode** - Test before deleting
2. **Database verification** - Only deletes files not in database
3. **File type filtering** - Only processes `.docpack` files
4. **Error logging** - Failed deletions are logged but don't stop the process
5. **Authentication** - Requires admin secret to prevent unauthorized cleanup

## Monitoring

### Vercel Dashboard
- View cron job execution history
- Check logs for errors or issues
- Monitor execution time and success rate

### Manual Monitoring
Run a dry run periodically to check for orphaned files:
```bash
curl -X POST "https://www.doctown.dev/api/admin/cleanup-bucket?dry_run=true" \
  -H "Authorization: Bearer YOUR_SECRET"
```

## Troubleshooting

### No files being deleted
- Check that docpacks have been actually deleted from the database
- Verify S3 credentials are correct
- Check logs for permission errors

### Files being deleted incorrectly
- Run dry run to inspect what would be deleted
- Check database `file_url` format matches expected pattern
- Verify path extraction regex is working correctly

### Cron job not running
- Check Vercel dashboard for cron job status
- Verify `vercel.json` is in the correct location
- Check authentication headers are correct
- Review Vercel function logs for errors

## Cost Optimization

Running the cleanup daily helps reduce storage costs:
- Average docpack size: ~100KB - 5MB
- If 10 orphaned docpacks per day: ~50KB - 50MB daily savings
- Monthly savings: ~1.5MB - 1.5GB

## Future Improvements

Potential enhancements:
- [ ] Send notifications when large cleanup occurs
- [ ] Track cleanup metrics over time
- [ ] Add cleanup for specific user folders
- [ ] Implement retention policies (e.g., keep files for 30 days after deletion)
- [ ] Add cleanup for other storage resources (logs, temp files, etc.)
