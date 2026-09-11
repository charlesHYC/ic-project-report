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
# A signal may carry a display suffix:
#   sig:dec     unsigned decimal      sig:hex   hexadecimal (the default)
#   sig:bin     binary                sig:analog  drawn as a curve
# Use :dec for lengths, counts, tags and pointers; a reader should not have
# to convert 0x80 to 128 to check a claim.
#
# Example figures file:
#   launch    50000    132000   clk go busy arvalid arready ch0_araddr
#   data     152000    260000   clk ch0_rvalid ch0_rlast ch0_rdata len:dec
#   credits  400000   9000000   clk busy inflight:analog
#
# Environment:
#   FIG_W    capture width in pixels (default 1280). The report shows figures
#            about 900 px wide, so much wider captures shrink the text.
#   DISP     X display to use (default :99, started with Xvfb if absent)
#   EDA_ENV  a script that puts verdi on PATH
set -e

FSDB=${1:?usage: verdi_capture.sh <fsdb> <top> <figures-file> [outdir]}
TOP=${2:?missing top module name}
FIGS=${3:?missing figures file}
OUT=${4:-verdi_out}
DISP=${DISP:-:99}
FIG_W=${FIG_W:-1280}

[ -r "$FSDB" ] || { echo "no such FSDB: $FSDB" >&2; exit 1; }
[ -r "$FIGS" ] || { echo "no such figures file: $FIGS" >&2; exit 1; }
mkdir -p "$OUT"
FSDB=$(readlink -f "$FSDB")
FIGS=$(readlink -f "$FIGS")
OUT=$(readlink -f "$OUT")

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

# Verdi writes verdiLog/, novas.rc and novas.conf into its working directory.
# Run it somewhere private so none of that lands in the user's project.
WORK=$(mktemp -d /tmp/verdi_cap_XXXX)
TCL=$WORK/capture.tcl
{
    echo "set T /$TOP"
    echo "set OUTDIR \"$OUT\""
    echo "set FIG_W $FIG_W"
    echo 'wvCreateWindow'
    echo "wvOpenFile -win \$_nWave2 \"$FSDB\""
    cat <<'PROC'
# The waveform pane sits docked inside the main window, which starts at
# 900x700, so a capture is 900x317 and shows about ten signals; the rest
# scroll off the top without any error. wvResizeWindow returns success and
# changes nothing. What works is resizing the main window and maximizing the
# waveform dock inside it. The capture comes out 98 px shorter than the main
# window; a digital row is 20 px, an analog row about 100 px.
#
# verdiDockWidgetMaximize is a toggle: call it once. Calling it per figure
# restores the dock on every second figure, which then comes out 200 px tall
# with most signals scrolled away.
verdiWindowResize -win $_Verdi_1 "0" "0" "$FIG_W" "700"
verdiDockWidgetMaximize -dock windowDock_nWave_2

# Signals are picked by position as the single string ( "G1" 2 5 7 ), the
# form Verdi itself records. A Tcl list such as {G1 2 5 7} is accepted
# without complaint and selects nothing, so the radix is silently not set.
proc pick {idx} {
    global _nWave2
    wvSelectSignal -win $_nWave2 "( \"G1\" [join $idx { }] )"
}

# One window, reused. wvCreateWindow makes a NEW window on every call while
# $_nWave2 keeps pointing at the first one, so a window per figure captures
# empty panes. Open once, then clear and refill between figures.
proc fig {name t0 t1 sigs} {
    global _nWave2 _Verdi_1 T OUTDIR FIG_W
    set names {}; set dec {}; set hex {}; set bin {}; set ana {}
    set i 0
    foreach s $sigs {
        incr i
        set p [split $s :]
        lappend names [lindex $p 0]
        switch -- [lindex $p 1] {
            dec    { lappend dec $i }
            hex    { lappend hex $i }
            bin    { lappend bin $i }
            analog { lappend ana $i }
        }
    }
    set h [expr {280 + 20 * ($i - [llength $ana]) + 100 * [llength $ana]}]
    verdiWindowResize -win $_Verdi_1 "0" "0" "$FIG_W" "$h"
    wvClearAll -win $_nWave2
    foreach s $names { wvAddSignal -win $_nWave2 "$T/$s" }
    foreach {lst fmt} [list $dec UDec $hex Hex $bin Bin] {
        if {[llength $lst]} {
            pick $lst
            wvSetRadix -win $_nWave2 -format $fmt
        }
    }
    # wvDigitalToAnalog does not convert in place: it appends an analog copy
    # at the bottom and leaves the original digital row where it was. Pick
    # the originals again by position and cut them, or every curve shows up
    # twice, once as an unreadable dense bus. Put :analog signals last in the
    # figure line so the positions of the others do not move.
    if {[llength $ana]} {
        pick $ana
        wvDigitalToAnalog -win $_nWave2
        pick $ana
        wvCut -win $_nWave2
    }
    wvSelectSignal -win $_nWave2 {}
    wvZoom -win $_nWave2 $t0 $t1
    wvCapture -win $_nWave2 -file "$OUTDIR/$name.png"
}
PROC
    # figures file -> fig calls
    awk 'NF && $1 !~ /^#/ {
            name=$1; t0=$2; t1=$3; sigs="";
            for (i=4; i<=NF; i++) sigs = sigs (i>4 ? " " : "") $i;
            printf "fig %s %s %s {%s}\n", name, t0, t1, sigs
         }' "$FIGS"
    echo 'debExit'
} > "$TCL"

