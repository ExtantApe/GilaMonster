# Changelog

## Unreleased

- **Add Plugin waits for a complete source.** The dialog opens on Modrinth with an empty project, and Add was already on, so it could try to add nothing. Now a source counts only once it has a project, a SpigotMC number, a GitHub owner/name or a web address starting with http or https. The same rule stops automatic checks on a half-filled source, and the Overview counts it as without a source.
- **Quitting during a backup asks first** (D215), for a quit, restart, log out or shutdown. It shows how far the backup has got and about how long is left. **Wait, Then Quit** quits as soon as it's done. **Cancel Backup and Quit** stops it and deletes only its unfinished file, so earlier backups stay. **Keep Using LeafJuice** cancels the quit, and at a restart, log out or shutdown macOS is told the app declined. Either way out stops running servers with a save, without a second question. Tested: 8 checks for the progress, the time left and what Cancel deletes, and the panel drawn in light and dark. Not tested: a real quit, restart or shutdown during a real backup.
- **A backup cap for each drive** (D213), set on the Backups page under Space on each drive. Every server's LeafJuice backups on that drive count, including one still being written. Before a backup would go over, this server's oldest backups there are removed first, starting with the ones its keeping rules would drop anyway. Pinned backups, the newest backup, the server's first backup and other servers' backups are never removed. If that isn't enough, the backup goes to the next storage in your list, or is skipped and you're told, so the drive never fills past the cap. You're warned at 85%. While a backup is written, it's stopped and its partial file removed if the drive's backups reach the cap.
- **Storage that's passed over says why, and it's kept.** A drive macOS won't let LeafJuice open used to look unplugged ("Not connected."). Now the Backups page and the reason say LeafJuice isn't allowed to open it, and where in System Settings to allow it. A backup that skips your first storage choice leaves an issue with the reason, which goes away once a backup reaches it again. Tested with stand-ins for a refused and an unplugged drive; not tested against a real refusal from macOS.
- **No more half-written backups after a quit.** Quitting during a backup used to leave its `.partial` file, which could be tens of gigabytes. Now every way of quitting stops the backup and removes it, and any leftover from a crash is cleared when the server opens or before its next backup. Tested: 40 new checks, including a made-up server whose oldest backup is removed to fit under a cap, a backup skipped when it can't fit, and a stand-in for tar stopped with its partial file removed. Not tested: quitting the real app in the middle of a real backup.

- **The shutdown save now works in release builds.** The quit handler and the power-off watcher from the shutdown change had landed inside a debug-only block, so the app built by `scripts/build-app.sh` didn't have them. Tested: a release build on a throwaway server stopped it with a world save and exited about 4 seconds after a simulated shutdown, without asking.
- **Shutting down the Mac** no longer gets stuck on "Stop running servers and quit?". At a shutdown, restart or log out,
  LeafJuice stops every server with a save without asking, then quits so the Mac can carry on.
- **Publish packs to your web server** (D189): each build under a new random path in the folder Caddy serves, named by
  its SHA-1, checked after copying, with the old build removed once nobody who might need it is online. With Packmule
  0.2.1, LeafJuice tells it the new link (`pack set`); otherwise you mark it updated by hand. The old build is never
  removed until Packmule uses the new one.
- **Printed invite tickets** (Latchkey 0.5): the server's name, where to go, the code, the expiry and a QR code that
  fills the code in, as a print, a PDF or plain text. Tested with a stand-in for Latchkey and macOS's own QR reader;
  not yet printed on paper or scanned with a phone.
- **Smart backups:** back up after people play, with a minimum gap; keep everything recent, then one a day, then one
  a week; use your storage in order, falling back when a drive isn't there, and show where each backup is. New
  servers start this way; existing ones keep their schedule until you switch.
- **Disk guard:** backups and test restores check first that they'd leave at least 20 GB free, and
  a test restore unpacks on the backup's own drive when that has room. Before this, a test restore of a 47 GB backup
  took a Mac from about 50 GB free to 6 GB.
- **Session access:** sessions and scripts on this Mac can read a server's status and recent log, and run commands
  from a list you keep, through `leafjuice-session`. Off by default. Chat, player names and addresses are kept out,
  everything else is refused, and every call is listed in Settings. Tested against a real Paper 26.3 server with a
  made-up bot.
- **Connections:** a card on the Overview page for the address players type and each tunnel or service: playit,
  and anything else that carries players or web traffic, or a domain name. Each has an on or off switch,
  a check and a plain-language status. Settings live in `.leafjuice/connections.json`; secrets stay in the Keychain
  or the service's own file, and a missing one shows as not ready. Checking from outside only runs when you click it.
  Tested with made-up answers, a throwaway keychain and local sockets, and read-only against a real playit agent. Not yet run against the real servers.
