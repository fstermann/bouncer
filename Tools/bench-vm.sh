#!/bin/sh
# Runs the bench inside a Tart macOS VM, so it leaves this Mac's screen alone. See docs/PERFORMANCE.md.
#
#   Tools/bench-vm.sh setup          make the template VM, once per Mac; you grant the permissions by hand
#   Tools/bench-vm.sh run [ARGS]     bench the current Debug build in a throwaway clone of the template
#   Tools/bench-vm.sh up             start a lasting clone with the current build, or reload the build into it
#   Tools/bench-vm.sh ctl CMD...     send a barctl command to it; a file it writes comes back to the path given
#   Tools/bench-vm.sh items on|off   start or stop the fixture that fills the hidden section
#   Tools/bench-vm.sh down           stop and delete it
set -eu

template=bouncer-bench
clone=bouncer-bench-run
lasting=bouncer-vm
image=ghcr.io/cirruslabs/macos-golden-gate-vanilla:27.2
app=".build/xcode/Build/Products/Debug/Bouncer Dev.app"
# The guest mirrors the checkout's layout under ~/bouncer, because the bench finds the app and its
# helpers relative to the directory it runs in.
guest=bouncer

command -v tart >/dev/null || {
    printf 'Tart is missing. Install it with:\n  brew trust --formula openai/tools/softnet\n  brew install openai/tools/tart\n'
    exit 1
}
[ -d "$app" ] || { echo "no Bouncer Dev build: make build"; exit 1; }

# The Cirrus Labs images log in as admin/admin, and the VM is reachable only from this Mac.
askpass=$(mktemp)
printf '#!/bin/sh\necho admin\n' >"$askpass"
chmod +x "$askpass"
export SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error"
vm=

finish() {
    rm -f "$askpass"
    [ "$vm" = "$clone" ] && { tart stop "$clone" >/dev/null 2>&1 || true; tart delete "$clone" >/dev/null 2>&1 || true; }
    return 0
}
trap finish EXIT
trap 'exit 130' INT TERM

on_vm() {
    # shellcheck disable=SC2086
    ssh $ssh_options "admin@$ip" "$@"
}

# Starts $1 and waits until its desktop session is up; $2 is passed to tart run.
start() {
    vm=$1
    tart run "$@" >/dev/null 2>&1 &
    ip=$(tart ip "$vm" --wait 180)
    tries=0
    until on_vm 'pgrep -qx Dock' 2>/dev/null; do
        tries=$((tries + 1))
        [ $tries -lt 60 ] || { echo "$vm never reached its desktop"; exit 1; }
        sleep 2
    done
}

copy_in() {
    on_vm "mkdir -p '$guest/.build/xcode/Build/Products/Debug' '$guest/.bench'"
    rsync -a --delete -e "ssh $ssh_options" "$app" "admin@$ip:$guest/.build/xcode/Build/Products/Debug/"
    rsync -a -e "ssh $ssh_options" .bench/bench .bench/bench-items .bench/barctl "admin@$ip:$guest/.bench/"
}

# This Mac's settings decide which pages exist and how the bar moves, so the VM gets them too,
# minus what is personal or points at this Mac's files.
copy_settings() {
    defaults read com.bouncer.app.dev preferences >/dev/null 2>&1 || return 0
    preferences=$(defaults export com.bouncer.app.dev - | plutil -extract preferences raw -o - - | base64 -d |
        python3 -I -c 'import json, sys
p = json.load(sys.stdin)
for key in ["todoFile", "notesFolder", "imagesFolder", "claudeFolder", "tagColors", "tagOrder",
            "tagRepositories", "claudeSessions", "decks", "spaceNames", "spaceOrder"]:
    p.pop(key, None)
print(json.dumps(p).encode().hex())')
    on_vm "defaults write com.bouncer.app.dev preferences -data $preferences"
}

# Finds the lasting clone's address, or stops if it is not running.
find_lasting() {
    tart list | grep -q "^local *$lasting .*running" || { echo "no VM running: make vm-up"; exit 1; }
    ip=$(tart ip "$lasting")
}

case "${1:-}" in
setup)
    if ! tart get "$template" >/dev/null 2>&1; then
        echo "Downloading macOS 27.2 (30 GB)..."
        tart clone "$image" "$template"
        tart set "$template" --cpu 4 --memory 6144 --display 1512x982
    fi
    start "$template"
    copy_in
    on_vm "open '$guest/$app'; open -R '$guest/$app'; open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'"
    cat <<EOF

In the VM's window (password admin):
  1. Screen & System Audio Recording: drag Bouncer Dev in from the Finder window and turn it on.
     If macOS offers Quit & Reopen, choose Later.
  2. Privacy & Security > Accessibility: the same.
  3. Allow any alert that comes up.
