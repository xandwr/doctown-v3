# Doctown Rust Pipeline Implementation

Summary
-------

This document outlines the end-to-end architecture and implementation plan for the Doctown pipeline: how a user triggers documentation generation for a Rust repository via a GitHub App webhook, how the serverless Rust builder parses and generates docs, and how the website accepts and serves the resulting `.docpack` artifact.

Architecture Overview
---------------------

Stack:

- GitHub App (webhooks) for triggering builds
- RunPod serverless CPU pod for builder execution
- Rust builder (pre-compiled binary) for parsing and doc generation
- OpenAI (via `llm` crate) for text generation
- Cloudflare R2 (object storage) for storing `.docpack` files
- SvelteKit (website) deployed on Vercel

High-level flow:

1. User installs the Doctown GitHub App on their repository.
2. GitHub sends `installation_repositories` or `push` webhook to SvelteKit backend.
3. Backend receives the webhook and tells RunPod CPU "start job for repo XYZ".
4. RunPod serverless CPU pod (builder) starts:
   - Pulls the repo using the GitHub App installation token
   - Parses Rust files (tree-sitter), extracting rich symbols
   - Batches symbols (≤ 16k token batches) and sends them to the LLM in parallel
   - Packages a `.docpack` ZIP containing manifest, symbols, and generated docs
   - Streams the result back to the SvelteKit API
5. SvelteKit API stores the `.docpack` in R2.
6. The docpack appears in the commons UI.

**Zero repo pollution:**
- No GitHub Actions required
- No device flow authentication
- No workflows or `.github/` files in user repos
- No `doctown.yml` config files
- Zero setup for users beyond installing the GitHub App

Phases
------

Phase 1 — Repository Setup & Infrastructure
------------------------------------------

1. **Split monorepo into two GitHub repositories**

   - `github.com/<you>/doctown` (website)
     - Move `website/` contents to repository root.
     - Keep `.env`, `package.json`, `svelte.config.js` as needed.
     - Add `LICENSE` (MIT) and `README.md`.

   - `github.com/<you>/doctown-builder` (builder)
     - Move `builder/` contents to repository root.
     - Keep `Cargo.toml`, `.env`, `src/` and move `DOCPACK_SPEC.md` here.
     - Add `LICENSE` (MIT) and `README.md`.

2. **Configure RunPod serverless CPU pod**
   - Create a RunPod template with the pre-compiled `doctown` binary
   - Configure as a serverless CPU pod (not GPU)
   - Set up API endpoint to accept job requests from SvelteKit backend
   - Configure environment variables: GitHub App credentials, OpenAI key

3. **Configure builder release pipeline** — create `.github/workflows/release.yml` in `doctown-builder`:

```yaml
name: Release Builder Binary

on:
  release:
    types: [created]
  workflow_dispatch:

jobs:
  build:
    name: Build ${{ matrix.target }}
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        include:
          - os: ubuntu-24.04
            target: x86_64-unknown-linux-gnu
            binary_name: doctown-linux-x64

    steps:
      - uses: actions/checkout@v4
      - name: Install Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          target: ${{ matrix.target }}
          override: true
      - name: Build release binary
        run: cargo build --release --target ${{ matrix.target }}
      - name: Strip binary (Linux)
        if: matrix.os == 'ubuntu-24.04'
        run: strip target/${{ matrix.target }}/release/doctown
      - name: Rename binary
        run: mv target/${{ matrix.target }}/release/doctown ${{ matrix.binary_name }}
      - name: Upload binary to release
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ github.event.release.upload_url }}
          asset_path: ./${{ matrix.binary_name }}
          asset_name: ${{ matrix.binary_name }}
          asset_content_type: application/octet-stream
```

Phase 2 — Rust Builder Implementation
------------------------------------

### 2.1 `Cargo.toml` dependencies

```toml
[package]
name = "doctown"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "doctown"
path = "src/main.rs"

[dependencies]
# Existing
dotenv = "0.15.0"
llm = "1.3.6"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1.48", features = ["full", "macros", "rt-multi-thread"] }

# New additions
tree-sitter = "0.22"
tree-sitter-rust = "0.21"
walkdir = "2.5"
zip = { version = "2.2", default-features = false, features = ["deflate"] }
reqwest = { version = "0.12", features = ["json", "multipart"] }
anyhow = "1.0"
clap = { version = "4.5", features = ["derive"] }
uuid = { version = "1.10", features = ["v4"] }
chrono = { version = "0.4", features = ["serde"] }
octocrab = "0.40"  # For GitHub API integration
```

