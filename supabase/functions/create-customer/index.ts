// Edge Function: create-customer
// Lets the business owner (admin) open a B2B customer account.
// Creating an auth user requires the service-role key, which must never live in
// the browser — so it is done here, after verifying the caller is an admin.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    // Verify the caller is an authenticated admin.
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: uErr } = await caller.auth.getUser();
    if (uErr || !user) return json({ error: "unauthorized" }, 401);
    const { data: prof } = await caller
      .from("profiles").select("role").eq("id", user.id).single();
    if (!prof || prof.role !== "admin") return json({ error: "forbidden" }, 403);

    const body = await req.json();
    const { email, password, business_name, contact_name, phone, discount_pct } = body ?? {};
    if (!email || !password) return json({ error: "email and password are required" }, 400);
    if (String(password).length < 6) return json({ error: "password must be at least 6 characters" }, 400);

    // Create the auth user with the service role.
    const admin = createClient(url, serviceKey);
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { business_name, contact_name, phone },
    });
    if (cErr || !created?.user) return json({ error: cErr?.message ?? "could not create user" }, 400);

    // Fill in the profile row (created by the on_auth_user_created trigger).
    const { error: pErr } = await admin.from("profiles").update({
      role: "customer",
      business_name: business_name ?? null,
      contact_name: contact_name ?? null,
      phone: phone ?? null,
      discount_pct: Number(discount_pct) || 0,
      active: true,
    }).eq("id", created.user.id);
    if (pErr) return json({ error: pErr.message }, 400);

    return json({ ok: true, id: created.user.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
