#!/bin/bash
# Makes throwaway data for the DEBUG snapshot (GILAMONSTER_SNAPSHOT) and draws every page in all four themes.
#   scripts/snapshot-fixtures.sh OUT normal   one server with a few plugins, worlds and allowlist entries
#   scripts/snapshot-fixtures.sh OUT heavy    eight servers with long names; the first has 60 plugins, 30 worlds,
#                                             80 allowlist entries and long errors in its log
#   KEYCHAIN=wait|denied  puts a made-up Keychain banner on top of every page (K809): waiting for the owner, or after a no.
#   MOTD='\u00A72Made-up Realms'  gives the first server that server message, as it would be written in server.properties,
#                                             and no name of the owner's, so the message names it (K824). RENAME='Pebble Garden'
#                                             adds the owner's own name on top. TWIN=1 adds a second server with the same
#                                             server message. The switcher's rows are drawn as dialog-switcher-rows.png.
#   Text and screen, stood in for because a snapshot can't change System Settings (K820). They pass straight through:
#   GILAMONSTER_SNAPSHOT_PIXEL=on|off|auto (the Pixel font setting, on if unset; auto is the first-launch default),
#   GILAMONSTER_SNAPSHOT_BODY=<points> (the system's body size, 13 by default), GILAMONSTER_SNAPSHOT_BOLD=1 (Bold Text),
#   GILAMONSTER_SNAPSHOT_SCALE=1|2 (screen pixels per point, 2 if unset), GILAMONSTER_SNAPSHOT_CONTRAST=1 (Increase Contrast).
#   BACKUPS=none  leaves out the first server's made-up backups, to draw one that GilaMonster has never backed up.
#   STARTABLE=<log file>  makes the first server one that would start, to prove a snapshot starts nothing (K829): it is
#                                             set to start when GilaMonster opens, and has a placeholder jar, a whole-folder
#                                             backup that really unpacks, and a stand-in for Java that only writes its
#                                             arguments to that log. gilamonster-check --snapshot-quiet reads the log.
#   HEIGHT=1800  draws taller pictures, to see the bottom of a long page.
#   BANNERS=external,trial-failed  puts those made-up banners above every page (K815): disk, trial-running, trial-open,
#                         trial-passed, trial-failed, notice, long-title, external, update, or all for one of each kind.
#                         The report then says where each page landed: a PUSHED line means a banner pushed it out of view.
#   PAGES=overview,console  draws only those pages. SCRATCH=<folder>  builds there instead of .build.
# Everything is made-up and lives under a temp folder that's removed at the end, pass or fail (D226). Nothing
# starts: the snapshot only draws. Pictures land in OUT/<fixture>/<theme>-<light|dark>/.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$1"; kind="$2"
[[ "$kind" == normal || "$kind" == heavy ]] || { echo "normal or heavy" >&2; exit 2; }
T="${TMPDIR:-/tmp}"; root="$(mktemp -d "${T%/}/gm-fixture.XXXXXX")"
trap 'rm -rf "$root"' EXIT
home="$root/home"; servers="$root/servers"; mkdir -p "$home" "$servers"

