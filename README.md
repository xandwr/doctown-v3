# Doctown

Documentation doesn't need to live somewhere else. It can stay with you.

Doctown generates portable documentation packages from your source code. You connect a repository. The system extracts every function, every struct, every class. AI writes documentation for each one. Everything gets compressed into a single `.docpack` file. You can open it locally. Search it. Read it. No internet required.

The documentation stays where you put it. It doesn't expire. It doesn't move to a different URL. It doesn't require a subscription to read.

## What it does

```bash
# Install the CLI
cargo install localdoc

# Inspect any docpack
localdoc inspect project.docpack

# Search documentation offline
localdoc search "authentication" project.docpack

# No network required. No tracking.
```

Three parts. They work together but they don't need to.

**Builder** – Rust service that accepts code repositories, parses them with tree-sitter, sends symbols to OpenAI, generates documentation, packages everything into `.docpack` files.

**Localdoc** – Rust CLI for reading docpacks. Works offline. Full-text search. Symbol lookup. Instant.

**Website** – SvelteKit dashboard for creators. Connect GitHub repos. Generate docpacks. Publish to the Commons. Track builds in realtime.

## The model

Consumption is free. Creation is paid.

Readers don't pay. Creators pay $10/month for compute tokens. They generate docpacks, publish them to the Commons, and anyone can download them. Forever. No login. No tracking.

The Commons is the public registry. Like npm, but for documentation. You can search it. Download anything. Use it however you want.

Documentation becomes a dependency. You install it once. It works forever.

## Stack

- **Builder**: Rust, tree-sitter, OpenAI API, Docker, RunPod
- **Localdoc**: Rust, ZIP archive parsing
- **Website**: SvelteKit, TypeScript, Tailwind, Supabase, Cloudflare R2

Supports Rust, Python, JavaScript, TypeScript. More languages will come.

## Philosophy

Most documentation platforms charge readers. They put docs behind paywalls, analytics, and CDNs. They make you search the same thing twice because they forgot what you asked. They go down. They change URLs. They delete your content.

Doctown doesn't do that.

Documentation here is a file. You download it. You keep it. It doesn't change unless you want it to. It doesn't phone home. It doesn't track you. It just exists.

Creators pay because generation costs money. Readers don't pay because reading shouldn't. The split is clean.

## Project structure

```
doctown-v3/
├── builder/          # Rust documentation generation pipeline
├── localdoc/         # Rust CLI for reading docpacks
├── website/          # SvelteKit web dashboard
└── scripts/          # Utility scripts for maintenance
```

### Builder

The builder is a complete documentation generation pipeline. It extracts symbols from source code using tree-sitter, generates AI-powered documentation via OpenAI API, and packages everything into portable `.docpack` files.

**Key features:**
- Symbol extraction from Rust, Python, JavaScript, TypeScript
- Parallel AI documentation generation
- Structured output in `.docpack` format (ZIP archive)
- Docker deployment ready for RunPod

See [`builder/README.md`](builder/README.md) for detailed usage and API documentation.

### Localdoc

A fast, offline CLI tool for querying docpack files. No network required. Instant full-text search across all documentation.

**Commands:**
- `inspect` – View docpack metadata and stats
- `query symbols` – List all symbols in the codebase
- `query symbol <name>` – Get detailed documentation for a specific symbol
- `query search <keyword>` – Full-text search across all documentation
- `query files` – List source files with symbol counts

See [`localdoc/README.md`](localdoc/README.md) and [`localdoc/EXAMPLES.md`](localdoc/EXAMPLES.md) for examples.

### Website

SvelteKit web application providing:
- GitHub OAuth integration for repository access
- Job creation and build status tracking with real-time streaming
- Public Commons for browsing and downloading docpacks
- Stripe subscription management ($10/month for unlimited builds)
- Manual editing of AI-generated documentation
- Docpack privacy controls (public/private)

## Getting started

### For readers

1. Visit the Commons at [doctown.dev](https://www.doctown.dev)
2. Find a docpack you need
3. Download it
4. Install localdoc: `cargo install localdoc`
5. Query it: `localdoc inspect your-docpack.docpack`

No account required. No tracking. The docpack is yours forever.

### For creators

1. Visit [doctown.dev](https://www.doctown.dev)
2. Sign in with GitHub
3. Subscribe ($10/month) for unlimited docpack generation
4. Connect a repository
5. Watch the build stream in realtime
6. Download or publish to the Commons

Your docpacks can be private or public. You choose.

## Development setup

See [`SETUP.md`](SETUP.md) for:
- Environment configuration
- Stripe integration setup
- GitHub OAuth callbacks
- RunPod deployment
- Supabase schema setup

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for:
- Docpack format specification
- Feature documentation and architecture
- Database schema details
- Automated cleanup systems

## Features

- **Portable documentation** – Single `.docpack` file contains everything
- **Offline-first** – No internet required to read documentation
- **AI-generated** – Comprehensive docs for every symbol
- **Manual editing** – Full control to refine AI-generated content
- **Full-text search** – Instant search across all documentation
- **Privacy controls** – Public or private docpacks
- **Real-time builds** – Watch your documentation generate live
- **Storage optimization** – Automated cleanup of orphaned files
- **Open source** – MIT licensed

## Docpack format

A `.docpack` is a ZIP archive containing:

```
project.docpack/
├── manifest.json       # Metadata, stats, privacy settings
├── symbols.json        # Extracted code structure
└── docs/
    ├── doc_0000.json   # AI-generated documentation
    ├── doc_0001.json
    └── ...
```

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the complete format specification.

---

Documentation shouldn't require permission to read. It should just be there, waiting. Like it always was.

Welcome to Doctown.
