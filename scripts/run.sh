#!/usr/bin/env bash
set -euo pipefail

project_dir="${WALLPICK_APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
qs_bin="${WALLPICK_QS:-qs}"
python_bin="${WALLPICK_PYTHON:-python3}"
find_instance() {
    "$qs_bin" list --all --json | "$python_bin" -c '
import json, sys
instances = [i for i in json.load(sys.stdin) if i.get("shell_id") == "wallpick"]
print(instances[0]["id"] if instances else "")
'
}
shader="$project_dir/src/shaders/liquidmetal.frag"
compiled="$shader.qsb"

if [[ "${WALLPICK_PACKAGED:-0}" != 1 && ( ! -e "$compiled" || "$shader" -nt "$compiled" ) ]]; then
    qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$compiled" "$shader"
fi

case "${1:-open}" in
    apply) shift; exec "$python_bin" "$project_dir/scripts/actions.py" apply -- "$@" ;;
    favorite) shift; exec "$python_bin" "$project_dir/scripts/actions.py" favorite-current -- "$@" ;;
    fetch)
        shift
        case "${1:-}" in
            anime) command=randomanime ;;
            general) command=randomwall ;;
            gooner) command=randomgooner ;;
            *) echo "Usage: wallpick fetch {anime|general|gooner} [tags...]" >&2; exit 2 ;;
        esac
        shift
        exec "$python_bin" "$project_dir/scripts/actions.py" "$command" -- "$@"
        ;;
    stop)
        instance="$(find_instance)"
        [[ -z "$instance" ]] && exit 0
        exec "$qs_bin" kill -i "$instance"
        ;;
    foreground)
        instance="$(find_instance)"
        if [[ -n "$instance" ]]; then echo "Wallpick is already running; use stop first."; exit 0; fi
        exec "$qs_bin" -p "$project_dir/src" --no-duplicate
        ;;
    open|close|toggle|status|refresh|random-anime|random-wall|random-gooner)
        action="${1:-open}"
        case "$action" in
            random-anime) ipc_function=randomAnime ;;
            random-wall) ipc_function=randomWall ;;
            random-gooner) ipc_function=randomGooner ;;
            *) ipc_function="$action" ;;
        esac
        instance="$(find_instance)"
        if [[ -z "$instance" ]]; then
            if [[ "$action" == close || "$action" == status ]]; then
                [[ "$action" == status ]] && echo stopped
                exit 0
            fi
            "$qs_bin" -p "$project_dir/src" --no-duplicate --daemonize
        fi
        ready=false
        for _ in {1..100}; do
            instance="$(find_instance)"
            if [[ -n "$instance" ]] && "$qs_bin" ipc -i "$instance" call wallpick status >/dev/null 2>&1; then
                ready=true
                break
            fi
            sleep 0.1
        done
        if [[ "$ready" != true ]]; then
            echo "Wallpick did not become ready within 10 seconds; inspect its Quickshell log." >&2
            exit 1
        fi
        exec "$qs_bin" ipc -i "$instance" call wallpick "$ipc_function"
        ;;
    --help|-h) echo "Usage: wallpick [open|close|toggle|status|stop|refresh|foreground|random-anime|random-wall|random-gooner|apply PATH|favorite|fetch SOURCE TAGS...]" ;;
    *) echo "Unknown command. Run wallpick --help." >&2; exit 2 ;;
esac
