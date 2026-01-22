import { createServer } from "http";
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Secrets from environment
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET!;
const GCAL_WEBHOOK_SECRET = process.env.GCAL_WEBHOOK_SECRET!;

const PORT = process.env.PORT || 3001;

// Debounce: prevent multiple syncs within 10 seconds
let lastForwardSync = 0;
let lastReverseSync = 0;
const DEBOUNCE_MS = 10000;

function runScript(scriptName: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn("npx", ["tsx", scriptName], {
      cwd: __dirname,
      stdio: "inherit",
      env: process.env,
    });
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Script exited with code ${code}`));
    });
    child.on("error", reject);
  });
}

async function runForwardSync() {
  const now = Date.now();
  if (now - lastForwardSync < DEBOUNCE_MS) {
    console.log("Forward sync debounced");
    return;
  }
  lastForwardSync = now;

  console.log("Running forward sync...");
  try {
    await runScript("sync.ts");
    console.log("Forward sync complete");
  } catch (error) {
    console.error("Forward sync failed:", error);
  }
}

async function runReverseSync() {
  const now = Date.now();
  if (now - lastReverseSync < DEBOUNCE_MS) {
    console.log("Reverse sync debounced");
    return;
  }
  lastReverseSync = now;

  console.log("Running reverse sync...");
  try {
    await runScript("reverse-sync.ts");
    console.log("Reverse sync complete");
  } catch (error) {
    console.error("Reverse sync failed:", error);
  }
}

const server = createServer((req, res) => {
  const url = new URL(req.url || "/", `http://localhost:${PORT}`);

  // Health check
  if (url.pathname === "/health") {
    res.writeHead(200);
    res.end("OK");
    return;
  }

  // OpenProject webhook (forward sync)
  if (url.pathname === "/openproject") {
    const token = url.searchParams.get("token");
    if (token !== WEBHOOK_SECRET) {
      console.log("Invalid OpenProject webhook token");
      res.writeHead(401);
      res.end("Unauthorized");
      return;
    }

    console.log("Received OpenProject webhook");
    // Run async, respond immediately
    runForwardSync();
    res.writeHead(200);
    res.end("OK");
    return;
  }

  // Google Calendar webhook (reverse sync)
  if (url.pathname === "/gcal") {
    const token = url.searchParams.get("token");
    if (token !== GCAL_WEBHOOK_SECRET) {
      console.log("Invalid Google Calendar webhook token");
      res.writeHead(401);
      res.end("Unauthorized");
      return;
    }

    // Google sends a sync message first, ignore it
    const channelId = req.headers["x-goog-channel-id"];
    const resourceState = req.headers["x-goog-resource-state"];
    console.log(`Received Google Calendar webhook: channel=${channelId}, state=${resourceState}`);

    if (resourceState === "sync") {
      res.writeHead(200);
      res.end("OK");
      return;
    }

    // Run async, respond immediately
    runReverseSync();
    res.writeHead(200);
    res.end("OK");
    return;
  }

  res.writeHead(404);
  res.end("Not Found");
});

server.listen(PORT, () => {
  console.log(`Webhook server running on port ${PORT}`);
  console.log("Endpoints:");
  console.log(`  POST /openproject?token=<secret> - OpenProject webhook`);
  console.log(`  POST /gcal?token=<secret> - Google Calendar webhook`);
  console.log(`  GET /health - Health check`);
});
