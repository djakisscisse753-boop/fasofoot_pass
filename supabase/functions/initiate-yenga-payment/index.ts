import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Configuration serveur manquante: ${name}`);
  return value;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  let ticketId: string | undefined;
  let paymentRequestStarted = false;
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Service indisponible." }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const input = await req.json();
    const matchId = typeof input.match_id === "string" ? input.match_id : "";
    const categoryName = typeof input.category_name === "string" ? input.category_name : "";
    const customerName = typeof input.customer_name === "string" ? input.customer_name.trim() : "";
    const phoneNumber = typeof input.phone_number === "string" ? input.phone_number.trim() : "";

    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(matchId)) {
      return json({ error: "Match invalide." }, 400);
    }
    if (customerName.length < 2 || customerName.length > 100) {
      return json({ error: "Le nom doit contenir entre 2 et 100 caractères." }, 400);
    }
    if (!/^(?:\+?226)?[0-9]{8}$/.test(phoneNumber)) {
      return json({ error: "Numéro burkinabè invalide." }, 400);
    }

    const authorization = req.headers.get("Authorization");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!authorization?.startsWith("Bearer ") || !anonKey) {
      return json({ error: "Connexion requise." }, 401);
    }
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Session invalide." }, 401);

    const { data: reservation, error: reserveError } = await admin.rpc("reserve_ticket", {
      p_match_id: matchId,
      p_category_name: categoryName,
      p_customer_name: customerName,
      p_customer_phone: phoneNumber,
      p_user_id: authData.user.id,
    });
    if (reserveError) throw reserveError;
    if (!reservation?.success) {
      return json({ error: reservation?.message ?? "Impossible de réserver cette place." }, 409);
    }
    const reservedTicketId = reservation.ticket_id;
    const ticketPrice = Number(reservation.price);
    if (typeof reservedTicketId !== "string" || !Number.isInteger(ticketPrice) || ticketPrice < 1) {
      throw new Error("Invalid reservation response");
    }
    ticketId = reservedTicketId;

    const apiBase = (Deno.env.get("YENGAPAY_BASE_URL") ?? "https://api.yengapay.com/api/v1")
      .replace(/\/$/, "");
    const groupId = Deno.env.get("YENGAPAY_GROUP_ID")?.trim() ||
      Deno.env.get("YENGA_ORG_ID")?.trim() ||
      requiredEnv("YENGAPAY_GROUP_ID");
    const projectId = Deno.env.get("YENGAPAY_PROJECT_ID")?.trim() ||
      Deno.env.get("YENGA_PROJECT_ID")?.trim() ||
      requiredEnv("YENGA_PROJECT_ID");
    const apiKey = Deno.env.get("YENGAPAY_API_KEY")?.trim() ||
      Deno.env.get("YENGA_API_KEY")?.trim() ||
      requiredEnv("YENGAPAY_API_KEY");
    paymentRequestStarted = true;
    const paymentResponse = await fetch(
      `${apiBase}/groups/${encodeURIComponent(groupId)}/payment-intent/${encodeURIComponent(projectId)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-api-key": apiKey },
        body: JSON.stringify({
          paymentAmount: ticketPrice,
          reference: reservedTicketId,
          articles: [{
            title: `Billet ${categoryName}`,
            description: `Accès au match ${matchId}`,
            price: ticketPrice,
          }],
        }),
        signal: AbortSignal.timeout(15000),
      },
    );
    const paymentData = await paymentResponse.json().catch(() => ({}));
    if (!paymentResponse.ok) {
      console.error(`YengaPay error: status=${paymentResponse.status}`, JSON.stringify(paymentData));
      if (paymentResponse.status >= 500) {
        return json({
          success: false,
          payment_pending: true,
          error: "YengaPay n’a pas confirmé la création du paiement. Vérifie ton compte Mobile Money avant de réessayer.",
        });
      }
      const { error: ticketUpdateError } = await admin
        .from("tickets")
        .update({ status: "failed" })
        .eq("id", reservedTicketId)
        .eq("status", "pending");
      if (ticketUpdateError) throw ticketUpdateError;
      const errorDetail = paymentData?.error?.message ?? paymentData?.message ?? `Erreur YengaPay (${paymentResponse.status})`;
      return json({ error: errorDetail }, 502);
    }

    const checkoutUrl = paymentData?.checkoutPageUrlWithPaymentToken;
    if (typeof checkoutUrl !== "string") {
      return json({
        success: false,
        payment_pending: true,
        error: "YengaPay a répondu sans lien de paiement. Vérifie ton compte avant de relancer la commande.",
      });
    }
    const parsedUrl = new URL(checkoutUrl);
    const trustedYengaHost = parsedUrl.hostname === "yengapay.com" ||
      parsedUrl.hostname.endsWith(".yengapay.com");
    if (parsedUrl.protocol !== "https:" || !trustedYengaHost) {
      return json({
        success: false,
        payment_pending: true,
        error: "YengaPay a retourné un lien non vérifiable. Vérifie ton compte avant de relancer la commande.",
      });
    }

      return json({ success: true, ticket_id: reservedTicketId, checkout_url: checkoutUrl });
  } catch (error) {
    if (ticketId && !paymentRequestStarted) {
      await admin.from("tickets").update({ status: "failed" }).eq("id", ticketId).eq("status", "pending");
    }
    console.error("YengaPay checkout initialization failed:", error);
    const errString = error instanceof Error ? error.message : String(error);
    if (ticketId && paymentRequestStarted) {
      return json({
        success: false,
        payment_pending: true,
        error: `Le statut du paiement est incertain (${errString}). Vérifie ton compte Mobile Money avant de réessayer.`,
      });
    }
    return json({ error: `Impossible de démarrer le paiement: ${errString}` }, 500);
  }
});
