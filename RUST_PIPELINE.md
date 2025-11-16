Doctown Rust Pipeline Implementation Plan
Architecture Overview
Stack: GitHub App + GitHub Actions + Rust Builder (pre-compiled binary) + OpenAI GPT-4o + Cloudflare R2 + SvelteKit (Vercel) Flow:
User authenticates via GitHub App (device flow) on doctown.dev
User selects a repo and clicks "Create Docpack"
Website backend dispatches GitHub Action with OIDC token
Action downloads pre-compiled doctown binary from GitHub releases
Binary parses Rust code with tree-sitter, extracts rich symbols
Binary batches symbols (16k token limit) and sends to OpenAI in parallel
Binary creates .docpack ZIP with manifest/symbols/docs
Binary sends ZIP to website API endpoint
Website uploads to R2 bucket and marks docpack complete
User sees completed docpack in commons
Phase 1: Repository Setup & Infrastructure
1.1 Split Monorepo into Two GitHub Repos
Create two new repositories:
github.com/yourusername/doctown (website)
Move website/ contents to root
Keep .env, package.json, svelte.config.js
Add MIT license, README
github.com/yourusername/doctown-builder (builder)
Move builder/ contents to root
Keep Cargo.toml, .env, src/
Move DOCPACK_SPEC.md here
Add MIT license, README
Set up GitHub Actions for release builds
1.2 Configure Builder Release Pipeline
Create .github/workflows/release.yml in doctown-builder:
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
Phase 2: Rust Builder Implementation
2.1 Update Cargo.toml Dependencies
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
2.2 Module Structure
Create the following files in src/:
src/main.rs - CLI entry point, orchestrates pipeline
src/parser.rs - Tree-sitter integration, Rust file parsing
src/extractor.rs - AST traversal, symbol extraction (rich format)
src/batcher.rs - Token counting, batching symbols for LLM
src/generator.rs - OpenAI integration, parallel batch processing
src/packager.rs - ZIP creation with docpack structure
src/uploader.rs - HTTP client for website API
src/models.rs - Shared types (Symbol, Docpack, Manifest)
2.3 Implementation Details
src/main.rs
use clap::Parser;
use anyhow::Result;

#[derive(Parser)]
#[command(name = "doctown")]
#[command(about = "Generate .docpack documentation from Rust codebases")]
struct Cli {
    /// Path to the repository to document
    #[arg(short, long, default_value = ".")]
    repo_path: String,

    /// API endpoint for doctown backend
    #[arg(short, long)]
    api_url: String,

    /// OIDC token for authentication
    #[arg(short, long)]
    token: String,

    /// Job ID from doctown
    #[arg(short, long)]
    job_id: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    println!("🔍 Parsing Rust files...");
    let symbols = parser::parse_repository(&cli.repo_path)?;
    
    println!("📊 Extracted {} symbols", symbols.len());
    
    println!("📦 Batching symbols for LLM...");
    let batches = batcher::create_batches(&symbols, 16000)?;
    
    println!("🤖 Generating documentation ({} batches)...", batches.len());
    let docs = generator::generate_docs(batches).await?;
    
    println!("📄 Creating .docpack...");
    let docpack_path = packager::create_docpack(&symbols, &docs, &cli.job_id)?;
    
    println!("☁️ Uploading to doctown...");
    uploader::upload_docpack(&cli.api_url, &cli.token, &cli.job_id, &docpack_path).await?;
    
