// POST /functions/v1/revenuecat-webhook (FR-SUB-02)
// RevenueCat posts subscription events here; entitlements are written only
// by the server. Configure the same secret as the webhook's Authorization
// header in the RevenueCat dashboard, and use the Supabase user id as the
// RevenueCat app user id.

import { adminClient, error, json } from "../_shared/http.ts";

const ACTIVE_EVENTS = new Set(["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "NON_RENEWING_PURCHASE"]);
const ENDED_EVENTS = new Set(["EXPIRATION"]);

function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "method_not_allowed", "Use POST.");
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  const provided = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!secret || !sameSecret(provided, secret)) return error(401, "unauthorized", "Invalid webhook secret.");

  const payload = await req.json().catch(() => null);
  const event = payload?.event;
  const userId: string | undefined = event?.app_user_id;
  if (!event || !userId || !/^[0-9a-f-]{36}$/i.test(userId)) return json({ ignored: true });

  const admin = adminClient();
  if (ACTIVE_EVENTS.has(event.type)) {
    const expiresAt = event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null;
    const { error: e } = await admin
      .from("entitlements")
      .upsert({ user_id: userId, tier: "premium", expires_at: expiresAt }, { onConflict: "user_id" });
    if (e) return error(500, "write_failed", e.message);
  } else if (ENDED_EVENTS.has(event.type)) {
    const { error: e } = await admin.from("entitlements").update({ tier: "free", expires_at: null }).eq("user_id", userId);
    if (e) return error(500, "write_failed", e.message);
  }
  return json({ received: true, type: event.type });
});
