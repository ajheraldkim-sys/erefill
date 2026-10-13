import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type PaymentMethod = "gcash" | "maya" | "card";

const paymongoMethod = (method: PaymentMethod) =>
  method === "maya" ? "paymaya" : method;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const paymongoSecretKey = Deno.env.get("PAYMONGO_SECRET_KEY") || "sk_test_DAyQ6miWLgJTQPqFVqMU8NrV";
    const appBaseUrl = Deno.env.get("APP_PUBLIC_URL") || Deno.env.get("SUPABASE_URL") || "https://ormmjxtbwosnraijphra.supabase.co";

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing payment service configuration.");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) throw new Error("Missing authorization token.");

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData.user) throw new Error("Invalid session.");

    const body = await req.json();
    const action = String(body.action ?? "").trim().toLowerCase();
    const orderId = String(body.order_id ?? "").trim();
    if (!orderId) throw new Error("Missing order id.");

    // Direct status verification against PayMongo
    if (action === "verify") {
      const { data: order, error: orderError } = await supabase
        .from("orders")
        .select("id, customer_id, payment_status, payment_checkout_id, payment_checkout_url")
        .eq("id", orderId)
        .eq("customer_id", userData.user.id)
        .single();

      if (orderError || !order) throw new Error("Order not found.");

      const currentStatus = String(order.payment_status ?? "").toLowerCase();
      if (["success", "paid", "succeeded"].includes(currentStatus)) {
        return new Response(
          JSON.stringify({ verified: true, payment_status: "success" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
        );
      }

      const checkoutId = order.payment_checkout_id;
      if (checkoutId) {
        try {
          const pmRes = await fetch(`https://api.paymongo.com/v1/checkout_sessions/${checkoutId}`, {
            method: "GET",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Basic ${btoa(`${paymongoSecretKey}:`)}`,
            },
          });

          if (pmRes.ok) {
            const pmData = await pmRes.json();
            const attr = pmData?.data?.attributes;
            const pmStatus = String(attr?.status ?? "").toLowerCase();
            const payments = Array.isArray(attr?.payments) ? attr.payments : [];
            const isPaid =
              pmStatus === "paid" ||
              payments.some((p: Record<string, unknown>) => {
                const pAttr = p?.attributes as Record<string, unknown> | undefined;
                return String(pAttr?.status ?? "").toLowerCase() === "paid";
              });

            if (isPaid) {
              await supabase
                .from("orders")
                .update({
                  payment_status: "success",
                  payment_error: null,
                  updated_at: new Date().toISOString(),
                })
                .eq("id", orderId);

              await supabase
                .from("payment_checkouts")
                .update({ status: "paid", updated_at: new Date().toISOString() })
                .eq("provider_checkout_id", checkoutId);

              return new Response(
                JSON.stringify({ verified: true, payment_status: "success" }),
                { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
              );
            } else if (["expired", "cancelled", "canceled", "failed"].includes(pmStatus)) {
              await supabase
                .from("orders")
                .update({
                  payment_status: "failed",
                  payment_error: `Payment ${pmStatus}`,
                  updated_at: new Date().toISOString(),
                })
                .eq("id", orderId)
                .neq("payment_status", "success");

              return new Response(
                JSON.stringify({ verified: false, payment_status: "failed" }),
                { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
              );
            }
          }
        } catch (checkErr) {
          console.error("PayMongo direct status check error:", checkErr);
        }
      }

      return new Response(
        JSON.stringify({ verified: false, payment_status: order.payment_status ?? "processing" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const forceNewCheckout = body.force_new_checkout === true;
    let paymentMethod = String(body.payment_method ?? "").trim().toLowerCase() as PaymentMethod;
    if ((paymentMethod as string) === "paymaya") {
      paymentMethod = "maya";
    }

    if (!["gcash", "maya", "card"].includes(paymentMethod)) {
      throw new Error("Unsupported payment method.");
    }

    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, customer_id, owner_id, station_name, customer_name, customer_phone, total_amount, status, payment_status, payment_method, payment_checkout_id, payment_checkout_url")
      .eq("id", orderId)
      .eq("customer_id", userData.user.id)
      .single();

    if (orderError || !order) throw new Error("Order not found.");
    const orderMethod = String(order.payment_method ?? "").trim().toLowerCase().replaceAll("paymaya", "maya");
    if (orderMethod !== paymentMethod) {
      throw new Error("Payment method does not match the order.");
    }
    if (order.payment_status === "success") {
      throw new Error("This order is already paid.");
    }
    if (order.status === "cancelled" || order.status === "delivered") {
      throw new Error("This order is no longer eligible for payment.");
    }

    // 1. If order already has an active checkout URL (and not in a failed/expired terminal status), return it immediately
    const isTerminalPaymentStatus = ["failed", "expired", "refunded"].includes((order.payment_status ?? "").toLowerCase());
    if (!forceNewCheckout && !isTerminalPaymentStatus && order.payment_checkout_url) {
      return new Response(
        JSON.stringify({
          checkout_url: order.payment_checkout_url,
          checkout_id: order.payment_checkout_id ?? "",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // 2. Check if an active checkout session already exists in payment_checkouts table
    const { data: existingCheckout } = await supabase
      .from("payment_checkouts")
      .select("provider_checkout_id, checkout_url, status")
      .eq("order_id", orderId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (
      !forceNewCheckout &&
      existingCheckout &&
      existingCheckout.checkout_url &&
      !["failed", "expired", "cancelled", "canceled", "paid", "succeeded", "completed"].includes(
        (existingCheckout.status ?? "").toLowerCase()
      )
    ) {
      // Re-link to orders table if missing
      await supabase
        .from("orders")
        .update({
          payment_checkout_id: existingCheckout.provider_checkout_id,
          payment_checkout_url: existingCheckout.checkout_url,
          payment_status: "processing",
        })
        .eq("id", orderId);

      return new Response(
        JSON.stringify({
          checkout_url: existingCheckout.checkout_url,
          checkout_id: existingCheckout.provider_checkout_id,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // A checkout URL can become inaccessible on the device even while the
    // gateway still labels it active. Retire previous session cleanly.
    if (forceNewCheckout) {
      await supabase
        .from("payment_checkouts")
        .update({ status: "expired", updated_at: new Date().toISOString() })
        .eq("order_id", orderId)
        .neq("status", "paid");

      await supabase
        .from("orders")
        .update({
          payment_status: "pending",
          payment_checkout_id: null,
          payment_checkout_url: null,
          payment_error: "Previous checkout was reopened.",
        })
        .eq("id", orderId)
        .neq("payment_status", "success");
    }

    const { data: isAvailable, error: availabilityError } = await supabase.rpc(
      "is_station_payment_method_available",
      {
        p_owner_id: order.owner_id,
        p_payment_method: paymentMethod,
      },
    );
    if (availabilityError) throw availabilityError;
    if (isAvailable !== true) {
      throw new Error("This payment method is not available for this station.");
    }

    const amount = Math.round(Number(order.total_amount) * 100);
    if (!Number.isFinite(amount) || amount < 100) {
      throw new Error("Invalid order amount. Minimum is PHP 1.00.");
    }

    let baseUrl = (appBaseUrl || supabaseUrl).trim();
    if (!baseUrl.startsWith("http://") && !baseUrl.startsWith("https://")) {
      baseUrl = supabaseUrl;
    }
    baseUrl = baseUrl.replace(/\/+$/, "");

    const isSupabaseHost = baseUrl.includes("supabase.co");
    const successUrl = isSupabaseHost
      ? `${baseUrl}/functions/v1/payment-callback?order_id=${encodeURIComponent(orderId)}&status=success`
      : `${baseUrl}/payment/success?order_id=${encodeURIComponent(orderId)}`;
    const cancelUrl = isSupabaseHost
      ? `${baseUrl}/functions/v1/payment-callback?order_id=${encodeURIComponent(orderId)}&status=cancel`
      : `${baseUrl}/payment/cancel?order_id=${encodeURIComponent(orderId)}`;
    const referenceNumber = orderId.replaceAll("-", "").slice(0, 22);

    const customerEmail = userData.user.email?.trim() || undefined;
    const customerName = (order.customer_name ?? userData.user.user_metadata?.full_name ?? "").trim() || undefined;
    const customerPhone = (order.customer_phone ?? "").trim() || undefined;

    const billingInfo: Record<string, string> = {};
    if (customerName) billingInfo.name = customerName;
    if (customerEmail) billingInfo.email = customerEmail;
    if (customerPhone) billingInfo.phone = customerPhone;

    const paymongoResponse = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${paymongoSecretKey}:`)}`,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            description: `eRefill order ${orderId}`,
            reference_number: referenceNumber,
            line_items: [
              {
                currency: "PHP",
                amount,
                name: order.station_name ?? "eRefill order",
                quantity: 1,
              },
            ],
            payment_method_types: [paymongoMethod(paymentMethod)],
            success_url: successUrl,
            cancel_url: cancelUrl,
            send_email_receipt: Boolean(customerEmail),
            show_description: true,
            show_line_items: true,
            ...(Object.keys(billingInfo).length > 0 ? { billing: billingInfo } : {}),
          },
        },
      }),
    });

    const paymongoJson = await paymongoResponse.json();
    if (!paymongoResponse.ok) {
      console.error("PayMongo checkout error", paymongoJson);
      const detailMsg = paymongoJson?.errors?.[0]?.detail;
      throw new Error(detailMsg ? `Payment gateway error: ${detailMsg}` : "Payment gateway rejected the checkout request.");
    }

    const checkout = paymongoJson.data;
    const checkoutUrl = checkout?.attributes?.checkout_url;
    if (!checkout?.id || !checkoutUrl) {
      throw new Error("Payment gateway did not return a checkout URL.");
    }

    const { error: recordError } = await supabase.rpc("record_payment_checkout", {
      p_order_id: order.id,
      p_customer_id: order.customer_id,
      p_owner_id: order.owner_id,
      p_payment_method: paymentMethod,
      p_provider_checkout_id: checkout.id,
      p_checkout_url: checkoutUrl,
      p_amount: Number(order.total_amount),
      p_status: checkout.attributes?.status ?? "pending",
      p_raw_response: paymongoJson,
    });
    if (recordError) throw recordError;

    return new Response(
      JSON.stringify({ checkout_url: checkoutUrl, checkout_id: checkout.id }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Payment error" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      },
    );
  }
});
