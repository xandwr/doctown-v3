#!/bin/bash

# This script commits and pushes changes to both builder/ and website/ submodules
# Usage: ./commit_all.sh -m "your commit message"

# Parse command line arguments
while getopts "m:" opt; do
  case $opt in
    m)
      COMMIT_MESSAGE="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 -m \"commit message\""
      exit 1
      ;;
  esac
done

# Check if commit message was provided
if [ -z "$COMMIT_MESSAGE" ]; then
  echo "Error: Commit message is required"
  echo "Usage: $0 -m \"commit message\""
  exit 1
fi

# Array of directories to process (including repo root)
DIRS=("." "builder" "website")

# Function to commit and push in a directory
commit_and_push() {
  local dir=$1
  local message=$2

  echo "================================================"
  echo "Processing: $dir"
  echo "================================================"

  if [ ! -d "$dir" ]; then
    echo "Warning: Directory $dir does not exist, skipping..."
    return 1
  fi

  cd "$dir" || exit 1

  # Check if there are any changes
  if git diff-index --quiet HEAD --; then
    echo "No changes in $dir, skipping..."
  else
    echo "Committing changes in $dir..."
    git add .
    git commit -m "$message"

    echo "Pushing changes in $dir..."
    git push

    if [ $? -eq 0 ]; then
      echo "Successfully pushed $dir"
    else
      echo "Error: Failed to push $dir"
      cd ..
      exit 1
    fi
  fi

  cd ..
}

# Process each directory
for dir in "${DIRS[@]}"; do
  commit_and_push "$dir" "$COMMIT_MESSAGE"
done

echo ""
echo "================================================"
echo "All repositories processed successfully!"
echo "================================================"
