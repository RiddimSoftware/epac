# Hansard Chat Session — smoke

## Goal

A user can find today's Hansard chat session and view the group chat.

## Sub-steps

1. **Launch app and verify responsiveness** — app starts and remains responsive for 5 seconds without crashing; crash gate passes
2. **Tap Parliament tab** — verify a calendar view appears with sitting dates listed
3. **Verify today's date is visible on the calendar** — the fixture date (November 4, 2025) appears as a selectable date in the calendar surface; do not assert against wall-clock today
4. **Tap the most-recent sitting with content** — select the sitting entry that corresponds to the fixture date; verify the tap is accepted
5. **Verify sitting overview loads** — the sitting detail screen is not blank and shows no error state; at least one subject of business is visible
6. **Navigate to group chat for this sitting** — tap into a subject of business or the chat entry point to open the Hansard chat surface
7. **Verify chat surface appears with at least one message rendered** — the group chat view is visible and at least one speech bubble containing parliamentary text is rendered on screen

## Anti-goals (out of scope)

- Asserting the specific text content of any speech or intervention
- Verifying speaker photos load or display correctly
- Testing calendar UI affordances beyond confirming the fixture date is visible
- Validating scroll behavior or message count within the chat thread
- Checking any tab other than Parliament during this CUJ
