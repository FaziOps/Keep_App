// POST /functions/v1/extract-receipt
// Reads a receipt photo with Claude and returns structured fields with a
// confidence score per field (PRD §11.1, FR-AI-01..08). The Anthropic key is
// a server-side secret and never reaches the app.

import Anthropic from "npm:@anthropic-ai/sdk";
import { adminClient, callerFrom, corsHeaders, error, json } from "../_shared/http.ts";

const MODEL = Deno.env.get("KEEPR_EXTRACTION_MODEL") ?? "claude-opus-5-5";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // NFR-SEC-06
const MAX_SCANS_PER_HOUR = 30;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const CATEGORIES = [
  "electronics", "appliances", "furniture", "clothing", "groceries",
  "health", "home", "travel", "dining", "other",
];

const anthropic = new Anthropic({ timeout: 25_000, maxRetries: 1 });

const nullableString = { type: ["string", "null"] };
const nullableNumber = { type: ["number", "null"] };
const nullableInteger = { type: ["integer", "null"] };
const confident = (value: Record<string, unknown>) => ({
  type: "object",
  properties: { value, confidence: { type: "number" } },
  required: ["value", "confidence"],
  additionalProperties: false,
});

// Structured output schema: the response is guaranteed to match it.
const RECEIPT_SCHEMA = {
  type: "object",
  properties: {
    is_receipt: { type: "boolean" },
    merchant: confident(nullableString),
    purchase_date: confident(nullableString),
    total: confident(nullableNumber),
    currency: nullableString,
    category: confident({ type: "string", enum: CATEGORIES }),
    payment_method: nullableString,
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          quantity: { type: "integer" },
          unit_price: nullableNumber,
          serial_number: nullableString,
          confidence: { type: "number" },
        },
        required: ["name", "quantity", "unit_price", "serial_number", "confidence"],
        additionalProperties: false,
      },
    },
    suggested_warranty_months: nullableInteger,
    suggested_return_days: nullableInteger,
  },
  required: [
    "is_receipt", "merchant", "purchase_date", "total", "currency", "category",
    "payment_method", "items", "suggested_warranty_months", "suggested_return_days",
  ],
  additionalProperties: false,
};

const SYSTEM_PROMPT = `You read photos of shopping receipts and invoices for Keepr, an app that tracks returns and warranties.

Extract what is printed on the receipt. Guidance:
- merchant: the store or seller name as a person would say it, not the legal entity or address.
- purchase_date: ISO format YYYY-MM-DD. When day and month are ambiguous, use the locale hint.
- total: the final amount paid in major units (e.g. 1499.50), after tax and discounts.
- currency: ISO-4217 code inferred from symbols, text or the currency hint.
- items: one entry per product line with quantity and unit price. Skip tax, discount, and subtotal lines. Copy serial numbers or IMEIs only if printed.
- category: the best fit for the purchase as a whole.
- suggested_warranty_months: the warranty printed on the receipt; otherwise the usual manufacturer warranty for that kind of durable product (often 12 months for electronics and appliances); null for consumables like food or clothing.
- suggested_return_days: the return window printed on the receipt, otherwise null.
- confidence: 0 to 1 per field, honest. Use low values when text is blurry, cut off or guessed, and null values for anything you cannot find.
- is_receipt: false if the image is not a receipt or invoice.`;

type Extracted = {
  is_receipt: boolean;
  merchant: { value: string | null; confidence: number };
  purchase_date: { value: string | null; confidence: number };
  total: { value: number | null; confidence: number };
  currency: string | null;
  category: { value: string; confidence: number };
  payment_method: string | null;
  items: { name: string; quantity: number; unit_price: number | null; serial_number: string | null; confidence: number }[];
  suggested_warranty_months: number | null;
  suggested_return_days: number | null;
};

const clamp01 = (n: number) => Math.min(1, Math.max(0, Number.isFinite(n) ? n : 0));
const toMinor = (major: number | null) => (major == null || !Number.isFinite(major) ? null : Math.round(major * 100));
const validDate = (d: string | null) => (d && /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d)) ? d : null);
const inRange = (n: number | null, min: number, max: number) => (n != null && n >= min && n <= max ? n : null);

