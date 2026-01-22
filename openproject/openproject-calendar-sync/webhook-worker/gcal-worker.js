/**
 * Cloudflare Worker that receives Google Calendar push notifications and triggers
 * the GitHub Actions workflow for reverse sync (Calendar -> OpenProject).
 *
 * Google Calendar push notifications docs:
 * https://developers.google.com/calendar/api/guides/push
 *
 * Environment variables:
 * - GITHUB_TOKEN: Personal access token with 'repo' scope
 * - GCAL_WEBHOOK_SECRET: Shared secret for verification
 *
 * KV namespace:
 * - GCAL_SYNC_KV: For debouncing and storing channel info
 */

export default {
  async fetch(request, env) {
    // Google sends a sync message when watch is first created - respond 200
    const channelId = request.headers.get("X-Goog-Channel-ID");
    const resourceState = request.headers.get("X-Goog-Resource-State");

    // Log all requests for debugging
    console.log(`Received request: ${request.method} ${request.url}`);
    console.log(`Channel ID: ${channelId}, Resource State: ${resourceState}`);

    // Verify this is a legitimate Google Calendar notification
    if (!channelId || !resourceState) {
      // Could be a verification request - check for token
      const url = new URL(request.url);
      const token = url.searchParams.get("token");

      if (token === env.GCAL_WEBHOOK_SECRET) {
        return new Response("OK", { status: 200 });
      }

      return new Response("Missing Google Calendar headers", { status: 400 });
    }

    // Verify the channel token matches our secret
    const channelToken = request.headers.get("X-Goog-Channel-Token");
    if (channelToken !== env.GCAL_WEBHOOK_SECRET) {
      console.error("Invalid channel token");
      return new Response("Unauthorized", { status: 401 });
    }

    // Handle sync message (sent when watch is first created)
    if (resourceState === "sync") {
      console.log("Received sync confirmation for channel:", channelId);
      return new Response("Sync acknowledged", { status: 200 });
    }

    // Only process actual changes (exists = event created/updated, not_exists = deleted)
    if (resourceState !== "exists" && resourceState !== "not_exists") {
      console.log(`Ignoring resource state: ${resourceState}`);
      return new Response("Ignored", { status: 200 });
    }

    // Debounce: only trigger once per 10 seconds per channel
    const debounceKey = `debounce:${channelId}`;
    const lastTrigger = await env.GCAL_SYNC_KV.get(debounceKey);
    const now = Date.now();

    if (lastTrigger && now - parseInt(lastTrigger) < 10000) {
      console.log("Debouncing: too soon since last trigger");
      return new Response("Debounced", { status: 200 });
    }

    // Update debounce timestamp
    await env.GCAL_SYNC_KV.put(debounceKey, String(now), { expirationTtl: 60 });

    try {
      // Trigger GitHub Actions workflow via repository_dispatch
      const response = await fetch(
        "https://api.github.com/repos/nickmeinhold/xdeca-infra/dispatches",
        {
          method: "POST",
          headers: {
            Accept: "application/vnd.github.v3+json",
            Authorization: `Bearer ${env.GITHUB_TOKEN}`,
            "Content-Type": "application/json",
            "User-Agent": "GCal-Reverse-Sync-Worker",
          },
          body: JSON.stringify({
            event_type: "gcal_event_changed",
            client_payload: {
              channel_id: channelId,
              resource_state: resourceState,
              resource_id: request.headers.get("X-Goog-Resource-ID"),
            },
          }),
        }
      );

      if (!response.ok) {
        const error = await response.text();
        console.error("GitHub API error:", error);
        return new Response(`GitHub API error: ${response.status}`, { status: 500 });
      }

      console.log("Reverse sync triggered successfully");
      return new Response("Reverse sync triggered", { status: 200 });
    } catch (error) {
      console.error("Worker error:", error);
      return new Response(`Error: ${error.message}`, { status: 500 });
    }
  },
};
