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

**Builder** Rust service that accepts code repositories, parses them with tree-sitter, sends symbols to OpenAI, generates documentation, packages everything into `.docpack` files.

**Localdoc** Rust CLI for reading docpacks. Works offline. Full-text search. Symbol lookup. Instant.

**Website** SvelteKit dashboard for creators. Connect GitHub repos. Generate docpacks. Publish to the Commons. Track builds in realtime.

## The model

Consumption is free. Creation is paid.

Readers don't pay. Creators pay $10/month for compute tokens. They generate docpacks, publish them to the Commons, and anyone can download them. Forever. No login. No tracking.

The Commons is the public registry. Like npm, but for documentation. You can search it. Download anything. Use it however you want.

Documentation becomes a dependency. You install it once. It works forever.

## Stack

- **Builder**: Rust, tree-sitter, OpenAI API, Docker, RunPod
- **Localdoc**: Rust, ZIP archive parsing
- **Website**: SvelteKit, TypeScript, Tailwind, Supabase, S3/R2

Supports Rust, Python, JavaScript, TypeScript. More languages will come.

## Philosophy

Most documentation platforms charge readers. They put docs behind paywalls, analytics, and CDNs. They make you search the same thing twice because they forgot what you asked. They go down. They change URLs. They delete your content.

Doctown doesn't do that.

Documentation here is a file. You download it. You keep it. It doesn't change unless you want it to. It doesn't phone home. It doesn't track you. It just exists.

Creators pay because generation costs money. Readers don't pay because reading shouldn't. The split is clean.

## Getting started

Visit the Commons. Find a docpack. Download it. Install `localdoc`. Run it.

Or create your own. Connect your GitHub. The system will handle the rest. The build logs stream in realtime. When it finishes, you get a `.docpack` file. You can publish it or keep it private.

Everything works locally. The web interface is optional. The CLI is permanent.

---

Documentation shouldn't require permission to read. It should just be there, waiting. Like it always was.

Welcome to Doctown.
