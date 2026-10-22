// Service fee wallet top-ups: an owner pays eRefill through PayMongo and the
// wallet is credited once the payment is confirmed (webhook or verify).

import {
  normalizePaymentMethod,
  paymongoAuthHeader,
  paymongoMethod,
} from "../_shared/paymongo.ts";

export type TopupContext = {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  userEmail?: string;
  secretKey: string;
  livemode: boolean;
  callbackBaseUrl: string;
};

const json = (body: unknown, corsHeaders: Record<string, string>) =>
  new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status: 200,
  });

const requireOwner = async (ctx: TopupContext) => {
  const { data: profile } = await ctx.supabase
    .from("profiles")
    .select("role, station_name")
    .eq("id", ctx.userId)
    .maybeSingle();
  if (profile?.role !== "owner") {
    throw new Error("Only station owners can top up a service fee wallet.");
  }
  return profile as { role: string; station_name: string | null };
};

const walletBalance = async (ctx: TopupContext): Promise<number> => {
  const { data } = await ctx.supabase
    .from("station_fee_wallets")
    .select("balance")
    .eq("owner_id", ctx.userId)
    .maybeSingle();
  return Number(data?.balance ?? 0);
};

export const handleTopup = async (
  // deno-lint-ignore no-explicit-any
  body: any,
  ctx: TopupContext,
  corsHeaders: Record<string, string>,
) => {
  const profile = await requireOwner(ctx);
  const paymentMethod = normalizePaymentMethod(body.payment_method);
  if (!paymentMethod) throw new Error("Unsupported payment method.");
  const amount = Number(body.amount);

  const { data: topupId, error: createError } = await ctx.supabase.rpc(
    "create_wallet_topup",
    { p_owner_id: ctx.userId, p_amount: amount, p_payment_method: paymentMethod },
  );
  if (createError) throw new Error(createError.message);

  const callback = (status: string) =>
    `${ctx.callbackBaseUrl}/functions/v1/payment-callback?topup_id=${encodeURIComponent(topupId)}&status=${status}`;

  const paymongoResponse = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: paymongoAuthHeader(ctx.secretKey),
    },
    body: JSON.stringify({
      data: {
        attributes: {
          description: `eRefill wallet top-up ${topupId}`,
          reference_number: String(topupId).replaceAll("-", "").slice(0, 22),
          line_items: [
            {
              currency: "PHP",
              amount: Math.round(amount * 100),
              name: `Service fee wallet top-up${profile.station_name ? ` — ${profile.station_name}` : ""}`,
              quantity: 1,
            },
          ],
          payment_method_types: [paymongoMethod(paymentMethod)],
          success_url: callback("success"),
          cancel_url: callback("cancel"),
          send_email_receipt: Boolean(ctx.userEmail),
          show_description: true,
          show_line_items: true,
          ...(ctx.userEmail ? { billing: { email: ctx.userEmail } } : {}),
          metadata: { kind: "wallet_topup", topup_id: topupId },
        },
      },
    }),
  });

  const paymongoJson = await paymongoResponse.json();
  if (!paymongoResponse.ok) {
    console.error("PayMongo top-up checkout error", paymongoJson);
    const detail = paymongoJson?.errors?.[0]?.detail;
    throw new Error(detail ? `Payment gateway error: ${detail}` : "Payment gateway rejected the top-up.");
  }

  const checkoutId = paymongoJson?.data?.id;
  const checkoutUrl = paymongoJson?.data?.attributes?.checkout_url;
  if (!checkoutId || !checkoutUrl) {
    throw new Error("Payment gateway did not return a checkout URL.");
  }

  const { error: recordError } = await ctx.supabase.rpc("record_wallet_topup_checkout", {
    p_topup_id: topupId,
    p_provider_checkout_id: checkoutId,
    p_checkout_url: checkoutUrl,
    p_livemode: ctx.livemode,
  });
  if (recordError) throw new Error(recordError.message);

  return json(
    { checkout_url: checkoutUrl, checkout_id: checkoutId, topup_id: topupId, livemode: ctx.livemode },
    corsHeaders,
  );
};

export const handleVerifyTopup = async (
  // deno-lint-ignore no-explicit-any
  body: any,
  ctx: TopupContext,
  corsHeaders: Record<string, string>,
) => {
  await requireOwner(ctx);
  const topupId = String(body.topup_id ?? "").trim();
  if (!topupId) throw new Error("Missing top-up id.");

  const { data: topup } = await ctx.supabase
    .from("station_fee_topups")
    .select("id, owner_id, status, provider_checkout_id")
    .eq("id", topupId)
    .eq("owner_id", ctx.userId)
    .maybeSingle();
  if (!topup) throw new Error("Top-up not found.");

  let status = String(topup.status);
  if (status === "pending" && topup.provider_checkout_id) {
    const res = await fetch(
      `https://api.paymongo.com/v1/checkout_sessions/${topup.provider_checkout_id}`,
      { headers: { Authorization: paymongoAuthHeader(ctx.secretKey) } },
    );
    if (res.ok) {
      const attr = (await res.json())?.data?.attributes;
      const sessionStatus = String(attr?.status ?? "").toLowerCase();
      const payments = Array.isArray(attr?.payments) ? attr.payments : [];
      const paid = sessionStatus === "paid" ||
        payments.some((p: { attributes?: { status?: string } }) =>
          String(p?.attributes?.status ?? "").toLowerCase() === "paid"
        );
      if (paid) {
        const { error } = await ctx.supabase.rpc("credit_wallet_topup", { p_topup_id: topupId });
        if (error) throw new Error(error.message);
        status = "paid";
      } else if (["expired", "cancelled", "canceled", "failed"].includes(sessionStatus)) {
        const failed = sessionStatus === "expired" ? "expired" : "failed";
        await ctx.supabase
          .from("station_fee_topups")
          .update({ status: failed })
          .eq("id", topupId)
          .eq("status", "pending");
        status = failed;
      }
    }
  }

  return json(
    {
      verified: status === "paid",
      status,
      balance: await walletBalance(ctx),
      livemode: ctx.livemode,
    },
    corsHeaders,
  );
};
