-- Migration: Add branch tracking to docpacks
-- Date: 2024-11-18
-- Description: Adds fields for tracking which branch a docpack follows,
--              the commit it was built from, and freeze toggle for auto-updates.

-- Add new columns to docpacks table
ALTER TABLE docpacks ADD COLUMN IF NOT EXISTS tracked_branch TEXT;
ALTER TABLE docpacks ADD COLUMN IF NOT EXISTS frozen BOOLEAN DEFAULT FALSE;

-- Note: commit_hash already exists but wasn't being populated
-- Note: full_name already exists (repo full name like "owner/repo")

-- Create index for efficient branch lookups
CREATE INDEX IF NOT EXISTS idx_docpacks_tracked_branch ON docpacks(tracked_branch);
CREATE INDEX IF NOT EXISTS idx_docpacks_full_name ON docpacks(full_name);

-- Create repo_branches table for tracking branch state (for future auto-update detection)
CREATE TABLE IF NOT EXISTS repo_branches (
    repo_full_name TEXT NOT NULL,
    branch TEXT NOT NULL,
    last_seen_commit TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (repo_full_name, branch)
);

-- Enable RLS on repo_branches
ALTER TABLE repo_branches ENABLE ROW LEVEL SECURITY;

-- Create trigger for repo_branches updated_at
CREATE TRIGGER update_repo_branches_updated_at BEFORE UPDATE ON repo_branches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comment explaining the purpose
COMMENT ON TABLE repo_branches IS 'Tracks the latest known commit for each branch of connected repos. Used for detecting changes and triggering auto-updates.';
COMMENT ON COLUMN docpacks.tracked_branch IS 'The branch this docpack is tracking for updates';
COMMENT ON COLUMN docpacks.frozen IS 'When true, auto-updates are disabled for this docpack';