LOG=$WORK/capture.log
( cd "$WORK" && DISPLAY="$DISP" verdi -play "$TCL" >"$LOG" 2>&1 ) || true

# Verdi does not fail the run on a bad command; it prints one line and carries
# on, leaving a figure silently missing or empty. Treat that as an error.
if grep -q "invalid command" "$LOG"; then
    echo "ERROR: Verdi rejected a command:" >&2
    grep "invalid command" "$LOG" >&2
    echo "  full log: $LOG" >&2
    exit 1
fi

want=$(awk 'NF && $1 !~ /^#/ {n++} END{print n+0}' "$FIGS")
got=0
for n in $(awk 'NF && $1 !~ /^#/ {print $1}' "$FIGS"); do
    [ "$OUT/$n.png" -nt "$TCL" ] && got=$((got + 1)) || echo "  missing or stale: $n.png" >&2
done
echo "[verdi] $got / $want figures -> $OUT/"
for n in $(awk 'NF && $1 !~ /^#/ {print $1}' "$FIGS"); do
    [ -e "$OUT/$n.png" ] && printf "  %-28s %7s B\n" "$n.png" "$(stat -c %s "$OUT/$n.png")"
done
[ "$got" -ge "$want" ] || { echo "ERROR: fewer figures than requested; see $LOG" >&2; exit 1; }
rm -rf "$WORK"

# A capture carries Verdi's menu bar and toolbar on top and a whole-file
# overview ruler at the bottom. The overview ruler is the harmful part: its
# numbers span the entire dump, not the zoomed window, and readers take them
# for the figure's time axis. Crop both off. CROP=0 keeps the raw capture.
if [ "${CROP:-1}" = 1 ] && python3 -c 'import PIL' 2>/dev/null; then
    for n in $(awk 'NF && $1 !~ /^#/ {print $1}' "$FIGS"); do
        python3 - "$OUT/$n.png" <<'PY'
import sys
from PIL import Image
f = sys.argv[1]
im = Image.open(f)
w, h = im.size
# 47 px of menu + toolbar above the time ruler; 34 px of overview ruler and
# scrollbar at the bottom. Both are fixed by Verdi's layout, not the data.
im.crop((0, 47, w, h - 34)).save(f)
PY
    done
    echo "[crop] removed toolbar and overview ruler (CROP=0 to keep them)"
fi

# A capture of a window whose signals all failed to resolve still writes a
# valid PNG, just an empty one. Sizes clustered at one identical value are
# the signature; check them rather than trusting the count.
echo
echo "NOTE: identical file sizes usually mean the signal paths did not resolve"
echo "      and the panes are blank. Open one and look before shipping."
