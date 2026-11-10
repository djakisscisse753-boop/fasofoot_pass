import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: "Service indisponible." }, 500);
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Session invalide." }, 401);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  let orderId: string | undefined;
  try {
    const input = await req.json();
    const phone = typeof input.phone_number === "string"
      ? input.phone_number.trim().replace(/[\s-]/g, "")
      : "";
    const customerName = typeof input.customer_name === "string"
      ? input.customer_name.trim()
      : null;
    if (!/^(?:\+?226)?[0-9]{8}$/.test(phone)) return json({ error: "Numéro burkinabè invalide." }, 400);
    if (!Array.isArray(input.items) || input.items.length < 1 || input.items.length > 20) {
      return json({ error: "Le panier est vide ou trop volumineux." }, 400);
    }

    const { data: reservations, error: reserveError } = await admin.rpc("reserve_marketplace_order", {
      p_user_id: authData.user.id,
      p_phone: phone,
      p_items: input.items,
      p_customer_name: customerName,
    });
    if (reserveError) {
      console.error("Marketplace order reservation rejected:", reserveError.message);
      return json({ error: "Réservation impossible : vérifiez le stock et les coordonnées de remise du club." }, 409);
    }
    const reservation = Array.isArray(reservations) ? reservations[0] : reservations;
    orderId = reservation?.order_id;
    const amount = Number(reservation?.total_amount);
    if (typeof orderId !== "string" || !Number.isSafeInteger(amount) || amount <= 0) {
      throw new Error("Invalid reservation response");
    }

    const apiBase = (Deno.env.get("YENGAPAY_BASE_URL") ?? "https://api.yengapay.com/api/v1").replace(/\/$/, "");
    const groupId = Deno.env.get("YENGAPAY_GROUP_ID")?.trim() || Deno.env.get("YENGA_ORG_ID")?.trim();
    const projectId = Deno.env.get("YENGAPAY_PROJECT_ID")?.trim() || Deno.env.get("YENGA_PROJECT_ID")?.trim();
    const apiKey = Deno.env.get("YENGAPAY_API_KEY")?.trim() || Deno.env.get("YENGA_API_KEY")?.trim();
    if (!groupId || !projectId || !apiKey) throw new Error("YengaPay configuration is incomplete");

    const { data: items, error: itemsError } = await admin.from("marketplace_order_items")
      .select("product_title, unit_price, quantity").eq("order_id", orderId);
    if (itemsError) throw itemsError;
    const paymentResponse = await fetch(
      `${apiBase}/groups/${encodeURIComponent(groupId)}/payment-intent/${encodeURIComponent(projectId)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-api-key": apiKey },
        body: JSON.stringify({
          paymentAmount: amount,
          reference: orderId,
          articles: (items ?? []).map((item) => ({
            title: item.product_title,
            description: `Quantité : ${item.quantity}`,
            price: Number(item.unit_price) * Number(item.quantity),
          })),
        }),
        signal: AbortSignal.timeout(15000),
      },
    );
    const paymentData = await paymentResponse.json().catch(() => ({}));
    const checkoutUrl = paymentData?.checkoutPageUrlWithPaymentToken;
    if (!paymentResponse.ok || typeof checkoutUrl !== "string") {
      await admin.rpc("fail_marketplace_order", { p_order_id: orderId });
      orderId = undefined;
      return json({ error: paymentData?.error?.message ?? "YengaPay n'a pas pu créer le paiement." }, 502);
    }
    const parsedUrl = new URL(checkoutUrl);
    if (parsedUrl.protocol !== "https:" || !(parsedUrl.hostname === "yengapay.com" || parsedUrl.hostname.endsWith(".yengapay.com"))) {
      await admin.rpc("fail_marketplace_order", { p_order_id: orderId });
      orderId = undefined;
      return json({ error: "Lien de paiement YengaPay invalide." }, 502);
    }
    return json({ success: true, order_id: orderId, checkout_url: checkoutUrl });
  } catch (error) {
    if (orderId) await admin.rpc("fail_marketplace_order", { p_order_id: orderId });
    console.error("Marketplace payment initialization failed:", error);
    return json({ error: "Impossible de démarrer le paiement. Réessaie plus tard." }, 500);
  }
});
