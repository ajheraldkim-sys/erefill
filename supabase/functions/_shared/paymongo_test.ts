import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  isLiveKey,
  normalizePaymentMethod,
  paymongoMethod,
  paymongoSecretKey,
} from "./paymongo.ts";

Deno.test("missing secret key fails instead of falling back", () => {
  Deno.env.delete("PAYMONGO_SECRET_KEY");
  assertThrows(() => paymongoSecretKey(), Error, "Payment gateway is not configured.");
  Deno.env.set("PAYMONGO_SECRET_KEY", "   ");
  assertThrows(() => paymongoSecretKey(), Error, "Payment gateway is not configured.");
});

Deno.test("configured secret key is returned trimmed", () => {
  Deno.env.set("PAYMONGO_SECRET_KEY", " sk_test_abc ");
  assertEquals(paymongoSecretKey(), "sk_test_abc");
});

Deno.test("live mode follows the key prefix", () => {
  assertEquals(isLiveKey("sk_live_123"), true);
  assertEquals(isLiveKey("sk_test_123"), false);
});

Deno.test("payment methods normalize and map to PayMongo names", () => {
  assertEquals(normalizePaymentMethod(" PayMaya "), "maya");
  assertEquals(normalizePaymentMethod("qrph"), "qrph");
  assertEquals(normalizePaymentMethod("cod"), null);
  assertEquals(paymongoMethod("maya"), "paymaya");
  assertEquals(paymongoMethod("qrph"), "qrph");
});
