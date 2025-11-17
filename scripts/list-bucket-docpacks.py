#!/usr/bin/env python3
"""
Script to list all docpacks in the R2/S3 bucket and extract their manifests

Usage:
    python3 scripts/list-bucket-docpacks.py
    python3 scripts/list-bucket-docpacks.py --public-only
"""

import boto3
import sys
import json
import zipfile
import io
from pathlib import Path
from botocore.config import Config
from dotenv import load_dotenv
import os

# Load environment variables from website/.env
env_path = Path(__file__).parent.parent / "website" / ".env"
load_dotenv(env_path)

# Get credentials from environment
BUCKET_NAME = os.getenv("BUCKET_NAME", "doctown-central")
ACCESS_KEY_ID = os.getenv("BUCKET_ACCESS_KEY_ID")
SECRET_ACCESS_KEY = os.getenv("BUCKET_SECRET_ACCESS_KEY")
ENDPOINT_URL = os.getenv("BUCKET_S3_ENDPOINT")

if not all([ACCESS_KEY_ID, SECRET_ACCESS_KEY, ENDPOINT_URL]):
    print("Error: Missing bucket credentials in website/.env")
    sys.exit(1)

# Initialize S3 client
s3_client = boto3.client(
    "s3",
    endpoint_url=ENDPOINT_URL,
    aws_access_key_id=ACCESS_KEY_ID,
    aws_secret_access_key=SECRET_ACCESS_KEY,
    config=Config(signature_version="s3v4"),
    region_name="auto",
)

def extract_manifest_from_docpack(bucket, key):
    """Download and extract manifest.json from a .docpack file"""
    try:
        # Download the .docpack file
        response = s3_client.get_object(Bucket=bucket, Key=key)
        docpack_data = response['Body'].read()

        # .docpack files are ZIP archives
        with zipfile.ZipFile(io.BytesIO(docpack_data)) as zf:
            # Look for manifest.json
            if 'manifest.json' in zf.namelist():
                manifest_data = zf.read('manifest.json')
                return json.loads(manifest_data)
            else:
                return {"error": "No manifest.json found in docpack"}
    except Exception as e:
        return {"error": str(e)}

def list_docpacks():
    """List all docpacks in the bucket"""
    print(f"\n🔍 Listing docpacks in bucket: {BUCKET_NAME}\n")

    try:
        # List all objects in the docpacks/ prefix
        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix='docpacks/')

        all_docpacks = []

        for page in pages:
            if 'Contents' not in page:
                continue

            for obj in page['Contents']:
                key = obj['Key']
                if key.endswith('.docpack'):
                    all_docpacks.append({
                        'key': key,
                        'size': obj['Size'],
                        'last_modified': obj['LastModified'],
                    })

        if not all_docpacks:
            print("❌ No docpacks found in bucket!")
            return

        print(f"📦 Found {len(all_docpacks)} docpack(s) in bucket\n")
        print("=" * 80)

        for i, docpack in enumerate(all_docpacks, 1):
            print(f"\n📦 Docpack {i}/{len(all_docpacks)}")
            print(f"   Key:          {docpack['key']}")
            print(f"   Size:         {docpack['size']:,} bytes ({docpack['size'] / (1024*1024):.2f} MB)")
            print(f"   Modified:     {docpack['last_modified']}")
            print(f"   URL:          {ENDPOINT_URL}/{BUCKET_NAME}/{docpack['key']}")

            # Extract manifest
            print(f"\n   📄 Extracting manifest...")
            manifest = extract_manifest_from_docpack(BUCKET_NAME, docpack['key'])

            if 'error' in manifest:
                print(f"   ⚠️  Error: {manifest['error']}")
            else:
                # Print full manifest for debugging
                print(f"\n   📋 Full Manifest:")
                print(f"   {json.dumps(manifest, indent=6)}\n")

                print(f"   Name:         {manifest.get('name', 'N/A')}")
                print(f"   Description:  {manifest.get('description', 'N/A')}")
                print(f"   Version:      {manifest.get('version', 'N/A')}")
                print(f"   Language:     {manifest.get('language', 'N/A')}")
                print(f"   Public:       {manifest.get('public', False)}")
                print(f"   Repo URL:     {manifest.get('repo_url', 'N/A')}")
                print(f"   Commit:       {manifest.get('commit_hash', 'N/A')}")

                # Show additional manifest fields if present
                if 'author' in manifest:
                    print(f"   Author:       {manifest['author']}")
                if 'license' in manifest:
                    print(f"   License:      {manifest['license']}")

        print("\n" + "=" * 80)
        print("\n✅ Done!\n")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    list_docpacks()
