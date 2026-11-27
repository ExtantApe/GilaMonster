# Test audit

Each audit lists what GilaMonster promises, which checks prove each promise, and the gaps. Run the checks with `swift run gilamonster-check` (offline, made-up data, about 80 seconds). The `--real-*`, `--lab` and `--sandbox` runs boot real Paper and are listed apart.


## 2026-11-27: accessibility fixes after review (K820)
- Promises: the Allow prompt shows a server's name whole, with Bold Text too, and is never wider than the screen; dialogs don't clip at the largest text size; headings with the owner's data are never in capitals and capital headings read as written; the Pixel font hint is complete; disclosure rows say Expanded or Collapsed and are 24 pt to press; the Upgrade field shows a focus ring.
- Covered: `pixelTypeChecks` (source rules, the placement rules `contentWidth` and `sideBySide`, the hint's words, no heading style used outside `HeadingText`, no fixed sheet width left); `snapshotOverflowChecks` (every dialog drawn and its edges read at the default size, 16.5 pt and 22 pt labels and Bold Text; a report that is missing fails; every sheet drawn too narrow on purpose is caught); `Overflow.flowRows`, `readDialogReport` and `edgeHasContent`.
- Failing first: with the disclosure words, the 24 pt height and the heading helper put back as they were, five source checks failed. The dialog check was written with its own failing run: sheets drawn at 60% of their width are all reported.
- After merging main (0278c78), 2026-11-27: `--look` 555 passed, `--connections` 1808 passed, `--snapshot` 54 passed. Main's settings check (K814) found the Pixel font setting defaulting to the app's own settings; it now uses `AppDefaults.store`. One earlier `--look` run found three removed settings files back on disk, and two runs after it passed. The full suite wasn't run.
- Gaps skipped (and why): Settings and the welcome screen can't be judged by their edges (a system form and a whole window) and are named as skipped in the report. The check sees content running off the side, not text cut inside a box. Text size and Bold Text are stood in for in the snapshot, and nothing was heard through VoiceOver.

## 2026-11-27: made-up names in checks (K827)
- Promises: no real server's name in tracked code, checks or docs; the rename checks still cover a two-word name with capitals, its hyphenated, joined, camel and underscore folder forms, a camel-case name going in, and the `screen -S` line and absolute paths in a start script.
- Covered: `Renames: the text` and `Renames: whole servers` in `main.swift`, with Riverbend Mountain in place of the old name and nothing else changed. `git grep -i` for the old name finds nothing in the tree.
- Gaps skipped (and why): no check greps the tree for real names, because the names are private and live outside the repo, in the leak check's own list. The overlap experiment is a by-hand run that needs zips and the network, so it has no place in the offline suite.
## 2026-11-27: banners above the page (K815)
- Promises: no banner above the page pushes the page out of view, whatever its text; the column beside the sidebar never asks for more height than the window gives it; no callout has a layout of its own for the banner row; the snapshot can draw each banner with a second line and reports where every page landed.
- Covered: `bannerRowChecks`, from the app's source: only the banners sit between the trail and the page; the column takes the height it is given, set before the one inspector; its smallest height is zero outside a debug-only switch; `inBannerRow` is gone from every file; the row has its Keychain banner, four callouts and the test copy's banner, and those banner views are used nowhere else. From made-up controllers: `all` puts up one of each banner with a second line, one name puts up only that banner, `long-title` is a title of over 100 characters, and the script accepts exactly the names the app knows. `overflowChecks` reads `PUSHED` and `PLACED` lines from a report. `--snapshot`: the heavy run has every page inside its window in both themes and looks; every banner at once with the denied Keychain banner, on Overview and Console in Bold light and dark, has over 300 points of banners drawn and no page pushed; the same run with `GILAMONSTER_SNAPSHOT_FORCE_TALL_COLUMN=1` reports both pages as pushed.
- Run, 2026-11-27: the default suite from a scratch build, 4235 passed and 1 failed (the gilamonster-mcp check a scratch build can't start). `--snapshot`: every banner check and the heavy run passed. Its too-wide proof failed with 18 reports for 17 pages, which is older than this work: the Players page has been drawn twice since K786 and both drawings are reported. Not fixed here.
- Failing first: six source checks fail against the 0.6.2 `RootView.swift` and `Theme.swift`. The measured check fails by design with the switch above, which puts the old behavior back.
- Pictures, looked at by hand: each of the ten made-up banners alone and all together on Overview, both Keychain banners with all the others on Overview and Console, and the wait banner on the welcome screen, in Bold light and dark, before and after. Before: the page was out of the picture for 7 of the 10 single banners (not for a failed test copy, whose text is capped at three lines, the running test copy or the update banner). After: every page starts at the top of the window, and no text is cut short.
- What the pictures showed about the cause: the banner row was always its right height (79 points for one banner). The column around it was up to 6,867 points taller than the 1,000-point window. With the inspector taken off for one run, the old layout drew correctly. So the inspector measures the column at a narrow width and uses that height.
- Gaps skipped (and why): the real window on screen. A session can't open it. The inspector in a real window with a toolbar may measure differently from the one in an off-screen picture, and nobody has reported a page vanishing under a notice, so this may never have shown in the app. The fix is safe either way. Also skipped: larger text sizes with banners, VoiceOver over the row (nothing spoken changed), and the Quiet theme by hand.

## 2026-11-26: a server's name from its server message (K824)
- Promises: the name shown is the owner's own name when there is one, then the first line of the server message with its colour and format codes removed, then the folder's name; the folder is also used when the message is empty, only codes, over 40 characters or the default; only the motd line of `server.properties` is read, with its escapes turned into characters the way Minecraft does; the owner's rename is kept in GilaMonster's settings and leaves `server.properties` alone; Reset to Server Message drops it and it stays dropped at the next launch; a name given before this change counts as the owner's; the headline, what VoiceOver reads for it, the window title, the switcher, the menu bar and notifications use the name; the name under the server's icon takes up to two lines, breaks only between words and is cut only at its end, with the whole name in the tooltip and the VoiceOver label; every switcher row shows the folder beneath the name and is read with it; the folder's name stays visible, and Show in Finder and Copy Folder Path still go by the folder.
- Covered: `serverNameChecks`, 102 checks. Stripping: colour and bold codes, §x hex colours, a second line, padding, the & codes, a § left at the end, an ordinary &, empty, only spaces, only codes, an empty first line, the default in two spellings, and 40 against 41 characters with and without codes. Reading the file: `\u00A7` and `\n` escapes, escaped separators, a line carried on with a backslash, the last of two motd lines, a file with no motd, an empty motd, and nothing from the made-up password lines beside it coming back. On a made-up server in the suite's temp folder: the message names it; the headline, the spoken headline, the folder line and an alert use that name; a rename beats the message, is still there when the folder is opened again, and leaves `server.properties` byte for byte; Reset clears it and it doesn't come back at the next open; a saved new message is picked up; the default, a long and an empty message each fall back to the folder; a server with a label from before this change keeps it until Reset. From the source: the Overview's headline and its VoiceOver label, the folder line, Copy Folder Path and Show in Finder, the window title and subtitle, the rename sheet's prefill and Reset button, the switcher, the menu bar, and that no file in the app shows the stored name apart from the Advisor's code name and picture file names. Under the icon: a short name, a long two-word name that wraps, three and five words that keep their whole words with an ellipsis, one very long word, a long second word, and for eight names that no line is over its room and every word shown is a whole word or the one cut word. The switcher: a row's spoken line with its folder, the Lab's row, two made-up servers with one server message each showing its own folder, and the button's tooltip and label carrying a name too long for the label. The Connect card's server message now loses hex colours too (one check).
- Failing first: with the app's sources put back as they were, the nine source checks failed, the label under the icon and the switcher rows among them. The Connect card check is for a fault seen in the first picture, where the card read "§x Made-up Realms". The other checks use functions this change added, so they couldn't be built against the old code.
- Pictures, looked at by hand: `scripts/snapshot-fixtures.sh` with `MOTD=` and `RENAME=`, the Overview and the rename sheet in Bold light and Bold dark, for a message with a hex colour, bold, padding and a second line (headline "Made-up Realms is stopped.", folder line under it), a message of a whole sentence (headline falls back to the folder, no folder line) and a rename over a coded message (headline "Pebble Garden is stopped."). A second round for the label under the icon and the switcher's rows (`TWIN=1`, `dialog-switcher-rows.png`): "Riverbend Mountain" on two lines, "The Pebble Garden Of Moss" as "The Pebble / Garden…", a renamed "Supercalifragilistic" as "Superca…", and two servers with one message each with its folder beneath.
- Gaps skipped (and why): the real switcher menu (the folder is the menu item's second line, which macOS draws; the off-screen pictures can't open a menu, so they draw the same words as plain rows, and the real menu needs a look in the app); the label under the icon with unusually wide letters (lines are sized by letter count, about ten to a line, and the view still cuts at the end of the second line if a line runs over); the rename sheet as a person uses it, by keyboard and with VoiceOver (the hint and the spoken line on Reset are set in code and weren't heard); the window title and subtitle, the menu bar and the quit question on screen (the off-screen pictures don't draw them; they're checked from the source); a real notification; the Quiet theme (no colour or layout of its own changed). Sessions were left alone on purpose: they name a server by its stored name, and the approval question shows that name.
## 2026-11-26: a backup drill's server outliving GilaMonster (K813)
- Promises: a drill's throwaway server never outlives GilaMonster. On every way out (Quit, a shutdown, SIGTERM, SIGHUP, SIGINT) the drill's Java is stopped and its copy removed; a copy left by a force quit or crash is found at the next launch by its mark, its Java is stopped if it's still running, and the copy is removed; only a real folder with a drill's name, directly inside `test-copies` or `.test-copies`, with a real file as its mark, is ever removed; a process is signalled only when the copy's own pid file names it, it's running, its program is Java and its working folder is that copy; nothing is swept while another GilaMonster runs, and a drill this GilaMonster is running is never swept; no drill starts once GilaMonster is quitting, and a drill ended by quitting records nothing about the backup.
- Covered: `drillCopyChecks` (names; a copy marked when made, never made over an existing one, refused once quitting; the sweep removing five marked leftovers and leaving an unmarked folder, a marked test copy without a drill's name, a link with a mark, a file with a mark, a mark that is a link, and what a link inside a copy points at; a stray mark removed; pid files naming this program, process 1, nonsense, and a running program that isn't Java working inside the copy, none signalled; another GilaMonster running; a folder that isn't test-copies; the folder beside a backup removed only when empty, with each place swept once). `drillCopyLifecycle` with the stand-in jar and real Java processes: a leftover Java in a marked copy stopped and removed by the sweep; a marked copy whose stale pid file names another server's running Java removed with that Java still running; an unmarked folder left as it was; and the signal path, where a second copy of the check program runs a real `runBackupDrill` on a real backup and is sent SIGTERM (doing what `stopAll` does about drills) and SIGHUP (doing what `applicationWillTerminate` does), after which the drill's Java is gone, the copy and mark are removed, and the server and its backup are still there. From the source: `stopAll` stops each drill first and ends with `DrillCopies.endAll()`, the signal handler calls it right before the exit, `applicationWillTerminate` calls it, the app watches signals through the same `QuitSignals.watch` the check uses, the launch calls the sweep, and a finished drill no longer deletes `.test-copies` whole.
- Failing first: the same checks were run with the stop on the way out and the sweep switched off, which is how the code behaved before. 23 failed there: after SIGTERM and after SIGHUP the drill's Java was still running and its copy and mark were still there, the leftover Java was still running after the sweep, and nothing marked was removed. The stand-in jar first had to be taught to keep running when its console closes, as real Paper does. Without that it exited by itself when the helper went away, and the check for a Java left running passed against the old behaviour. With the fix, the full suite is 4479 passing, none failing.
- The checks found two faults in the first draft of the fix: asking for a copy that already existed took the running drill off the list, and the sweep visited a folder twice once its first visit had removed it (macOS reads `/private/tmp/x` as `/tmp/x` only while it exists).
- Whether macOS can end the child with the parent was looked at: there is no parent-death signal on macOS, a process group only helps when the signal is sent to the group, and neither Paper nor the stand-in stops when its input closes. So the fix is the stop on the way out plus the launch sweep.
- Gaps skipped (and why): the app itself signalled or quit during a drill (the app layer isn't in the check harness and the app the owner uses mustn't be signalled; its calls are read from the source, and the core calls are the ones the signal check runs); a Java that ignores SIGTERM and is forced after the wait (the stand-in always exits; the second kill re-checks the pid first); real Paper in a drill (the stand-in exits on SIGTERM the way Paper's shutdown hook does, without the save); a tar still unpacking after a force quit, which could write into a copy the sweep is removing (on Quit and on a signal the tar is stopped first, read from the source); the sweep at a real launch and the other-copy-running guard through AppKit; the ordinary test copies and the upgrade check's copies, which already stop through `stopTrialCopy` and aren't marked or swept here.

## 2026-11-26: backup ages are GilaMonster's own (K823)
- Promises: every backup age GilaMonster shows is labelled as its own backup (the Overview's line, the Overview's Backups card, the status line); the Needs you item for a server with no backup says GilaMonster has made none and that it can't see other tools' backups, and no longer says nothing can be restored; only backups GilaMonster made are listed or counted, in the server's own folder and in each added storage folder; another tool's folders and archives are never counted and never touched, wherever they sit; each added storage folder shows its own newest backup, and a drive that isn't connected shows nothing; the pictures' made-up backups start no drill.
- Covered: `backupSeenChecks`. The words for the fact line with and without a backup, the status line, the Needs you item's title, detail and button, and the Lab still saying nothing about backups. On disk, with made-up folders: a server with one 23-hour-old backup, plus another tool's newer dated folder in a place GilaMonster wasn't given, the same kind of folder inside the server's own backup folder, an archive with no record beside it, and a dated folder inside the added storage. The listing has one backup, 23 hours old, and the other tool's files are still there afterwards. Then two GilaMonster backups in the added storage (4 days and 2 hours): three listed, the newest of all is the one in storage, each folder has its own newest time, a folder that wasn't given has none, and a record with no folder is given no place. The storage row's line for a backup, for none, and for a drive that isn't connected. From the source: the card's label and note, the list's note, the storage row's line with its connected-drive guard, and the picture fixture turning the drill off.
- Failing first: with `NeedsYou.swift`, `OverviewPage.swift` and `BackupsPage.swift` put back to main, 17 checks failed: 10 new word and source checks, 4 older checks whose expected words changed, and 3 date checks that were off by a second because a backup's record keeps whole seconds. Those 3 were a fault in the new check and now use a whole-second clock. They pass on old and new code alike, since the listing itself didn't change; they hold the rule in place.
- Old-backup warning: there is none. Needs you has "No backup yet" (now "No GilaMonster backup yet") and nothing that fires on age, so a fresh backup somewhere else has nothing to silence. A check says so, so adding one later means deciding what it counts.
- Pictures, looked at by hand: `scripts/snapshot-fixtures.sh` with `PAGES=overview,backups`, Bold light and dark, at `HEIGHT=1900` so Saved backups is in the picture, and Overview once more with `BACKUPS=none`. The first Backups picture showed "The last drill failed" and an open issue: the app's ticker had run the weekly drill on the placeholder archive during the snapshot. The fixture now turns the drill off for that server. The ticker running in a snapshot at all is on the lead's list.
- Gaps skipped (and why): counting another tool's backups (GilaMonster has no way to register a folder it doesn't write to, and guessing paths or reading unknown archives would claim backups it can't vouch for; a watched folder is a feature for the lead to decide); the session `backup-status` answer, whose `lastBackup` is GilaMonster's last run and has no words to relabel; VoiceOver's speech (the new lines are plain text in existing views); a real drive being unplugged (the row's guard is `DriveCheck.isConnected`, covered by `driveFallbackChecks`).

## 2026-11-26: a listening server is seen as answering (K822)
- Promises: whether the address a tunnel forwards to answers is decided by a plain connection that sends nothing; a server with Paper's `proxy-protocol` on, or with `enable-status` off, is ready when it listens, and no status ping is sent to it; a refused connection on a running server is not ready; a refused one while the server starts, a timeout and any other error are unknown, with the reason in words; unknown never reaches Needs you; a start or stop clears the last answer.
- Cause, found on 2026-11-26: the game check used only the status ping. A server with `proxy-protocol: true` drops a ping that has no PROXY header, so a healthy server read as "Nothing answers" for as long as it ran.
- Covered: `localAnswerChecks` in `ConnectionChecks.swift`, on real sockets through the real probe. The stand-in servers bind 127.0.0.1 with plain IPv4 sockets (`::1` is checked as refused). One drops the ping: ready with `proxy-protocol` on, ready with status off, unknown with neither. A tunnel written as `localhost` finds it. One answers the ping. A closed port: refused, not ready when running, a warning when stopped, unknown while starting, then ready once a stand-in starts late on that port. One that never accepts, with its queue full: undecided at the time limit, unknown for a game and a web service. With made-up answers: no ping is asked with `proxy-protocol` on, and another error is unknown with its reason. `ConnectionCheck.problems` lists not ready and needs a look, and leaves out unknown, turned off and not checked. `PaperGlobalSettings.proxyProtocol` reads true, false, a comment, a deeper key, another section, quotes and no file.
- Failing first: with the old local check put back under the same tests, 17 failed, including every proxy-protocol, timeout and starting case.
- Full suite, 2026-11-27, from a scratch build under the shared test-server lock: 4246 passed and 1 failed, the `gilamonster-mcp` check, which can't run from a scratch build.
- Gaps skipped (and why): a real Paper server with `proxy-protocol` on (the stand-in drops the ping the same way; no ping was sent to the owner's server); the Connections card and Needs you on screen (the wording comes from the checked function; the badge for unknown still reads "Not checked"); clearing `connectionProblems` when the state changes (a one-line `didSet`, read in the source; a state change needs a server process); a server whose running settings differ from the file because a change is staged (it reads as unknown at worst).
## 2026-11-26: a test copy's own settings (K814)
- Promises: with `GILAMONSTER_HOME` set, every saved setting lives in `preferences.plist` inside that folder, and the app's own settings are neither read nor written; without it the store is `UserDefaults.standard`, as before; `GILAMONSTER_SERVERS` alone moves nothing; a relative or empty folder still gives a full path, never a settings domain; if the file can't be opened the app stops, it doesn't fall back.
- Covered: `appDefaultsChecks` (the place and the store for no variable, the servers variable alone, a folder, a second folder, a relative and an empty value; a saved value and the theme read back from the folder's plist on disk, absent from the app's own settings and from another folder's store; this run's own store is inside its scratch home; no first-launch folder question when `GILAMONSTER_SERVERS` names the folder; a read of the app, core, advisor, session and MCP sources that fails on `UserDefaults.standard`, a `.standard` default argument, `defaultAppStorage`, `@SceneStorage`, a frame autosave name, or an `@AppStorage` without `store: AppDefaults.store`). It runs in the full suite and with `--connections`. The checks themselves now save to the scratch home, which the run deletes.
- Gaps skipped (and why): the stop when the file can't be opened (macOS accepted every full path tried, so there is no honest way to force it); the real app's settings before and after (never opened, by the rule against touching them; identity with `UserDefaults.standard` is the proof); the window frame, saved window state and open-panel folders, which macOS writes to the app's own settings whatever the store is, so a test copy that must not share them needs its own bundle id.

## 2026-11-26: the Hosting card with an empty library (K812)
- Promises: Resource Packs shows the Hosting card whatever the library holds, so the Serving badge, the switch for only players joining and Add an Exact Pack are always reachable; the switch's choice is saved; publishing still needs a library pack and still comes first once its folder is set.
- Covered: `packCardChecks` (the page's source draws the card once with no condition around it, read by brace depth, and the reader is checked against a made-up page; the card's serving row, badge, switch and exact pack rows; the switch saved off, read back from disk and saved on again). It runs in the full suite and with `--connections`.
- Gaps skipped (and why): a click on the switch in the running app (a wrapper over the checked setter; the page was drawn off screen and looked at); serving with only players joining (already covered by `packGateChecks`); a real server with an exact pack (`--demo-pack` boots real Paper, left to the owner's test).

## 2026-11-26: pixel type (K820)
- Promises: one screen title in Pixelify Sans 700, Departure Mono on headings, labels, buttons, badges, tabs and numbers, the system font on anything that wraps; labels are 11 pt at the default text size and snap up to the next sharp size, never down, again when the screen's scale changes; controls grow with the labels; Bold Text sends labels, buttons and numbers to the system font at their usual weight, which macOS bolds itself, and keeps the title in Pixelify 700; a 1x screen above the default size uses the system font for labels; signs and arrows go through one helper in the system font, and no label has a character its face lacks; only card headings get extra spacing, and VoiceOver gets them as written; the Allow prompt never breaks a server's name; a Pixel font setting, on by default, off on a first launch with larger text, Bold Text or only 1x screens, and remembered; off uses no pixel face; a font that fails to load falls back to the system font; both fonts and their OFL files are in the app bundle.
- Covered: `pixelTypeChecks` in the plain run. The snap at every body size macOS offers, on Retina and 1x (never under the target, always a whole number of screen pixels per font pixel, never a size further than needed); the face, size and weight of every kind of text at the default size, with Bold Text, on 1x at and above the default size, with the setting off and with either font missing; the first-launch rule and that a saved choice wins over it, in scratch settings domains that are removed; `FontFiles.register` with a missing file, a file that isn't a font, and a broken file ahead of the real one; each font's character map read with CoreText, against every string on a line of the app's source that sets a pixel face, plus the section, check, feature and state names from the models; the rule shown to catch a sign in a label, a tick on a button and a missing character in a title, and to pass the same sign through `SymbolText`; heading spacing in one place only; the no-break form of a name and the cut around a long one; the growing parts by their source lines (buttons, the switch, the Upgrade picker, status symbols, disclosure arrows, glyphs, the sidebar); no view setting a system text style of its own; the licence text, the font file's SHA-256 and the copy lines in `build-app.sh`. `snapshotOverflowChecks` (`--snapshot`) now draws with pixel type on, and adds heavy-data runs at 16.5 and 22 pt labels.
- Failing first: the logic is new, so it was broken on purpose and the checks run again. Rounding the snap to the nearest size failed 9 checks; leaving Bold Text out of the label rule failed 6; turning the first-launch rule's text-size test around failed 2; dropping the off rule for the status sentence failed 1; a plain "▾" in the server switcher's label failed 2. The older `desertChecks` fingerprint of the Allow list still gives main's value once the K820 pieces are put back by their exact text.
- After review, 2026-11-27: Bold Text no longer asks for bold. macOS bolds the system font itself, so labels were thickened twice in the pictures; they now keep the weight they had. Putting the old rule back failed 10 checks. The setting's hint now ends "to use the system font for them", since off keeps Lilita One on the status sentence, a player's name and the Allow sentence; the hint's words are one constant, and a check holds them to what off does for each of the four things it names.
- Run, 2026-11-27, under the shared test-server lock: the full suite, 4597 passing and none failing; `--snapshot`, 18 passing, after one fix. Its too-wide run reported 18 for 17 pages, because Players is drawn twice and each drawing added a line; the report now names a page once, and a source check holds that. The suite ran one commit before that fix, which touches only the debug snapshot; `--look` (new: the look's checks only, starting no process; 538 passing) and `--snapshot` ran after it.
- Pictures, looked at by hand (normal made-up data, three pages and the dialogs per run, each report showing no page wider than its window): Overview, Lab, Plugins, the Allow prompt (a short name, a name that takes its own line, a name cut in the middle) and Settings, in Bold light and dark, with Increase Contrast, at 16.5 and 22 pt labels, with Bold Text, at 1x at the default size and above it, with the setting off, and a first launch with Bold Text.
- Gaps skipped (and why): the real Text Size, Bold Text and Increase Contrast settings (a snapshot can't change System Settings, so it stands in for what the Mac would report and the rules run from there; whether macOS gives a third-party app its Text Size through the preferred body font is the one thing the code assumes and nobody has seen); VoiceOver's speech for headings, the prompt and disclosure rows (the labels are in the source and checked there); a window dragged between a Retina and a 1x screen (the report on a scale change is checked in the source); the built app bundle loading its fonts from Resources (the copy lines are checked, and the debug build loads the same files from brand/fonts); dynamic names such as a server's or a plugin's containing a character Departure Mono lacks (they can't be read from source; each pixel font names the system font as its fallback).

## 2026-11-26: the Lab and required plugins (K804)
- Promises: what a `paper-plugin.yml` requires is read (required unless it says `required: false`, in the server or bootstrap phase, written as a block or inline) and its optional plugins are kept apart; a plugin and everything it requires share one Lab group, the earliest any of them was in, with worlds and permissions still first; optional plugins move nothing; a plugin whose required plugin is left out, not installed, turned off or skipped itself isn't installed in the lab and is reported as skipped with what it needs, in words, and never turns the light red; inside a group, the plugin that didn't load stays failed and one that only required it is skipped; each group's restart log stays with that group's result after the lab is deleted and after GilaMonster is opened again; results saved before logs were kept still open.
- Covered: `labDependencyChecks` (the nested format with a default, an explicit true, an explicit false, both inline forms, both phases and a later section that also has a `required` key; a `plugin.yml` not read that way; a real jar; a chain of three across groups; a plugin sorted after what it requires; two that require each other and one that names itself, with grouping ending and nobody lost or doubled; an optional plugin staying put; a made-up server whose lab gets only the plugins that have what they require); the skipped group in the same file (the exact words for left out, not installed, turned off and skipped too; several needs in one sentence; a circle that runs and a circle that's skipped; the row's outcome and title; a group's badge; the light's rule; the count under the check; the plugin at the root of a failure staying failed, and a circle of failures staying failed); `labRestartLogChecks` (two groups each keeping their own log and a skipped group keeping none, through a stand-in run that deletes its lab, read back by a new controller, an older result with no log field, a second run replacing the first, and the 400-line and long-line limits).
- Failing first: the ten checks that use what was already there (reading, grouping and the lab's jar list) were run against the code before the fix and all ten failed. The rest use functions the fix added.
- Real run, 2026-11-26: `--lab-model` on a folder of four made-up jars, Paper 26.3, one throwaway lab on 127.0.0.1 under the shared test-server lock. Two plugins came back skipped with their reasons, the left-out one was named, the lab was deleted, and the group's result held a 101-line restart log from the stop to the bot rejoining. `--lab-model` now prints each group's log length and last lines.
- Gaps skipped (and why): the Skipped badge, the row and the Restart log as VoiceOver speaks them (the row's mark has the spoken label "skipped" and the words say Skipped; seen in off-screen pictures in the bold theme, light and dark; not tried with VoiceOver); Copy Log as a click; the older list form of `dependencies` from Paper 1.19.3 (GilaMonster's plugins target 26.1 and up); a plugin that requires a newer version of a plugin than the one installed (Paper's format has no version field). Also not run: the settings, upgrade and fresh checks with a skipped plugin on a real lab (they take the same list from `spec(copying:)`, which is checked), and a restart that fails on a real lab, so the failure sentences were read in code only.

## 2026-11-26: Keychain banner accessibility (K809, after the accessibility review)
- Promises: the spoken line for a wait says where to look; how the wait ended is spoken every time, and an ordinary launch says nothing; the denied banner stays in place through a retry, with its button gray and the focus moved to Dismiss; the wait banner is no Tab stop and is read as one item; the retry button is called Try Keychain Again; button outlines and the focus ring are held to the contrast minimum on every callout wash; the snapshot can draw a made-up wait and a made-up no.
- Covered: `keychainWaitChecks`: the spoken wait line word for word; the three outcome lines; `report` staying quiet for a read that came straight back, speaking once after a wait that was shown, speaking every no (two in a row), and speaking a yes on a retry; the banner list for nothing, a wait, a no, a retry before and after the threshold (one banner, no second notice), and another wait during a retry; the same outcomes through the real service for allowed, denied, Try Keychain Again, a failed read and off during the wait; the snapshot's made-up states telling the app nothing. From the source: no `.focusable()` in the banner, the focus move before the button goes gray, the button's label, the forced announcements, the announcer saying an outcome even when the same words were just said, the callout's two new options, the snapshot switch and the script refusing any other word. `paletteChecks`: `controlBorder`, `popText` and `accent` on all four washes are listed pairs; the plain outline on the light Increase Contrast danger wash is 4.5:1 or more, and the wash it replaced was under.
- Pictures, looked at by hand: `scripts/snapshot-fixtures.sh` with `KEYCHAIN=wait` and `KEYCHAIN=denied`, Overview, Console and the welcome screen, in Bold light, Bold dark and Quiet light. The first pictures came out with the page pushed up out of view, further the longer the banner's second line was. The cause was in the shared callout: its detail text is held to its full height, and in the banner row above the page that height was worked out far too tall. A callout with no detail, or a short one, drew correctly. Both Keychain banners now set `inBannerRow`, which lets the row size the detail, and the pictures are right. Whether the real window did the same was not seen, since the app wasn't launched on screen. The other callouts with a detail in that row (a server running outside GilaMonster, a finished test copy) still use the old layout and are on the lead's list. The snapshot also now draws at the real window's minimum size (1120 by 640), which did not change the result.
- Gaps skipped (and why): VoiceOver's speech and where the focus really lands after the retry button goes gray (by hand; the checks read the source); the retry state as a picture (it is the denied banner with other words and a gray button, a style drawn elsewhere); Increase Contrast as a picture (held by the color checks).

## 2026-11-26: a visible Keychain wait (K809)
- Promises: a Keychain call that can wait on a person never runs on the main thread; once one has waited 2 seconds the app shows a banner saying to look for the macOS password window and what is waiting, and the banner goes when the call returns; a no is shown with what won't work, and is never worked around by making a new token; a session that asks while the token is waited for is refused with the reason, and nothing is allowed without the token; one Mac notification is posted only when macOS already allows them, and nobody is asked for permission.
- Where the Keychain is used, and what can wait on a person: the session token read (`SessionAccess.readToken`, at launch and when session access is turned on) and Make New Token, both already off the main thread; the Advisor's Allow Keychain Access (`KeychainVault(interactive: true)`), which ran on the main thread and now doesn't; the helper's `--allow-keychain`, a separate program. The Advisor's quiet reads and the connection secrets' presence check turn macOS prompts off, so they fail at once.
- Covered: `keychainWaitChecks`, with a stand-in Keychain that blocks its thread until released. The banner's state: off for a quick call, off before the threshold, on after it, one notice for two overlapping waits, off when the last returns, and no late timer. The stand-in is never called on the main thread. Over the real socket during a wait: the right token, a wrong token, a listed command and an action all get the waiting refusal, nothing is sent or put to the owner, a request with no token or unreadable JSON hears that, all six calls are logged as refused without the token, and the Keychain is asked only once. Allowed: listening, the right token answers and a wrong one is refused. Denied: banner off, denied message on, no socket, no token, one Keychain call; Try Again asks once more. A failed read and an empty token close the socket. Off during the wait stays off; off and on during the wait ends listening with one Keychain call. The mapping from a Keychain answer to a token, a no, missing or a failure, and the real read against a throwaway keychain file. The notification rule for every authorization value and with Mac alerts off. The words. The app's source: where the banner sits, the callout it uses, that nothing in it moves, the forced VoiceOver line, the notification guard with no permission request, and that no screen calls the Keychain's functions or the token's directly.
- Gaps skipped (and why): a real macOS password window, allowed and denied (it can't be triggered without asking the owner, and the owner's app is running; which status macOS returns for Deny is taken from its headers and from the Advisor's existing mapping); the banner as a picture in light and dark (it is the existing callout, whose ink on the warning and danger washes the color checks hold to 4.5:1); VoiceOver's speech and the Tab stop (by hand); the notification as macOS shows it (the rule is checked, the post isn't); saving or removing a connection secret, which writes on the main thread from a button and could wait only if the login Keychain is locked (left as it is, on the lead's list).

## 2026-11-26: four fixes (K798, K799, K800, K801)
- Promises: the Allow prompt's buttons are never narrower than their labels, and nothing else about the prompt changed; a Lab switch shows on or off with its knob at one end, and a locked one says so to the eye and to VoiceOver; a disabled button's label has 4.5:1 or more on its fill in both themes; every stop GilaMonster asks for is written to the server's stop file with what asked before anything is sent, and every exit is written with its code, as from outside when nothing here asked; the stop file can't grow past its cap and holds no player data; leftover backup clones are removed at launch, only by GilaMonster's own name pattern, only real folders, never through a link, never while a backup runs.
- Covered: `desertChecks` (the same fingerprint value as main with two exact layout strings taken out, `.fixedSize()` on all four buttons, no truncation, the 580 pt minimum); `controlLookChecks` (knob ends, the lock, every knob, lock and edge pair in both themes, four appearances and five color visions, an unknown color name failing closed, the spoken values, the Lab's source, the disabled label at 4.5:1 or more in light and dark for Bold and Quiet, and the old half-strength figure under 4.5:1); `stopLogChecks` (words and keys for every source, lines read back, the exit carrying its ask, a damaged line skipped, long names cut, 3000 lines staying under the cap with the newest kept, the Overview sentence for each case, and the source of every caller); `stopLogLifecycle` with a real Java process on the stand-in jar (a button, a session, stop typed in the console, a SIGTERM from outside and a restart, each read back from the file); `backupCloneChecks` (the name pattern, a backup running, a wrong folder, leftovers removed with everything else kept, a link inside a clone not followed, a link with a clone's name kept, a linked clones folder and a linked parent refused, a missing folder, several server folders swept once each, and the wiring).
- The stop methods take their source with no default, so a new caller that names nothing doesn't compile.
- Gaps skipped (and why): the Allow window on screen at a larger macOS text size (the row was measured in a standalone SwiftUI copy at 13, 20 and 28 pt; the app wasn't launched, since the owner's servers run under the installed one); the switch and the disabled button as pictures, and VoiceOver's speech; the Server menu's shortcut against a click (one line reading the current event, checked as a rule and in the source); quit, shutdown, logout and signal stops end to end (each passes its source to `stopAll`, read from the source; the write itself is the same code the lifecycle check runs); the sweep at a real launch and the other-copy-running guard (AppKit, read from the source); the stop file's privacy beyond its fields (it has no field a player's name could enter by, and the lifecycle check looks for one).

## 2026-11-25: the desert redesign (K786)
- Promises: every page stays reachable from five sections, each page in exactly one; ⌥⌘1 to ⌥⌘5 pick a section without taking another shortcut, ⌘1 to ⌘9 still open pages by number, and ⌃Tab wraps along the trail; a state always shows a distinct shape with its word; player faces are made on the Mac from the name with no network; the Allow prompt keeps its wording, order, default, focus, countdown, Need More Time, Allow for Today, Escape and click guard byte for byte; text is 13 pt or more; Reduce Motion stops the trail slide and the status pulse; decorative art is hidden; every color pair passes 4.5:1 text and 3:1 controls, and 7:1 and 4.5:1 with Increase Contrast, in every color vision.
- Covered: `desertChecks` (sections and coverage against the app's page list, digits, spoken bead labels, trail stepping and wrap, landing page, badges; the shortcut table read from the menu source with no other view claiming a digit or ⌃Tab; glyph shapes and the state mapping; face determinism, art colors only, initials, no URLSession or http in the art code; the sentence and fact line; roster order; a fingerprint of SessionAskList with fonts removed, equal to main's, plus button order, Deny default and focus, Allow never default, countdown text, guard and Escape, and a tamper case; the font file, its OFL licence and the bundle copy; no small text style in any view; motion and accessibility markers read from source; the Increase Contrast minimums, a gray that sits between them, and the new palette values); `paletteChecks` now applies the stricter minimums in the two Increase Contrast appearances.
- By hand, 2026-11-26: a renamed copy (own bundle id, made-up folders) driven by key presses posted only to its process, reading the accessibility tree after each. Every section and page shortcut, ⌃Tab both ways, Tab into the spine, ↑↓, Return and Space passed, and focus moved to the new section's chosen page after a section change (the accessibility review's finding, fixed in this pass). Section tooltips now name ⌥⌘.
- Gaps skipped (and why): VoiceOver's own speech (the tree it reads was checked instead); Reduce Motion as a live setting (it changes the whole Mac; read from source only); the window toolbar (not drawn by the off-screen snapshot); the snapshot of the Allow prompt uses a separate made-up service, so the shared service isn't touched, and the panel's placement and sound are unchanged code.

## 2026-11-25: case-variant adds on offline servers (K755)
- Promises: on an offline server, a name spelled with other capitals than one on the allowlist, in player files or in Multiverse-Inventories files is refused by every add path, naming both spellings, with nothing typed, sent or queued; exact spellings, other names and online servers pass.
- Covered: gilamonster-check main.swift, the K755 block (PlayerMerge.addRefusal on each source; requestAccess, sheriffApply and createInvite refuse with the same words; waitingAccess empty; console empty; online passes).
- Gaps skipped (and why): Sheriff's own check on the server side belongs to Sheriff's repo (filed for the Games lead); on-screen sheets not driven.

## 2026-11-25: case-clash merges (K161) and checks that clean up (K744)
- Promises: a merge never writes one player's Multiverse-Inventories files onto another's, because files are named by player and a Mac's disk folds capitals; a refused merge names both spellings, says nothing changed, and changes nothing (no file, no archive, the server isn't stopped); the checks remove every settings domain and file they make, and the snapshot run doesn't write the app's saved server choice.
- Covered: the K161 group in main.swift (a merge into a spelling another player uses, with both names in the words; apply throws the same words; every inventory file unchanged and no archive; two spellings of one name; a stray file with another spelling and no player; a clean merge and the same name twice allowed; no plugin, no clash); `scratchDefaultsChecks` (runs at the end of the full suite and of `--connections`: no file of a domain this run made is left); an atexit hook also removes them if a run dies.
- Gaps skipped (and why): the merge sheet on screen (a wrapper over the checked rule); the snapshot not writing `selectedServer` (needs the debug GUI run, checked by reading the defaults before and after `--snapshot`); a snapshot restore or an allowlist add producing a clash (neither writes a second player's file; the existing warning stays).

## 2026-11-24: the full-review release (0.5.0)
- Promises: lists past their limits are cut with a way to see the rest and lose nothing; long errors keep one sentence as the title and the whole text in the detail; names stay on one line; Need More Time extends an ask by a minute, three times at most, and never allows it; the click guard holds pointer clicks only; text size stays between 9 and 32 points; no page is wider than its window with heavy data, and that measure can fail; search appears past 12 allowlist entries and the worlds filter past 10; Allow and Deny still work after more time; link buttons keep ink contrast on every background.
- Covered: `overflowChecks` (callout split, slice, limits, matching, which worlds load at startup, changes grouped by kind, console words, text size, reading the snapshot report); the Need More Time group in `sessionActionChecks` (three extensions work and the fourth is refused, the wait grows, the answer is still no, nothing changes); the click guard in `sessionAskPlacementChecks`; `gilamonster-check --snapshot` for the heavy fixture in Bold and Quiet, light and dark (old reports deleted first, every page must be drawn: N of M), plus a run with every page made too wide on purpose that must report every page; the search and filter thresholds, the Update badge text, the online word, the 1 second quiet period, and Stop's shortcut read from the menu source; text size against the literal 9 to 32; `linkButtonColorChecks`.
- Gaps skipped (and why): the Escape key and the Window menu item (UI wrappers); the dropped-click dimming; everything VoiceOver says (announcements, the ask panel taking focus, chart descriptors, hints) because it can't be run from the suite and wasn't tried by hand; the Show More and Show All buttons and the collapsed Not loaded group as clicks (state and slicing are checked, the views are seen in the pictures only); Command-plus and Command-minus as key presses; the theme change keeping an open sheet open.
- Not in the default run: `--snapshot` needs a debug GUI build and several minutes, so it runs before a release, not with every `gilamonster-check`.

## 2026-11-24: Quit question (K728, 0.4.1)
- Promises: a quit with servers running names each one, says the pack downloads and session access stop too, and keeps everything running on Return.
- Covered: wording for one server, several, servers left running, and with or without the pack host and session access (`quitWordingChecks`); the alert's button order and default read from the source in the same group.
- Gaps skipped (and why): the alert on screen. NSAlert's own key handling is AppKit's, and the button order and key equivalents are checked; seeing it is part of the next real quit.

## 2026-11-23: the GilaMonster rename (D271, 0.4.0)
- Promises: every name the app shows, writes or reads is GilaMonster (bundle id, data folder, per-server folder, own folder beside the servers, Keychain services, environment variables, tools); the palette keeps WCAG AA everywhere; older recipe exports still import; Sheriff accepts the new source word; nothing in the app moves old data by itself.
- Covered: the full suite (3647 checks) under the new names, including every palette pair in both themes, four appearances and five vision simulations (`paletteChecks`), the Theme setting's default, saving and unknown values (`themeChoiceChecks`), and no color written into a view outside the theme (`noHardCodedColorChecks`); the app half's switch by `ops/scripts/rename-d271-rehearse` (24 checks, forward and back on a throwaway copy) and the Keychain helper by `rename-d271-keychain-test` (12 checks, no UI); a search showing no old name in any tracked file.
- Gaps skipped (and why): the views on screen under the new palette (screenshots before and after, compared by hand; the heavy-data pass and overflow test are 0.5.0); VoiceOver and keyboard (an accessibility review read the code; its findings are 0.5.0, apart from Settings keeping focus on a theme change and Quit's ⌘Q, fixed now); importing a real older recipe export (the check is the kind's ending, covered by the existing export and import check under the new kind).

## 2026-11-23: Allow for today (K721)
- Promises: one click on a waiting ask allows that kind of action on every server until local midnight; it covers only the listed kinds (power, pack serving, publish, Packmule handoff, pack addresses) and never removals, naming a player, deletes, restores or world resets; each covered action checks nobody is on that server, asks as usual when someone is, and refuses when that can't be told; each shows a notice, a server log line and a record entry; the menu bar revokes all; grants are memory only, and no file, socket call or request field makes or extends one.
- Covered: `TodayGrantChecks.swift` (8 groups): the family table and the never-covered list; midnight in a fixed time zone, a second click not extending, revoke, not Codable; the online rule for every server state, plus a real never-started server; unknown session calls and request fields ignored, a click for a request that isn't waiting making nothing; a grant covering a second server and not another kind, a removal offering no Allow for today and a click on it doing nothing; players online asking, unsure refusing with nothing changed; after midnight asking again, a new click the next day, revoke; a fresh service with no grants, record notes, nothing but the record written and no grant file in either server's folder.
- Gaps added after the security review: a hidden player's login line counted and a chat line shaped like one not; a revoke during the online check asking as usual; a clock set back not covered; midnight on the day the clocks go back; what went ahead listed for the menu bar; a job starting while the owner is asked stopping a session's start; a recipe name with a line break refused.
- Gaps skipped (and why): the button, notification action, notice and menu item on screen, and the click lock after rows shift (UI wrappers over the checked service; to be seen after the release); start, stop and restart under a grant end to end (needs a real server and the owner's go; the grant path is the same one the pack-address checks prove); a real start or stop through a grant (needs a real server and the owner's go); the management server's live answer (the rule is checked, the call is the one GilaMonster already uses).

## 2026-11-23: Overview redesign (K672)
- Promises: Needs you shows no backup, automatic backups off, a backup drive running low, serious issues, connection problems, plugin updates and a software update, most urgent first, and says "Nothing needs you" otherwise; the Lab shows no backup, drive or connection items; the status line says state, uptime, players and the last backup.
- Covered: `needsYouChecks` in main.swift (14 checks: each item, order, wording, plural and singular, the cut connection list, the Lab, four status lines).
- Gaps skipped (and why): the drive warning's sizing reuses BackupCaps.warning and BackupCaps.used, already covered in BackupCapChecks; the buttons only call existing actions (backupNow, page changes). The screen itself wasn't looked at, and neither a real near-full drive nor a broken tunnel was tried.

## 2026-11-22: K692 (servers outliving GilaMonster)

- Promises: a shutdown the server ran itself, with no crash line, is a stop and isn't restarted; any crash marker wins; only exact, non-chat shutdown lines count; signals to the app stop servers with a save; left-over servers are stopped when quitting.
- Covered: `shutdownSignalChecks` (11 checks) and the stand-in lifecycle's outside-SIGTERM run (no restart after 12 s with restarts on, console note). The existing crash check still sees a crash, now with the stand-in's shutdown hook logging "Stopping server" after it, so crash markers winning is covered on a real process.
- Gaps skipped (and why): the signal handler and the quit question with a left-over server need the app running, and the app the owner uses mustn't be signalled. Left for his next restart of GilaMonster, or a separate build in another folder.

## 2026-11-22: 31 changes since 2026-11-14

- **Promises added since the last audit:** backups go to one drive only, are skipped while the drive is missing with no fallback to the Mac's disk, are capped on a shared drive, leave no partial file after a quit, say when macOS blocks a drive, and resume saving as soon as the files are cloned (D213, D215, D250); quitting during a backup asks first; sessions can start, stop and restart servers and manage packs only behind Allow and the children mark, and each session ask opens its own window, reaching the owner during a Focus; typed patterns in the command list; no server starts at launch unless its box is on; the lab is built per status-board run and deleted when the run ends; Packmule's link check lets only joining players past; token downloads use a real HTTP client; plugin source badges; the old Sheriff and WelcomeWagon list formats are no longer read; the build refuses to overwrite a running app; the shutdown quit handler is registered in release builds.
- **Covered:** backups by `BackupCapChecks.swift` and `DriveFallbackChecks.swift`, and the resume in `main.swift`; session powers and refusals by `SessionActionChecks.swift` and `SessionAccessChecks.swift`; asks by `SessionAskChecks.swift`; patterns by `CommandPatternChecks.swift`; launch by `LaunchStartChecks.swift`; the lab by `LabRunChecks.swift`, including its deletion; the pack gate and downloads by `PackGateChecks.swift`; the pack card by `PackPublishChecks.swift`; badges by `PaletteChecks.swift`; the old formats by `PluginCommandChecks.swift`; the build guard by `scripts/test-build-guard.sh`.
- **Gaps added:** the shutdown handler had no guard against slipping back into the debug-only block, which is how release builds lost it (6b44886). `scripts/test-release-quit.sh` now checks that, with a self-test, and runs in CI.
- **Gaps skipped (and why):** the wording of the drive-only failure notice, the server menu's state dots, the outlined switches and the status board's station wording are on-screen text and styling, checked by eye. The signing script's stable certificate is build plumbing with no user data at stake. A real Mac shutdown is still untested, as in the last audit.

## 2026-11-14: quitting at a Mac shutdown (K650)

- **The reason codes:** 'shut', 'rest', 'rlgo' and 'logo' are a shutdown, a restart and a log out, none of which waits
  for an answer. No reason, or any other, is a person quitting, who is still asked.
- **A simulated shutdown, end to end:** the real app (a sandboxed copy with its own bundle id) ran a throwaway Paper 26.3
  server on 127.0.0.1. It was sent macOS's own quit request carrying the shutdown reason. No question appeared, the
  server logged "Stopping server", "Saving players" and "Saving worlds", the app answered the request and exited, all
  within 4 seconds. A second run with the restart reason did the same. The sandbox was deleted afterwards.
- **An ordinary quit** stopped nothing. That test can't see the question itself, which needs a screen; its code is
  unchanged and is what the owner saw on screen.
- **What the test found:** in the test copy, AppKit's terminate never reached GilaMonster's check, so the shutdown path
  doesn't rely on it. It holds macOS's request, saves, answers, asks AppKit to terminate, and exits two seconds later if
  still running.
- **Not covered:** a real shutdown of this Mac. The quit request is the same one macOS sends, but loginwindow's own
  time limits weren't exercised.

## 2026-11-14: the plugin renames (D196, D197)

Real release jars, checked against their published SHA-256, on throwaway Paper 26.3 with made-up offline accounts:

- **Sheriff 0.5.0** (`--real-sheriff`): describe, profiles and apply through the console under the new name.
- **Sheriff 0.5.0 with WelcomeWagon 0.6.0** (`--real-invites`): an invite made here with a profile, redeemed on
  WelcomeWagon's own page in its new two steps (the code first, then "Yes, that's me"), the profile applied by Sheriff,
  the invite shown as used, a bot signed in with `/login`, GilaMonster's links page signing them in by WelcomeWagon's
  cookie, and Sign Out Everywhere ending every session. 0.6.0 counted only live sessions but ended every one; 0.6.1
  counts the same way for both, so the check asks for exactly the number shown, and passes against the real 0.6.1.
- **WelcomeWagon 0.6.0 sign-in** (`--real-signin`): no permission gives no link, off the whitelist gives no link, then a
  link that signs the page in, and nobody gets a link made for someone else.
- **Packmule 0.3.0** (`--real-packmule`): `pack set` refused a link nothing serves and kept the old one, as with 0.2.1.
- **What the runs found:** the in-game command is `/login` (two of GilaMonster's hints still said `/signin`), redeeming
  takes two steps, and WelcomeWagon's features are off until switched on. The checks now use its shipped config.

## 2026-11-14: publishing packs

- **Settings:** no folder and four bad web addresses refused.
- **Publishing:** a 64-character random path, the SHA-1 as the name, byte for byte, 0644. A new path every time. A build
  that doesn't match its hash isn't published and leaves nothing behind. Nothing else in the folder is touched, the
  record never goes there, and the disk guard applies.
- **Cleanup:** not within ten minutes, not while someone online at the switch is on, then the old one goes; the current
  build never does. A record that isn't a random path removes nothing, and a folder holding anything else is left alone.
- **Through a made-up server:** publishing the same build twice is refused; old waits, then goes after the grace time.
- **Telling Packmule:** through a stand-in Packmule 0.2.1. With no pack name it says to copy by hand. A confirmed
  answer marks the build in use, and the exact command is typed. A failed download check, an unknown pack, and
  Packmule 0.2.0 are each refused in plain words, and the build isn't marked. Six unsafe links are never sent (http, no
  SHA-1 name, a space, a `;`, a line break, a user name).
- **Cleanup waits for Packmule:** an old build stays while the current one isn't confirmed in use, however long.
- **The real Packmule 0.2.1** (`--real-packmule`, the release jar) on throwaway Paper 26.3: GilaMonster's `pack set`
  reached the console, Packmule tried the link, refused it with `check-failed` because nothing serves it here, and kept
  the old link in its config. GilaMonster reported that in plain words and left the build unconfirmed. That proves the two
  speak the same format; a successful switch needs the real https join host.
- **Not covered:** a real Caddy serving the folder, a real client loading the published link, and Packmule's
  successful switch, which needs the real https join host.

## 2026-11-14: printed invite tickets

- **Latchkey's ticket:** the code goes after `#`; a join address under a path is used exactly. Ten bad shapes are
  refused: plain http, a user name, a query, another site, a link that adds a query, the code twice, no code, no join,
  no expiry, not an address. Five codes that aren't plain letters and digits are refused. Control characters are taken
  out of the name.
- **Through the stand-in Latchkey:** no ticket before 0.5; 0.5's ticket gets the code from the once-file; an odd link
  drops the ticket and still shows the code.
- **The QR code** reads back as the link with macOS's own QR reader. The text version has every step and spells the code
  out.
- **Not covered:** printing on paper, scanning with a phone, and the sheet with VoiceOver. The layout was checked from a
  rendered sample (`GILAMONSTER_SAMPLE_TICKET`).

## 2026-11-14: disk safety and smart backups

Covered:

- **Every refusal of the disk guard:**
  - unknown free space;
  - the real case (47 GB into 50 GB free);
  - the 20 GB floor, which a normal Mac with 47 GB free still clears;
  - a restore point refused before anything is written, with no archive or partial file left behind;
  - a copy to the second location refused the same way;
  - a drill with no disk that has room, or with only the running server's disk;
  - a backup with every disk nearly full, refused with the reason.
- **The in-flight floor:** a running job is stopped when its watch says so, and doesn't count as done. The watch stops
  below 5 GB and when free space can't be read.
- **When to back up:** 13 cases.
  - During play, under and over six hours.
  - After play, before and after ten idle minutes.
  - The minimum gap, including a gap set too low.
  - No backup yet.
  - Played but not seen empty.
  - A world that changed with nobody on, before and after a day.
  - No sign of change.
- **Settings:** a server from before keeps its schedule and keeping rules, a new one starts smart, missing fields take
  defaults, and targets survive a save.
- **Keeping:** everything from the last day, one a day for a week, one a week for eight weeks. Pinned backups and the
  first one are never deleted.
- **Where:** an unplugged drive is skipped without making its folder on this Mac, a file in a folder's place is
  skipped, a nearly full disk is skipped, and the first usable target wins. A real made-up server's backup went to the
  second target, in its own claimed folder, listed with its location and deleted from there. A restore point stayed
  home. A second server sharing the drive got its own folder and isn't listed by the first.
- **Mutations:** removing the gap, letting pinned or first backups go, dropping the floor, treating an unplugged drive
  as present, and skipping the idle wait each failed checks.
- **The trial** on a real Paper 26.3 server: `docs/backup-trial.md`.

Not covered by a check:

- The tick's one-hour back-off after a refused backup.
- The drill's own skip path on a real server. Its rules are covered.
- The Backups page controls with VoiceOver.

## 2026-11-14: the owner's Overview bugs and the sidebar

- **Version:** Paper's "running Paper version 26.3-249-…" line gives the build; chat-shaped text doesn't.
- **Issues:** three dimensions in quotes make one row counted three times; a HikariPool failure names its pool.
- **Pasted secrets:** each is found by where it is; moving them leaves no value in the file, points the connection at
  the Keychain, keeps the rest of the entry, and refuses something that isn't there. If the Keychain refuses, the file
  keeps the value.
- **Sidebar:** every page from the app's own list appears once, Overview first, groups in order, alphabetical inside,
  folded state remembered (unknown names dropped), and badges roll up from a group's own pages only.
- **Not covered by a check:** the card rechecking on a state change, and how the grouped sidebar reads with VoiceOver
  and the arrow keys. Both are SwiftUI wiring, listed for the hands-on pass in `docs/ux-audit.md`.

## 2026-11-14: session access

Covered:

- **Every refusal:** off, unreadable, too long, no token, a wrong token (and one a character off), no token in the
  Keychain, no caller or one with a line break, an unknown call, a command off the list, a listed command with words
  added or in other letters, part of a listed command, a second command after a line break, a control character.
  `stop` and line breaks can't be put on the list.
- **Allowed:** status, log (capped from 1 to 200 lines), listed commands with a slash or extra spaces.
- **What a session sees:** chat left out; names (any case, longest first, not inside longer words), UUIDs, IPv4 and
  IPv6 addresses replaced, with log times left alone. Status gives a count of players, never names.
- **The record:** both allowed and refused calls; the token never written; a caller can't break or bloat a line.
- **The token,** in a throwaway keychain: made once, read back, replaced.
- **The real socket and client:** private to this account, status, log, refusals with exit codes, every call recorded,
  turned off removes the socket, and a file in its place is neither used nor deleted.
- **A real Paper 26.3 server with a made-up bot** (`--real-session`): status shows one player without naming them;
  `list` and `save-all` run and their output comes back with the name replaced; `op` is refused and never reaches the
  console; the console notes the session's command; the real log comes back without the name or address.
- **Mutations:** accepting any token, allowing any command, showing chat and ignoring the switch each failed checks.
  Opening the socket with a looser umask didn't, because chmod makes it private as well; each guards the other.

Gaps skipped:

- **Another macOS account connecting.** The kernel's peer check refuses other accounts, but this Mac has one account
  to test with. The socket's 0600 mode is checked instead.
- **The Keychain prompt** a session sees the first time it reads the token. That needs the owner's click.

## 2026-11-14: colors, and three reported fixes

- **Colors.** Every pair the app draws (47), in four appearances and five kinds of color vision: 940 combinations, all
  at WCAG AA. The formula and the simulations are checked against fixed points. A weak pair fails the run, and the first
  run caught three real ones (see `docs/ux-audit.md`).
- **The `secret` field.** The README's own shapes (`agent`, `keychain`, `file`) aren't flagged. A value pasted straight
  into `secret` is named, not repeated, and dropped, keeping the rest of the entry. This was a gap: the first checks
  accepted any count of problems at or above six, so the false flag passed. They now check the documented shape gives none.
- **The database rule.** HikariPool's normal INFO lines from a SQLite plugin don't match. Two real pool failures do.
- **The start line.** "Starting minecraft server version" is read for 26.3 and 1.21.11. Chat-shaped and nonsense
  text isn't. The update to the saved record wasn't run against a real server here; the Server lead's next start will show it.

Gaps skipped: hands-on VoiceOver and keyboard use (no screen control this session; listed in `docs/ux-audit.md`).

## 2026-11-14: connections (tunnels and services)

The owner's requests of 2026-11-14 (see `docs/PLAN.md`). `gilamonster-check --connections`: 112 passed, also part of the default run.

Covered:

- **The file.** No file means no connections and no complaint. An unreadable file is reported, kept, and moved aside as `connections.json.unreadable` on the next save. Broken entries, a bad id and a repeated id are skipped, each with a reason. An unknown provider reads as Other and unknown traffic as admin access. An entry that doesn't say it's on is off.
- **Secrets pasted into the file.** Fields named like `token` or `authKey` are ignored and named, the value is never repeated, and saving drops them.
- **Addresses.** host:port, IPv6 in brackets and a bare name with the game's port are read. Nine bad shapes are refused.
- **Shown as not ready,** with a plain reason, for each of these: no playit agent, an agent that won't answer or answers garbage, a stopped agent, an agent with no secret, a secret missing from the Keychain, a secret file that isn't there or is empty, addresses that can't be read, a playit tunnel with no local address, a running server that doesn't answer where the tunnel points.
- **Unknown, never ready:** an agent that doesn't say whether it has its secret, and a locked Keychain.
- **Needs a look:** a secret file other accounts can read, recent refusals in playit's log for this address (older ones and other addresses don't count), a stopped server.
- **The 2026-11-10 case:** a tunnel forwarding to another address on this Mac while the server only listens on 127.0.0.1 is not ready, and the summary gives the fix. So is a tunnel to the wrong port.
- **Nothing over the internet unless asked.** The quiet check makes no public ping, HTTP request or lookup. From outside: game addresses get a status ping, web addresses an HTTP request (any answer counts, since pack serving answers strangers 404), names a lookup.
- **Off means off:** nothing about it is checked.
- **Real sockets on 127.0.0.1:** the status ping sees a fake server that answers it, doesn't mistake an HTTP answer for Minecraft, and a closed port isn't seen. The real lookup finds localhost.
- **A real keychain:** a throwaway keychain file, never the login Keychain. Missing, saved, replaced, removed, an empty secret refused, and a locked keychain not mistaken for a missing secret.
- **Mutations:** ignoring a missing Keychain secret, ignoring an agent with no secret, always checking from outside, checking a service that's off, and not flagging pasted secrets each failed at least one check.
- **The map and sign-in page.** Both read, saved and missing from older files. Five bad addresses refused. Unset says so and asks nothing; the quiet check never fetches; plain http is flagged. From outside: a page, a sign-in prompt (401) and a refusal (403) count as answering, 404 needs a look, a proxy error or no answer is not ready.
- **Beside the invite code:** the configured address, with Latchkey's named when it differs, Latchkey's when none is configured (labelled), and with neither the screen says so and still shows the code.
- **Read-only against this Mac's real agents** (`--connections --live`): the playit agent was found running with its secret, and its log showed the pack tunnel refused while pack serving was off.

Gaps skipped:

- **The real servers' values.** The Server lead enters them on this Mac; a check run on them comes after.
- **The editor sheet with a keyboard and VoiceOver.** Labels are set, but nobody has used it that way yet.
- **SRV records and PROXY headers.** Stated as limits in the README rather than handled.

## 2026-11-10: the code audit's fixes

The fixes from `docs/audit-2026-11-10.md` (the Server lead's code audit). Default run: 2742 passed, 0 failed, with 22 new
checks in "One long operation at a time". The real sign-in run (`--real-signin`) is updated for Latchkey 0.2+ (whitelist
on, the bot allowlisted to join and taken off to check the refusal); with the landing page off it waits on Latchkey 0.4.0,
which fixes sign-in-page in that case.

Covered:

- **One long operation at a time.** A held busy mark turns Start off; Start during a rename does nothing and leaves the
  rename's mark; a second long operation is refused; queued changes wait; Start holds the server from its first moment, a
  second Start returns without touching the first, and Start lets go when it's done even when it couldn't start.
  Removing the mark from Start failed 1 check ("Start holds the server from its first moment").
- **No line breaks into the console.** A player name, a world name and a seed with a trailing newline are refused, and a
  newline name never reaches a plugin command; a carriage return is escaped in `server.properties`.
- **Chat is never the server.** Chat lines are recognised in the console and in log files (including "Not Secure"), a
  server line isn't, chat saying "Result: true" isn't LuckPerms' yes, and LuckPerms' own line still is.
  Making `isChat` always false failed 2 checks.
- **Access around Usher.** With Usher, the raw allowlist add is refused; without online mode, a name-based op is refused;
  bans work as before.
- **Files and archives.** A gzip header with no end to its name fails cleanly; a restore swaps the file in whole and
  leaves nothing behind; a server jar name with a path in it isn't used; no checksum, or MD5 alone, isn't a published hash.
- **The web side.** A request with no player headers is refused before any file is read; BlueMap on its default address
  keeps `/map/` off, and with `ip: "127.0.0.1"` it's on.

Gaps:

- Two Starts racing for real, and Start during a real rename, are shown with the busy mark and a stand-in wait, not with
  two real JVMs.
- The pack-check pass staying on its own host, and refusing redirects, have no check yet (they need a second host).
- Map-access checks running one at a time are covered by reading, not by two simultaneous viewers.
- Left as task K386: a Modrinth hash match offered as a suggestion, real-size pack extraction, and a setting for the
  Modrinth checksum lookups.
- Each `gilamonster-check` run leaves a `gilamonster-check-<uuid>` preferences domain behind (about 66 on 2026-11-10).

## 2026-11-10: packs served only to players joining

The owner's request of 2026-11-10 (see `docs/PLAN.md`). Default run: 2710 passed. With `--real-pack` (throwaway Paper 26.3, bots): 2762 passed.

Covered:

- **The game's headers.** A name, a dashed or undashed UUID, and a version are read. Nine bad shapes are refused.
- **The server's log lines.** A UUID counts only from the login thread, and joins and leaves only from the server thread.
  - Chat can't vouch for someone or put them online, and neither can a line from another thread or one with text added.
  - A line from 23:59 read at 00:02 counts as three minutes old.
- **The decision.**
  - A player gets the pack 1 or 4.5 minutes after connecting, and while online.
  - Six minutes after connecting, or once they've left, they don't.
  - None of these get it: another name with that UUID, a UUID not on the whitelist, a player who's joining but isn't on the whitelist, an unreadable or damaged whitelist, an unreadable log, or no headers.
- **The real listener on 127.0.0.1.**
  - A joining player gets the pack.
  - These all get the same 404 as a wrong address: curl with no headers, a browser, a UUID not on the whitelist, the `.sha1` address, a HEAD request, a stale player, and no log to read.
  - A header sent twice is a bad request.
  - The app's one-time pass works once, a made-up pass is refused, and a pass lapses after two minutes.
  - Turned off, anyone with the address gets the pack. Turned back on, it's refused again.
  - Settings saved before this existed keep their addresses and get the check switched on.
- **Real Paper 26.3 with bots,** made-up offline accounts, deleted after. Each whitelisted bot that joined fetched the pack with the game's headers, built from the real server's own log, across a restart and for an exact pack. The same address without the headers, and for an unlisted UUID, got 404. The bot was still on the server three seconds later.
- **The older serving checks** turn the gate off, so they still test serving itself.
- **Mutations:** letting everyone through failed 4 checks, and dropping the time limit failed 4.

Gaps skipped:

- **A real 26.x game client.** That it sends the three headers comes from how the game has worked since 1.20.3. The bots send them because the check does. This is owner test T28, with `--demo-pack`. If the headers turn out different, every player would be refused the pack.
- **Through the playit tunnel.** It's plain TCP, so headers pass unchanged, but that wasn't tried. Pack serving on the real server waits on the owner anyway.

## 2026-11-10: the Advisor's token list, sealed with a key in the Keychain

The owner's decision of 2026-11-10 (see `docs/PLAN.md`). Default run: 2659 passed.

Covered:

- **Every PrivacyKey in the run uses a stand-in vault,** so the login Keychain is never touched. The real helper program and the real Keychain code use throwaway keychain files in the scratch folder, never added to the search list (checked before and after).
- **Sealed at rest.** The file starts `LJAK1`, the planted name and UUID can't be read from it, and there's no plain copy. One key is made, and the same key opens the file after a restart.
- **Failing closed, with a plain reason, and nothing written:**
  - a locked Keychain;
  - a refusal;
  - a key gone from the Keychain (no new key is made over the old file);
  - a different key;
  - one changed byte;
  - no key yet with a locked Keychain, where no token is given out and no file is written.

  Falling back to a fixed key on a Keychain error was tried on purpose and failed 6 checks. That also showed the locked and refused checks were too loose, because any refusal passed them. They now need the right reason, and the same change failed them.
- **The old plain `key.json`.** It isn't used while the Keychain is locked, and stays as it was. Once the key can be reached, its tokens carry over and the plain file is deleted. A plain file left beside a sealed one is never read. One that's a symlink is refused.
- **The real Keychain code, on throwaway keychains,** with prompts off as the helper runs. All of these happen at once, with no prompt:
  - a missing key;
  - a 256-bit key made once and read back;
  - a locked keychain, which says it needs access and makes no new key;
  - a key that doesn't trust this program, which says it was refused.
- **The real helper.** It reaches a key that trusts it. A key the app makes for itself and the helper opens for the helper with no prompt. A key made only for the app is refused to the helper with the denied reason. A locked keychain stops it with the needs-access reason. The helper's answers to an AI client still pass every earlier check, now with a sealed file, opened here to prove it holds no secrets.
- **Where the app may start programs.** Claude Code is started once, with `AdvisorLaunch`'s arguments. The helper is started only with `--keychain-check` or `--allow-keychain`.

Gaps skipped:

- **The login Keychain, macOS's own prompt, and the Allow Keychain Access button.** These need a person and their password. They're in owner test T25, which also seals the existing `key.json` on the owner's Mac.
- **Turning prompts on in the helper by mistake.** That mutation would show a real macOS prompt and stall the run, so it wasn't tried. The source and the check of the helper's two flags cover it.

## 2026-11-10: Latchkey 0.3, web sign-ins, and the Advisor's first audit

Latchkey 0.3's lobby and paging, Sign Out Everywhere on the player sheets, and the Advisor, which merged on 2026-11-09 without an audit entry. Default run: 2614 passed. With `--real-invites` (Usher 0.4.1 and Latchkey 0.3.0): 2579 passed, before the Advisor checks below were added. With Latchkey 0.2.0: 2578 passed.

Covered:

- **Latchkey 0.3's lobby.** Its status shows on the Invites card when Latchkey reports it, and nothing is shown when 0.2.0 doesn't. Real 0.3.0 reported it (off, on the throwaway's default settings).
- **Invite list paging.** Against a fake Latchkey:
  - every invite is read two to a page, none of them twice;
  - each page asks from the last page's cursor, checked word for word;
  - a long list stops at the page limit and says there's more;
  - a cursor shaped like a flag (`--yes`) ends the list and is never typed.

  Loosening the cursor guard failed 1 check: the runner refuses it as a second guard. 0.2.0's single page is still read.
- **Web sign-ins, offered only through `describe`.**
  - With 0.2.0, which doesn't list the session commands, nothing is shown, signing out is refused and no session command is typed.
  - With 0.3.0, the browser count is shown and Sign Out Everywhere ends every session.
  - A bad name is refused before anything is typed.
  - With Plugin commands off, nothing is asked.

  Making the `describe` gate always say yes failed 5 checks.
- **Web sign-ins, for real.** Real Latchkey 0.3.0 on throwaway Paper 26.3: the bot's one browser is counted, and Sign Out Everywhere deletes the session file and ends GilaMonster's page sign-in. The 0.2.0 run still proves that `whitelist remove` ends a session.
- **The Advisor, against `docs/ADVISOR-SECURITY.md`.** Each threat in its table maps to a section of the run:

  | Threat | Section |
  | --- | --- |
  | Chat or commands reach the AI | what chat can't do; text inside code |
  | Names, UUIDs and IPs | who's who; identity; a whole planted server |
  | Secrets | a whole planted server; the real program |
  | Forged identity | identity |
  | Changing the server, or network and process code | the real program (source rule 4) |
  | Reading other files | files outside the server |
  | Translating tokens | suggestions |
  | Guessable tokens | tokens and the key file |
  | A long line hangs it | a long line can't hang it |
  | Failing silently | failing closed |
  | The two independent reviews' attacks | the two review sections |

Gaps added, with the checks:

- **How Claude Code is started.** The flags that take away its shell and files (`--tools ""`), settings, hooks, slash commands, transcript and other MCP servers, and its short environment list, were only tested by hand when the Advisor was built. They lived in the app's page, which the run can't reach. They're now built in `AdvisorLaunch` and checked:
  - each flag is passed;
  - only the five advisor tools are pre-approved;
  - risky flags are never passed;
  - planted `ANTHROPIC_BASE_URL`, `HTTPS_PROXY`, `NODE_OPTIONS` and `CLAUDE_CONFIG_DIR` never reach it, and `PATH` is fixed;
  - a dismissed title can't carry `@`, a path or code into the prompt;
  - the app starts Claude Code in one place, with exactly these.

  Dropping `--tools ""` failed 1 check. Adding a variable to the list first went uncaught, because the check read the same list. The expected list is now written out in the check, and the same change failed 2 checks.

Gaps skipped:

- **The sheets and cards by hand,** with keyboard and VoiceOver. That's owner test T24.
- **Multi-page invite lists on a real Latchkey.** The throwaway has two invites. The fake covers paging, and real 0.3.0 answered in the spec's shape.
- **The Advisor with real data and Claude Code really running.** That's the trial, which waits for the owner's go on a real server. The flags are checked as data, not by running Claude Code.
- **The key file still isn't encrypted.** Encrypting it only helps with the key in the Keychain, and an unsigned app is asked for Keychain access again after every rebuild. That's a question for the owner.

## 2026-11-10: invites through Latchkey, and Latchkey's session files

The Allowlist page gains an Invites card on servers with Latchkey. It makes an invite with Usher profiles, shows the code once, and lists and revokes invites, all through Latchkey 0.2.0's format-1 commands. The links page and map gateway now also sign people in by Latchkey's session file, read in the agreed format on every request. Default run: 2535 passed. With `--real-invites`: 2559 passed.

Covered:

- **The session file (fail closed).** It's named by the SHA-256 of the cookie as sent, and unknown keys are ignored. No session in each of these cases: no `since`, expiry before sign-in, more than 30 days from sign-in, already run out, signed in in the future, a capitalised uuid, a bad name, not JSON, readable by others, a folder others can look in, a link elsewhere, or no file. Loosening the time checks failed 3 checks, and they were put back.
- **The links page by Latchkey's cookie.** Someone is signed in by it, but not once banned, off the allowlist, or after Latchkey deletes the file. An extended session counts at once.
- **Invites through a fake Latchkey.** It isn't offered without Latchkey, or with plugin commands off. Latchkey not taking invites is shown, with its reason. A bad name, 0 or 31 days, and a profile called "none" are refused before anything is typed. The code comes only from the once-file, which is deleted, and never appears in the console. A risky mix asks first. The typed commands are checked word for word. Invites are listed and revoked.
- **Real Latchkey 0.2.0, Usher 0.4.0 and LuckPerms on throwaway Paper 26.3** (`--real-invites <usher.jar> <latchkey.jar>`, made-up offline accounts, deleted after):
  - The invite code never appears in the console or `latest.log`.
  - Usher's `bridge` question comes back through Latchkey.
  - Invites can be listed and revoked.
  - The code works when typed in lowercase on Latchkey's own page. That whitelists the player, and Usher applies the profile.
  - A bot signs in with `/signin`, after an admin gives `latchkey.signin`, which is op-only by default.
  - GilaMonster reads the real session file, and its links page signs the player in.
  - `whitelist remove` ends both.
- **Looked at by hand by this session, against `--demo-invites`.** An invite was made through the real screen: the question showed inline, the code appeared once, and the list updated. One fix came from it: the hint under the profiles no longer moves the button.

Gaps skipped:

- **Keyboard, VoiceOver and wording, by a person.** That's owner test T24.
- **A real server, a real browser and a real client.** These wait for the owner's go. Latchkey's HTTPS through a tunnel is Latchkey's own gap.
- **GilaMonster's own sign-in.** It still works alongside Latchkey's. Retiring it is a later change, after T24.

## 2026-11-10: the Allowlist page goes through Usher

On a server with Usher, the Allowlist page approves people and changes their profiles through Usher's format-1 commands: `profiles`, `show`, `apply` (with its questions) and `attempts`. It never goes around Usher with raw LuckPerms or `whitelist add`. This was decided on 2026-11-07, for kids' and adults' groups. Default run: 2493 passed, 0 failed. With the real run: 2520 passed.

Covered:

- **Never around Usher (fail closed).** With an Usher jar on the server, raw adding, adding a group and removing a group are each refused. Nothing is queued, and no `lp` or `whitelist add` is typed. Taking someone off the allowlist still works. Removing the guard failed 5 checks, and it was put back.
- **Usher can't be reached.** The page says why and changes nothing in each case: plugin commands off, the server not started here, an Usher with no `apply` (it names 0.4.0), or a newer format.
- **Through a fake Usher.** Profiles come with labels and worlds, and Usher's settings problems come through. "none" is refused as a profile. An approval runs, then a question, then nothing changes until the yes. Adding and removing happen in one go. The typed command is checked word for word.
- **Real Usher 0.4.0 and LuckPerms on throwaway Paper 26.3** (`--real-usher <jar> --with-luckperms`):
  - Usher's describe gives format 1 and the optional arguments.
  - Its problems name the missing groups until they exist.
  - An approval gives the profile, the group in LuckPerms and the whitelist entry.
  - A second chat circle asks `bridge`, and nothing changes until it's answered.
  - `grown_sky` asks `confirm-grown-sky`.
  - Adding and removing in one go works.
  - The raw path is refused.
  - Usher's change log names GilaMonster.
  - Every account is made up and offline.
- **Usher 0.4.0's `attempts`.** It uses `attempts` and a number for `next`, where the spec says `items` and a string. GilaMonster reads both, and the Plugins Lead has been told.

Gaps skipped:

- **The screen itself.** The wording, layout, keyboard and VoiceOver on the Allowlist page's Usher parts haven't been looked at by hand. They go in owner test T6.
- **A real server.** These are throwaway servers only, until the owner's go.

## 2026-11-10: optional arguments in describe

Signalbox 0.2.0 marks an argument that may be left out with `"optional": true`, and Usher 0.4.0 uses it. GilaMonster now reads it, and refuses a describe with a required argument after an optional one (fail closed: it couldn't tell which slot a value fills). Two checks added; 2468 passed, 0 failed. Not yet tried against Usher 0.4.0 itself, which isn't released.

## 2026-11-09: plugin commands, format 1

GilaMonster's side of the shared plugin command format (ops `briefs/plugin-commands-spec.md`), behind a new module, Plugin commands, that starts off. 2463 passed, 0 failed (111 new).

Covered:

- **The wire.** Every type is written the agreed way. Uuids go lowercase. Free text is quoted, escaped and last. `--yes` comes before `--json`. Sixteen bad inputs are refused before anything is typed, among them a word that's a flag (`--yes` could answer a question for you), a line break in free text, and an invisible character.
- **Spoofing (fail closed).** An answer counts only when `ea-result ` comes straight after an INFO log header. Thirteen spoof lines are refused: chat, `[Not Secure]` chat, the chat thread, `/say`, `/me`, a logged player command, a Discord bridge, WARN, no header, and junk before the header. Ids are 32 secure random hex characters and never repeat. A second answer, a reused id, an unknown id, a mismatched id inside the JSON, an answer over 8 KB and a refusal with no reason are each refused.
- **Confirm questions.** Nothing goes ahead until every question id is sent back.
- **Timeouts.** No answer is "not confirmed", not "failed". A late answer is passed on once, under its id.
- **Switched off, or not GilaMonster's own console.** Nothing is typed, and the refusal says why.
- **describe.** It is read. Unknown keys are ignored, and unknown types are marked rather than guessed. A newer format is refused. No format, format 0 or a plugin name that's a path is unreadable.
- **Once-files (fail closed).** A secret is read once and deleted. These are refused, and the file is still deleted: one others could read, one in a folder others could look in, one for another request, and an expired one. A link to another file isn't followed, and its target is kept. A plugin folder that's a link elsewhere isn't read, and nothing is deleted through it. A path or another request's file named in the answer is refused.
- **End to end.** A fake server in Java with a format-1 plugin runs through GilaMonster's real console. A player's chat answer with the same id comes first, and the real answer is still read. Free text with quotes and backslashes survives. describe comes through. An invite code reaches only the once-file, never the console. A plugin that never answers gives "not confirmed". Switched off, nothing is typed into a running server.
- **Proved by breaking it.** Loosening the parser to accept the prefix anywhere in a line failed 11 checks, including the end-to-end one. Then it was put back.

Gaps skipped:

- **A real Paper plugin.** None speaks format 1 yet. The console line's shape is settled, though. On throwaway Paper 26.1.2, 26.2 and 26.3, a plugin's plain console reply came out as `[hh:mm:ss INFO]: <text>`, and in `latest.log` as `[hh:mm:ss] [Server thread/INFO]: <text>`, with no `System chat:` label (checked by the Plugins Lead, 2026-11-09). Those exact shapes are now checks, and so is a reply sent through a plugin's logger, which isn't read.
- **Screens.** There are none yet. The Players page invite flow comes after Latchkey 0.2.0.

## 2026-11-09: BlueMinimap rename

BlueMapHUD became BlueMinimap 0.2.0. GilaMonster never looks for this plugin by name or folder: an exact pack is whatever zip you add, stored under its own SHA-1. So no check changes. Only the README and the Exact Pack hint now name `/blueminimap pack export`. The new export has a new SHA-1, so it needs adding again as a new exact pack. GilaMonster already handles that (a new export gets a new address, old ones keep serving). Built clean; the default run was not repeated, because no code path changed.

## 2026-11-09: Packmule rename

Resource Pack Butler became Packmule 0.2.0. Serving packs now checks that Packmule is noticed under both names, `Packmule` and `ResourcePackButler` (0.1.x), and that the pack settings are refused under each. Nothing else needed: GilaMonster reads only the plugin's name, never its folder, so the window where both `plugins/ResourcePackButler/` and `plugins/Packmule/` exist doesn't matter here. 1829 passed, 0 failed.

## 2026-11-08: first audit

At `a2b3cf6` plus this change. Default run before: 1807 passed. After the checks added below: 1826 passed, 0 failed.

### Covered

The README's promises, mapped to the sections that prove them (section names as printed by the run):

| Promise | Checks |
| --- | --- |
| Runs your server: start, stop, restart, console | Server lifecycle (stand-in jar), Launch; real: `--real-paper` |
| Uses an existing server, keeps servers together | Importing an existing server, Servers folder, Pre-26 servers |
| Keeps server software current, with hashes | Versions, Software moves, Jar picking, Update decisions; live: `--live` (real APIs) |
| Knows which plugins fit | Plugin descriptors, Source parsing, Tag-aware compatibility, Plugin scanning |
| Settings screens from your files | Properties, Config validation, Config forms |
| Never changes a running server underneath its players | The change queue (edits wait for a restart) |
| Protects you on upgrades, rollback in one step | Upgrade safety (a mismatched jar blocks start), Server lifecycle; real: `--real-paper` upgrade 1.21.11 → 26.3 and back |
| Switches off plugins that won't start, through Preflight's tool | Plugins on upgrade; real: `--real-upgrade-plugins` |
| Worlds with Multiverse | Multiverse |
| **Backs up safely while running** | Backups, Backup location, Comparing backups, Schedule |
| Tries changes on a test copy first | Server lifecycle, Serving packs ("a test copy never serves"); real: test copy to 26.3 |
| Rotates server icons | Server icons |
| **Renames deeply, with a restore point and undo** | Renames: the text, Renames: whole servers; real: `--real-paper` (its "REAL RENAMES" part) |
| **Looks after players: snapshots, restores** | Player data format, Players; sandbox: player features on real data, on 1.21.11 and 26.3 |
| **Cleans up old servers, and can bring them back** | Cleanup |
| Watches health, explains problems | Issue rules, Issue catalog, Analytics, Storage |
| **The Lab: wiping only the real Lab** | Analytics (the wipe guard, added today); real: `--lab` (a plain folder called lab is moved aside whole, never deleted; no Lab without the EULA) |
| **Resource packs, builds byte for byte** | Resource packs, What each pack contributes, Exact packs, Songs in a pack |
| **Serving packs** | Serving packs: off by default, needs an address, long random paths, 404 for everything else, no climbing out, read only, no cookies, big files streamed, a full house turns newcomers away, a test copy never serves, a taken port is reported, addresses never leave in an exported recipe; real: `--real-pack` (a bot gets the pack) |
| **Allowlist** | Analytics (access changes: unsafe group names, groups without LuckPerms and empty changes are refused), the links page; real: `--real-signin`, `--real-prejoin` |
| **Map behind sign-in** | Map behind sign-in; real: `--real-map` |
| **Plugin links page** | The links page checks (printed without their own header, ending "checked unreachable from N other local addresses"): loopback only, sign-in, what each person can see, a privileged port refused |
| EULA is yours to accept | The change queue ("false isn't accepted"); every real run asks for `--i-accept-the-minecraft-eula` |

### Gaps added, with the checks

- **A download that fails its hash.** Nothing proved it is thrown away. Every server jar, plugin, pack and the upgrade tool depends on this. Added to Plugins on upgrade: a wrong hash is refused and nothing is saved, and the right one is saved unchanged. It uses a stand-in web server on 127.0.0.1.
- **The whole upgrade check, end to end.** The tool was tested, but not the path that fetches Paper, copies the server and cleans up. Added, with the tool stood in for, checking that:
  - the tool gets a copy, never the server;
  - Paper must pass its hash first;
  - a bad Paper stops the check before the tool runs;
  - the shared-database allowance is sent only after Check Anyway;
  - nothing is left in `test-copies`.
- **Pack serving reaches only this Mac.** The listener binds to 127.0.0.1, but nothing checked it. Added: while serving, every other address on the Mac is tried and refused (two tried on this run).
- **A pack address survives a folder rename.** The fix in `913e383` had no check. Added: the same address before and after a rename that moves the folder.
- **The Lab's wipe guard.** It was only checked in the real `--lab` run, which needs Paper downloads. Added to the default run: a wipe needs both the mark and the exact folder, and a folder inside the Lab or one elsewhere never qualifies.

### Gaps skipped, and why

- **Pack serving starting when the app opens** (`AppModel`, `913e383`). The app layer isn't in the check harness. `startPackHostIfWanted()` itself is checked ("comes back"). The launch itself is in owner test T6 and the pack-hosting check (plan 1.6).
- **SwiftUI screens:** wording, layout, keyboard and VoiceOver. These are by-hand checks, in owner test T6. No UI test harness, and adding one would cost more than it catches for now.
- **Upstreams that publish no hash.** A download with no expected hash is accepted. That's deliberate: some sources publish none, and the file is still hashed and recorded. It's not a gap in a fail-closed check.
- **Real game clients.** Bots cover joining, packs and sign-in. A real client is on the "Needs a real client" list (the pack prompt, how the icon looks in the server list).
- **Overkill, left out:** Codable round-trips of plain settings structs, and SwiftUI view bodies. Stronger checks already save, reload and use these settings.

### Next audit

After the next feature or fix, or by 2026-11-22.
