# NOVA — Home Records Creative OS

NOVA is a static, mobile-friendly writing studio published from GitHub Pages.

## Included

- Song projects: create, edit, search, save, and export plain-text files.
- La Biblia: a personal collection of titled fragments.
- Songwriting assistant: connect a Gemini API key and generate creative drafts.
- Local rhyme finder, song structures, tap tempo, BPM slider, and browser metronome.
- Browser-local backup export and installable/offline shell (PWA).

## Live URL

https://zamird52-sketch.github.io/Home-Records/nova/

## AI setup

1. Open Conexiones in the app.
2. Obtain a personal API key from Google AI Studio.
3. Paste it, select a model available to your account, and choose whether to keep it for this session or save it locally.
4. Use Verificar conexión before generating.

The site has no server-side secret store. AI requests are sent directly from the browser to Google's Gemini API using the visitor's own key. Do not embed a private key in this repository or share one across visitors. Availability, free-tier limits, terms, and data handling depend on the selected provider/model and account.

## Local storage

Projects, notes, and AI-session counters are stored only in the current browser. They do not synchronize between devices. Use Exportar mi archivo completo in Conexiones to save a backup.

## Hosting

The folder is self-contained and can be published as a subpath on GitHub Pages. It has no build step or third-party frontend dependencies. The service worker caches the app shell after the first visit; AI generation still requires a network connection.