import { google } from "googleapis";
import { createHash } from "crypto";

// Configuration from environment
const OPENPROJECT_URL = process.env.OPENPROJECT_URL!;
const OPENPROJECT_API_KEY = process.env.OPENPROJECT_API_KEY!;
const GOOGLE_CALENDAR_ID = process.env.GOOGLE_CALENDAR_ID!;
const GOOGLE_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_SERVICE_ACCOUNT_JSON!;

interface CalendarEvent {
  id?: string | null;
  summary?: string | null;
  start?: { date?: string | null; dateTime?: string | null } | null;
  end?: { date?: string | null; dateTime?: string | null } | null;
  extendedProperties?: {
    private?: { [key: string]: string } | null;
  } | null;
}

// Generate a hash of event content for change detection
function generateEventHash(date: string, summary: string): string {
  return createHash("md5").update(`${date}:${summary}`).digest("hex").slice(0, 16);
}

async function getCalendarClient() {
  const credentials = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON);

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/calendar"],
  });

  return google.calendar({ version: "v3", auth });
}

async function updateOpenProjectMilestone(
  workPackageId: string,
  newDate: string
): Promise<boolean> {
  const url = `${OPENPROJECT_URL}/api/v3/work_packages/${workPackageId}`;

  // First, get the current work package to get the lockVersion
  const getResponse = await fetch(url, {
    headers: {
      Authorization: `Basic ${Buffer.from(`apikey:${OPENPROJECT_API_KEY}`).toString("base64")}`,
      "Content-Type": "application/json",
    },
  });

  if (!getResponse.ok) {
    console.error(`Failed to fetch work package ${workPackageId}: ${getResponse.status}`);
    return false;
  }

  const workPackage = await getResponse.json();
  const lockVersion = workPackage.lockVersion;

  // Update the milestone date
  const patchResponse = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Basic ${Buffer.from(`apikey:${OPENPROJECT_API_KEY}`).toString("base64")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      lockVersion,
      date: newDate,
    }),
  });

  if (!patchResponse.ok) {
    const error = await patchResponse.text();
    console.error(`Failed to update work package ${workPackageId}: ${patchResponse.status} ${error}`);
    return false;
  }

  return true;
}

async function reverseSync() {
  const calendar = await getCalendarClient();

  // Fetch events that have our syncSource property
  const eventsWithProperty = await calendar.events.list({
    calendarId: GOOGLE_CALENDAR_ID,
    privateExtendedProperty: "syncSource=openproject",
    maxResults: 500,
    singleEvents: true,
  });

  // Also fetch events by searching for our emoji prefix (in case extendedProperties were lost)
  const eventsWithEmoji = await calendar.events.list({
    calendarId: GOOGLE_CALENDAR_ID,
    q: "🎯",
    maxResults: 500,
    singleEvents: true,
  });

  // Merge and deduplicate by event ID
  const allEventsMap = new Map<string, CalendarEvent>();
  for (const event of [...(eventsWithProperty.data.items || []), ...(eventsWithEmoji.data.items || [])]) {
    if (event.id?.startsWith("openproject")) {
      allEventsMap.set(event.id, event as CalendarEvent);
    }
  }

  const items = Array.from(allEventsMap.values());
  console.log(`Found ${items.length} OpenProject events (${eventsWithProperty.data.items?.length || 0} with extendedProperties, ${eventsWithEmoji.data.items?.length || 0} with emoji search)`);

  let updatedCount = 0;
  let skippedCount = 0;

  for (const event of items as CalendarEvent[]) {
    const eventId = event.id;
    const extendedProps = event.extendedProperties?.private || {};
    const storedHash = extendedProps.contentHash;
    const workPackageId = extendedProps.workPackageId;

    // Debug: log event details
    const eventDate = event.start?.date || event.start?.dateTime?.split("T")[0];
    const eventSummary = event.summary || "";
    console.log(`\nEvent: ${eventId}`);
    console.log(`  Summary: ${eventSummary}`);
    console.log(`  Date: ${eventDate}`);
    console.log(`  Stored hash: ${storedHash}`);
    console.log(`  WorkPackageId: ${workPackageId}`);

    // Extract workPackageId from event ID if not in extendedProperties
    const extractedWpId = eventId?.startsWith("openproject") ? eventId.replace("openproject", "") : null;
    const wpId = workPackageId || extractedWpId;

    if (!wpId) {
      console.log(`  -> Skipping: no workPackageId`);
      skippedCount++;
      continue;
    }

    if (!eventDate) {
      console.log(`  -> Skipping: no date`);
      skippedCount++;
      continue;
    }

    // Calculate current hash
    const currentHash = generateEventHash(eventDate, eventSummary);
    console.log(`  Current hash: ${currentHash}`);

    // If no stored hash (extendedProperties were lost), we need to check against OpenProject
    if (!storedHash) {
      console.log(`  -> ExtendedProperties lost! Will sync this event.`);
      // Fall through to update
    } else if (storedHash === currentHash) {
      // If hash matches, event hasn't been modified in Calendar - skip
      console.log(`  -> Skipping: hash matches (no changes)`);
      skippedCount++;
      continue;
    }

    console.log(`Event ${eventId} modified in Calendar (hash mismatch)`);
    console.log(`  Stored hash: ${storedHash}, Current hash: ${currentHash}`);
    console.log(`  Updating OpenProject work package ${wpId} to date ${eventDate}`);

    // Update OpenProject milestone
    const success = await updateOpenProjectMilestone(wpId, eventDate);

    if (success) {
      console.log(`  Successfully updated work package ${wpId}`);
      updatedCount++;

      // Update the hash in Calendar to prevent re-processing
      // and mark as user-modified from calendar
      await calendar.events.patch({
        calendarId: GOOGLE_CALENDAR_ID,
        eventId: eventId!,
        requestBody: {
          extendedProperties: {
            private: {
              ...extendedProps,
              contentHash: currentHash,
              syncSource: "calendar", // Mark as modified from calendar
            },
          },
        },
      });
    }
  }

  console.log(`\nReverse sync complete: ${updatedCount} updated, ${skippedCount} skipped`);
}

async function main() {
  console.log("Starting Google Calendar -> OpenProject reverse sync...");

  // Validate environment
  const required = [
    "OPENPROJECT_URL",
    "OPENPROJECT_API_KEY",
    "GOOGLE_CALENDAR_ID",
    "GOOGLE_SERVICE_ACCOUNT_JSON",
  ];
  for (const key of required) {
    if (!process.env[key]) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
  }

  await reverseSync();

  console.log("Reverse sync complete!");
}

main().catch((error) => {
  console.error("Reverse sync failed:", error);
  process.exit(1);
});
