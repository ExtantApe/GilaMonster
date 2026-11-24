#!/bin/bash
# Makes throwaway data for the DEBUG snapshot (GILAMONSTER_SNAPSHOT) and draws every page in all four themes.
#   scripts/snapshot-fixtures.sh OUT normal   one server with a few plugins, worlds and allowlist entries
#   scripts/snapshot-fixtures.sh OUT heavy    eight servers with long names; the first has 60 plugins, 30 worlds,
#                                             80 allowlist entries and long errors in its log
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
server() { # name plugins worlds allowlist errors
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
    : > "$s/logs/latest.log"
    for ((i = 1; i <= $5; i++)); do
        printf '[12:0%d:00 ERROR]: Could not pass event PlayerJoinEvent to MadeUpPlugin%d v2.%d.1\njava.lang.IllegalStateException: A made-up failure with a long message that keeps going so the screen has to deal with it: the configuration value at section.subsection.key could not be read because the file was written by a newer version\n\tat com.example.MadeUpPlugin%d.Main.onJoin(Main.java:%d)\n\tat io.papermc.paper.event.Dispatcher.call(Dispatcher.java:88)\n' $((i % 10)) "$i" "$i" "$i" $((100 + i)) >> "$s/logs/latest.log"
    done
    echo "$s"
}
list=()
if [[ "$kind" == normal ]]; then
    list+=("$(server "Made-up Server" 6 2 4 0)")
else
    list+=("$(server "A Made-up Server With A Name Long Enough To Need Truncating" 60 30 80 12)")
    for n in 2 3 4 5 6 7 8; do list+=("$(server "Made-up Server Number $n With A Long Name" 3 1 2 0)"); done
fi
{ echo "["; for ((i = 0; i < ${#list[@]}; i++)); do printf '  "%s"' "${list[$i]}"; (( i < ${#list[@]} - 1 )) && echo "," || echo; done; echo "]"; } > "$home/servers.json"

swift build --product GilaMonster >/dev/null
for theme in ${THEMES:-bold quiet}; do
    for look in ${LOOKS:-light dark}; do
        dir="$out/$kind/$theme-$look"; mkdir -p "$dir"
        var=GILAMONSTER_SNAPSHOT_LIGHT; [[ $look == dark ]] && var=GILAMONSTER_SNAPSHOT_DARK
        env GILAMONSTER_HOME="$home" GILAMONSTER_SERVERS="$servers" GILAMONSTER_SNAPSHOT="$dir" GILAMONSTER_SNAPSHOT_FIRST=1 \
            GILAMONSTER_SNAPSHOT_THEME=$theme "$var=1" perl -e 'alarm 900; exec @ARGV' .build/debug/GilaMonster >/dev/null 2>&1 || true
        echo "$kind $theme-$look: $(ls "$dir" | wc -l | tr -d ' ') pictures"
    done
done
