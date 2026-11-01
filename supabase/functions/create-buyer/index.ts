// Supabase Edge Function: Create Buyer
// Invoked securely by Admin to provision new Buyer accounts with custom Buyer IDs.

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
    
    // Auth client to verify calling Admin user JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const adminAuthClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user: callingUser }, error: userError } = await adminAuthClient.auth.getUser();
    if (userError || !callingUser) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Invalid session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Service Role client for Admin Auth API & Database bypass
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Verify caller is active Admin
    const { data: callerProfile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("role")
      .eq("id", callingUser.id)
      .single();

    if (profileError || !callerProfile || callerProfile.role !== "admin") {
      return new Response(
        JSON.stringify({ error: "Forbidden: Only active Admin users can create Buyer accounts" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { email, password, full_name, phone, buyer_id } = body;

    if (!email || !password || !full_name || !buyer_id) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: email, password, full_name, buyer_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check if buyer_id is unique
    const { data: existingBuyerId } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .eq("buyer_id", buyer_id)
      .single();

    if (existingBuyerId) {
      return new Response(
        JSON.stringify({ error: `Buyer ID '${buyer_id}' is already registered.` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Create auth user in auth.users
    const { data: authData, error: createAuthError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name, role: "buyer", buyer_id },
    });

    if (createAuthError || !authData.user) {
      return new Response(
        JSON.stringify({ error: createAuthError?.message || "Failed to create authentication user" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const newUserId = authData.user.id;

    // 2. Insert corresponding profile row
    const { data: newProfile, error: insertProfileError } = await supabaseAdmin
      .from("profiles")
      .insert([
        {
          id: newUserId,
          buyer_id,
          email,
          full_name,
          phone: phone || null,
          role: "buyer",
          avatar_url: `https://api.dicebear.com/7.x/bottts/svg?seed=${buyer_id}`,
        },
      ])
      .select()
      .single();

    if (insertProfileError) {
      // Compensating Cleanup: Rollback auth user creation if profile insert fails
      await supabaseAdmin.auth.admin.deleteUser(newUserId);
      return new Response(
        JSON.stringify({ error: `Failed to create buyer profile: ${insertProfileError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Record Audit Log Entry
    await supabaseAdmin.from("audit_logs").insert([
      {
        actor_id: callingUser.id,
        action: "CREATE_BUYER",
        entity_type: "profile",
        entity_id: newUserId,
        details: { buyer_id, email, full_name, phone },
      },
    ]);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Buyer account created successfully",
        buyer: newProfile,
      }),
      { status: 201, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
