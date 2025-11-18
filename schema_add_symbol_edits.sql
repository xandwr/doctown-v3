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
