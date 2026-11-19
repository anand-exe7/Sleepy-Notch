#!/bin/zsh
# Shows the first-launch setup again, without marking it done, so it can be
# tried as many times as you like. Choices made in it still apply (they're
# the same switches as in Settings).
#
#   scripts/onboarding-demo.sh            # use the app already built
#   scripts/onboarding-demo.sh --build    # rebuild build/Sleepy Notch.app first
#   scripts/onboarding-demo.sh --auto     # it clicks through by itself, taking
#                                         # a picture of every page into
#                                         # build/onboarding-demo/
set -e
cd "$(dirname "$0")/.."

app="build/Sleepy Notch.app"
build=0
auto=0
for arg in "$@"; do
  case "$arg" in
    --build) build=1 ;;
    --auto) auto=1 ;;
  esac
done

if [[ $build == 1 || ! -d "$app" ]]; then
  scripts/make-app.sh
fi

# Only one copy may run (they share sockets).
pkill -x SleepyNotch 2>/dev/null || true
sleep 0.5

if [[ $auto == 1 ]]; then
  out="$PWD/build/onboarding-demo"
  rm -rf "$out"
  open --env SLEEPY_ONBOARDING=demo --env SLEEPY_BENCH=onboarding --env SLEEPY_BENCH_FINISH=1 \
       --env SLEEPY_BENCH_OUT="$out" "$app"
  echo "Walking through the setup; pictures land in $out in about 25 seconds."
else
  open --env SLEEPY_ONBOARDING=demo "$app"
  echo "Setup open (demo: it will show again next time you run this)."
fi
