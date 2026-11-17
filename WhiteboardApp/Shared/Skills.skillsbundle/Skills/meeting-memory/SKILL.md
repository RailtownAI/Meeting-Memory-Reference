---
name: meeting-memory
description: Save photos of meeting whiteboards to the right calendar meeting, and answer questions about what was written on them, with their action items and meeting dates.
---

# Meeting Memory

Meeting Memory keeps whiteboard photos from meetings. Each saved whiteboard has a title, a summary, action items, the date it was captured, and the calendar meeting it belongs to.

## When to use each action

- **Remember Whiteboard**: the user has a photo of a whiteboard and wants to keep it. Pass the photo. Pass a meeting only when the user names one; without it, the app uses the meeting that started last within the past day, whether it is in progress or has ended. The result is the saved whiteboard with its title and action items.
- **Ask Meeting Memory**: the user asks about something discussed or decided in meetings, or about action items, owners or dates. Pass the user's question as written. The answer is plain text: the answer first, then each supporting whiteboard with its capture date in full, its meeting, and its action items as sentences.
- **Ask About a Meeting**: the user asks about one calendar meeting, for example the one open in Calendar, or wants to prepare for it. Pass the meeting's title and start, and the question when there is one. The answer lists the whiteboards from earlier occurrences of that meeting, newest first, each with its meeting date in full, its summary and its action items.
- **Search** (in-app search): the user wants to find whiteboards by a topic or a word. It answers the same way as Ask Meeting Memory.

## Passing results on

- Action items in a result can become reminders in the Reminders app. Use each action item sentence as the reminder title.
- Meeting names and full dates in a result can be used to find or create events in the Calendar app, for example a follow-up meeting.

Meeting Memory does not create reminders or calendar events itself.
