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

async function signPayload(payload: unknown, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(JSON.stringify(payload)));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function createQrSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  const webhookSecret = Deno.env.get("YENGAPAY_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookSecret || !supabaseUrl || !serviceKey) {
    console.error("YengaPay webhook configuration is incomplete.");
    return json({ error: "Configuration serveur manquante." }, 500);
  }

  try {
    const payload = await req.json();
    const receivedHash = req.headers.get("x-webhook-hash") ?? "";
    const expectedHash = await signPayload(payload, webhookSecret);
    if (!safeHexEqual(receivedHash, expectedHash)) {
      return json({ error: "Signature webhook invalide." }, 401);
    }

    if (payload?.paymentStatus !== "DONE") {
      return json({ received: true, ignored: true });
    }
    const reference = typeof payload.reference === "string" ? payload.reference : "";
    const transactionId = typeof payload.transId === "string" ? payload.transId : "";
    const grossAmount = payload.paymentGrossAmount;
    if (!reference || !transactionId || !Number.isInteger(grossAmount) || payload.currency !== "XOF") {
      return json({ error: "Données de paiement invalides." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: ticket, error: lookupError } = await supabase
      .from("tickets")
      .select("id, price, status, transaction_id")
      .eq("id", reference)
      .maybeSingle();
    if (lookupError) throw lookupError;
    if (!ticket) {
      const { data: orders, error: orderError } = await supabase
        .from("marketplace_orders")
        .select("id, total_amount, status, provider_transaction_id")
        .eq("id", reference)
        .maybeSingle();
      if (orderError) throw orderError;
      if (!orders) return json({ error: "Commande inconnue." }, 404);
      if (orders.status === "paid" && orders.provider_transaction_id === transactionId) {
        return json({ received: true, duplicate: true });
      }
      const { data: result, error: confirmError } = await supabase.rpc("confirm_marketplace_order", {
        p_order_id: orders.id,
        p_transaction_id: transactionId,
        p_amount: grossAmount,
      });
      if (confirmError) throw confirmError;
      if (result === "paid" || result === "duplicate") return json({ received: true, duplicate: result === "duplicate" });
      if (result === "refund_required") {
        console.error("Paid marketplace order requires manual refund:", { orderId: reference });
        return json({ received: true, review_required: true });
      }
      if (result === "amount_mismatch") return json({ error: "Le montant payé ne correspond pas à la commande." }, 409);
      if (result === "not_pending") return json({ error: "Cette commande ne peut plus être payée." }, 409);
      return json({ error: "Commande inconnue." }, 404);
    }

    if (ticket.status === "paid" && ticket.transaction_id === transactionId) {
      return json({ received: true, duplicate: true });
    }
    if (ticket.status === "refund_required" && ticket.transaction_id === transactionId) {
      return json({ received: true, review_required: true });
    }
    if (ticket.status !== "pending") {
      return json({ error: "Cette commande ne peut plus être payée." }, 409);
    }
    if (Number(ticket.price) !== grossAmount) {
      console.error("YengaPay amount does not match ticket price:", { ticketId: ticket.id });
      return json({ error: "Le montant payé ne correspond pas au billet." }, 409);
    }

    const { data: result, error: confirmError } = await supabase.rpc("confirm_ticket_payment", {
      p_ticket_id: ticket.id,
      p_transaction_id: transactionId,
      p_amount: grossAmount,
    });
    if (confirmError) throw confirmError;
    if (result === "paid" || result === "duplicate") {
      const { error: qrError } = await supabase
        .from("tickets")
        .update({ qr_token_secret: createQrSecret() })
        .eq("id", ticket.id)
        .eq("status", "paid")
        .is("qr_token_secret", null);
      if (qrError) throw qrError;
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
