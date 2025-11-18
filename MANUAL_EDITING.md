# Manual Editing Feature

## Overview

The manual editing feature allows docpack owners to make custom edits and overwrites to all portions of symbol entries in their generated docpacks. While AI generates the initial documentation, users have full control to refine, correct, or enhance any aspect of the documentation.

## Features

### What Can Be Edited

Users can manually edit all portions of a symbol entry:

**Symbol Metadata:**
- `kind` - The symbol type (function, struct, enum, etc.)
- `signature` - The full signature/declaration

**Documentation Fields:**
- `summary` - Brief one-line description
- `description` - Detailed explanation
- `parameters` - Array of parameter objects with name, type, and description
- `returns` - Return value description
- `example` - Code example demonstrating usage
- `notes` - Array of additional notes and caveats

### Persistence

- Edits are stored in the `symbol_edits` database table
- Each user can have one set of edits per symbol per docpack
- Edits are applied on-the-fly when viewing the docpack
- Original AI-generated content is preserved
- Users can revert individual edits at any time

### Export

- Edited docpacks can be exported with all modifications applied
- Creates a new `.docpack` file with edits merged into the original structure
- Maintains the DOCPACK format specification
- Both `symbols.json` and individual doc files are updated

## Usage

### Viewing Edits

When viewing a docpack you own:
1. Symbols with edits show an "Edited" badge
2. The header displays the total number of edits
3. All displayed content reflects your edits automatically

### Making Edits

1. Navigate to your docpack and select a symbol
2. Click the "Edit" button in the documentation panel
3. Modify any fields in the editor
4. Click "Save" to persist your changes
5. Or click "Cancel" to discard changes

### Reverting Edits

1. Open the edit mode for a symbol with existing edits
2. Click the "Revert" button
3. Confirm the revert action
4. The symbol returns to its original AI-generated state

### Exporting Edited Docpack

1. Make edits to one or more symbols
2. Click "Export Edited" in the header (appears when edits exist)
3. A new `.docpack` file downloads with all edits applied
4. This file can be used with any docpack-compatible tool

## Database Schema

### `symbol_edits` Table

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

### Row Level Security (RLS)

- Users can only read, insert, update, and delete their own edits
- Edits are scoped to the user who created them
- Other users viewing the same docpack see the original content

## API Endpoints

### GET `/api/docpacks/[id]/edits`
Fetch all edits for a docpack by the current user.

**Response:** `Record<symbol_id, SymbolEdit>`

### POST `/api/docpacks/[id]/edits`
Save or update a symbol edit.

**Body:**
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

### DELETE `/api/docpacks/[id]/edits`
Remove an edit (revert to original).

**Body:**
```json
{
  "symbol_id": "string"
}
```

### POST `/api/docpacks/[id]/export`
Export docpack with all user edits applied.

**Response:**
```json
{
  "success": true,
  "download_url": "string",
  "edits_applied": number
}
```

## Implementation Details

### Edit Merging

Edits are merged with original content using the following logic:

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

Only fields that are explicitly edited are overridden. Null/undefined fields fall back to the original value.

### Export Process

1. Download original docpack from storage
2. Load as ZIP archive
3. Parse `symbols.json` and all `docs/*.json` files
4. Apply user edits to matching symbols and docs
5. Repackage as ZIP
6. Upload to storage with `-edited` suffix
7. Return download URL

## Future Enhancements

- Collaborative editing (multiple users)
- Edit history and versioning
- Bulk edit operations
- AI-assisted edit suggestions
- Diff view showing changes from original
- Comments and review system
- Edit approval workflow for public docpacks
