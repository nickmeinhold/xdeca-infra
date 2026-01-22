import { google } from "googleapis";
import { createHash } from "crypto";

// Configuration from environment
const OPENPROJECT_URL = process.env.OPENPROJECT_URL!;
const OPENPROJECT_API_KEY = process.env.OPENPROJECT_API_KEY!;
const GOOGLE_CALENDAR_ID = process.env.GOOGLE_CALENDAR_ID!;
const GOOGLE_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_SERVICE_ACCOUNT_JSON!;

// Generate a hash of event content for change detection
function generateEventHash(date: string, summary: string): string {
  return createHash("md5").update(`${date}:${summary}`).digest("hex").slice(0, 16);
}

interface WorkPackage {
  id: number;
  subject: string;
  description?: { raw: string };
  startDate?: string;
  dueDate?: string;
  date?: string; // Milestones use this field instead of startDate/dueDate
  _links: {
    type: { title: string };
    project: { title: string };
    self: { href: string };
  };
}

interface OpenProjectResponse {
  _embedded: {
    elements: WorkPackage[];
  };
  total: number;
}

async function fetchWorkPackages(): Promise<WorkPackage[]> {
  const filters = JSON.stringify([
    { status: { operator: "o", values: [] } }, // Open statuses only
  ]);

  const url = `${OPENPROJECT_URL}/api/v3/work_packages?filters=${encodeURIComponent(filters)}&pageSize=200`;

  const response = await fetch(url, {
    headers: {
      Authorization: `Basic ${Buffer.from(`apikey:${OPENPROJECT_API_KEY}`).toString("base64")}`,
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`OpenProject API error: ${response.status} ${await response.text()}`);
  }

  const data: OpenProjectResponse = await response.json();
  return data._embedded.elements;
}

async function getCalendarClient() {
  const credentials = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON);

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/calendar"],
  });

  return google.calendar({ version: "v3", auth });
}

function generateEventId(workPackageId: number): string {
  // Google Calendar event IDs must be lowercase alphanumeric
  return `openproject${workPackageId}`;
}

async function syncToCalendar(workPackages: WorkPackage[]) {
  const calendar = await getCalendarClient();

  // Filter to milestones only (milestones use `date` field, not startDate/dueDate)
  const milestones = workPackages.filter(
    (wp) => wp._links.type.title.toLowerCase() === "milestone" && (wp.date || wp.startDate || wp.dueDate)
  );

  console.log(`Found ${workPackages.length} open work packages, ${milestones.length} milestones with dates`);

  for (const wp of milestones) {
    const eventId = generateEventId(wp.id);

    // Use the date (milestones use `date` field, regular work packages use startDate/dueDate)
    const startDate = wp.date || wp.startDate || wp.dueDate!;
    const endDate = wp.date || wp.dueDate || wp.startDate!;

    // Add one day to end date because Google Calendar end dates are exclusive
    const endDatePlusOne = new Date(endDate);
    endDatePlusOne.setDate(endDatePlusOne.getDate() + 1);

    const eventSummary = `🎯 [${wp._links.project.title}] ${wp.subject}`;
    const contentHash = generateEventHash(startDate, eventSummary);

    const event = {
      summary: eventSummary,
      description: [
        wp.description?.raw || "",
        "",
        `Type: ${wp._links.type.title}`,
        `OpenProject: ${OPENPROJECT_URL}/work_packages/${wp.id}`,
      ].join("\n"),
      start: { date: startDate },
      end: { date: endDatePlusOne.toISOString().split("T")[0] },
      transparency: "transparent", // Don't block time
      extendedProperties: {
        private: {
          syncSource: "openproject",
          contentHash: contentHash,
          workPackageId: String(wp.id),
        },
      },
    };

    try {
      // Try to update existing event
      await calendar.events.update({
        calendarId: GOOGLE_CALENDAR_ID,
        eventId,
        requestBody: event,
      });
      console.log(`Updated: ${wp.subject}`);
    } catch (error: unknown) {
      if (error && typeof error === "object" && "code" in error && error.code === 404) {
        // Event doesn't exist, create it
        await calendar.events.insert({
          calendarId: GOOGLE_CALENDAR_ID,
          requestBody: { ...event, id: eventId },
        });
        console.log(`Created: ${wp.subject}`);
      } else {
        console.error(`Failed to sync "${wp.subject}":`, error);
      }
    }
  }
}

async function cleanupClosedWorkPackages() {
  const calendar = await getCalendarClient();

  // Fetch all OpenProject events from calendar
  const events = await calendar.events.list({
    calendarId: GOOGLE_CALENDAR_ID,
    q: "OpenProject:", // Our events have this in description
    maxResults: 500,
  });

  // Get current open milestone IDs only
  const openWPs = await fetchWorkPackages();
  const openMilestoneIds = new Set(
    openWPs
      .filter((wp) => wp._links.type.title.toLowerCase() === "milestone")
      .map((wp) => generateEventId(wp.id))
  );

  // Delete events for closed/non-milestone work packages
  for (const event of events.data.items || []) {
    if (event.id?.startsWith("openproject") && !openMilestoneIds.has(event.id)) {
      try {
        await calendar.events.delete({
          calendarId: GOOGLE_CALENDAR_ID,
          eventId: event.id,
        });
        console.log(`Deleted closed: ${event.summary}`);
      } catch (error) {
        console.error(`Failed to delete "${event.summary}":`, error);
      }
    }
  }
}

async function main() {
  console.log("Starting OpenProject → Google Calendar sync...");

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

  const workPackages = await fetchWorkPackages();
  await syncToCalendar(workPackages);
  await cleanupClosedWorkPackages();

  console.log("Sync complete!");
}

main().catch((error) => {
  console.error("Sync failed:", error);
  process.exit(1);
});