/** Converts the model output to the response contract the app parses. */
function toResponse(x: Extracted, fallbackCurrency: string) {
  const currency = x.currency && /^[A-Za-z]{3}$/.test(x.currency) ? x.currency.toUpperCase() : fallbackCurrency;
  const date = validDate(x.purchase_date.value);
  return {
    merchant: { value: x.merchant.value?.trim() || null, confidence: clamp01(x.merchant.confidence) },
    purchase_date: { value: date, confidence: date ? clamp01(x.purchase_date.confidence) : 0 },
    total: { value_minor: toMinor(x.total.value), confidence: clamp01(x.total.confidence) },
    currency,
    category: {
      value: CATEGORIES.includes(x.category.value) ? x.category.value : "other",
      confidence: clamp01(x.category.confidence),
    },
    payment_method: x.payment_method,
    items: x.items
      .filter((i) => i.name.trim().length > 0)
      .slice(0, 50)
      .map((i) => ({
        name: i.name.trim(),
        quantity: Math.max(1, Math.round(i.quantity || 1)),
        unit_price_minor: toMinor(i.unit_price),
        serial_number: i.serial_number,
        confidence: clamp01(i.confidence),
      })),
    suggested_warranty_months: inRange(x.suggested_warranty_months, 0, 120),
    suggested_return_days: inRange(x.suggested_return_days, 0, 365),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return error(405, "method_not_allowed", "Use POST.");

  const user = await callerFrom(req);
  if (!user) return error(401, "unauthenticated", "Sign in to scan receipts.");

  let body: { image_base64?: string; mime_type?: string; currency?: string; locale?: string };
  try {
    body = await req.json();
  } catch {
    return error(400, "bad_request", "Body must be JSON.");
  }
  const image = body.image_base64 ?? "";
  const mimeType = body.mime_type ?? "image/jpeg";
  const currency = /^[A-Z]{3}$/.test(body.currency ?? "") ? body.currency! : "USD";
  if (!image || !ALLOWED_MIME.has(mimeType)) return error(400, "bad_request", "Send a JPEG, PNG, WebP or GIF image.");
  if (image.length * 0.75 > MAX_IMAGE_BYTES) return error(413, "too_large", "Images must be under 5 MB.");

  const admin = adminClient();

  // Abuse protection: per-user hourly rate limit.
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("ai_usage")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", since);
  if ((count ?? 0) >= MAX_SCANS_PER_HOUR) return error(429, "rate_limited", "Too many scans. Try again later.");

  // BR-07: reserve one scan from the monthly quota; refunded on failure.
  const { data: allowed, error: quotaError } = await admin.rpc("reserve_ai_scan", { p_user: user.id });
  if (quotaError) return error(500, "quota_error", "Could not check your plan.");
  if (!allowed) return error(402, "quota_exceeded", "You have used all AI scans for this month.");

  const started = Date.now();
  const logUsage = (fields: Record<string, unknown>) =>
    admin.from("ai_usage").insert({ user_id: user.id, model: MODEL, latency_ms: Date.now() - started, ...fields });
  const refund = () => admin.rpc("refund_ai_scan", { p_user: user.id });

  try {
    const params = {
      model: MODEL,
      max_tokens: 4096,
      // Opus-tier safety classifiers can decline; let the API reroute automatically.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: RECEIPT_SCHEMA },
      },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mimeType, data: image } },
            {
              type: "text",
              text: `Currency hint: ${currency}. Locale hint: ${body.locale ?? "en"}. Today's date: ${
                new Date().toISOString().slice(0, 10)
              }. Extract this receipt.`,
            },
          ],
        },
      ],
    };
    const response = await anthropic.beta.messages.create(
      params as unknown as Parameters<typeof anthropic.beta.messages.create>[0],
    ) as Anthropic.Beta.Messages.BetaMessage;

    const usage = { input_tokens: response.usage.input_tokens, output_tokens: response.usage.output_tokens };
    if (response.stop_reason === "refusal" || response.stop_reason === "max_tokens") {
      await Promise.all([refund(), logUsage({ ...usage, success: false, error: response.stop_reason })]);
      return error(422, "unreadable", "We could not read this receipt.");
    }

    const text = response.content.find((b) => b.type === "text");
    const extracted = JSON.parse(text && "text" in text ? text.text : "{}") as Extracted;
    if (!extracted.is_receipt) {
      await Promise.all([refund(), logUsage({ ...usage, success: false, error: "not_a_receipt" })]);
      return error(422, "not_a_receipt", "This does not look like a receipt.");
    }

    await logUsage({ ...usage, success: true });
    return json(toResponse(extracted, currency));
  } catch (e) {
    await refund();
    if (e instanceof Anthropic.RateLimitError) {
      await logUsage({ success: false, error: "rate_limited" });
      return error(429, "busy", "The AI service is busy. Please try again shortly.");
    }
    if (e instanceof Anthropic.APIConnectionTimeoutError) {
      await logUsage({ success: false, error: "timeout" });
      return error(504, "timeout", "Reading the receipt took too long.");
    }
    if (e instanceof Anthropic.APIError) {
      await logUsage({ success: false, error: `api_${e.status}` });
      return error(502, "ai_error", "The AI service returned an error.");
    }
    if (e instanceof SyntaxError) {
      await logUsage({ success: false, error: "invalid_json" });
      return error(422, "unreadable", "We could not read this receipt.");
    }
    await logUsage({ success: false, error: "unexpected" });
    return error(500, "unexpected", "Something went wrong.");
  }
});
