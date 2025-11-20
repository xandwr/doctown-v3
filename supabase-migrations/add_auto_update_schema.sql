-- Migration: Add Auto-Update Schema for Incremental Documentation Builds
-- This migration adds tables and columns to support automatic incremental
-- documentation generation when git commits are pushed.

-- Add auto-update fields to docpacks table
ALTER TABLE docpacks
ADD COLUMN IF NOT EXISTS auto_update_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS parent_docpack_id UUID REFERENCES docpacks(id),
ADD COLUMN IF NOT EXISTS previous_commit_hash TEXT;

-- Create auto_update_log table to track incremental build history
CREATE TABLE IF NOT EXISTS auto_update_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  docpack_id UUID NOT NULL REFERENCES docpacks(id) ON DELETE CASCADE,
  previous_commit TEXT NOT NULL,
  new_commit TEXT NOT NULL,
  symbols_unchanged INTEGER NOT NULL DEFAULT 0,
  symbols_modified INTEGER NOT NULL DEFAULT 0,
  symbols_added INTEGER NOT NULL DEFAULT 0,
  symbols_removed INTEGER NOT NULL DEFAULT 0,
  docs_generated INTEGER NOT NULL DEFAULT 0,
  docs_reused INTEGER NOT NULL DEFAULT 0,
  cache_hit_rate REAL NOT NULL DEFAULT 0.0,
  build_duration_ms INTEGER,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'building', 'completed', 'failed')),
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for auto_update_log
CREATE INDEX IF NOT EXISTS idx_auto_update_log_docpack_id ON auto_update_log(docpack_id);
CREATE INDEX IF NOT EXISTS idx_auto_update_log_status ON auto_update_log(status);
CREATE INDEX IF NOT EXISTS idx_auto_update_log_created_at ON auto_update_log(created_at DESC);

-- Add indexes for new docpack columns
CREATE INDEX IF NOT EXISTS idx_docpacks_auto_update_enabled ON docpacks(auto_update_enabled) WHERE auto_update_enabled = TRUE;
CREATE INDEX IF NOT EXISTS idx_docpacks_parent ON docpacks(parent_docpack_id);

-- Trigger to auto-update updated_at for auto_update_log
CREATE TRIGGER update_auto_update_log_updated_at BEFORE UPDATE ON auto_update_log
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS on auto_update_log
ALTER TABLE auto_update_log ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can read auto-update logs for their own docpacks
CREATE POLICY "Users can read their own auto-update logs" ON auto_update_log
  FOR SELECT
  USING (
    docpack_id IN (
      SELECT docpacks.id
      FROM docpacks
      JOIN jobs ON jobs.id = docpacks.job_id
      WHERE jobs.user_id = auth.uid()
    )
  );

-- Grant permissions to service_role (bypasses RLS)
GRANT ALL ON auto_update_log TO service_role;
GRANT SELECT ON auto_update_log TO anon, authenticated;

-- Comments for documentation
COMMENT ON TABLE auto_update_log IS 'Tracks incremental build history for auto-updated docpacks';
COMMENT ON COLUMN docpacks.auto_update_enabled IS 'Whether this docpack should be automatically updated on new commits';
COMMENT ON COLUMN docpacks.parent_docpack_id IS 'Reference to the previous version of this docpack (for versioning)';
COMMENT ON COLUMN docpacks.previous_commit_hash IS 'Git commit hash that this docpack was built from (for diff computation)';
COMMENT ON COLUMN auto_update_log.cache_hit_rate IS 'Percentage (0.0-1.0) of symbols that reused existing documentation';
COMMENT ON COLUMN auto_update_log.build_duration_ms IS 'Time taken for the incremental build in milliseconds';
