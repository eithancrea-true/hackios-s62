#!/bin/bash
# Host test of the S62 GPT editor (emmc_gpt_split in bsd/dev/sweet_ufs.c, patch 9000).
# Needs gcc and sgdisk. Builds a sparse 30 GiB disk with an S62-like GPT (72 entries,
# userdata last), runs plan and apply, checks with sgdisk, and checks the refusals.
set -e
cd "$(dirname "$0")"; W=$(mktemp -d)
python3 - "$W/gpt_body.c" ../../xnu/patches/9000-*.patch <<'PY'
import sys
lines = open(sys.argv[2]).read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith('+ * S62 GPT editor')) - 1
j = next(k for k in range(i, len(lines)) if lines[k][1:] == 'sweet_ufs_init(void)') - 1
body = [l[1:] for l in lines[i:j] if not l.startswith('+#include <sys/random.h>')]
open(sys.argv[1], 'w').write('\n'.join(body) + '\n')
PY
cp harness.c $W/ && gcc -std=gnu11 -Wall -Wno-format -Wno-unused-function -o $W/harness $W/harness.c
truncate -s 30G $W/d.img && sgdisk -o $W/d.img >/dev/null && sgdisk --resize-table=72 $W/d.img >/dev/null
for i in $(seq 1 68); do sgdisk -n $i:0:+1M -c $i:part$i $W/d.img >/dev/null; done
sgdisk -n 69:0:0 -c 69:userdata $W/d.img >/dev/null
$W/harness $W/d.img 1 16384 && $W/harness $W/d.img 2 16384 && sgdisk -v $W/d.img | grep "No problems found"
! $W/harness $W/d.img 2 16384 >/dev/null && echo "second apply refused: OK"
rm -rf $W
