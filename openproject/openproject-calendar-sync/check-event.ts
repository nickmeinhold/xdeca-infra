import { google } from "googleapis";

const GOOGLE_CALENDAR_ID = process.env.GOOGLE_CALENDAR_ID!;
const GOOGLE_SERVICE_ACCOUNT_JSON = process.env.GOOGLE_SERVICE_ACCOUNT_JSON!;

async function main() {
  const credentials = JSON.parse(GOOGLE_SERVICE_ACCOUNT_JSON);
  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
  });
  const calendar = google.calendar({ version: "v3", auth });
  
  // List recent events
  const events = await calendar.events.list({
    calendarId: GOOGLE_CALENDAR_ID,
    q: "🎯",
    maxResults: 10,
  });
  
  for (const event of events.data.items || []) {
    console.log(`\n${event.summary}`);
    console.log(`  id: ${event.id}`);
    console.log(`  start.date: ${event.start?.date}`);
    console.log(`  start.dateTime: ${event.start?.dateTime}`);
    console.log(`  start.timeZone: ${event.start?.timeZone}`);
  }
}

main();
