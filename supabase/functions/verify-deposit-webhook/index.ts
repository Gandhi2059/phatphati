// Supabase Edge Function: Verify Deposit Webhook
// Handles production payment gateway webhook notifications idempotently.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json();
    const { idempotency_key, round_id, auction_id, buyer_id, amount, provider_transaction_id } = body;

    if (!idempotency_key || !round_id || !auction_id || !buyer_id || !amount) {
      return new Response(
        JSON.stringify({ error: "Missing required payment parameter" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Check idempotency: If payment already exists for key, return existing payment record
    const { data: existingPayment } = await supabase
      .from("deposit_payments")
      .select("*")
      .eq("idempotency_key", idempotency_key)
      .single();

    if (existingPayment) {
      return new Response(
        JSON.stringify({
          message: "Payment request already processed (Idempotent replay)",
          payment: existingPayment,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Fetch Round to verify deposit status
    const { data: round, error: roundError } = await supabase
      .from("auction_rounds")
      .select("*, auctions(title)")
      .eq("id", round_id)
      .single();

    if (roundError || !round) {
      return new Response(
        JSON.stringify({ error: "Auction round not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (round.status !== "winner_pending_deposit") {
      return new Response(
        JSON.stringify({ error: "Round is not accepting deposit payments" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Atomically Record Deposit Payment
    const { data: paymentRecord, error: paymentError } = await supabase
      .from("deposit_payments")
      .insert([
        {
          idempotency_key,
          round_id,
          auction_id,
          buyer_id,
          amount,
          provider_transaction_id: provider_transaction_id || `TXN_${Date.now()}`,
          status: "verified",
          paid_at: new Date().toISOString(),
        },
      ])
      .select()
      .single();

    if (paymentError) {
      throw paymentError;
    }

    // 4. Update Auction Round & Parent Auction to SECURED
    await supabase
      .from("auction_rounds")
      .update({ status: "secured", updated_at: new Date().toISOString() })
      .eq("id", round_id);

    await supabase
      .from("auctions")
      .update({ status: "secured", updated_at: new Date().toISOString() })
      .eq("id", auction_id);

    const auctionTitle = round.auctions?.title || "Auction";

    // 5. Send Successful Deposit Notification to Buyer
    await supabase.from("notifications").insert([
      {
        user_id: buyer_id,
        type: "deposit_paid",
        title: "✅ DEPOSIT CONFIRMED",
        message: `Your 10% deposit of Rs. ${amount.toLocaleString()} has been received for ${auctionTitle}. Winning Bid: Rs. ${round.winning_bid.toLocaleString()}. Your winning position is now secured.`,
        entity_type: "auction",
        entity_id: auction_id,
      },
    ]);

    // 6. Record Audit Log Entry
    await supabase.from("audit_logs").insert([
      {
        actor_id: buyer_id,
        action: "DEPOSIT_PAID",
        entity_type: "deposit_payment",
        entity_id: paymentRecord.id,
        details: {
          round_id,
          auction_id,
          amount,
          idempotency_key,
          provider_transaction_id,
        },
      },
    ]);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Deposit verified and auction secured successfully",
        payment: paymentRecord,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
