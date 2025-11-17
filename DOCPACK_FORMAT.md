# DOCPACK Specification

**Version:** 1  
**Extension:** `.docpack`  
**Format:** A ZIP archive containing a small set of structured, human-readable JSON files and directories.

A docpack is a portable, self-contained documentation bundle generated from a source code repository.
It includes the extracted symbol graph, AI-generated documentation, and optional source snapshots.

---

## Directory Structure

A `.docpack` file is a ZIP archive with the following structure:

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

---

## `manifest.json`

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
- `docpack_format`: Version of the docpack format specification
- `project`: Project metadata including name, version, repository URL, and commit hash
- `generated_at`: ISO 8601 timestamp of when the docpack was generated
- `language_summary`: Count of files by language/type
- `stats`: Counts of extracted symbols and generated documentation
- `public`: Boolean indicating if this docpack is intended for public visibility (defaults to `false`)

---

## `symbols.json`

Array of symbol records extracted from the source using the AST analysis phase.  
Each symbol links to a doc entry via `doc_id`.

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

This file contains **no AI-generated content**.  
It is the ground-truth structural representation of the codebase.

---

## `docs/<doc_id>.json`

AI-generated documentation for a single symbol.  
Each file corresponds to one symbol defined in `symbols.json`.

Example:

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

---

## `source/` (optional)

A snapshot of the source repository at the time the docpack was created.

Recommended contents:
- entire project directory  
- `.rs`, `.ts`, `.py`, etc.  
- configuration files (`Cargo.toml`, `package.json`, etc.)

Binary files may be omitted at generator discretion.

---

## Packaging

To create a `.docpack`:

1. Create the directory structure above.
2. Write all JSON files.
3. Optionally write the source tree.
4. Zip the directory without compression level requirements.
5. Rename:  
   ```
   my_project.docpack
   ```

---

## Goals of the Format

- Human-readable  
- Machine-parseable  
- Minimal file count  
- Stable & versionable  
- Friendly to GitHub Actions, CI pipelines, and local tools  
- Supports incremental regeneration  
- Clean separation between AST truth (`symbols.json`) and generated docs (`docs/*.json`)