    println!("✅ Docpack generated successfully!");
    Ok(())
}
src/parser.rs
Use tree-sitter with tree-sitter-rust
Walk repo with walkdir, filter *.rs files
Parse each file, extract AST nodes
Return Vec<RawNode> for processing
src/extractor.rs
Convert tree-sitter nodes to rich Symbol structs
Extract: name, type, visibility, signature, params, return type, doc comments, attributes, file path, line number
Handle: functions, structs, enums, traits, impls, consts
Filter: only pub items by default (configurable later)
src/batcher.rs
Estimate token count per symbol (rough: symbol_json.len() / 4)
Group symbols into batches under 16k tokens
Each batch: { symbols: [Symbol], batch_id: usize }
Return Vec<Batch>
src/generator.rs
Use existing llm crate for OpenAI integration
Process batches in parallel (tokio tasks)
For each batch: send all symbols as JSON context
Prompt: "Generate documentation for these symbols following the docpack spec"
Use structured output (JSON mode) to match docpack schema
Collect results into HashMap<symbol_id, Doc>
src/packager.rs
Create temp directory
Write manifest.json (repo info, timestamp, version)
Write symbols.json (array of all symbols)
Write docs/ folder with {symbol_id}.json per symbol
Optionally include source/ (skip for MVP)
Zip everything into {job_id}.docpack
Return path to ZIP file
src/uploader.rs
Create multipart form with ZIP file
POST to {api_url}/api/docpack/upload
Headers: Authorization: Bearer {token}
Body: { job_id, file: <binary> }
Handle errors, retry once on failure
src/models.rs
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub id: String,
    pub name: String,
    pub symbol_type: String, // "function" | "struct" | "enum" | ...
    pub visibility: String,  // "pub" | "pub(crate)" | ...
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
Phase 3: GitHub Action Workflow
3.1 Create Action Template
File: .github/workflows/doctown.yml (users will install this in their repos)
name: Generate Docpack

on:
  workflow_dispatch:
    inputs:
      job_id:
        description: 'Doctown job ID'
        required: true
      api_url:
        description: 'Doctown API URL'
        required: true
        default: 'https://doctown.dev'

permissions:
  contents: read
  id-token: write  # For OIDC token

jobs:
  generate:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Download doctown builder
        run: |
          curl -L https://github.com/yourusername/doctown-builder/releases/latest/download/doctown-linux-x64 -o doctown
          chmod +x doctown

      - name: Get OIDC token
        id: oidc
        run: |
          TOKEN=$(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=doctown" | jq -r .value)
          echo "token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Generate docpack
        env:
          OPENAI_API_KEY: ${{ secrets.DOCTOWN_OPENAI_KEY }}
        run: |
          ./doctown \
            --repo-path . \
            --api-url ${{ inputs.api_url }} \
            --token ${{ steps.oidc.outputs.token }} \
            --job-id ${{ inputs.job_id }}

      - name: Notify completion
        if: always()
        run: |
          curl -X POST ${{ inputs.api_url }}/api/docpack/complete \
            -H "Authorization: Bearer ${{ steps.oidc.outputs.token }}" \
            -H "Content-Type: application/json" \
            -d '{"job_id": "${{ inputs.job_id }}", "status": "${{ job.status }}"}'
Phase 4: Website API Endpoints
4.1 Create API Routes in SvelteKit
Create these files in website/src/routes/api/:
api/docpack/create/+server.ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ request, locals }) => {
  const session = locals.session;
  if (!session) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { repo_owner, repo_name, branch = 'main' } = await request.json();

  // Generate job ID
  const job_id = crypto.randomUUID();

  // Dispatch GitHub Action
  const dispatch_url = `https://api.github.com/repos/${repo_owner}/${repo_name}/actions/workflows/doctown.yml/dispatches`;
  
  const response = await fetch(dispatch_url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${session.github_token}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
    body: JSON.stringify({
      ref: branch,
      inputs: {
        job_id: job_id,
        api_url: process.env.NODE_ENV === 'production' 
          ? 'https://doctown.dev' 
          : 'http://localhost:5173'
      }
    })
  });

  if (!response.ok) {
    return json({ error: 'Failed to dispatch action' }, { status: 500 });
  }

  // Store job in database/session (for now, in-memory)
  // TODO: Add proper database later

  return json({ job_id, status: 'pending' });
};
api/docpack/upload/+server.ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

