// Deletes the signed-in person's TakaDe account (docs/adr/0016-accounts-on-supabase.md).
//
// The app calls this with the person's own access token. Deleting an auth user needs the
// service-role key, which exists only here, on Supabase, as the SUPABASE_SERVICE_ROLE_KEY
// secret that Supabase provides to every function. It is never shipped in the app.
//
// Not deployed yet. When the project exists:
//   supabase functions deploy delete-account
// JWT verification stays on (the default), so only a signed-in person can call it, and it
// only ever deletes the caller.
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "not_signed_in" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "not_configured" }, 500);

  // Who is asking, read from their own token.
  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error } = await asCaller.auth.getUser();
  if (error || !data.user) return json({ error: "not_signed_in" }, 401);

  // Deleting the user also deletes its linked identities and sessions. Nothing else about
  // the person is stored on Supabase: groups and expenses stay on their phone.
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  // No ids, emails or tokens in logs.
  if (deleteError) {
    console.error("delete-account failed");
    return json({ error: "delete_failed" }, 500);
  }
  return json({ deleted: true }, 200);
});