EOF
    # Read the grants rather than trying a command: without Accessibility, screenshots still work and
    # only posted keys fail, silently.
    while :; do
        printf 'Press return when both are on. '
        read -r _
        granted=$(on_vm "echo admin | sudo -S sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \
            \"select count(*) from access where client = 'com.bouncer.app.dev' and auth_value = 2 and service in
            ('kTCCServiceScreenCapture', 'kTCCServiceAccessibility')\"" 2>/dev/null)
        [ "$granted" = 2 ] && break
        echo "Not both on yet: check Screen & System Audio Recording and Accessibility."
    done
    # A bench run boots into whatever the template last showed, so leave an empty desktop and keep
    # macOS from reopening windows. A clean shutdown, because tart stop cuts the power before
    # these writes reach the disk.
    on_vm "defaults write com.apple.loginwindow TALLogoutSavesState -bool false
        defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
        killall 'Bouncer Dev' 'System Settings' Finder 2>/dev/null
        sleep 2
        rm -rf ~/Library/Saved\ Application\ State
        echo admin | sudo -S shutdown -h now" >/dev/null 2>&1 || true
    until tart list | grep -q "^local *$template .*stopped"; do sleep 2; done
    echo "Template ready: make bench-vm"
    ;;
run)
    shift
    tart get "$template" >/dev/null 2>&1 || { echo "no template VM: make bench-vm-setup"; exit 1; }
    tart delete "$clone" >/dev/null 2>&1 || true
    tart clone "$template" "$clone"
    start "$clone" --no-graphics
    copy_in
    copy_settings
    # The guest has no Git, so the label comes from here; a --label in ARGS wins, being later.
    status=0
    on_vm "cd $guest && .bench/bench --label $(git rev-parse --short HEAD)-vm $*" || status=$?
    rsync -a --include='*.json' --exclude='*' -e "ssh $ssh_options" "admin@$ip:$guest/.bench/" .bench/ || true
    exit $status
    ;;
up)
    tart get "$template" >/dev/null 2>&1 || { echo "no template VM: make bench-vm-setup"; exit 1; }
    if tart list | grep -q "^local *$lasting .*running"; then
        ip=$(tart ip "$lasting")
    else
        tart delete "$lasting" >/dev/null 2>&1 || true
        tart clone "$template" "$lasting"
        # nohup, so the VM outlives this script.
        nohup tart run "$lasting" --no-graphics >/dev/null 2>&1 &
        ip=$(tart ip "$lasting" --wait 180)
        tries=0
        until on_vm 'pgrep -qx Dock' 2>/dev/null; do
            tries=$((tries + 1))
            [ $tries -lt 60 ] || { echo "$lasting never reached its desktop"; exit 1; }
            sleep 2
        done
    fi
    on_vm "pkill -x 'Bouncer Dev'; while pgrep -qx 'Bouncer Dev'; do sleep 0.1; done" || true
    copy_in
    copy_settings
    on_vm "open '$guest/$app'; for i in \$(seq 20); do sleep 0.5; $guest/.bench/barctl rest 2>/dev/null | grep -q 'at rest' && exit 0; done; echo 'Bouncer Dev did not start'; exit 1"
    echo "VM up at $ip with this build: make vm-ctl CMD=\"dump\""
    ;;
ctl)
    shift
    find_lasting
    # A command that writes a file names it second; the guest writes to out/ and the file is copied back.
    case "${1:-}" in
    shoot | record | dump | capture)
        if [ $# -ge 2 ]; then
            local_path=$2
            verb=$1
            shift 2
            status=0
            on_vm "mkdir -p out && $guest/.bench/barctl $verb /Users/admin/out/$(basename "$local_path") $*" || status=$?
            mkdir -p "$(dirname "$local_path")"
            rsync -a -e "ssh $ssh_options" "admin@$ip:out/$(basename "$local_path")" "$local_path" || true
            exit $status
        fi
        ;;
    esac
    on_vm "$guest/.bench/barctl $*"
    ;;
items)
    find_lasting
    case "${2:-}" in
    on) on_vm "pgrep -qx bench-items || nohup $guest/.bench/bench-items >/dev/null 2>&1 &" ;;
    off) on_vm "pkill -x bench-items" || true ;;
    *) echo "usage: items on|off"; exit 1 ;;
    esac
    ;;
down)
    tart stop "$lasting" >/dev/null 2>&1 || true
    tart delete "$lasting" >/dev/null 2>&1 || true
    ;;
*)
    sed -n '4,9p' "$0"
    exit 1
    ;;
esac
