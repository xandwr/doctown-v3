# Setup Guide: Manual Editing Feature

This guide will help you set up the manual editing feature for docpacks.

## Prerequisites

- Existing Doctown v3 installation
- PostgreSQL/Supabase database access
- Node.js and npm installed

## Step 1: Database Migration

Run the SQL migration to create the `symbol_edits` table:

```bash
# Using psql
psql -U your_user -d your_database -f schema_add_symbol_edits.sql

# Or using Supabase CLI
supabase db push
```

Or manually execute the SQL in your database console:

```sql
-- See schema_add_symbol_edits.sql for the complete migration
```

## Step 2: Verify Database Types

The TypeScript types should already be in place. Verify that `website/src/lib/types.ts` includes:

```typescript
export interface SymbolEdit {
  id: string;
  docpack_id: string;
  user_id: string;
  symbol_id: string;
  signature?: string;
  kind?: string;
  summary?: string;
  description?: string;
  parameters?: DocpackParameter[];
  returns?: string;
  example?: string;
  notes?: string[];
  created_at: string;
  updated_at: string;
}
```

## Step 3: Install Dependencies (if needed)

The feature uses existing dependencies, but verify they're installed:

```bash
cd website
npm install
```

## Step 4: Update Environment Variables

Ensure your `.env` file has the necessary S3/R2 credentials for exporting:

```env
BUCKET_ACCESS_KEY_ID=your_access_key
BUCKET_SECRET_ACCESS_KEY=your_secret_key
BUCKET_S3_ENDPOINT=https://your-endpoint.r2.cloudflarestorage.com
BUCKET_NAME=doctown-central
BUCKET_PUBLIC_URL=https://your-cdn-url
```

## Step 5: Build and Deploy

```bash
cd website
npm run build
npm run preview  # or deploy to your hosting platform
```

## Testing the Feature

### 1. Create or access a docpack you own

```bash
# Navigate to your docpack
http://localhost:5173/docpacks/[your-docpack-id]
```

### 2. Test editing

1. Select a symbol from the list
2. Click the "Edit" button
3. Modify any fields
4. Click "Save"
5. Verify the "Edited" badge appears

### 3. Test reverting

1. Open edit mode for an edited symbol
2. Click "Revert"
3. Confirm the action
4. Verify the symbol returns to original state

### 4. Test exporting

1. Make several edits
2. Click "Export Edited" in the header
3. Verify the download starts
4. Extract and inspect the `.docpack` file
5. Verify edits are applied in `symbols.json` and `docs/*.json`

## API Testing

You can test the API endpoints directly:

### Fetch edits
```bash
curl -X GET http://localhost:5173/api/docpacks/[id]/edits \
  -H "Cookie: session_token=your_token"
```

### Save edit
```bash
curl -X POST http://localhost:5173/api/docpacks/[id]/edits \
  -H "Content-Type: application/json" \
  -H "Cookie: session_token=your_token" \
  -d '{
    "symbol_id": "example::function",
    "summary": "Updated summary",
    "description": "Updated description"
  }'
```

### Revert edit
```bash
curl -X DELETE http://localhost:5173/api/docpacks/[id]/edits \
  -H "Content-Type: application/json" \
  -H "Cookie: session_token=your_token" \
  -d '{"symbol_id": "example::function"}'
```

### Export
```bash
curl -X POST http://localhost:5173/api/docpacks/[id]/export \
  -H "Cookie: session_token=your_token"
```

## Troubleshooting

### Issue: "Unauthorized" errors

**Solution:** Ensure you're logged in and own the docpack you're trying to edit.

### Issue: Edits not saving

**Solution:** Check browser console for errors. Verify database connection and RLS policies.

### Issue: Export fails

**Solution:** 
- Verify S3/R2 credentials in environment variables
- Check that the original docpack file exists in storage
- Ensure you have write permissions to the bucket

### Issue: Edits not appearing

**Solution:**
- Clear browser cache
- Verify the edit was saved (check network tab)
- Query the database directly to confirm the edit exists

### Issue: Database RLS errors

**Solution:** Make sure your Supabase auth setup properly passes `auth.uid()` for RLS policies.

## Files Created/Modified

### New Files
- `schema_add_symbol_edits.sql` - Database migration
- `website/src/routes/api/docpacks/[id]/edits/+server.ts` - Edit API endpoint
- `website/src/routes/api/docpacks/[id]/export/+server.ts` - Export endpoint
- `website/src/lib/components/SymbolEditor.svelte` - Edit UI component
- `MANUAL_EDITING.md` - Feature documentation
- `SETUP_MANUAL_EDITING.md` - This setup guide

### Modified Files
- `website/src/lib/types.ts` - Added `SymbolEdit` interface
- `website/src/routes/docpacks/[id]/+page.svelte` - Integrated editing UI

## Security Considerations

- Row Level Security (RLS) ensures users can only edit their own docpacks
- Edits are scoped per user, preventing conflicts
- Original content is never modified, allowing safe reverts
- Export endpoint verifies ownership before generating files

## Performance Notes

- Edits are fetched once on page load and cached in memory
- Merging happens client-side for instant feedback
- Export is an on-demand operation that doesn't impact viewing
- Database indexes optimize edit lookups

## Next Steps

After setup, consider:

1. Monitoring edit usage and storage
2. Adding edit analytics
3. Implementing collaborative editing features
4. Creating an edit history/versioning system
5. Adding AI-assisted edit suggestions

## Support

For issues or questions:
- Check the console for errors
- Review the database logs
- Verify API responses in network tab
- Consult `MANUAL_EDITING.md` for feature details
