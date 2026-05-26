# Hansard Chat Session — smoke

## Goal

A user can find a sitting with Hansard content, open its table of contents, read a debate from start to end, and return to the topics list.

## Sub-steps

1. **Launch app and remain responsive for 5s** — app starts and remains responsive for 5 seconds without crashing.
2. **App is on the Parliament tab** — verify the calendar is visible on the current tab; tap the Parliament tab only if the app did not launch there by default.
3. **Verify today's date is visible on the calendar** — confirm `2025-11-04` is visible as a selectable date in the calendar surface. Do not assert against wall-clock today.
4. **Tap a green date** — select the fixture date (`2025-11-04`) or any visible date marked as a sitting day.
5. **Verify the table of contents opens** — the debate / subjects-of-business list for the selected sitting appears.
6. **Tap a debate entry in the ToC** — open a debate detail screen from the list; the view is not blank and renders debate content.
7. **Page through the debate to the end** — use the debate pagination interaction (tap-anywhere to advance) until the end marker is reached.
8. **Return to topics** — navigate back to the table of contents and verify the topics list is visible again.

## Anti-goals (out of scope)

- Asserting any specific debate, speech, or speaker content.
- Verifying speaker photos load.
- Validating exact page count of a debate.
- Asserting which debate is tapped in step 6 (any debate is acceptable).
- Testing calendar UI affordances beyond confirming green-date visibility and tap.
- Checking any tab other than Parliament.
