import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const parseWebhookSignature = (header: string | null): string | null => {
  if (!header) return null;
  const raw = header.trim();
  const candidates = raw.split(/[\s,;]+/);
  for (const candidate of candidates) {
    const match = candidate.match(/(?:v1=)?([0-9a-fA-F]{64})/);
    if (match) return match[1].toLowerCase();
  }
  return raw.match(/^([0-9a-fA-F]{64})$/)?.[1]?.toLowerCase() ?? null;
};

const hexEncode = (buffer: ArrayBuffer) =>
  Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const timingSafeEqual = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
};

const parsePaymongoSignatureParts = (header: string | null) => {
  if (!header) return { timestamp: null as string | null, testSig: null as string | null, liveSig: null as string | null };
  const parts = header.split(",");
  let timestamp: string | null = null;
  let testSig: string | null = null;
  let liveSig: string | null = null;

  for (const part of parts) {
    const [key, ...rest] = part.trim().split("=");
    const value = rest.join("=").trim().toLowerCase();
    if (key === "t") timestamp = value;
    else if (key === "te") testSig = value;
    else if (key === "li") liveSig = value;
  }
  return { timestamp, testSig, liveSig };
};

const verifyWebhookSignature = async (
  body: string,
  secret: string,
  header: string,
) => {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const { timestamp, testSig, liveSig } = parsePaymongoSignatureParts(header);

  // Standard PayMongo webhook signature: HMAC of `${timestamp}.${rawBody}`
  if (timestamp && (testSig || liveSig)) {
    const payloadToSign = `${timestamp}.${body}`;
    const signatureBuffer = await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(payloadToSign),
    );
    const computed = hexEncode(signatureBuffer);
    if (liveSig && timingSafeEqual(computed, liveSig)) return true;
    if (testSig && timingSafeEqual(computed, testSig)) return true;
  }

  // Fallback: check raw body HMAC for single hex signature headers
  const rawSignature = parseWebhookSignature(header);
  if (rawSignature) {
    const signatureBuffer = await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(body),
    );
    const computed = hexEncode(signatureBuffer);
    return timingSafeEqual(computed, rawSignature);
  }

  return false;
};

