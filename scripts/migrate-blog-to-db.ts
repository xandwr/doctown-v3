#!/usr/bin/env node
/**
 * Migrate existing blog posts from markdown files to the database
 *
 * Usage:
 *   npx ts-node scripts/migrate-blog-to-db.ts
 *
 * Requires SUPABASE_URL and SUPABASE_SECRET_KEY env vars
 */

import { createClient } from '@supabase/supabase-js';
import fsPromises from 'fs/promises';
import path from 'path';

interface BlogMetadata {
  [key: string]: string;
}

interface BlogPost {
  slug: string;
  title: string;
  date: string;
  author: string;
  read_time: string;
  tags: string[];
  description: string;
  content: string;
  cover_image?: string;
}

async function parseBlogPost(filePath: string): Promise<BlogPost> {
  const content = await fsPromises.readFile(filePath, 'utf-8');
  const slug = path.basename(filePath, '.md');

  // Extract frontmatter
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);

  if (!frontmatterMatch) {
    throw new Error(`No frontmatter found in ${filePath}`);
  }

  const [, frontmatter, markdown] = frontmatterMatch;
  const metadata: BlogMetadata = {};

  frontmatter.split('\n').forEach((line) => {
    const [key, ...valueParts] = line.split(':');
    if (key && valueParts.length) {
      const value = valueParts.join(':').trim();
      metadata[key.trim()] = value.replace(/^['"]|['"]$/g, '');
    }
  });

  return {
    slug,
    title: metadata.title || slug,
    date: metadata.date || new Date().toISOString().split('T')[0],
    author: metadata.author || 'Xander',
    read_time: metadata.readTime?.replace(' read', '') || '5 min',
    tags: metadata.tags ? metadata.tags.split(',').map(t => t.trim()) : [],
    description: metadata.description || '',
    content: markdown.trim(),
    cover_image: metadata.coverImage
  };
}

async function main() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SECRET_KEY;

  if (!supabaseUrl || !supabaseKey) {
    console.error('Error: SUPABASE_URL and SUPABASE_SECRET_KEY environment variables are required');
    process.exit(1);
  }

  const supabase = createClient(supabaseUrl, supabaseKey);

  const blogDir = path.join(process.cwd(), 'blog-posts');

  console.log('🚀 Migrating blog posts to database...');
  console.log(`📁 Reading from: ${blogDir}`);

  // Read all markdown files
  const files = await fsPromises.readdir(blogDir);
  const mdFiles = files.filter((f) => f.endsWith('.md'));

  if (mdFiles.length === 0) {
    console.log('No markdown files found');
    process.exit(0);
  }

  console.log(`📝 Found ${mdFiles.length} blog post(s)`);

  for (const file of mdFiles) {
    const post = await parseBlogPost(path.join(blogDir, file));

    console.log(`   Processing: ${post.title}`);

    // Check if post already exists
    const { data: existing } = await supabase
      .from('blog_posts')
      .select('id')
      .eq('slug', post.slug)
      .single();

    if (existing) {
      console.log(`   ⏭️  Skipping (already exists): ${post.slug}`);
      continue;
    }

    // Insert post
    const { error } = await supabase
      .from('blog_posts')
      .insert({
        slug: post.slug,
        title: post.title,
        date: post.date,
        author: post.author,
        read_time: post.read_time,
        tags: post.tags,
        description: post.description,
        content: post.content,
        cover_image: post.cover_image || null,
        published: true, // Publish by default since these are existing posts
      });

    if (error) {
      console.error(`   ❌ Error inserting ${post.slug}:`, error.message);
    } else {
      console.log(`   ✅ Inserted: ${post.slug}`);
    }
  }

  console.log('\n✅ Migration complete!');
}

main().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