const s3 = new S3Client({
  region: 'auto',
  endpoint: 'https://<account_id>.r2.cloudflarestorage.com',
  credentials: {
    accessKeyId: process.env.BUCKET_ACCESS_KEY_ID!,
    secretAccessKey: process.env.BUCKET_SECRET!,
  },
});

export const POST: RequestHandler = async ({ request }) => {
  // Verify OIDC token from GitHub Actions
  const auth = request.headers.get('authorization');
  if (!auth?.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const token = auth.slice(7);
  // TODO: Verify OIDC token signature
  
  const formData = await request.formData();
  const job_id = formData.get('job_id') as string;
  const file = formData.get('file') as File;

  if (!job_id || !file) {
    return json({ error: 'Missing job_id or file' }, { status: 400 });
  }

  // Upload to R2
  const buffer = Buffer.from(await file.arrayBuffer());
  await s3.send(new PutObjectCommand({
    Bucket: 'doctown-central',
    Key: `docpacks/${job_id}.docpack`,
    Body: buffer,
    ContentType: 'application/zip',
  }));

  return json({ success: true });
};
api/docpack/complete/+server.ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ request }) => {
  const auth = request.headers.get('authorization');
  if (!auth?.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { job_id, status } = await request.json();

  // Update job status in database
  // TODO: Add proper database later
  
  console.log(`Job ${job_id} completed with status: ${status}`);

  return json({ success: true });
};
4.2 Update Dashboard UI
Modify website/src/routes/dashboard/+page.svelte: Change the "Create Docpack" button handler to call the API:
async function createDocpack(repo: GitHubRepo) {
  const response = await fetch('/api/docpack/create', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      repo_owner: repo.owner.login,
      repo_name: repo.name,
      branch: repo.default_branch,
    }),
  });

  const { job_id } = await response.json();
  
  // Add to local state (will be replaced with DB later)
  docpacks.push({
    id: job_id,
    repository: repo.full_name,
    status: 'pending',
    createdAt: new Date().toISOString(),
  });
}
Phase 5: GitHub App Setup
5.1 Convert to GitHub App
Go to GitHub Settings → Developer settings → GitHub Apps
Create new GitHub App: "Doctown"
Permissions:
Repository: Contents (read)
Repository: Actions (write)
Repository: Metadata (read)
Webhook: Enable, point to https://doctown.dev/api/webhook
Device Flow: Enable
OAuth: Enable with callback https://doctown.dev/auth/callback
5.2 Update Auth Flow in Website
Replace GitHub OAuth with GitHub App flow:
Update website/src/routes/auth/+server.ts to use device flow
Store installation ID and access token
Use GitHub App JWT for API calls
Phase 6: Testing & Deployment
6.1 Local Testing Setup
Run website: cd website && npm run dev
Use ngrok for webhook testing: ngrok http 5173
Update GitHub App webhook URL to ngrok URL
Test full flow with doctown-builder as test repo
6.2 Deployment
Builder:
Push to doctown-builder repo
Create GitHub release (v0.1.0)
Binary auto-builds and attaches to release
Website:
Push to doctown repo
Connect to Vercel
Add environment variables (GitHub App secrets, R2 credentials, OpenAI key)
Deploy to doctown.dev
6.3 Self-Documentation Test
Install doctown action in doctown-builder repo
Click "Create Docpack" on doctown.dev for doctown-builder
Action runs, parses itself
Generates docpack, uploads to R2
View in commons on doctown.dev
MVP Success Criteria
✅ User authenticates with GitHub App (device flow)
✅ User selects a Rust repo and clicks "Create Docpack"
✅ Website dispatches GitHub Action with OIDC token
✅ Action downloads pre-compiled binary
✅ Binary parses Rust files with tree-sitter
✅ Binary extracts rich symbols (name, signature, docs, etc.)
✅ Binary batches symbols (16k token limit)
✅ Binary sends batches to OpenAI in parallel
✅ Binary creates .docpack ZIP
✅ Binary uploads to website API
✅ Website uploads to R2 bucket
✅ Docpack appears in commons