### 2.2 Module structure

Create the following files in `src/`:

- `main.rs` — CLI entry point, orchestrates pipeline
- `github.rs` — GitHub API integration, repo cloning using installation token
- `parser.rs` — tree-sitter integration, Rust file parsing
- `extractor.rs` — AST traversal, symbol extraction (rich format)
- `batcher.rs` — token counting, batching symbols for LLM
- `generator.rs` — OpenAI integration, parallel batch processing
- `packager.rs` — ZIP creation with docpack structure
- `uploader.rs` — HTTP client for website API
- `models.rs` — shared types (`Symbol`, `Docpack`, `Manifest`)

### 2.3 Implementation details

`src/main.rs` (outline):

```rust
use clap::Parser;
use anyhow::Result;

#[derive(Parser)]
#[command(name = "doctown")]
#[command(about = "Generate .docpack documentation from Rust codebases")]
struct Cli {
    /// Repository owner/name (e.g., "rust-lang/rust")
    #[arg(short, long)]
    repo: String,

    /// GitHub App installation token
    #[arg(short, long)]
    token: String,

    /// API endpoint for doctown backend
    #[arg(short, long)]
    api_url: String,

    /// Job ID from doctown
    #[arg(short, long)]
    job_id: String,

    /// Git ref (branch, tag, or commit SHA)
    #[arg(short = 'b', long, default_value = "main")]
    git_ref: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    println!("🔐 Cloning repository using GitHub App...");
    let repo_path = github::clone_repo(&cli.repo, &cli.token, &cli.git_ref).await?;

    println!("🔍 Parsing Rust files...");
    let symbols = parser::parse_repository(&repo_path)?;

    println!("📊 Extracted {} symbols", symbols.len());

    println!("📦 Batching symbols for LLM...");
    let batches = batcher::create_batches(&symbols, 16000)?;

    println!("🤖 Generating documentation ({} batches)...", batches.len());
    let docs = generator::generate_docs(batches).await?;

    println!("📄 Creating .docpack...");
    let docpack_path = packager::create_docpack(&symbols, &docs, &cli.job_id)?;

    println!("☁️ Streaming to doctown API...");
    uploader::upload_docpack(&cli.api_url, &cli.token, &cli.job_id, &docpack_path).await?;

    println!("✅ Docpack generated successfully!");
    Ok(())
}
```

Other modules (high-level expectations):

- `github.rs`
  - Use `octocrab` to authenticate with GitHub App installation token.
  - Clone the specified repository to a temporary directory.
  - Checkout the specified git ref (branch, tag, or commit).
  - Return the local path to the cloned repository.

- `parser.rs`
  - Use tree-sitter with `tree-sitter-rust`.
  - Walk repo with `walkdir`, filter `*.rs` files.
  - Parse each file and collect AST nodes → `Vec<RawNode>`.

- `extractor.rs`
  - Convert tree-sitter nodes to rich `Symbol` structs.
  - Extract: name, type, visibility, signature, params, return type, doc comments, attributes, file path, line number.
  - Handle: functions, structs, enums, traits, impls, consts.
  - Filter: only `pub` items by default (configurable later).

- `batcher.rs`
  - Estimate token count per symbol (e.g. `symbol_json.len() / 4`).
  - Group symbols into batches under 16k tokens.
  - Each batch: `{ symbols: Vec<Symbol>, batch_id: usize }`.

- `generator.rs`
  - Use `llm` crate or OpenAI client.
  - Process batches in parallel (`tokio` tasks).
  - For each batch: send all symbols as JSON context.
  - Prompt: "Generate documentation for these symbols following the docpack spec".
  - Use structured output (JSON mode) to match docpack schema.

- `packager.rs`
  - Create temp directory.
  - Write `manifest.json` (repo info, timestamp, version).
  - Write `symbols.json` (array of all symbols).
  - Write `docs/` folder with `{symbol_id}.json` per symbol.
  - Optionally include `source/` (skip for MVP).
  - Zip everything into `{job_id}.docpack` and return the path.

- `uploader.rs`
  - Create multipart form with ZIP file.
  - `POST` to `{api_url}/api/docpack/upload`.
  - Headers: `Authorization: Bearer {token}`.
  - Body: `{ job_id, file: <binary> }`.
  - Handle errors, retry once on failure.

