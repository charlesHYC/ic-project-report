#!/bin/bash
# End-to-end demo: simulate a tiny design, then export its waveforms.
#
# rr_writer is a round-robin channel writer that exists only to have something
# to photograph. Burst N goes to channel N mod CH, and the address inside a
# channel advances only after the walk has been all the way round - which is
# exactly the kind of rule a waveform can prove at a glance.
#
#   EDA_ENV=/path/to/your/eda/setup ./run.sh
set -e
cd "$(dirname "$0")"
[ -n "${EDA_ENV:-}" ] && [ -r "$EDA_ENV" ] && source "$EDA_ENV" >/dev/null 2>&1 || true
: "${VERDI_HOME:=$(dirname "$(dirname "$(command -v verdi)")")}"
export VERDI_HOME

vcs -full64 -sverilog +v2k -timescale=1ns/1ps -debug_access+all \
    rr_writer.v tb_rr_writer.v -top tb_rr_writer -o simv_demo
./simv_demo +fsdb
../scripts/verdi_capture.sh tb_rr_writer.fsdb tb_rr_writer figs.txt sample
