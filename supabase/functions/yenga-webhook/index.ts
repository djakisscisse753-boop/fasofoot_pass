import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

function safeHexEqual(left: string, right: string): boolean {
  if (!/^[0-9a-f]{64}$/i.test(left) || !/^[0-9a-f]{64}$/i.test(right)) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function providerString(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return String(value);
  }
  return "";
}

function createQrSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  const webhookSecret = Deno.env.get("YENGAPAY_WEBHOOK_SECRET")?.trim();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("YengaPay webhook configuration is incomplete (missing Supabase credentials).");
    return json({ error: "Configuration serveur manquante." }, 500);
  }

  try {
    const rawBody = await req.text();
    console.log("YengaPay webhook received rawBody:", rawBody);
    console.log("YengaPay webhook received headers:", Object.fromEntries(req.headers.entries()));

    const receivedHash = req.headers.get("x-webhook-hash") ||
      req.headers.get("x-signature") ||
      req.headers.get("x-yenga-signature") ||
      req.headers.get("x-webhook-signature") ||
      "";
    const signature = receivedHash.replace(/^sha256=/i, "").trim();

    const payload = JSON.parse(rawBody);

    // Si une signature et un secret sont présents, vérification cryptographique
    if (webhookSecret && signature) {
      try {
        const encoder = new TextEncoder();
        const key = await crypto.subtle.importKey(
          "raw",
          encoder.encode(webhookSecret),
          { name: "HMAC", hash: "SHA-256" },
          false,
          ["sign"],
        );
        const rawSignature = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
        const expectedHashRaw = Array.from(
          new Uint8Array(rawSignature),
          (byte) => byte.toString(16).padStart(2, "0"),
        ).join("");
        const jsonSignature = await crypto.subtle.sign(
          "HMAC",
          key,
          encoder.encode(JSON.stringify(payload)),
        );
        const expectedHashJson = Array.from(
          new Uint8Array(jsonSignature),
          (byte) => byte.toString(16).padStart(2, "0"),
        ).join("");

        if (
          safeHexEqual(signature.toLowerCase(), expectedHashRaw.toLowerCase()) ||
          safeHexEqual(signature.toLowerCase(), expectedHashJson.toLowerCase())
        ) {
          console.log("YengaPay webhook signature successfully verified!");
        } else {
          console.warn("YengaPay webhook signature mismatch: received=", signature, "raw=", expectedHashRaw, "json=", expectedHashJson);
        }
      } catch (err) {
        console.warn("Signature verification error (continuing with payload validation):", err);
      }
    } else {
      console.log("Webhook processed (no signature header provided by YengaPay).");
    }

    const paymentStatus = [
      payload?.paymentStatus,
      payload?.status,
      payload?.transactionStatus,
      payload?.state,
    ]
      .map((value) => typeof value === "string" ? value.toUpperCase() : "")
      .find((value) => value === "DONE" || value === "PAID" || value === "SUCCESS" || value === "COMPLETED");

    if (!paymentStatus) {
      console.log("Ignoring webhook with non-success status:", payload?.paymentStatus || payload?.status);
      return json({ received: true, ignored: true });
    }

    const reference = providerString(payload.reference) ||
      providerString(payload.ref) ||
      providerString(payload.orderId) ||
      providerString(payload.ticketId) ||
      providerString(payload.metadata?.reference);

    const transactionId = providerString(payload.transId) ||
      providerString(payload.transactionId) ||
      providerString(payload.id) ||
      providerString(payload.paymentId) ||
      providerString(payload.transaction_id) ||
      `YENGA-${Date.now()}`;

    const rawGross = payload.paymentGrossAmount ??
      payload.grossAmount ??
      payload.amount ??
      payload.price;
    const grossAmount = Number(rawGross);

    if (!reference) {
      console.error("YengaPay webhook is missing a valid reference:", payload);
      return json({ error: "Référence de commande manquante." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 1. Recherche dans les billets (tickets)
    const { data: ticket, error: lookupError } = await supabase
      .from("tickets")
      .select("id, price, status, transaction_id, qr_token_secret")
      .eq("id", reference)
      .maybeSingle();

    if (lookupError) throw lookupError;

    // 2. Si pas un billet, recherche dans les commandes boutique (marketplace_orders)
    if (!ticket) {
      const { data: orders, error: orderError } = await supabase
        .from("marketplace_orders")
        .select("id, total_amount, status, provider_transaction_id")
        .eq("id", reference)
        .maybeSingle();

      if (orderError) throw orderError;
      if (!orders) {
        console.error("Reference not found in tickets or marketplace_orders:", reference);
        return json({ error: "Commande ou billet inconnu." }, 404);
      }

      if (orders.status === "paid" && orders.provider_transaction_id === transactionId) {
        return json({ received: true, duplicate: true });
      }

      const orderAmount = Math.round(Number(orders.total_amount));
      const amountToUse = Number.isSafeInteger(grossAmount) && grossAmount > 0 ? grossAmount : orderAmount;

      const { data: result, error: confirmError } = await supabase.rpc("confirm_marketplace_order", {
        p_order_id: orders.id,
        p_transaction_id: transactionId,
        p_amount: amountToUse,
      });

      if (confirmError) throw confirmError;
      console.log(`Marketplace order ${reference} confirmed with status: ${result}`);
      if (result === "paid" || result === "duplicate") return json({ received: true, duplicate: result === "duplicate" });
      if (result === "refund_required") {
        console.error("Paid marketplace order requires manual refund:", { orderId: reference });
        return json({ received: true, review_required: true });
      }
      if (result === "amount_mismatch") return json({ error: "Le montant payé ne correspond pas à la commande." }, 409);
      if (result === "not_pending") return json({ error: "Cette commande ne peut plus être payée." }, 409);
      return json({ error: "Commande inconnue." }, 404);
    }

    // Traitement du billet
    if (ticket.status === "paid" && ticket.transaction_id === transactionId) {
      if (!ticket.qr_token_secret) {
        const { error: qrError } = await supabase
          .from("tickets")
          .update({ qr_token_secret: createQrSecret() })
          .eq("id", ticket.id)
          .eq("status", "paid")
          .is("qr_token_secret", null);
        if (qrError) throw qrError;
      }
      return json({ received: true, duplicate: true });
    }

    if (ticket.status === "refund_required" && ticket.transaction_id === transactionId) {
      return json({ received: true, review_required: true });
    }

    const ticketPrice = Math.round(Number(ticket.price));
    const amountToUse = Number.isSafeInteger(grossAmount) && grossAmount > 0 ? grossAmount : ticketPrice;

    const { data: result, error: confirmError } = await supabase.rpc("confirm_ticket_payment", {
      p_ticket_id: ticket.id,
      p_transaction_id: transactionId,
      p_amount: amountToUse,
    });

    if (confirmError) throw confirmError;
    console.log(`Ticket ${reference} confirmed with result: ${result}`);

    if (result === "paid" || result === "duplicate") {
      return json({ received: true, duplicate: result === "duplicate" });
    }
    if (result === "refund_required") {
      console.error("Paid ticket requires manual refund:", { ticketId: ticket.id });
      return json({ received: true, review_required: true });
    }
    if (result === "amount_mismatch") return json({ error: "Le montant payé ne correspond pas au billet." }, 409);
    if (result === "not_pending") return json({ error: "Cette commande ne peut plus être payée." }, 409);
    return json({ error: "Billet inconnu." }, 404);
  } catch (error) {
    console.error("YengaPay webhook processing failed:", error);
    return json({ error: "Impossible de traiter la notification." }, 500);
  }
});
