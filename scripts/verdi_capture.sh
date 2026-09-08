#!/bin/bash
# verdi_capture.sh - export waveform figures from an FSDB by driving Verdi.
#
# Verdi is a GUI tool, but it takes a Tcl script and it will run against a
# private virtual display, so waveform figures can be produced by script
# instead of by hand. That makes them reproducible: the same command a month
# later gives the same picture, and a reviewer can regenerate them.
#
#   verdi_capture.sh <fsdb> <top> <figures-file> [outdir]
#
# The figures file is one figure per line:
#
#   <name>  <t_start>  <t_end>  <signal> <signal> ...
#
# Times are in the FSDB's own time unit - see the trap below, it is usually
# ps and getting this wrong is the most common way to end up with a picture
# of nothing. Signal paths are relative to the top, and dut/foo works.
# Blank lines and lines starting with # are ignored.
#
# Example figures file:
#   launch    50000    132000   clk go busy arvalid arready ch0_araddr
#   data     152000    260000   clk ch0_rvalid ch0_rlast ch0_rdata
#   done    4180000   4262000   clk busy done cycles
set -e

FSDB=${1:?usage: verdi_capture.sh <fsdb> <top> <figures-file> [outdir]}
TOP=${2:?missing top module name}
FIGS=${3:?missing figures file}
OUT=${4:-verdi_out}
DISP=${DISP:-:99}

[ -r "$FSDB" ] || { echo "no such FSDB: $FSDB" >&2; exit 1; }
[ -r "$FIGS" ] || { echo "no such figures file: $FIGS" >&2; exit 1; }
mkdir -p "$OUT"

# Site EDA environment, if there is one. Point EDA_ENV at your own setup
# script, or drop this line if verdi is already on PATH.
[ -n "${EDA_ENV:-}" ] && [ -r "$EDA_ENV" ] && source "$EDA_ENV" >/dev/null 2>&1 || true
command -v verdi >/dev/null || { echo "verdi not on PATH; set EDA_ENV or load your tools first" >&2; exit 1; }

# Two startup failures that have nothing to do with waveforms, both of the
# same shape: a tool tree on the library path shadows a system library with
# an older build that no longer exports a symbol something else needs.
# Catapult's libxml2 breaks the system libxslt; a Synopsys libkrb5support
# breaks the preloaded libk5crypto. Drop the first, front-load the second.
LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v -i catapult | paste -sd:)
export LD_LIBRARY_PATH
case ":${LD_PRELOAD}:" in
    *":/usr/lib64/libkrb5support.so.0:"*) ;;
    *) [ -e /usr/lib64/libkrb5support.so.0 ] &&
       export LD_PRELOAD="/usr/lib64/libkrb5support.so.0${LD_PRELOAD:+:$LD_PRELOAD}" ;;
esac

# Verdi needs a display even with -nogui, and -nogui does not render the
# waveform pane at all - a capture taken under it is blank. So run the real
# GUI, but against our own Xvfb rather than whatever screen the user is on.
if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
    echo "[xvfb] starting $DISP"
    Xvfb "$DISP" -screen 0 1920x1200x24 >/dev/null 2>&1 &
    sleep 4
fi

TCL=$(mktemp /tmp/verdi_cap_XXXX.tcl)
{
    echo "set T /$TOP"
    echo 'wvCreateWindow'
    echo "wvOpenFile -win \$_nWave2 \"$(readlink -f "$FSDB")\""
    cat <<'PROC'
# One window, reused. wvCreateWindow makes a NEW window on every call while
# $_nWave2 keeps pointing at the first one, so a window per figure captures
# empty panes. Open once, then clear and refill between figures.
proc fig {name t0 t1 sigs} {
    global _nWave2 T OUTDIR
    wvClearAll -win $_nWave2
    foreach s $sigs { wvAddSignal -win $_nWave2 "$T/$s" }
    wvIncSignalHeight -win $_nWave2
    wvZoom -win $_nWave2 $t0 $t1
    wvCapture -win $_nWave2 -file "$OUTDIR/$name.png"
}
PROC
    echo "set OUTDIR \"$(readlink -f "$OUT")\""
    # figures file -> fig calls
    awk 'NF && $1 !~ /^#/ {
            name=$1; t0=$2; t1=$3; sigs="";
            for (i=4; i<=NF; i++) sigs = sigs (i>4 ? " " : "") $i;
            printf "fig %s %s %s {%s}\n", name, t0, t1, sigs
         }' "$FIGS"
    echo 'debExit'
} > "$TCL"

LOG="${TCL%.tcl}.log"
DISPLAY="$DISP" verdi -play "$TCL" >"$LOG" 2>&1 || true

# Verdi does not fail the run on a bad command; it prints one line and carries
# on, leaving a figure silently missing or empty. Treat that as an error.
if grep -q "invalid command" "$LOG"; then
    echo "ERROR: Verdi rejected a command:" >&2
    grep "invalid command" "$LOG" >&2
    echo "  full log: $LOG" >&2
    exit 1
fi

want=$(awk 'NF && $1 !~ /^#/ {n++} END{print n+0}' "$FIGS")
got=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l)
echo "[verdi] $got / $want figures -> $OUT/"
ls -la "$OUT"/*.png 2>/dev/null | awk '{printf "  %-44s %7s B\n", $NF, $5}'
[ "$got" -ge "$want" ] || { echo "ERROR: fewer figures than requested; see $LOG" >&2; exit 1; }

# A capture of a window whose signals all failed to resolve still writes a
# valid PNG, just an empty one. Sizes clustered at one identical value are
# the signature; check them rather than trusting the count.
echo
echo "NOTE: identical file sizes usually mean the signal paths did not resolve"
echo "      and the panes are blank. Open one and look before shipping."
