#!/usr/bin/env node
/**
 * Blog Docpack Generator
 *
 * Takes markdown blog posts and generates a valid .docpack file
 * where each post is represented as a Symbol with kind="article"
 *
 * Usage:
 *   npx ts-node scripts/generate-blog-docpack.ts [blogDir] [outputPath] [--upload]
 *
 * Options:
 *   --upload    Upload the generated docpack to R2 bucket (blog-posts/ folder)
 */

import fs from 'fs';
import fsPromises from 'fs/promises';
import path from 'path';
// @ts-ignore - archiver types not installed
import archiver from 'archiver';
import crypto from 'crypto';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

interface BlogMetadata {
  [key: string]: string;
}

interface BlogPost {
  slug: string;
  title: string;
  date: string;
  author: string;
  readTime: string;
  tags: string[];
  description: string;
  content: string;
  coverImage?: string;
}

async function parseBlogPost(filePath: string): Promise<BlogPost> {
  const content = await fsPromises.readFile(filePath, 'utf-8');
  const slug = path.basename(filePath, '.md');

  // Extract frontmatter (simple parser)
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
    readTime: metadata.readTime || '5 min read',
    tags: metadata.tags ? metadata.tags.split(',').map(t => t.trim()) : [],
    description: metadata.description || '',
    content: markdown.trim(),
    coverImage: metadata.coverImage
  };
}

function createSymbol(post: BlogPost) {
  const id = `blog/${post.slug}`;

  return {
    id,
    kind: 'article',
    file: `blog/${post.slug}.md`,
    line: 1,
    signature: `${post.date} | ${post.readTime} | ${post.tags.join(', ')}`,
    doc_id: id
  };
}

function createDocumentation(post: BlogPost) {
  return {
    symbol: `blog/${post.slug}`,
    summary: post.title,
    description: post.content,
    parameters: [
      { name: 'author', type: post.author, description: 'Post author' },
      { name: 'date', type: post.date, description: 'Publication date' },
      { name: 'tags', type: post.tags.join(','), description: 'Post tags' },
      { name: 'read_time', type: post.readTime.replace(' read', ''), description: 'Estimated read time' },
      { name: 'slug', type: post.slug, description: 'URL slug' },
      ...(post.coverImage ? [{ name: 'cover_image', type: post.coverImage, description: 'Cover image URL' }] : [])
    ],
    returns: '',
    example: post.description || '',
    notes: [
      `seo_description: ${post.description}`,
      `canonical_url: https://doctown.dev/blog/${post.slug}`
    ]
  };
}

async function generateBlogDocpack(blogDir: string, outputPath: string) {
  console.log('🚀 Generating blog docpack...');

  // Read all markdown files
  const files = await fsPromises.readdir(blogDir);
  const mdFiles = files.filter((f) => f.endsWith('.md'));

  if (mdFiles.length === 0) {
    throw new Error(`No markdown files found in ${blogDir}`);
  }

  console.log(`📝 Found ${mdFiles.length} blog post(s)`);

  // Parse all posts
  const posts = [];
  for (const file of mdFiles) {
    const post = await parseBlogPost(path.join(blogDir, file));
    posts.push(post);
    console.log(`   ✓ ${post.title}`);
  }

  // Sort by date (newest first)
  posts.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  // Generate symbols and documentation
  const symbols = posts.map(createSymbol);
  const docs = posts.map(createDocumentation);

  // Create manifest
  const manifest = {
    docpack_format: 1,
    project: {
      name: 'xandwr_doctown_blog',
      version: '1.0.0',
      repo: 'xandwr/doctown-v3',
      commit: crypto.createHash('sha256').update(JSON.stringify(posts)).digest('hex').slice(0, 8)
    },
    generated_at: new Date().toISOString(),
    language_summary: {
      markdown_files: posts.length
    },
    stats: {
      symbols_extracted: symbols.length,
      docs_generated: docs.length
    },
    public: true
  };

  // Create temp directory for docpack contents
  const tempDir = path.join('/tmp', `doctown-blog-${Date.now()}`);
  await fsPromises.mkdir(tempDir, { recursive: true });

  // Write JSON files
  await Promise.all([
    fsPromises.writeFile(path.join(tempDir, 'manifest.json'), JSON.stringify(manifest, null, 2)),
    fsPromises.writeFile(path.join(tempDir, 'symbols.json'), JSON.stringify(symbols, null, 2)),
    fsPromises.writeFile(path.join(tempDir, 'docs.json'), JSON.stringify(docs, null, 2))
  ]);

  console.log('📦 Creating docpack archive...');

  // Create ZIP archive
  const output = fs.createWriteStream(outputPath);
  const archive = archiver('zip', { zlib: { level: 9 } });

  await new Promise<void>((resolve, reject) => {
    output.on('close', resolve);
    archive.on('error', reject);

    archive.pipe(output);
    archive.directory(tempDir, false);
    archive.finalize();
  });

  // Cleanup
  await fsPromises.rm(tempDir, { recursive: true, force: true });

  console.log(`✅ Blog docpack generated: ${outputPath}`);
  console.log(`📊 Stats: ${symbols.length} articles, ${archive.pointer()} bytes`);

  return outputPath;
}

async function uploadToR2(filePath: string): Promise<string> {
  console.log('☁️  Uploading to R2...');

  const accessKeyId = process.env.BUCKET_ACCESS_KEY_ID;
  const secretAccessKey = process.env.BUCKET_SECRET_ACCESS_KEY;
  const endpoint = process.env.BUCKET_S3_ENDPOINT;
  const bucketName = process.env.BUCKET_NAME || 'doctown-central';

  if (!accessKeyId || !secretAccessKey || !endpoint) {
    throw new Error(
      'Missing R2 credentials. Set BUCKET_ACCESS_KEY_ID, BUCKET_SECRET_ACCESS_KEY, and BUCKET_S3_ENDPOINT'
    );
  }

  const s3Client = new S3Client({
    region: 'auto',
    endpoint: endpoint,
    credentials: {
      accessKeyId,
      secretAccessKey,
    },
  });

  const fileContent = await fsPromises.readFile(filePath);
  const key = 'blog-posts/blog.docpack';

  await s3Client.send(
    new PutObjectCommand({
      Bucket: bucketName,
      Key: key,
      Body: fileContent,
      ContentType: 'application/zip',
    })
  );

  const fileUrl = `${endpoint}/${bucketName}/${key}`;
  console.log(`✅ Uploaded to R2: ${fileUrl}`);

  return fileUrl;
}

// CLI
const args = process.argv.slice(2);
const shouldUpload = args.includes('--upload');
const positionalArgs = args.filter((arg) => !arg.startsWith('--'));

const blogDir = positionalArgs[0] || './blog-posts';
const outputPath = positionalArgs[1] || './xandwr_doctown_blog.docpack';

(async () => {
  try {
    const generatedPath = await generateBlogDocpack(blogDir, outputPath);

    if (shouldUpload) {
      await uploadToR2(generatedPath);
    }

    process.exit(0);
  } catch (err: any) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
})();