jar() { # folder name version
    local d; d="$(mktemp -d "$root/jar.XXXXXX")"
    printf 'name: %s\nversion: %s\nmain: com.example.%s.Main\napi-version: "26.1"\nauthors: [Made-up Author]\ndescription: A made-up plugin for screenshots.\n' "$2" "$3" "$(echo "$2" | tr -cd 'A-Za-z')" > "$d/paper-plugin.yml"
    (cd "$d" && zip -q "$1/$2-$3.jar" paper-plugin.yml); rm -rf "$d"
}
server() { # name plugins worlds allowlist errors waiting-changes
    local s="$servers/$(echo "$1" | tr ' ' '-' | tr 'A-Z' 'a-z')"; mkdir -p "$s/plugins" "$s/logs"
    printf 'motd=%s\nmax-players=20\nserver-port=25565\nwhite-list=true\n' "$1" > "$s/server.properties"
    echo "eula=true" > "$s/eula.txt"
    mkdir -p "$s/.gilamonster"; printf '{"id": "%s", "name": "%s"}' "$(uuidgen)" "$1" > "$s/.gilamonster/server.json"
    local i
    for ((i = 1; i <= $2; i++)); do
        if (( i % 9 == 0 )); then jar "$s/plugins" "AnExtremelyLongPluginNameThatGoesOnAndOn$i" "1.$i.0-SNAPSHOT-build-20261123"
        else jar "$s/plugins" "MadeUpPlugin$i" "2.$i.1"; fi
    done
    for ((i = 1; i <= $3; i++)); do
        local w; (( i == 1 )) && w=world || w="made_up_world_number_${i}_with_a_rather_long_folder_name"
        mkdir -p "$s/$w/region"; : > "$s/$w/level.dat"
    done
    { echo "["; for ((i = 1; i <= $4; i++)); do
        printf '  {"uuid": "%08x-0000-4000-8000-%012x", "name": "MadeUpPlayer%d"}' "$i" "$i" "$i"; (( i < $4 )) && echo "," || echo; done; echo "]"; } > "$s/whitelist.json"
    if (( ${6:-0} > 0 )); then   # waiting changes: some of each kind, one with a long summary
        python3 -I - "$s/.gilamonster/pending.json" "$6" <<'PY'
import json, sys, uuid, datetime
out, n = sys.argv[1], int(sys.argv[2])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rows = []
for i in range(1, n + 1):
    if i % 3 == 0:
        kind, text = {"config": {"path": "plugins/MadeUpPlugin%d/config.yml" % i}}, "Change plugins/MadeUpPlugin%d/config.yml: a made-up setting with a rather long description of what changed" % i
    elif i % 3 == 1:
        kind, text = {"pluginRemove": {"fileName": "MadeUpPlugin%d-2.%d.1.jar" % (i, i)}}, "Remove MadeUpPlugin%d" % i
    else:
        kind, text = {"pluginToggle": {"fileName": "MadeUpPlugin%d-2.%d.1.jar" % (i, i), "enable": False}}, "Turn off MadeUpPlugin%d" % i
    row = {"id": str(uuid.uuid4()).upper(), "kind": kind, "summary": text, "created": now}
    if i == 4: row["conflict"] = "Another change to the same made-up file was made after this one, so applying both would lose the first."
    rows.append(row)
json.dump(rows, open(out, "w"))
PY
    fi
    : > "$s/logs/latest.log"
    for ((i = 1; i <= $5; i++)); do
        printf '[12:0%d:00 ERROR]: Could not pass event PlayerJoinEvent to MadeUpPlugin%d v2.%d.1\njava.lang.IllegalStateException: A made-up failure with a long message that keeps going so the screen has to deal with it: the configuration value at section.subsection.key could not be read because the file was written by a newer version\n\tat com.example.MadeUpPlugin%d.Main.onJoin(Main.java:%d)\n\tat io.papermc.paper.event.Dispatcher.call(Dispatcher.java:88)\n' $((i % 10)) "$i" "$i" "$i" $((100 + i)) >> "$s/logs/latest.log"
    done
    echo "$s"
}
players() { # folder: made-up players with saved files and a small inventory, so the Players roster has rows (K786)
    python3 -I - "$1" <<'PY'
import gzip, json, os, struct, sys, time, uuid
root = sys.argv[1]
data = os.path.join(root, "world", "playerdata"); os.makedirs(data, exist_ok=True)
def s(t): b = t.encode(); return struct.pack(">H", len(b)) + b
def item(slot, iid, n): return b"\x01" + s("Slot") + struct.pack(">b", slot) + b"\x08" + s("id") + s(iid) + b"\x03" + s("count") + struct.pack(">i", n) + b"\x00"
stuff = [(0, "minecraft:cobblestone", 64), (1, "minecraft:iron_pickaxe", 1), (2, "minecraft:bread", 12), (4, "minecraft:torch", 3), (7, "minecraft:oak_sapling", 1)]
cache = []
for i, name in enumerate(["MadeUpKid", "PixelPal", "CactusJo", "SandyB", "LizardLou"]):
    pid = str(uuid.uuid5(uuid.NAMESPACE_DNS, name + ".example"))
    inv = b"\x09" + s("Inventory") + b"\x0a" + struct.pack(">i", len(stuff)) + b"".join(item(*x) for x in stuff)
    body = b"\x0a" + s("") + inv + b"\x03" + s("XpLevel") + struct.pack(">i", 7 + i) + b"\x00"
    f = os.path.join(data, pid + ".dat")
    with gzip.open(f, "wb") as out: out.write(body)
    t = time.time() - 3600 * (i * 9 + 1); os.utime(f, (t, t))
    cache.append({"uuid": pid, "name": name, "expiresOn": "2099-01-01 00:00:00 +0000"})
json.dump(cache, open(os.path.join(root, "usercache.json"), "w"))
PY
}
list=()
if [[ "$kind" == normal ]]; then
    list+=("$(server "Made-up Server" 6 2 4 0)")
    players "${list[0]}"
else
    list+=("$(server "A Made-up Server With A Name Long Enough To Need Truncating" 60 30 80 12 30)")
    for n in 2 3 4 5 6 7 8; do list+=("$(server "Made-up Server Number $n With A Long Name" 3 1 2 0)"); done
fi
if [[ -n "${MOTD:-}" ]]; then   # the first server is named by its server message, or by the owner's rename
    MOTD="$MOTD" RENAME="${RENAME:-}" python3 -I - "${list[0]}" <<'PY'
