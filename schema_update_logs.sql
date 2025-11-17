-- Add logs table for storing build logs
CREATE TABLE IF NOT EXISTS job_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  level TEXT NOT NULL DEFAULT 'info', -- 'info', 'warning', 'error', 'debug'
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient querying by job_id
CREATE INDEX IF NOT EXISTS idx_job_logs_job_id ON job_logs(job_id, timestamp DESC);

-- Enable Row Level Security
ALTER TABLE job_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read logs for their own jobs
CREATE POLICY "Users can read their own job logs" ON job_logs
  FOR SELECT
  USING (
    job_id IN (
      SELECT id FROM jobs WHERE user_id = auth.uid()
    )
  );
