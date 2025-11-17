#!/usr/bin/env python3
"""
Script to list public docpacks from R2/S3 bucket by reading manifests directly.
This demonstrates querying privacy information from the manifest itself rather than a database.

Usage:
    python3 scripts/list-public-docpacks.py
    python3 scripts/list-public-docpacks.py --json  # Output as JSON
"""

import boto3
import sys
import json
import zipfile
import io
import argparse
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
    print("Error: Missing bucket credentials in website/.env", file=sys.stderr)
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
        docpack_data = response["Body"].read()

        # .docpack files are ZIP archives
        with zipfile.ZipFile(io.BytesIO(docpack_data)) as zf:
            # Look for manifest.json
            if "manifest.json" in zf.namelist():
                manifest_data = zf.read("manifest.json")
                return json.loads(manifest_data)
            else:
                return None
    except Exception as e:
        print(f"Warning: Failed to extract manifest from {key}: {e}", file=sys.stderr)
        return None


def list_public_docpacks(output_json=False):
    """List all public docpacks by reading manifests directly from R2"""

    if not output_json:
        print(f"\n🔍 Scanning R2 bucket for public docpacks: {BUCKET_NAME}\n", file=sys.stderr)

    try:
        # List all objects in the docpacks/ prefix
        paginator = s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix="docpacks/")

        public_docpacks = []
        total_docpacks = 0

        for page in pages:
            if "Contents" not in page:
                continue

            for obj in page["Contents"]:
                key = obj["Key"]
                if not key.endswith(".docpack"):
                    continue

                total_docpacks += 1

                # Extract manifest to check public status
                manifest = extract_manifest_from_docpack(BUCKET_NAME, key)

                if manifest is None:
                    continue

                # Check if the docpack is public
                is_public = manifest.get("public", False)

                if is_public:
                    public_docpack = {
                        "key": key,
                        "url": f"{ENDPOINT_URL}/{BUCKET_NAME}/{key}",
                        "size": obj["Size"],
                        "last_modified": obj["LastModified"].isoformat(),
                        "manifest": {
                            "project": manifest.get("project", {}),
                            "generated_at": manifest.get("generated_at"),
                            "language_summary": manifest.get("language_summary", {}),
                            "stats": manifest.get("stats", {}),
                            "public": True,
                        },
                    }
                    public_docpacks.append(public_docpack)

        if output_json:
            # Output as JSON for programmatic consumption
            print(json.dumps(public_docpacks, indent=2))
        else:
            # Human-readable output
            print(f"📊 Statistics:", file=sys.stderr)
            print(f"   Total docpacks scanned: {total_docpacks}", file=sys.stderr)
            print(f"   Public docpacks found:  {len(public_docpacks)}", file=sys.stderr)
            print("", file=sys.stderr)

            if not public_docpacks:
                print("❌ No public docpacks found in bucket!", file=sys.stderr)
                return

            print("=" * 80, file=sys.stderr)

            for i, docpack in enumerate(public_docpacks, 1):
                manifest = docpack["manifest"]
                project = manifest.get("project", {})
                stats = manifest.get("stats", {})

                print(f"\n📦 Public Docpack {i}/{len(public_docpacks)}", file=sys.stderr)
                print(f"   Project:      {project.get('name', 'N/A')}", file=sys.stderr)
                print(f"   Version:      {project.get('version', 'N/A')}", file=sys.stderr)
                print(f"   Repository:   {project.get('repo', 'N/A')}", file=sys.stderr)
                print(f"   Commit:       {project.get('commit', 'N/A')}", file=sys.stderr)
                print(f"   Generated:    {manifest.get('generated_at', 'N/A')}", file=sys.stderr)
                print(f"   Symbols:      {stats.get('symbols_extracted', 0)}", file=sys.stderr)
                print(f"   Docs:         {stats.get('docs_generated', 0)}", file=sys.stderr)
                print(f"   Size:         {docpack['size']:,} bytes ({docpack['size'] / (1024*1024):.2f} MB)", file=sys.stderr)
                print(f"   URL:          {docpack['url']}", file=sys.stderr)
                print(f"   S3 Key:       {docpack['key']}", file=sys.stderr)

            print("\n" + "=" * 80, file=sys.stderr)
            print("\n✅ Done!\n", file=sys.stderr)

    except Exception as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="List public docpacks from R2 by reading manifests directly"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON instead of human-readable format",
    )
    args = parser.parse_args()

    list_public_docpacks(output_json=args.json)
