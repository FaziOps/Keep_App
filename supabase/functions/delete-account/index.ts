// POST /functions/v1/delete-account (FR-SET-04, NFR-PRV-02)
// Deletes the caller's images, households they own and the auth user. The
// database cascades from auth.users -> profiles -> households -> receipts.

import { adminClient, callerFrom, corsHeaders, error, json } from "../_shared/http.ts";

const BUCKET = "receipts";

async function removeFolder(admin: ReturnType<typeof adminClient>, prefix: string): Promise<number> {
  const { data: entries } = await admin.storage.from(BUCKET).list(prefix, { limit: 1000 });
  let removed = 0;
  for (const entry of entries ?? []) {
    const path = `${prefix}/${entry.name}`;
    // Folders have no id in Storage listings.
    if (entry.id == null) {
      removed += await removeFolder(admin, path);
    } else {
      await admin.storage.from(BUCKET).remove([path]);
      removed++;
    }
  }
  return removed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return error(405, "method_not_allowed", "Use POST.");

  const user = await callerFrom(req);
  if (!user) return error(401, "unauthenticated", "Sign in again to delete your account.");

  const admin = adminClient();
  const { data: owned, error: ownedError } = await admin.from("households").select("id").eq("owner_id", user.id);
  if (ownedError) return error(500, "lookup_failed", "Could not load your data.");

  let files = 0;
  for (const household of owned ?? []) {
    files += await removeFolder(admin, household.id);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return error(500, "delete_failed", "Could not delete the account. Please contact support.");

  console.log(JSON.stringify({ event: "account_deleted", user_id: user.id, households: owned?.length ?? 0, files }));
  return json({ deleted: true });
});
