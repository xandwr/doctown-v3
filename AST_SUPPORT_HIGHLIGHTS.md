# AST Support Visual Highlights

This document explains the visual highlighting system for repositories with AST support on the Doctown website.

## Overview

The website now visually differentiates repositories based on whether they have full AST (Abstract Syntax Tree) support. Repos with AST support are highlighted with badges and full color, while unsupported languages are grayed out to indicate limited documentation capabilities.

## Supported Languages

Based on `builder/src/pipeline/ingest.rs`, the following languages have **full AST support** via tree-sitter:

- **Rust** (.rs)
- **Python** (.py)
- **JavaScript** (.js)
- **TypeScript** (.ts, .tsx)
- **Go** (.go)
- **Java** (.java)
- **C** (.c, .h)
- **C++** (.cpp, .cc, .cxx, .hpp)
- **Ruby** (.rb)
- **C#** (.cs)
- **PHP** (.php)
- **Swift** (.swift)
- **Scala** (.scala)
- **Shell/Bash** (.sh, .bash)
