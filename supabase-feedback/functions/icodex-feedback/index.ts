import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  Vary: "Origin",
});

type SubmissionCategory = "support" | "feedback" | "feature";

type FeedbackPayload = {
  category?: SubmissionCategory;
  name?: string;
  email?: string;
  message?: string;
  pageContext?: string;
};

const normalizeText = (value: unknown, maxLength: number) => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, maxLength);
};

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders(origin),
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: {
        ...corsHeaders(origin),
        "Content-Type": "application/json",
      },
    });
  }

  try {
    const body = (await req.json()) as FeedbackPayload;
    const category = body.category;
    const name = normalizeText(body.name, 120);
    const email = normalizeText(body.email, 160);
    const message = normalizeText(body.message, 3000);
    const pageContext = normalizeText(body.pageContext, 120);

    if (!category || !["support", "feedback", "feature"].includes(category)) {
      return new Response(JSON.stringify({ error: "Invalid category" }), {
        status: 400,
        headers: {
          ...corsHeaders(origin),
          "Content-Type": "application/json",
        },
      });
    }

    if (!message || message.length < 8) {
      return new Response(JSON.stringify({ error: "Message is too short" }), {
        status: 400,
        headers: {
          ...corsHeaders(origin),
          "Content-Type": "application/json",
        },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "Server is not configured" }), {
        status: 500,
        headers: {
          ...corsHeaders(origin),
          "Content-Type": "application/json",
        },
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const userAgent = normalizeText(req.headers.get("user-agent"), 512);
    const referer = normalizeText(req.headers.get("referer"), 512);

    const { error } = await supabase
      .from("icodex_feedback_submissions")
      .insert({
        category,
        name,
        email,
        message,
        page_context: pageContext,
        user_agent: userAgent,
        metadata: {
          referer,
          origin,
        },
      });

    if (error) {
      console.error("Failed to insert iCodex feedback", error);
      return new Response(JSON.stringify({ error: "Could not save submission" }), {
        status: 500,
        headers: {
          ...corsHeaders(origin),
          "Content-Type": "application/json",
        },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: {
        ...corsHeaders(origin),
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    console.error("Unexpected iCodex feedback error", error);
    return new Response(JSON.stringify({ error: "Unexpected server error" }), {
      status: 500,
      headers: {
        ...corsHeaders(origin),
        "Content-Type": "application/json",
      },
    });
  }
});
