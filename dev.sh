#!/bin/bash

# This script sets up and runs the local development environment
# Usage: ./dev.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "Doctown Local Development Setup"
echo "================================================"
echo ""

# Check if .env file exists in website/
if [ ! -f "$SCRIPT_DIR/website/.env" ]; then
  echo "⚠️  Warning: website/.env file not found!"
  echo ""
  echo "Please create website/.env with your local configuration:"
  echo "  - GitHub OAuth credentials (doctown-dev app)"
  echo "  - Supabase keys"
  echo "  - RunPod credentials"
  echo "  - R2 bucket credentials"
  echo ""
  echo "See website/.env.example for reference"
  echo ""
  read -p "Press Enter to continue anyway, or Ctrl+C to exit..."
fi

# Navigate to website directory
cd "$SCRIPT_DIR/website" || exit 1

echo ""
echo "📦 Installing dependencies..."
npm install

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ Error: Failed to install dependencies"
  exit 1
fi

echo ""
echo "✅ Dependencies installed"
echo ""
echo "🚀 Starting development server..."
echo ""
echo "   Local:   http://localhost:5173"
echo "   Network: Use the network address shown below"
echo ""
echo "================================================"
echo ""

# Start the dev server
npm run dev