- `models.rs`

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub id: String,
    pub name: String,
    pub symbol_type: String,
    pub visibility: String,
    pub signature: String,
    pub parameters: Vec<Parameter>,
    pub return_type: Option<String>,
    pub file: String,
    pub line: usize,
    pub doc_comments: Option<String>,
    pub attributes: Vec<String>,
    pub dependencies: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Parameter {
    pub name: String,
    pub param_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub version: String,
    pub generated_at: String,
    pub repository: RepoInfo,
    pub symbol_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoInfo {
    pub name: String,
    pub url: String,
    pub commit_sha: String,
    pub branch: String,
}
```

Phase 3 — Website API Endpoints
--------------------------------

### 3.1 SvelteKit routes

Create these files in `website/src/routes/api/`:

- `webhook/+server.ts` — GitHub App webhook handler
- `docpack/upload/+server.ts` — Receive `.docpack` from builder
- `docpack/complete/+server.ts` — Mark job as complete

`webhook/+server.ts`:

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { verifyGitHubWebhook } from '$lib/github';
import { triggerRunPodJob } from '$lib/runpod';

export const POST: RequestHandler = async ({ request }) => {
  const payload = await request.text();
  const signature = request.headers.get('x-hub-signature-256');

  if (!verifyGitHubWebhook(payload, signature)) {
    return json({ error: 'Invalid signature' }, { status: 401 });
  }

  const event = JSON.parse(payload);
  const eventType = request.headers.get('x-github-event');

  // Handle installation or push events
  if (eventType === 'installation_repositories' || eventType === 'push') {
    const job_id = crypto.randomUUID();

    const repoFullName =
      eventType === 'push'
        ? event.repository.full_name
        : event.repositories_added[0]?.full_name;
        // I CAN do this for MVP... but GitHub might notify of multiple additions at once so it should be made more robust in prod.

    const gitRef =
      eventType === 'push'
        ? event.ref.replace('refs/heads/', '')
        : event.repositories_added[0]?.default_branch || 'main'; // Same shit here.

    // Get GitHub App installation token
    const installationToken = await getInstallationToken(event.installation.id);

    // Trigger RunPod job
    await triggerRunPodJob({
      job_id,
      repo: repoFullName,
      git_ref: gitRef,
      token: installationToken,
      api_url: process.env.NODE_ENV === 'production'
        ? 'https://doctown.dev'
        : 'http://localhost:5173'
    });

    // Store job in database (TODO: implement persistence)
    // Should use Vercel KV here for a little easy to rip cache
    // We should definitely store job metadata immediately.
    console.log(`Created job ${job_id} for ${repoFullName}`);

    return json({ job_id, status: 'pending' });
  }

  return json({ message: 'Event ignored' });
};
```

`docpack/upload/+server.ts`:

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

const s3 = new S3Client({
  region: 'auto',
  endpoint: 'https://<account_id>.r2.cloudflarestorage.com',
  credentials: {
    accessKeyId: process.env.BUCKET_ACCESS_KEY_ID!,
    secretAccessKey: process.env.BUCKET_SECRET!
  }
});

export const POST: RequestHandler = async ({ request }) => {
  const auth = request.headers.get('authorization');
  if (!auth?.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const formData = await request.formData();
  const job_id = formData.get('job_id') as string;
  const file = formData.get('file') as File;

  if (!job_id || !file) {
    return json({ error: 'Missing job_id or file' }, { status: 400 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  await s3.send(
    new PutObjectCommand({
      Bucket: 'doctown-central',
      Key: `docpacks/${job_id}.docpack`,
      Body: buffer,
      ContentType: 'application/zip'
    })
  );

  return json({ success: true });
};
```

`docpack/complete/+server.ts`:

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ request }) => {
  const auth = request.headers.get('authorization');
  if (!auth?.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { job_id, status } = await request.json();

  // TODO: update job status in persistent storage
  console.log(`Job ${job_id} completed with status: ${status}`);

  return json({ success: true });
};
```

### 3.2 RunPod integration

Create `website/src/lib/runpod.ts`:

```ts
export async function triggerRunPodJob(params: {
  job_id: string;
  repo: string;
  git_ref: string;
  token: string;
  api_url: string;
}) {
  const response = await fetch(process.env.RUNPOD_ENDPOINT!, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${process.env.RUNPOD_API_KEY}`
    },
    body: JSON.stringify({
      input: {
        repo: params.repo,
        git_ref: params.git_ref,
        token: params.token,
        api_url: params.api_url,
        job_id: params.job_id
      }
    })
  });

  if (!response.ok) {
    throw new Error('Failed to trigger RunPod job');
  }

  return await response.json();
}
```

### 3.3 GitHub App integration

Create `website/src/lib/github.ts`:

```ts
import crypto from 'crypto';
import { App } from '@octokit/app';

export function verifyGitHubWebhook(payload: string, signature: string | null): boolean {
  if (!signature) return false;

  const secret = process.env.GITHUB_WEBHOOK_SECRET!;
  const hmac = crypto.createHmac('sha256', secret);
  const digest = 'sha256=' + hmac.update(payload).digest('hex');

  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest));
}