- **Map and sign-in addresses** in the same file, each with a check. The invite code screen shows the sign-in page
  beside the code, with Copy Both. If none is set, it says so and still shows the code.
- **Colors held to WCAG AA in code.** Every text and control pair, in light, dark and increased contrast, and with
  common color blindness simulated. Buttons and fields get outlines at 3:1 or better, and the main button an outline
  of its own. See `docs/ux-audit.md`.
- **VoiceOver:** repeated row buttons now name their row, such as "Remove" plus the pack's name.
- **Spelled LeafJuice** everywhere you see the name. Your data folder and macOS permissions stay as they were.
- **Fixed:** a database plugin's normal connection-pool line no longer shows as "A database connection failed".
- **Fixed:** the documented `secret` field in connections.json is no longer flagged as a pasted secret.
- **Fixed:** the recorded Minecraft version and build follow the server's own start lines, so the header says what's
  really running.
- **Sidebar groups:** Overview on top, then Server, Content, People and Upkeep, alphabetical inside each. Groups fold
  away and stay folded, and a folded group shows the total of its badges.
- **Issues:** repeats that differ only by a quoted name, such as one warning per world, are one row with a count. An
  issue with no known plugin says where it came from, and a database failure names its pool.
- **Connections:** a tunnel check redoes itself when the server starts or stops, and a server started outside
  LeafJuice counts as running. A secret pasted into the file gets a button that moves it into the Keychain.
- **Removed:** the Tailscale check. An older `tailscale` entry reads as Other.

## 0.2.0

Tested against real Paper 26.x servers started for the tests, with made-up players, and with the real plugins named
below. Not yet tested by anyone running it on a server people play on. The new screens haven't been checked with a
keyboard and VoiceOver yet. Plugin commands and the Advisor are off until you turn them on.

**Opening it:** LeafJuice is unsigned, so macOS blocks the first launch. Allow it one of two ways:

- **System Settings:** try to open the app once, then go to System Settings > Privacy & Security, scroll down, click
  **Open Anyway**, and click **Open** when the warning comes back. Apple says to do this only for an app you trust.
- **Terminal:** `xattr -dr com.apple.quarantine "/Applications/LeafJuice.app"`

Players and sign-in:

- Add someone to the allowlist before they've ever joined, with their LuckPerms groups. Groups you haven't ticked are
  never offered, and you can mark pairs of groups that shouldn't be combined.
- With Usher installed, approving someone goes through Usher's profiles and its questions, and never around it. People
  the whitelist turned away are listed. Needs Plugin commands, which is off by default.
- With Latchkey, make six-character invites for one Minecraft name with Usher profiles, see the code once, and list or
  revoke them. With Latchkey 0.3, the card shows whether its lobby is on, and each player's sheet can sign them out of
  the web pages everywhere.
- A page listing your plugins for people on the server, and BlueMap's web map behind the same sign-in. Players sign
  in with `/signin` in the game, through Latchkey. Both are off by default.

Resource packs:

- See what each pack contributes, serve packs from this Mac with their own address per build, and serve an exact pack
  file unchanged. Serving comes back when the app opens.
- Leave out any song a pack lists in its `songs.json`, so Minecraft's own track plays.

Upgrades and the rest:

- Before an upgrade, check plugins with Preflight's own tool on a copy, and offer to switch off ones that won't start.
- Pick the server icon from a folder of choices in `server-icons/`.
- The Advisor, an optional page that asks Claude Code for suggestions about a server, using your own Claude account.
  It's off until you turn it on in Settings, each server has to be shared, and the first check asks before sending.
  Only recognised log lines, stack traces and a fixed list of settings are sent, with players and addresses replaced
  by code names. The list of who each code name stands for is sealed with a key in your Keychain. macOS asks for
  that key once, and again after each update until LeafJuice is signed. See `docs/ADVISOR-SECURITY.md`. Tested with
  made-up servers. It hasn't been run on a real server yet.

## 0.1.0

The first release. Tested against real Paper servers started for the tests, with made-up data. Not yet tested by
anyone running it on a server people play on.

- Runs a Minecraft Java server from a Mac app: console, CPU and memory, restart after a crash with a limit, and
  keeps the Mac awake while running.
- Finds the server software, version, memory and flags of an existing server, and keeps everything it adds in
  `.leafjuice/`.
- Keeps Paper, Folia, Purpur, Vanilla or your own jar current, with hashes checked.
- Updates plugins from Modrinth, Hangar, SpigotMC, GitHub Releases, Jenkins or any web address, skipping
  releases tagged for another Minecraft version.
- Settings forms generated from `server.properties`, Bukkit, Spigot, Paper and each plugin's config.
- The Lab, a practice server with bot players for rehearsing an upgrade before doing it for real.
- Resource pack recipes: version, rank, build and share packs.
- A plugin links page listing each plugin, its version and where to read about it. It replaces the wiki.
