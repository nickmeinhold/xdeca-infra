import { google } from "googleapis";
import { randomUUID } from "crypto";

// Configuration from environment
const GOOGLE_CALENDAR_ID = process.env.GOOGLE_CALENDAR_ID!;
const GOOGLE_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_SERVICE_ACCOUNT_JSON!;
const GCAL_WEBHOOK_URL = process.env.GCAL_WEBHOOK_URL!;
const GCAL_WEBHOOK_SECRET = process.env.GCAL_WEBHOOK_SECRET!;

async function getCalendarClient() {
  const credentials = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON);

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/calendar"],
  });

  return google.calendar({ version: "v3", auth });
}

async function stopExistingWatch(channelId: string, resourceId: string) {
  const calendar = await getCalendarClient();

  try {
    await calendar.channels.stop({
      requestBody: {
        id: channelId,
        resourceId: resourceId,
      },
    });
    console.log(`Stopped existing watch: ${channelId}`);
  } catch (error) {
    // Channel might not exist or already expired
    console.log(`Could not stop channel ${channelId}: ${error}`);
  }
}

async function setupWatch() {
  const calendar = await getCalendarClient();

  // Generate a unique channel ID
  const channelId = `openproject-gcal-sync-${randomUUID()}`;

  // Watch expires in 7 days (max allowed by Google)
  // We'll renew every 6 days to be safe
  const expiration = Date.now() + 7 * 24 * 60 * 60 * 1000;

  console.log(`Setting up watch for calendar: ${GOOGLE_CALENDAR_ID}`);
  console.log(`Webhook URL: ${GCAL_WEBHOOK_URL}`);
  console.log(`Channel ID: ${channelId}`);

  const response = await calendar.events.watch({
    calendarId: GOOGLE_CALENDAR_ID,
    requestBody: {
      id: channelId,
      type: "web_hook",
      address: GCAL_WEBHOOK_URL,
      token: GCAL_WEBHOOK_SECRET,
      expiration: String(expiration),
    },
  });

  console.log("\nWatch created successfully!");
  console.log(`  Channel ID: ${response.data.id}`);
  console.log(`  Resource ID: ${response.data.resourceId}`);
  console.log(`  Expiration: ${new Date(parseInt(response.data.expiration!)).toISOString()}`);

  // Output channel info for renewal
  const channelInfo = {
    channelId: response.data.id,
    resourceId: response.data.resourceId,
    expiration: response.data.expiration,
  };

  console.log("\nChannel info (save for renewal):");
  console.log(JSON.stringify(channelInfo, null, 2));

  return channelInfo;
}

async function main() {
  const action = process.argv[2] || "setup";

  console.log("Google Calendar Watch Setup/Renewal");
  console.log("====================================\n");

  // Validate environment
  const required = [
    "GOOGLE_CALENDAR_ID",
    "GOOGLE_SERVICE_ACCOUNT_JSON",
    "GCAL_WEBHOOK_URL",
    "GCAL_WEBHOOK_SECRET",
  ];
  for (const key of required) {
    if (!process.env[key]) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
  }

  if (action === "stop" && process.argv[3] && process.argv[4]) {
    // Stop existing watch: npx tsx watch-setup.ts stop <channelId> <resourceId>
    await stopExistingWatch(process.argv[3], process.argv[4]);
  } else {
    // Setup new watch
    await setupWatch();
  }
}

main().catch((error) => {
  console.error("Watch setup failed:", error);
  process.exit(1);
});
