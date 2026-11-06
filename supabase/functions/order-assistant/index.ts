// AI ordering assistant ("Ask eRefill").
//
// The customer chats in English, Filipino or Taglish; Gemini looks up their
// stations, last order, products and delivery fee through the tools below and
// returns a CART PROPOSAL. It never places orders: the app shows the proposal
// and the customer reviews it in the normal checkout.
//
// Secrets: GEMINI_API_KEY (Google AI Studio), optional GEMINI_MODEL,
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY. Tools query the
// database AS THE USER (their JWT), so row-level security applies.
// Limit: 20 messages per user per 24 h (public.assistant_usage,
// supabase/scripts/order_assistant_usage.sql).
//
// Request:  { messages: [{ role: "user" | "assistant", text: string }, ...] }
// Response: { reply: string, proposal: Proposal | null, remaining: number }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest";
const GEMINI_URL = (model: string) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
const DAILY_LIMIT = 20;
const MAX_TOOL_ROUNDS = 6;
const MAX_HISTORY = 20;

const SYSTEM = `You are eRefill's ordering assistant for a water-refilling delivery app in Cantilan and Madrid, Surigao del Sur, Philippines.
Help the customer put together a refill order. Understand English, Filipino and Taglish ("suki" = the station they usually order from) and reply in the language they use, briefly and warmly.

How to work:
- Use the tools to look up real stations, products, prices and delivery fees. Never invent a station, product, price or fee.
- "My usual" / "suki" / "same as last time" means their last order: call get_last_order.
- When you know the station and items, call propose_cart once with the product ids and quantities. That shows the customer a card they can review and check out. You cannot place or pay for orders yourself; say they can tap "Review & checkout".
- If the request is ambiguous (which station, how many gallons), ask one short question instead of guessing.
- Delivery times are a preference note for the station, not a guarantee.
- Only help with eRefill water orders, accessories, delivery fees and order questions. Politely decline anything else.`;

// Gemini function declarations (OpenAPI-style schema subset).
const tools = [{
  functionDeclarations: [
    {
      name: "list_nearby_stations",
      description:
        "List verified, open water refilling stations in the customer's town with price per gallon, rating and review count. Use to pick or suggest a station.",
    },
    {
      name: "get_last_order",
      description:
        "The customer's most recent delivered order: station id/name and the items with product ids and quantities. Use for 'my usual', 'suki', 'same as last time'.",
    },
    {
      name: "get_station_products",
      description:
        "Products a station sells right now: its water (kind 'water', priced per gallon) and accessories (caps, seals, empty gallons, dispensers) with ids, prices and stock.",
      parameters: {
        type: "object",
        properties: { station_id: { type: "string", description: "Station (owner) id" } },
        required: ["station_id"],
      },
    },
    {
      name: "get_delivery_quote",
      description:
        "Delivery fee from a station to the customer's saved address, and whether it is free (free zone, free barangay, or enough gallons).",
      parameters: {
        type: "object",
        properties: {
          station_id: { type: "string" },
          gallons: { type: "integer", description: "Water gallons in the order" },
        },
        required: ["station_id", "gallons"],
      },
    },
    {
      name: "propose_cart",
      description:
        "Show the customer a cart to review: one station and its product ids with quantities. Call once the order is clear. Returns the validated cart with prices.",
      parameters: {
        type: "object",
        properties: {
          station_id: { type: "string" },
          items: {
            type: "array",
            items: {
              type: "object",
              properties: {
                product_id: { type: "string" },
                quantity: { type: "integer" },
              },
              required: ["product_id", "quantity"],
            },
          },
          delivery_note: {
            type: "string",
            description: "Customer's timing preference, e.g. 'tomorrow morning', or empty",
          },
        },
        required: ["station_id", "items"],
      },
    },
  ],
}];

type GeminiPart = {
  text?: string;
  thought?: boolean;
  functionCall?: { name: string; args?: Record<string, unknown> };
  functionResponse?: { name: string; response: Record<string, unknown> };
  [k: string]: unknown; // e.g. thoughtSignature, echoed back unchanged
};
type GeminiContent = { role: "user" | "model"; parts: GeminiPart[] };

class GeminiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

async function callGemini(apiKey: string, contents: GeminiContent[]) {
  const res = await fetch(GEMINI_URL(MODEL), {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM }] },
      contents,
      tools,
      generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
    }),
  });
  if (!res.ok) throw new GeminiError(res.status, (await res.text()).slice(0, 500));
  return await res.json();
}

type Proposal = {
  station_id: string;
  station_name: string;
  items: { product_id: string; name: string; kind: string; price: number; quantity: number }[];
  subtotal: number;
  delivery_fee: number | null;
  delivery_label: string | null;
  delivery_note: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function runTool(
  db: SupabaseClient,
  userId: string,
  name: string,
  input: Record<string, unknown>,
  state: { proposal: Proposal | null },
): Promise<unknown> {
  switch (name) {
    case "list_nearby_stations": {
      const { data: me } = await db.from("profiles").select("town").eq("id", userId).single();
      let q = db
        .from("profiles")
        .select("id, station_name, barangay, town, price_per_gallon, average_rating, review_count, station_availability, verification_status")
        .eq("role", "owner")
        .limit(15);
      if (me?.town) q = q.eq("town", me.town);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []).filter(
        (s) => (s.verification_status ?? "approved") === "approved" && (s.station_availability ?? "open") === "open",
      );
    }
    case "get_last_order": {
      const { data, error } = await db
        .from("orders")
        .select("id, owner_id, station_name, created_at, order_items(product_id, product_name, quantity)")
        .eq("customer_id", userId)
        .eq("status", "delivered")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data ?? { message: "No delivered orders yet." };
    }
    case "get_station_products": {
      const { data, error } = await db
        .from("products")
        .select("id, name, kind, category, price, stock_level, is_available")
        .eq("owner_id", String(input.station_id))
        .eq("is_available", true);
      if (error) throw error;
      return data ?? [];
    }
    case "get_delivery_quote": {
      const { data: me } = await db
        .from("profiles")
        .select("latitude, longitude, barangay")
        .eq("id", userId)
        .single();
      const { data, error } = await db.rpc("compute_delivery_quote", {
        p_station_id: String(input.station_id),
        p_lat: me?.latitude ?? null,
        p_lng: me?.longitude ?? null,
        p_barangay: me?.barangay ?? null,
        p_gallons: Number(input.gallons) || 0,
      });
      if (error) throw error;
      return data;
    }
    case "propose_cart": {
      const stationId = String(input.station_id);
      const wanted = (input.items as { product_id: string; quantity: number }[]) ?? [];
      const ids = wanted.map((i) => i.product_id);
      const [{ data: station }, { data: products, error }] = await Promise.all([
        db.from("profiles").select("station_name").eq("id", stationId).single(),
        db.from("products").select("id, name, kind, price, stock_level, is_available").eq("owner_id", stationId).in("id", ids),
      ]);
      if (error) throw error;
      const items = wanted.flatMap((w) => {
        const p = (products ?? []).find((x) => x.id === w.product_id && x.is_available);
        const qty = Math.max(1, Math.min(50, Math.round(Number(w.quantity) || 1)));
        return p ? [{ product_id: p.id, name: p.name, kind: p.kind ?? "water", price: Number(p.price), quantity: qty }] : [];
      });
      if (items.length === 0) return { error: "None of those products are available at this station." };
      const gallons = items.filter((i) => i.kind !== "accessory").reduce((s, i) => s + i.quantity, 0);
      let fee: number | null = null;
      let label: string | null = null;
      try {
        const quote = (await runTool(db, userId, "get_delivery_quote", { station_id: stationId, gallons }, state)) as
          Record<string, unknown>;
        fee = Number(quote.fee);
        label = quote.is_free ? "Free delivery" : `₱${fee} · ${quote.distance_km ?? "?"} km`;
      } catch (_) {
        // Fee is shown at checkout anyway.
      }
      state.proposal = {
        station_id: stationId,
        station_name: station?.station_name ?? "Station",
        items,
        subtotal: items.reduce((s, i) => s + i.price * i.quantity, 0),
        delivery_fee: fee,
        delivery_label: label,
        delivery_note: String(input.delivery_note ?? ""),
      };
      return state.proposal;
    }
    default:
      return { error: `Unknown tool ${name}` };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) return json({ error: "The assistant is not set up yet." }, 503);
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Sign in to use the assistant." }, 401);

    // As-the-user client: every tool query goes through RLS.
    const db = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const { data: userData, error: userError } = await db.auth.getUser();
    if (userError || !userData.user) return json({ error: "Sign in to use the assistant." }, 401);
    const userId = userData.user.id;

    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count } = await admin
      .from("assistant_usage")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", since);
    const used = count ?? 0;
    if (used >= DAILY_LIMIT) {
      return json({ error: "You've reached today's 20 assistant messages. Try again tomorrow.", remaining: 0 }, 429);
    }

    const body = await req.json().catch(() => ({}));
    const history = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m: { role?: string; text?: string }) =>
        (m.role === "user" || m.role === "assistant") && typeof m.text === "string" && m.text.trim() !== ""
      )
      .slice(-MAX_HISTORY);
    if (history.length === 0 || history[history.length - 1].role !== "user") {
      return json({ error: "Send a message first." }, 400);
    }
    const contents: GeminiContent[] = history.map((m: { role: "user" | "assistant"; text: string }) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.text.slice(0, 2000) }],
    }));

    const state: { proposal: Proposal | null } = { proposal: null };
    let reply = "";
    let inputTokens = 0;
    let outputTokens = 0;

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const response = await callGemini(apiKey, contents);
      inputTokens += response.usageMetadata?.promptTokenCount ?? 0;
      outputTokens += response.usageMetadata?.candidatesTokenCount ?? 0;

      const candidate = response.candidates?.[0];
      if (!candidate || ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].includes(candidate.finishReason)) {
        reply = "Sorry, I can only help with eRefill water orders.";
        break;
      }

      const parts: GeminiPart[] = candidate.content?.parts ?? [];
      const text = parts
        .filter((p) => typeof p.text === "string" && !p.thought)
        .map((p) => p.text)
        .join("\n")
        .trim();
      const calls = parts.filter((p) => p.functionCall);

      if (calls.length === 0) {
        reply = text || (candidate.finishReason === "MAX_TOKENS" ? "Sorry, that took too long. Please try again." : "");
        break;
      }

      // Echo the model turn back unchanged (keeps thought signatures intact).
      contents.push({ role: "model", parts });
      const results: GeminiPart[] = [];
      for (const p of calls) {
        const call = p.functionCall!;
        let out: unknown;
        try {
          out = await runTool(db, userId, call.name, call.args ?? {}, state);
        } catch (e) {
          out = { error: `Lookup failed: ${e instanceof Error ? e.message : String(e)}` };
        }
        // functionResponse.response must be a JSON object.
        const wrapped = out !== null && typeof out === "object" && !Array.isArray(out)
          ? (out as Record<string, unknown>)
          : { result: out };
        results.push({ functionResponse: { name: call.name, response: wrapped } });
      }
      // All function results go back in one turn.
      contents.push({ role: "user", parts: results });
      reply = text;
    }

    await admin.from("assistant_usage").insert({
      user_id: userId,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
    });

    if (!reply && state.proposal) reply = "Here's your cart. Tap Review & checkout to confirm.";
    if (!reply) reply = "Sorry, I couldn't finish that. Could you say it another way?";
    return json({ reply, proposal: state.proposal, remaining: DAILY_LIMIT - used - 1 });
  } catch (e) {
    if (e instanceof GeminiError) {
      console.error("gemini error", e.status, e.message);
      if (e.status === 429) return json({ error: "The assistant is busy. Try again in a minute." }, 503);
      return json({ error: "The assistant is unavailable right now." }, 502);
    }
    console.error("order-assistant error", e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
