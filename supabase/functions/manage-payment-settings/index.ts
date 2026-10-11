import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const encoder = new TextEncoder();

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const cleanMobile = (value: string) => {
  let cleaned = value.trim().replace(/[\s\-().]/g, "");
  if (cleaned.startsWith("+63")) {
    cleaned = "0" + cleaned.slice(3);
  } else if (cleaned.startsWith("63") && cleaned.length === 12) {
    cleaned = "0" + cleaned.slice(2);
  } else if (cleaned.startsWith("9") && cleaned.length === 10) {
    cleaned = "0" + cleaned;
  }
  return cleaned;
};

const maskMobile = (value: string) => {
  const mobile = cleanMobile(value);
  if (mobile.length >= 7) {
    return `${mobile.slice(0, 4)} **** ${mobile.slice(-3)}`;
  }
  return mobile;
};

const maskBank = (value: string) => {
  const digits = value.replace(/\D/g, "");
  return `**** **** ${digits.slice(-4)}`;
};

const validMobile = (value: string) => /^09\d{9}$/.test(cleanMobile(value));
const validBank = (value: string) => /^\d{6,20}$/.test(value.replace(/\D/g, ""));

const encryptionKey = async () => {
  const secret =
    Deno.env.get("PAYMENT_DATA_ENCRYPTION_KEY") ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
    "erefill_secure_payout_encryption_key_2026_prod";
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, ["encrypt"]);
};

const base64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

const encryptValue = async (value: string) => {
  const key = await encryptionKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    encoder.encode(value),
  );
  return `${base64(iv)}.${base64(new Uint8Array(encrypted))}`;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing Supabase service configuration.");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) throw new Error("Missing authorization token.");

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData.user) throw new Error("Invalid session.");

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("id, role")
      .eq("id", userData.user.id)
      .single();
    if (profileError || !profile) throw new Error("Profile not found.");

    const body = await req.json();
    const action = String(body.action ?? "");
    const scope = String(body.scope ?? "");

    const isCustomerScope = scope === "customer_payment_methods";
    const isOwnerScope = scope === "owner_payout_accounts";
    if (!isCustomerScope && !isOwnerScope) throw new Error("Unsupported scope.");
    if (isCustomerScope && profile.role !== "customer") {
      throw new Error("Only customers can manage payment methods.");
    }
    if (isOwnerScope && profile.role !== "owner") {
      throw new Error("Only owners can manage payout accounts.");
    }

    const table = isCustomerScope ? "customer_payment_methods" : "owner_payout_accounts";
    const ownerColumn = isCustomerScope ? "customer_id" : "owner_id";

    if (action === "list") {
      const { data, error } = await supabase
        .from(table)
        .select("*")
        .eq(ownerColumn, userData.user.id)
        .order("is_default", { ascending: false })
        .order("created_at", { ascending: false });
      if (error) throw error;
      return json({ accounts: data ?? [] });
    }

    if (action === "delete") {
      const id = String(body.id ?? "");
      const { error } = await supabase
        .from(table)
        .delete()
        .eq("id", id)
        .eq(ownerColumn, userData.user.id);
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "set_default") {
      const id = String(body.id ?? "");
      if (!id) throw new Error("Payment account id is required.");
      const { error } = await supabase.rpc("set_payment_account_default", {
        p_user_id: userData.user.id,
        p_account_id: id,
        p_scope: scope,
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "create") {
      const type = String(body.type ?? "");
      const accountName = String(body.account_name ?? "").trim();
      const accountRef = String(body.account_ref ?? "").trim();
      const providerName = String(body.provider_name ?? type.toUpperCase()).trim();
      if (!accountName) throw new Error("Account name is required.");

      if (isCustomerScope) {
        if (!["gcash", "maya", "card"].includes(type)) throw new Error("Unsupported payment type.");

        if (type === "card") {
          const gatewayPaymentMethodId = String(body.gateway_payment_method_id ?? "").trim();
          const cardLast4 = String(body.card_last4 ?? accountRef).trim();
          if (!gatewayPaymentMethodId) throw new Error("Gateway token is required for cards.");
          if (!/^\d{4}$/.test(cardLast4)) throw new Error("Card last four digits are required.");

          const { error } = await supabase.from(table).insert({
            customer_id: userData.user.id,
            type,
            label: accountName,
            masked_value: `Card **** ${cardLast4}`,
            gateway_payment_method_id: gatewayPaymentMethodId,
            card_brand: body.card_brand ?? null,
            card_last4: cardLast4,
            status: "active",
          });
          if (error) throw error;
          return json({ ok: true });
        }

        if (!validMobile(accountRef)) throw new Error("Invalid mobile number.");
        const { error } = await supabase.from(table).insert({
          customer_id: userData.user.id,
          type,
          label: accountName,
          masked_value: maskMobile(accountRef),
          status: "active",
        });
        if (error) throw error;
        return json({ ok: true });
      }

      if (!["gcash", "maya", "bank"].includes(type)) throw new Error("Unsupported payout type.");
      const effectiveRef =
        type === "gcash" || type === "maya"
          ? cleanMobile(accountRef)
          : accountRef.replace(/\s+/g, "");

      if ((type === "gcash" || type === "maya") && !validMobile(effectiveRef)) {
        throw new Error("Invalid mobile number. Please enter an 11-digit mobile number (e.g. 09123456789).");
      }
      if (type === "bank" && !validBank(effectiveRef)) {
        throw new Error("Invalid bank account number. Please use 6 to 20 digits.");
      }

      const encrypted = await encryptValue(effectiveRef);
      const { error } = await supabase.from(table).insert({
        owner_id: userData.user.id,
        type,
        label: accountName,
        provider_name: providerName,
        masked_value: type === "bank" ? maskBank(effectiveRef) : maskMobile(effectiveRef),
        encrypted_account_ref: encrypted,
        status: "active",
      });
      if (error) throw error;
      return json({ ok: true });
    }

    throw new Error("Unsupported action.");
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Payment settings error" },
      400,
    );
  }
});
