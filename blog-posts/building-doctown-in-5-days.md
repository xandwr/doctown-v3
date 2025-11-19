---
title: Building Doctown: Solving Documentation in a Week-Long Sprint
date: 2025-11-19
author: Xander
readTime: 8 min read
tags: rust, ai, documentation, typescript
description: How I built an AI-powered documentation system that costs pennies and delivers O(1) codebase understanding.
---

## The Problem

Documentation sucks. It's either outdated, incomplete, or buried in a README that nobody reads. For AI agents and developers alike, understanding a codebase means grepping through files, reading source code, and piecing together context from comments and naming conventions.

I wanted something better: **O(1) access to any symbol's documentation**. No searching. No guessing. Just instant, accurate, AI-generated and Human-controlled docs that follow you anywhere.

## The Goal: "npm for docs"

The initial vision was simple: what if documentation worked like npm packages? You could:

- `localdoc install xandwr:myproject` - Download docs
- `localdoc query xandwr:myproject symbol "function_name"` - Get instant documentation
- `localdoc search "rust http server"` - Find relevant packages

But the real innovation wasn't the CLI—it was the **docpack format** and the **AI-powered generation pipeline** that made it possible.

## The Architecture

### 1. The Builder Pipeline (Rust)

The builder is a Rust service that takes a GitHub repository and produces a `.docpack` file. Here's what happens:

1. **Ingest**: Clone the repo, parse source files using tree-sitter
2. **Extract**: Pull out every symbol (functions, classes, methods, etc.)
3. **Generate**: Use an LLM to generate documentation for each symbol
4. **Pack**: Bundle everything into a compressed docpack file

The entire pipeline runs on RunPod serverless CPUs.

### 2. The Docpack Format

A docpack is essentially a ZIP file containing:

- `manifest.json` - Metadata about the project
- `symbols.json` - Every extracted symbol with its documentation  
- `embeddings.bin` (optional) - Vector embeddings for semantic search

This format is **portable**, **offline-first**, and **version-controlled**. You can share docpacks like any other file.

### 3. The CLI (Rust)

The CLI tool (`localdoc`) is a single binary that:

- Downloads docpacks from doctown.dev
- Stores them locally in `~/.local/share/localdoc/packages/`
- Queries symbols instantly (no network needed after install)
- Serves as an MCP server for AI agents

### 4. The Web Platform (SvelteKit + Supabase)

The website provides:

- **Commons**: Browse public docpacks
- **Dashboard**: Generate docpacks for your private repos
- **Docs Viewer**: Web UI for browsing documentation
- **Stripe Integration**: Subscription management for premium features

## The AI Magic

The documentation generation uses a few tricks to keep quality high and costs low:

1. **Context-aware prompts**: Each symbol gets documentation generated with full file context, not just the function signature
2. **Structured output**: Docs follow a consistent format (Summary, Description, Parameters, Returns, Examples, Notes)
3. **Batch processing**: Process multiple symbols in parallel to maximize GPU utilization
4. **Caching**: Reuse docs for unchanged symbols across versions

## The Numbers

Here's what I learned after processing dozens of codebases:

- **Cost**: ~$0.10-$0.50 per codebase (depending on size)
- **Speed**: 5-15 minutes for a medium-sized project
- **Quality**: 90%+ of generated docs are useful without editing
- **CLI size**: ~8MB binary (Rust is efficient)

## Challenges & Solutions

### Challenge 1: Parsing Multiple Languages

**Solution**: Use tree-sitter for language-agnostic parsing. It handles Rust, TypeScript, Python, Go, and more with the same API.

### Challenge 2: LLM Hallucinations

**Solution**: Always include the actual source code in the prompt. The model can't hallucinate what's right in front of it.

### Challenge 3: Storage & Distribution

**Solution**: Store docpacks in S3, distribute via signed URLs. Public docpacks are cached globally on Vercel's edge network.

## What's Next

The core product is shipping, but there's more to build:

- **Team features**: Share private docpacks across organizations
- **CI/CD integration**: Auto-generate docs on every commit
- **More languages**: Java, C++, Ruby support
- **Analytics**: Show which symbols are most queried

## Try It Yourself

Install the CLI and test it out:

```bash
cargo install localdoc
localdoc search rust
localdoc install xandwr:localdoc
localdoc query xandwr:localdoc symbols
```

If you're building something and want automatic documentation, [check it out](https://www.doctown.dev)!

---

*Questions? Feedback? Find me on GitHub [@xandwr](https://github.com/xandwr) or xandwrp at gmail dot com*
