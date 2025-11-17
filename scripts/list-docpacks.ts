#!/usr/bin/env node
/**
 * Script to list all docpacks in the database and show which ones are public
 *
 * Usage:
 *   node --loader tsx scripts/list-docpacks.ts
 */

import("../website/src/lib/supabase.js").then(async ({ supabase }) => {
  try {
    console.log("\n🔍 Querying docpacks database...\n");

    const { data: docpacks, error } = await supabase
      .from("docpacks")
      .select("*")
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Error fetching docpacks:", error);
      process.exit(1);
    }

    if (!docpacks || docpacks.length === 0) {
      console.log("❌ No docpacks found!");
      process.exit(0);
    }

    console.log(`📦 Found ${docpacks.length} docpack(s)\n`);

    // Separate public and private
    const publicPacks = docpacks.filter((d) => d.public);
    const privatePacks = docpacks.filter((d) => !d.public);

    console.log(`📊 Summary:`);
    console.log(`   Public:  ${publicPacks.length}`);
    console.log(`   Private: ${privatePacks.length}`);
    console.log(`   Total:   ${docpacks.length}\n`);

    console.log("=".repeat(80));
    console.log("\n🌍 PUBLIC DOCPACKS\n");
    console.log("=".repeat(80));

    if (publicPacks.length === 0) {
      console.log("\n❌ No public docpacks found!\n");
    } else {
      for (const pack of publicPacks) {
        printDocpack(pack);
      }
    }

    if (privatePacks.length > 0) {
      console.log("\n" + "=".repeat(80));
      console.log("\n🔒 PRIVATE DOCPACKS\n");
      console.log("=".repeat(80));

      for (const pack of privatePacks) {
        printDocpack(pack);
      }
    }

    console.log("\n" + "=".repeat(80));
    console.log("\n✅ Done!\n");
    process.exit(0);
  } catch (error) {
    console.error("\n❌ Error:", error);
    process.exit(1);
  }
});

function printDocpack(pack: any) {
  console.log(`\n📦 ${pack.name}`);
  console.log(`   ID:          ${pack.id}`);
  console.log(`   Full Name:   ${pack.full_name}`);
  console.log(`   Description: ${pack.description || "(none)"}`);
  console.log(`   Public:      ${pack.public ? "✅ YES" : "❌ NO"}`);
  console.log(`   Repo:        ${pack.repo_url}`);
  console.log(`   Commit:      ${pack.commit_hash || "(unknown)"}`);
  console.log(`   Version:     ${pack.version || "(none)"}`);
  console.log(`   Language:    ${pack.language || "(unknown)"}`);
  console.log(`   File URL:    ${pack.file_url}`);
  console.log(`   Created:     ${new Date(pack.created_at).toLocaleString()}`);
  console.log(`   Updated:     ${new Date(pack.updated_at).toLocaleString()}`);
}