serve(async (req) => {
  let adminClient: ReturnType<typeof createClient> | null = null;
  let webhookEventId: string | null = null;
  try {
    const rawBody = await req.text();
    const webhookToken = Deno.env.get("PAYMENT_WEBHOOK_TOKEN");
    const suppliedToken = req.headers.get("x-erefill-webhook-token");
    const signingSecret = Deno.env.get("PAYMONGO_WEBHOOK_SIGNING_SECRET");
    const signatureHeader = req.headers.get("paymongo-signature") ??
      req.headers.get("x-paymongo-signature");

    let isAuthorized = false;

    // 1. Primary: Verify official PayMongo HMAC signature if signing secret is provided
    if (signingSecret && signatureHeader) {
      isAuthorized = await verifyWebhookSignature(rawBody, signingSecret, signatureHeader);
    }

    // 2. Secondary: If token is provided, verify match
    if (!isAuthorized && webhookToken && suppliedToken && timingSafeEqual(suppliedToken, webhookToken)) {
      isAuthorized = true;
    }

    // Reject unauthorized payloads
    if (!isAuthorized) {
      return new Response("Unauthorized", { status: 401 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing Supabase service configuration.");
    }

    const payload = rawBody ? JSON.parse(rawBody) : null;
    const eventType = payload?.data?.attributes?.type ?? payload?.type ?? "";
    const resource = payload?.data?.attributes?.data ?? payload?.data;
    const providerEventId = payload?.data?.id ?? payload?.id ?? null;
    const providerCheckoutId = resource?.id ?? payload?.data?.id;
    const providerStatus = resource?.attributes?.status ?? payload?.data?.attributes?.status ?? "pending";

    if (!providerCheckoutId) {
      throw new Error("Missing provider checkout id.");
    }

    const isPaid =
      String(eventType).includes("paid") ||
      ["paid", "succeeded", "completed"].includes(String(providerStatus));
    const isFailed =
      String(eventType).includes("failed") ||
      ["failed", "expired", "cancelled", "canceled"].includes(String(providerStatus));

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    adminClient = supabase;

    let checkout = null;
    const { data: directCheckout } = await supabase
      .from("payment_checkouts")
      .select("id, order_id, customer_id, owner_id")
      .eq("provider_checkout_id", providerCheckoutId)
      .maybeSingle();

    checkout = directCheckout;

    if (!checkout) {
      const description = String(resource?.attributes?.description ?? "");
      const match = description.match(/eRefill order ([0-9a-fA-F-]+)/i);
      const orderIdFromDesc = match ? match[1] : null;

      if (orderIdFromDesc) {
        const { data: orderCheckout } = await supabase
          .from("payment_checkouts")
          .select("id, order_id, customer_id, owner_id")
          .eq("order_id", orderIdFromDesc)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        checkout = orderCheckout;
      }
    }

    if (!checkout) {
      const isTestPing =
        Boolean(providerEventId?.includes("test")) ||
        Boolean(providerCheckoutId?.includes("test")) ||
        String(resource?.attributes?.description ?? "").toLowerCase().includes("test");

      if (isTestPing) {
        console.log("PayMongo test webhook ping received and verified successfully.");
        return new Response(
          JSON.stringify({ ok: true, message: "Test webhook verified successfully." }),
          {
            headers: { "Content-Type": "application/json" },
            status: 200,
          },
        );
      }

      throw new Error(`Checkout record not found for provider id: ${providerCheckoutId}`);
    }

    if (providerEventId) {
      const { data: existingEvent } = await supabase
        .from("payment_webhook_events")
        .select("id, processing_status")
        .eq("provider_event_id", providerEventId)
        .maybeSingle();
      if (existingEvent?.processing_status === "processed") {
        return new Response(JSON.stringify({ ok: true, duplicate: true }), {
          headers: { "Content-Type": "application/json" },
          status: 200,
        });
      }
    }

    const { data: webhookEvent, error: webhookEventError } = await supabase
      .from("payment_webhook_events")
      .insert({
        checkout_id: checkout.id,
        provider_event_id: providerEventId,
        order_id: checkout.order_id,
        customer_id: checkout.customer_id,
        owner_id: checkout.owner_id,
        provider_checkout_id: providerCheckoutId,
        event_type: String(eventType),
        provider_status: String(providerStatus),
        processing_status: "received",
        raw_payload: payload,
      })
      .select("id")
      .single();
    if (webhookEventError || !webhookEvent) {
      throw new Error("Could not record payment callback.");
    }
    webhookEventId = webhookEvent.id;

    const { error: checkoutUpdateError } = await supabase
      .from("payment_checkouts")
      .update({
        status: providerStatus,
        raw_response: payload,
        updated_at: new Date().toISOString(),
      })
      .eq("id", checkout.id);
    if (checkoutUpdateError) throw checkoutUpdateError;

    if (isPaid) {
      const { error: orderUpdateError } = await supabase
        .from("orders")
        .update({ payment_status: "success", payment_error: null })
        .eq("id", checkout.order_id);
      if (orderUpdateError) throw orderUpdateError;
    } else if (isFailed) {
      const { error: orderUpdateError } = await supabase
        .from("orders")
        .update({
          payment_status: "failed",
          payment_error: `Payment ${providerStatus}`,
          retry_allowed: true,
        })
        .eq("id", checkout.order_id)
        .neq("payment_status", "success");
      if (orderUpdateError) throw orderUpdateError;
    }

    const { error: finalEventError } = await supabase
      .from("payment_webhook_events")
      .update({
        processing_status: "processed",
        processed_at: new Date().toISOString(),
      })
      .eq("id", webhookEventId);
    if (finalEventError) throw finalEventError;

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("Webhook error", error);
    if (adminClient && webhookEventId) {
      const { error: errorLogError } = await adminClient
        .from("payment_webhook_events")
        .update({
          processing_status: "failed",
          processing_error: error instanceof Error ? error.message : "Unknown processing error",
          processed_at: new Date().toISOString(),
        })
        .eq("id", webhookEventId);
      if (errorLogError) {
        console.error("Could not persist webhook processing error", errorLogError);
      }
    }
    return new Response(JSON.stringify({ error: "Webhook processing failed" }), {
      headers: { "Content-Type": "application/json" },
      status: 400,
    });
  }
});
