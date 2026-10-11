import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (req) => {
  const url = new URL(req.url);
  const orderId = url.searchParams.get("order_id") ?? "";
  const status = url.searchParams.get("status") ?? "success";
  const isSuccess = status === "success";

  const deepLink = `io.supabase.erefill://payment-callback?order_id=${encodeURIComponent(orderId)}&status=${encodeURIComponent(status)}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>eRefill Payment</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      background: #F8FAFC;
      color: #0F172A;
      padding: 20px;
    }
    .card {
      background: #FFFFFF;
      padding: 36px 28px;
      border-radius: 24px;
      box-shadow: 0 12px 32px rgba(15, 23, 42, 0.06);
      max-width: 400px;
      width: 100%;
      text-align: center;
      border: 1px solid #E2E8F0;
    }
    .icon {
      width: 68px;
      height: 68px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 20px;
      font-size: 32px;
      font-weight: bold;
    }
    .success {
      background: #ECFDF5;
      color: #10B981;
      border: 2px solid #A7F3D0;
    }
    .cancel {
      background: #FEF2F2;
      color: #EF4444;
      border: 2px solid #FECACA;
    }
    h1 {
      font-size: 22px;
      font-weight: 800;
      margin-bottom: 8px;
      letter-spacing: -0.02em;
    }
    p {
      font-size: 14px;
      color: #64748B;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .btn {
      display: inline-block;
      width: 100%;
      padding: 14px 20px;
      background: #0284C7;
      color: #FFFFFF;
      text-decoration: none;
      border-radius: 14px;
      font-weight: 700;
      font-size: 15px;
      transition: background 0.15s ease;
    }
    .btn:active {
      background: #0369A1;
    }
    .subtext {
      margin-top: 16px;
      font-size: 12px;
      color: #94A3B8;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon ${isSuccess ? 'success' : 'cancel'}">
      ${isSuccess ? '✓' : '✕'}
    </div>
    <h1>${isSuccess ? 'Payment Successful!' : 'Payment Cancelled'}</h1>
    <p>
      ${isSuccess
        ? 'Your online payment was verified. Redirecting you back to eRefill...'
        : 'Your payment process was cancelled. You can retry payment in the app.'}
    </p>
    <a href="${deepLink}" class="btn">Open eRefill App</a>
    <p class="subtext">If the app does not open automatically, tap the button above.</p>
  </div>
  <script>
    setTimeout(function() {
      window.location.href = "${deepLink}";
    }, 1000);
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store, no-cache, must-revalidate",
    },
    status: 200,
  });
});