import json, os, sys
root = sys.argv[1]
props = os.path.join(root, "server.properties")
lines = [l for l in open(props).read().split("\n") if not l.startswith("motd=")]
open(props, "w").write("motd=" + os.environ["MOTD"] + "\n" + "\n".join(lines))
meta = os.path.join(root, ".gilamonster", "server.json")
profile = json.load(open(meta))
profile["name"] = os.path.basename(root)
profile["customNameSettled"] = True
if os.environ["RENAME"]: profile["customName"] = os.environ["RENAME"]
json.dump(profile, open(meta, "w"))
PY
fi
if [[ -n "${TWIN:-}" ]]; then   # a second server with the first one's server message, to tell apart by folder
    twin="$(server "Made-up Twin" 1 1 1 0)"
    grep '^motd=' "${list[0]}/server.properties" > "$twin/motd.tmp"; grep -v '^motd=' "$twin/server.properties" >> "$twin/motd.tmp"; mv "$twin/motd.tmp" "$twin/server.properties"
    printf '{"id": "%s", "name": "made-up-twin", "customNameSettled": true}' "$(uuidgen)" > "$twin/.gilamonster/server.json"
    list+=("$twin")
fi
{ echo "["; for ((i = 0; i < ${#list[@]}; i++)); do printf '  "%s"' "${list[$i]}"; (( i < ${#list[@]} - 1 )) && echo "," || echo; done; echo "]"; } > "$home/servers.json"

scratch="${SCRATCH:-.build}"
for b in $(echo "${BANNERS:-}" | tr ',' ' '); do
    case "$b" in disk|trial-running|trial-open|trial-passed|trial-failed|notice|long-title|external|update|all) ;; *) echo "BANNERS: no banner is called $b" >&2; exit 2;; esac
done
case "${KEYCHAIN:-}" in ""|wait|denied) ;; *) echo "KEYCHAIN is wait or denied" >&2; exit 2;; esac
swift build --scratch-path "$scratch" --product GilaMonster >/dev/null
# Made-up Lab results for the first server, so the Lab page's details, a skipped plugin and a restart log are drawn (K804).
swift build --scratch-path "$scratch" --product gilamonster-check >/dev/null
"$scratch/debug/gilamonster-check" --lab-fixture "$home" "$servers" "${list[0]}" >/dev/null
# Made-up backups for the first server (K823): one from 23 hours ago, and an added storage folder with an older one.
# BACKUPS=none leaves them out, to draw a server GilaMonster has never backed up.
case "${BACKUPS:-}" in ""|none) ;; *) echo "BACKUPS is none or unset" >&2; exit 2;; esac
[[ "${BACKUPS:-}" == none ]] || "$scratch/debug/gilamonster-check" --backup-fixture "$home" "$servers" "${list[0]}" >/dev/null
if [[ -n "${STARTABLE:-}" ]]; then
    mkdir -p "$root/standin"
    printf '#!/bin/sh\n# A stand-in for Java in the off-screen pictures: it writes what it was asked to run, and runs nothing.\necho "$*" >> "%s"\n[ "$1" = "-version" ] && echo '"'"'openjdk version "25.0.1" 2026-01-01'"'"' >&2\nexit 0\n' "$STARTABLE" > "$root/standin/java"
    chmod +x "$root/standin/java"
    "$scratch/debug/gilamonster-check" --startable-fixture "$home" "$servers" "${list[0]}" "$root/standin/java" >/dev/null
fi
for theme in ${THEMES:-bold quiet}; do
    for look in ${LOOKS:-light dark}; do
        dir="$out/$kind/$theme-$look"; mkdir -p "$dir"
        rm -f "$dir/overflow-report.txt" "$dir/dialog-report.txt"   # a run that draws nothing must not pass on an old report
        var=GILAMONSTER_SNAPSHOT_LIGHT; [[ $look == dark ]] && var=GILAMONSTER_SNAPSHOT_DARK
        [[ "$kind" == heavy ]] && height=2800 || height=1000   # tall enough that Show More and group headings are in the picture
        height="${HEIGHT:-$height}"
        env GILAMONSTER_SNAPSHOT_HEIGHT=$height GILAMONSTER_HOME="$home" GILAMONSTER_SERVERS="$servers" GILAMONSTER_SNAPSHOT="$dir" GILAMONSTER_SNAPSHOT_FIRST=1 \
            GILAMONSTER_SNAPSHOT_THEME=$theme GILAMONSTER_SNAPSHOT_KEYCHAIN="${KEYCHAIN:-}" GILAMONSTER_SNAPSHOT_BANNERS="${BANNERS:-}" ${PAGES:+GILAMONSTER_SNAPSHOT_PAGES="$PAGES"} "$var=1" \
            perl -e 'alarm 900; exec @ARGV' "$scratch/debug/GilaMonster" >/dev/null 2>&1 || true
        echo "$kind $theme-$look: $(ls "$dir" | wc -l | tr -d ' ') pictures"
    done
done