export async function getInstallationToken(installationId: number): Promise<string> {
  const app = new App({
    appId: process.env.GITHUB_APP_ID!,
    privateKey: process.env.GITHUB_APP_PRIVATE_KEY!
  });

  const { token } = await app.octokit.request(
    'POST /app/installations/{installation_id}/access_tokens',
    { installation_id: installationId }
  );

  return token;
}
```

Phase 4 — GitHub App Setup
---------------------------

1. Go to **GitHub Settings → Developer settings → GitHub Apps**.
2. Create new GitHub App: **Doctown**.
3. Permissions:
   - Repository: Contents (read)
   - Repository: Metadata (read)
4. Webhooks:
   - Enable and point to `https://doctown.dev/api/webhook`.
   - Set webhook secret and store in `GITHUB_WEBHOOK_SECRET` env var.
   - Subscribe to events: `push`, `installation_repositories`
5. Generate a private key and store in `GITHUB_APP_PRIVATE_KEY` env var.
6. Note the App ID and store in `GITHUB_APP_ID` env var.

Phase 5 — RunPod Serverless Setup
----------------------------------

1. Create a RunPod serverless endpoint (CPU, not GPU).
2. Create a Docker image with:
   - Pre-compiled `doctown` binary from releases
   - Runtime dependencies (git, etc.)
   - Handler script that receives job params and runs the builder
3. Configure endpoint to accept JSON input with fields:
   - `repo`: Repository full name
   - `git_ref`: Branch/tag/commit to build
   - `token`: GitHub App installation token
   - `api_url`: Doctown API URL
   - `job_id`: Job identifier
4. Store RunPod API key in `RUNPOD_API_KEY` env var.
5. Store RunPod endpoint URL in `RUNPOD_ENDPOINT` env var.

Phase 6 — Testing & Deployment
------------------------------

### 6.1 Local testing

- Run website:

```bash
cd website
npm run dev
```

- For webhooks during local development:

```bash
ngrok http 5173
```

Update the GitHub App webhook URL to the ngrok URL. Test the full flow by pushing to a test Rust repository.

### 6.2 Deployment

- **Builder**
  - Push to `doctown-builder` repo.
  - Create GitHub release (e.g. `v0.1.0`).
  - Release workflow builds and attaches the binary.
  - Upload binary to RunPod Docker image.

- **Website**
  - Push to `doctown` repo.
  - Connect to Vercel.
  - Add environment variables:
    - `GITHUB_APP_ID`
    - `GITHUB_APP_PRIVATE_KEY`
    - `GITHUB_WEBHOOK_SECRET`
    - `RUNPOD_API_KEY`
    - `RUNPOD_ENDPOINT`
    - `BUCKET_ACCESS_KEY_ID` (R2)
    - `BUCKET_SECRET` (R2)
    - `OPENAI_API_KEY`
  - Deploy to `doctown.dev`.

### 6.3 Self-documentation test

1. Install the Doctown GitHub App on the `doctown-builder` repo.
2. Push a commit to trigger the webhook.
3. Confirm that:
   - Webhook is received
   - RunPod job is triggered
   - Builder clones the repo
   - Builder parses Rust files
   - Builder generates `.docpack`
   - Builder uploads to SvelteKit API
   - SvelteKit stores in R2
   - Docpack appears in commons UI

MVP Success Criteria
--------------------

- ✅ User installs Doctown GitHub App on their Rust repository.
- ✅ Push event or installation triggers webhook to SvelteKit backend.
- ✅ Backend triggers RunPod serverless CPU job with repo details.
- ✅ RunPod builder clones repo using GitHub App installation token.
- ✅ Builder parses Rust files with tree-sitter.
- ✅ Builder extracts rich symbols (name, signature, docs, etc.).
- ✅ Builder batches symbols (16k token limit).
- ✅ Builder sends batches to OpenAI in parallel.
- ✅ Builder creates `.docpack` ZIP.
- ✅ Builder streams result back to website API.
- ✅ Website uploads to R2 bucket.
- ✅ Docpack appears in commons.
- ✅ **Zero repo pollution** — no workflows, no config files, no setup required.
