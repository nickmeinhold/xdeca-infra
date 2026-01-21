/**
 * Cloudflare Worker that receives OpenProject webhooks and triggers
 * the GitHub Actions workflow for calendar sync.
 *
 * Environment variables (set in Cloudflare dashboard):
 * - GITHUB_TOKEN: Personal access token with 'repo' scope
 * - WEBHOOK_SECRET: Shared secret to verify OpenProject requests (optional)
 */

export default {
  async fetch(request, env) {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // Optional: Verify webhook secret
    if (env.WEBHOOK_SECRET) {
      const authHeader = request.headers.get("X-OpenProject-Signature");
      // OpenProject uses HMAC-SHA256 for webhook signatures
      // For simplicity, we'll use a simple token check
      const url = new URL(request.url);
      const token = url.searchParams.get("token");
      if (token !== env.WEBHOOK_SECRET) {
        return new Response("Unauthorized", { status: 401 });
      }
    }

    try {
      const payload = await request.json();

      // Only trigger for work_package events
      if (!payload.action || !payload.work_package) {
        return new Response("Ignored: not a work_package event", { status: 200 });
      }

      // Only trigger for milestone type changes
      const wpType = payload.work_package?._links?.type?.title?.toLowerCase();
      if (wpType !== "milestone") {
        return new Response("Ignored: not a milestone", { status: 200 });
      }

      // Trigger GitHub Actions workflow via repository_dispatch
      const response = await fetch(
        "https://api.github.com/repos/nickmeinhold/xdeca-infra/dispatches",
        {
          method: "POST",
          headers: {
            Accept: "application/vnd.github.v3+json",
            Authorization: `Bearer ${env.GITHUB_TOKEN}`,
            "Content-Type": "application/json",
            "User-Agent": "OpenProject-Calendar-Sync-Worker",
          },
          body: JSON.stringify({
            event_type: "openproject_milestone_changed",
            client_payload: {
              action: payload.action,
              milestone_id: payload.work_package?.id,
              milestone_subject: payload.work_package?.subject,
            },
          }),
        }
      );

      if (!response.ok) {
        const error = await response.text();
        console.error("GitHub API error:", error);
        return new Response(`GitHub API error: ${response.status}`, { status: 500 });
      }

      return new Response("Sync triggered", { status: 200 });
    } catch (error) {
      console.error("Worker error:", error);
      return new Response(`Error: ${error.message}`, { status: 500 });
    }
  },
};
