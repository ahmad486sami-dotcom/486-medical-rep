# 486 Medical Rep

Personal iPhone app for inviting doctors to events and following up on WhatsApp.
Everything is stored on the phone only (no server, no account).

## Get it on your iPhone
1. Push this folder to a **new GitHub repo** (GitHub Desktop: File > Add local repository > Publish).
   The hidden `.github` folder must be included.
2. GitHub runs **Build IPA** automatically on every push to `main`
   (or Actions tab > Build IPA > Run workflow).
3. When it's green, open **Releases** on the repo page and download `486MedicalRep.ipa`
   (on the iPhone, open the repo in Safari while signed in, tap the .ipa, then "Open in ESign").
   If the repo is public, you can paste the .ipa link straight into ESign's downloader instead.
4. In ESign: sign with your certificate and install.

No Expo, no npm: it's a plain SwiftUI app built with XcodeGen + xcodebuild on GitHub's Mac runner.

## What's inside
- **Today** - suggestions + the messages due today (after-visit details, maybe follow-up, 1 week, 2 days, morning of,
  thank-you / missed-you after the event, "good news, your colleague is coming"). Tap Write -> edit -> Open in WhatsApp.
  "Ask rep" writes a WhatsApp to the hospital's mirror rep.
- **Events** - name, date, venue, CME, main points, target, allowed specialties. Invite tab only shows matching doctors.
  Event day tab: tick who came / didn't. Share list as Excel (full list or only one mirror rep's hospitals).
- **Doctors** - specialty, hospital, WhatsApp, LinkedIn, notes, required visits per month (+ "Log a visit today"),
  "usually brings" and "comes only if" colleagues, full event history, first-timer badge.
- **Hospitals** - area + mirror reps; the hospital page is the pre-visit brief. Share as Excel.
- **More** - your name/company, mirror reps and numbers, occasions & greetings (UAE National Day, New Year,
  Ramadan, both Eids, Hijri New Year; Islamic dates are estimates you edit), wins & report (Excel), backup/restore.

Excel files are real .xlsx written by the app itself (Sources/XLSX.swift), styled as a plain bordered sheet.
