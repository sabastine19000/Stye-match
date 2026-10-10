# Voice and Keyboard Stability Audit

Date: 2026-07-22

## Confirmed root cause

The speech service allowed an asynchronous permission request to resume after cancellation/view teardown. That stale path could reach the controller while another session owned the input tap. The controller itself already guarded tap ownership, route availability, and format validity, but the service lacked a start-attempt identity across suspension points.

## Remediation

- One `activeStartAttemptID` per requested start.
- Identity checks after microphone permission, speech permission, and immediately before controller start.
- Cancellation, completion, error, interruption, and teardown invalidate the attempt.
- Recognition callbacks remain scoped to the active session.
- Controller maintains one StyleMatch-owned tap and removes only that tap.
- Invalid route/format returns a recoverable state.
- Debug diagnostics report guard categories only; never speech text or private content.

## Automated evidence

Tests cover rapid repeated starts, start/stop/restart, permission denial, cancellation while permission is suspended, unavailable recognition, no speech, draft preservation, typed/voice convergence, keyboard visibility, navigation dismissal, and owned-tap source contract.

## Physical gate

The prior `AVAudioNode.installTap` crash remains **NOT PHYSICALLY VERIFIED AS RESOLVED**. Required device proof:

1. three microphone start/stop cycles;
2. rapid double taps;
3. microphone → keyboard → microphone;
4. navigation away/back during recognition;
5. background/foreground and interruption;
6. Bluetooth/wired/built-in route changes when available;
7. invalid/unavailable input recovery;
8. transcript and draft preservation;
9. successful real transcription after stress.

No device, audio route, microphone, or installation was used in this checkpoint.
