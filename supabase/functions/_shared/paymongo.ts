// PayMongo helpers shared by create-payment-checkout and paymongo-webhook.

export type PaymentMethod = "gcash" | "maya" | "card" | "qrph";

export type CheckoutKind = "order" | "wallet_topup";

export const ONLINE_PAYMENT_METHODS: readonly PaymentMethod[] = [
  "gcash",
  "maya",
  "card",
  "qrph",
];

/** The configured PayMongo secret key. There is deliberately no fallback:
 * a missing key must fail loudly instead of silently taking test payments. */
export const paymongoSecretKey = (): string => {
  const key = Deno.env.get("PAYMONGO_SECRET_KEY")?.trim();
  if (!key) throw new Error("Payment gateway is not configured.");
  return key;
};

export const isLiveKey = (key: string): boolean => key.startsWith("sk_live_");

/** PayMongo names Maya `paymaya`; every other method keeps its id. */
export const paymongoMethod = (method: PaymentMethod): string =>
  method === "maya" ? "paymaya" : method;

export const normalizePaymentMethod = (raw: unknown): PaymentMethod | null => {
  let method = String(raw ?? "").trim().toLowerCase();
  if (method === "paymaya") method = "maya";
  return (ONLINE_PAYMENT_METHODS as readonly string[]).includes(method)
    ? method as PaymentMethod
    : null;
};

export const paymongoAuthHeader = (key: string): string =>
  `Basic ${btoa(`${key}:`)}`;
