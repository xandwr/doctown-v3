-- Doctown v3 Database Schema

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  github_id BIGINT UNIQUE NOT NULL,
  github_login TEXT NOT NULL,
  email TEXT UNIQUE,
  name TEXT,
  avatar_url TEXT,
  html_url TEXT,
  access_token TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sessions table
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_token TEXT UNIQUE NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Jobs table
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repo TEXT NOT NULL,
  git_ref TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'building', 'completed', 'failed')),
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Docpacks table
CREATE TABLE docpacks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  description TEXT,
  file_url TEXT NOT NULL,
  public BOOLEAN DEFAULT FALSE,
  repo_url TEXT NOT NULL,
  commit_hash TEXT,
  version TEXT,
  language TEXT,
  tracked_branch TEXT,
  frozen BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Repo branches table (for tracking branch state and auto-updates)
CREATE TABLE repo_branches (
  repo_full_name TEXT NOT NULL,
  branch TEXT NOT NULL,
  last_seen_commit TEXT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  PRIMARY KEY (repo_full_name, branch)
);

-- GitHub installations table
CREATE TABLE github_installations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repo_full_name TEXT NOT NULL,
  installation_id BIGINT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, repo_full_name)
);

-- Subscriptions table
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stripe_customer_id TEXT UNIQUE NOT NULL,
  stripe_subscription_id TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'canceled', 'past_due', 'incomplete', 'trialing')),
  current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
  current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Indexes for better query performance
CREATE INDEX idx_sessions_token ON sessions(session_token);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX idx_users_github_id ON users(github_id);
CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_docpacks_job_id ON docpacks(job_id);
CREATE INDEX idx_docpacks_public ON docpacks(public);
CREATE INDEX idx_docpacks_tracked_branch ON docpacks(tracked_branch);
CREATE INDEX idx_docpacks_full_name ON docpacks(full_name);
CREATE INDEX idx_github_installations_user_id ON github_installations(user_id);
CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to auto-update updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sessions_updated_at BEFORE UPDATE ON sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_jobs_updated_at BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_docpacks_updated_at BEFORE UPDATE ON docpacks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_github_installations_updated_at BEFORE UPDATE ON github_installations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_repo_branches_updated_at BEFORE UPDATE ON repo_branches
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE docpacks ENABLE ROW LEVEL SECURITY;
ALTER TABLE github_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE repo_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies (for service role, all access is allowed by default)
-- These policies would apply if using anon or authenticated roles

-- Public docpacks can be read by anyone
CREATE POLICY "Public docpacks are viewable by everyone" ON docpacks
  FOR SELECT USING (public = TRUE);

-- Users can read their own data
CREATE POLICY "Users can view their own data" ON users
  FOR SELECT USING (auth.uid()::text = id::text);

CREATE POLICY "Users can view their own sessions" ON sessions
  FOR SELECT USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can view their own jobs" ON jobs
  FOR SELECT USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can view their own docpacks" ON docpacks
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM jobs WHERE jobs.id = docpacks.job_id AND jobs.user_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can view their own installations" ON github_installations
  FOR SELECT USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can view their own subscription" ON subscriptions
  FOR SELECT USING (auth.uid()::text = user_id::text);

-- JOB LOGS
CREATE TABLE IF NOT EXISTS job_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  level TEXT NOT NULL DEFAULT 'info',
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE INDEX IF NOT EXISTS idx_job_logs_job_id ON job_logs(job_id, timestamp DESC);

ALTER TABLE job_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own job logs" ON job_logs
  FOR SELECT
  USING (
    job_id IN (
      SELECT id FROM jobs WHERE user_id = auth.uid()
    )
  );

-- Add support for user edits to docpack symbols and documentation

-- Symbol edits table: stores user modifications to symbol entries and docs
CREATE TABLE symbol_edits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  docpack_id UUID NOT NULL REFERENCES docpacks(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  symbol_id TEXT NOT NULL, -- The symbol ID from symbols.json
  
  -- Edited fields from symbol entry
  signature TEXT,
  kind TEXT,
  
  -- Edited fields from documentation
  summary TEXT,
  description TEXT,
  parameters JSONB, -- Array of {name, type, description}
  returns TEXT,
  example TEXT,
  notes JSONB, -- Array of strings
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Ensure one edit per user per symbol per docpack
  UNIQUE(docpack_id, user_id, symbol_id)
);

-- Indexes for performance
CREATE INDEX idx_symbol_edits_docpack_id ON symbol_edits(docpack_id);
CREATE INDEX idx_symbol_edits_user_id ON symbol_edits(user_id);
CREATE INDEX idx_symbol_edits_lookup ON symbol_edits(docpack_id, user_id, symbol_id);

-- Trigger to auto-update updated_at
CREATE TRIGGER update_symbol_edits_updated_at BEFORE UPDATE ON symbol_edits
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add RLS (Row Level Security) policies
ALTER TABLE symbol_edits ENABLE ROW LEVEL SECURITY;

-- Users can only read their own edits
CREATE POLICY "Users can read their own symbol edits"
  ON symbol_edits FOR SELECT
  USING (auth.uid() = user_id);

-- Users can only insert their own edits
CREATE POLICY "Users can insert their own symbol edits"
  ON symbol_edits FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can only update their own edits
CREATE POLICY "Users can update their own symbol edits"
  ON symbol_edits FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can only delete their own edits
CREATE POLICY "Users can delete their own symbol edits"
  ON symbol_edits FOR DELETE
  USING (auth.uid() = user_id);

-- Add role column with default value 'user'
ALTER TABLE users
ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user'
CHECK (role IN ('user', 'admin'));

-- Update your admin user (replace with your actual github_login if different)
UPDATE users
SET role = 'admin'
WHERE github_login = 'xandwr';

-- Verify the migration
SELECT github_login, role FROM users;

-- Grant permissions to service_role (bypasses RLS)
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant permissions to anon and authenticated for RLS-controlled access
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;

-- Blog posts table
CREATE TABLE blog_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  author TEXT NOT NULL DEFAULT 'Xander',
  read_time TEXT NOT NULL DEFAULT '5 min',
  tags TEXT[] DEFAULT '{}',
  description TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  cover_image TEXT,
  published BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for published posts
CREATE INDEX idx_blog_posts_published ON blog_posts(published, date DESC);
CREATE INDEX idx_blog_posts_slug ON blog_posts(slug);

-- Trigger to auto-update updated_at
CREATE TRIGGER update_blog_posts_updated_at BEFORE UPDATE ON blog_posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE blog_posts ENABLE ROW LEVEL SECURITY;

-- Anyone can read published blog posts
CREATE POLICY "Published blog posts are viewable by everyone" ON blog_posts
  FOR SELECT USING (published = TRUE);

-- Grant full access to service_role for blog_posts (bypasses RLS)
GRANT ALL ON blog_posts TO service_role;