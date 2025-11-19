# Setup Guide

This guide covers the technical setup and configuration for deploying and running Doctown.

## Table of contents

- [Environment variables](#environment-variables)
- [Stripe integration](#stripe-integration)
- [GitHub OAuth](#github-oauth)
- [Supabase setup](#supabase-setup)
- [RunPod deployment](#runpod-deployment)
- [Cloudflare R2/S3 storage](#cloudflare-r2s3-storage)
- [Local development](#local-development)

## Environment variables

### Website (SvelteKit)

Create a `.env` file in the `website/` directory:

```env
# Supabase
PUBLIC_SUPABASE_URL=https://your-project.supabase.co
PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# GitHub OAuth
GITHUB_CLIENT_ID=your-github-oauth-app-id
GITHUB_CLIENT_SECRET=your-github-oauth-secret

# Stripe
PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_... # or pk_live_...
STRIPE_SECRET_KEY=sk_test_... # or sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_ID=price_... # Your monthly subscription price ID

# RunPod
RUNPOD_API_KEY=your-runpod-api-key
RUNPOD_ENDPOINT_ID=your-runpod-endpoint-id

# Storage (Cloudflare R2)
BUCKET_ACCESS_KEY_ID=your-r2-access-key
BUCKET_SECRET_ACCESS_KEY=your-r2-secret-key
BUCKET_S3_ENDPOINT=https://your-account.r2.cloudflarestorage.com
BUCKET_NAME=doctown-central
PUBLIC_BUCKET_URL=https://commons.doctown.dev

# Shared secrets
DOCTOWN_BUILDER_SHARED_SECRET=your-secure-random-string
CRON_SECRET=your-cron-secret # Optional, defaults to builder secret
```

### Builder (Rust)

Create a `.env` file in the `builder/` directory:

```env
# OpenAI
OPENAI_API_KEY=your-openai-api-key
OPENAI_MODEL=gpt-4-turbo # Optional, defaults to gpt-4o-mini

# Docpack privacy
DOCPACK_PUBLIC=false # Set to true for public docpacks
```

## Stripe integration

### Prerequisites

- Stripe account at [stripe.com](https://stripe.com)
- Access to Stripe Dashboard

### 1. Create subscription product

1. Go to [Stripe Dashboard → Products](https://dashboard.stripe.com/products)
2. Click **Add product**
3. Configure:
   - **Name**: Doctown Premium
   - **Description**: Unlimited docpack generation and access
   - **Pricing model**: Recurring
   - **Price**: $10.00 CAD (or your preferred currency)
   - **Billing period**: Monthly
4. Save and copy the **Price ID** (starts with `price_`)

### 2. Get API keys

1. Go to [Stripe Dashboard → API Keys](https://dashboard.stripe.com/apikeys)
2. Copy:
   - **Publishable key** (starts with `pk_test_` or `pk_live_`)
   - **Secret key** (starts with `sk_test_` or `sk_live_`)

### 3. Configure webhooks

#### Development (using Stripe CLI)

```bash
# Install Stripe CLI
brew install stripe/stripe-brew/stripe  # macOS
# or download from https://stripe.com/docs/stripe-cli

# Login
stripe login

# Forward webhooks to local server
stripe listen --forward-to http://localhost:5173/api/webhooks/stripe

# Copy the webhook signing secret (starts with whsec_)
```

#### Production

1. Go to [Stripe Dashboard → Webhooks](https://dashboard.stripe.com/webhooks)
2. Click **Add endpoint**
3. Endpoint URL: `https://www.doctown.dev/api/webhooks/stripe`
4. Select events:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Copy the **Signing secret**

### 4. Enable customer portal

1. Go to [Stripe Dashboard → Settings → Billing → Customer portal](https://dashboard.stripe.com/settings/billing/portal)
2. Click **Activate link**
3. Configure:
   - ✅ Allow customers to update payment methods
   - ✅ Allow customers to update billing information
   - ✅ Allow customers to cancel subscriptions
4. Save

### 5. Update environment variables

Add to `website/.env`:

```env
PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_ID=price_...
```

### Testing

Use Stripe test cards:

- **Success**: `4242 4242 4242 4242`
- **Requires authentication**: `4000 0025 0000 3155`
- **Declined**: `4000 0000 0000 9995`

Use any future expiry date and any 3-digit CVC.

## GitHub OAuth

### Create OAuth app

1. Go to [GitHub Settings → Developer settings → OAuth Apps](https://github.com/settings/developers)
2. Click **New OAuth App**
3. Configure:
   - **Application name**: Doctown
   - **Homepage URL**: `https://www.doctown.dev`
   - **Authorization callback URL**: `https://www.doctown.dev/auth/callback`
4. Save and copy:
   - **Client ID**
   - **Client Secret**

### Development callbacks

For local development, add additional callback URLs:

- `http://localhost:5173`
- `http://localhost:5173/auth/callback`

### Webhook endpoint

To receive GitHub webhook events:

- **URL**: `https://www.doctown.dev/api/github/webhook`
- **Events**: Push, pull request (optional)

### Environment variables

Add to `website/.env`:

```env
GITHUB_CLIENT_ID=your-client-id
GITHUB_CLIENT_SECRET=your-client-secret
```

## Supabase setup

### Create project

1. Go to [supabase.com](https://supabase.com)
2. Create a new project
3. Note your:
   - Project URL
   - Anon/public key
   - Service role key

### Apply schema

Run the SQL schema file:

```bash
psql -h your-db-host.supabase.co -U postgres -d postgres -f supabase-schema.sql
```

Or paste the contents into the Supabase SQL Editor.

### Environment variables

Add to `website/.env`:

```env
PUBLIC_SUPABASE_URL=https://your-project.supabase.co
PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

## RunPod deployment

### Create serverless endpoint

1. Go to [RunPod](https://www.runpod.io)
2. Create a new serverless endpoint
3. Configure:
   - **Docker image**: Your builder Docker image
   - **GPU**: None (CPU only for builder)
4. Note your:
   - **API Key**
   - **Endpoint ID**

### Environment variables

Add to `website/.env`:

```env
RUNPOD_API_KEY=your-api-key
RUNPOD_ENDPOINT_ID=your-endpoint-id
```

### Deploy builder

Build and push the Docker image:

```bash
cd builder
docker build -t your-registry/doctown-builder:latest .
docker push your-registry/doctown-builder:latest
```

Update your RunPod endpoint to use this image.

## Cloudflare R2/S3 storage

### Create R2 bucket

1. Go to [Cloudflare Dashboard → R2](https://dash.cloudflare.com/?to=/:account/r2)
2. Create a bucket named `doctown-central`
3. Configure CORS:

```json
[
  {
    "AllowedOrigins": ["https://www.doctown.dev", "http://localhost:5173"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3000
  }
]
```

### Create API token

1. In R2 settings, create an API token with:
   - **Permissions**: Read & Write
   - **Bucket**: doctown-central
2. Copy:
   - Access Key ID
   - Secret Access Key

### Configure public access

1. Set up a custom domain for public access (e.g., `commons.doctown.dev`)
2. Point it to your R2 bucket
3. Configure as public for read access

### Environment variables

Add to `website/.env`:

```env
BUCKET_ACCESS_KEY_ID=your-access-key
BUCKET_SECRET_ACCESS_KEY=your-secret-key
BUCKET_S3_ENDPOINT=https://your-account.r2.cloudflarestorage.com
BUCKET_NAME=doctown-central
PUBLIC_BUCKET_URL=https://commons.doctown.dev
```

## Local development

### Prerequisites

- Node.js 18+
- Rust 1.70+
- Cargo

### Install dependencies

```bash
# Website
cd website
npm install

# Builder
cd ../builder
cargo build

# Localdoc
cd ../localdoc
cargo build
```

### Run development servers

```bash
# Website (from website/)
npm run dev

# Builder (from builder/)
cargo run --release -- path/to/repo.zip output-name

# Localdoc (from localdoc/)
cargo run --release -- inspect path/to/docpack.docpack
```

### Environment setup

1. Copy `.env.example` to `.env` in both `website/` and `builder/`
2. Fill in all required values
3. Ensure Supabase is running (or use hosted Supabase)
4. Start the website dev server: `npm run dev`

### Testing Stripe webhooks locally

```bash
# Terminal 1: Start dev server
npm run dev

# Terminal 2: Forward Stripe webhooks
stripe listen --forward-to localhost:5173/api/webhooks/stripe
```

### Testing the full pipeline

```bash
# 1. Build a test docpack
cd builder
OPENAI_API_KEY=your-key cargo run --release -- test-data/sample.zip test-output

# 2. Inspect it
cd ../localdoc
cargo run --release -- inspect ../builder/test-output.docpack

# 3. Upload to local storage (optional)
# Use the website UI or test scripts
```

## Deployment

### Vercel (recommended for website)

1. Connect your GitHub repository to Vercel
2. Configure environment variables in Vercel dashboard
3. Deploy

Vercel automatically handles:
- Cron jobs (defined in `vercel.json`)
- Edge functions
- Build optimization

### Docker (builder)

```bash
cd builder
docker build -t doctown-builder:latest .
docker push your-registry/doctown-builder:latest
```

Deploy to RunPod or any Docker-compatible platform.

## Troubleshooting

### Stripe webhooks not working

- Verify webhook URL is accessible from internet
- Check webhook secret matches
- Review Stripe Dashboard webhook logs
- Ensure endpoint returns 200 status

### GitHub OAuth fails

- Verify callback URLs match exactly
- Check client ID and secret
- Ensure app is not suspended

### Builder fails to generate docs

- Check OpenAI API key is valid
- Verify sufficient API credits
- Check tree-sitter parsers are installed
- Review builder logs for errors

### Storage upload fails

- Verify R2 credentials
- Check bucket exists and is accessible
- Ensure CORS is configured
- Check bucket permissions

## Security notes

- Never commit `.env` files
- Use environment variables for all secrets
- Rotate API keys regularly
- Use HTTPS in production
- Enable webhook signature verification
- Implement rate limiting
- Monitor for suspicious activity

## Support

For issues and questions:
- Check existing documentation
- Review error logs
- Test in development environment first
- Verify all environment variables are set correctly
