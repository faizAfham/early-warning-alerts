#!/bin/bash
# Downloads the PhysioNet/CinC Challenge 2019 training data (CC BY 4.0, ~40k ICU stays,
# one .psv file per stay) from PhysioNet's open S3 mirror, then merges every stay into
# data/vitals.psv with a leading pid column (e.g. A_p000001), so DuckDB reads one file.
set -e
cd "$(dirname "$0")/data"
BASE=https://physionet-open.s3.amazonaws.com/challenge-2019/1.0.0/training
for s in A B; do
  mkdir -p training_set$s
  aws s3 ls --no-sign-request s3://physionet-open/challenge-2019/1.0.0/training/training_set$s/ \
    | awk '{print $4}' | grep psv > list_$s.txt
  (cd training_set$s && comm -23 <(sort ../list_$s.txt) <(ls | sort) \
    | xargs -P 48 -I{} curl -sfS --retry 3 -o {} $BASE/training_set$s/{})
done
# every file must have the same 41-column header; abort if one differs
HEADER=$(head -1 training_setA/p000001.psv)
{ echo "pid|$HEADER"
  find training_setA training_setB -name '*.psv' | sort | xargs awk -v H="$HEADER" '
    FNR == 1 { if ($0 != H) { print "bad header: " FILENAME > "/dev/stderr"; exit 1 }
               n = split(FILENAME, a, "/"); id = substr(a[1], 13) "_" substr(a[n], 1, length(a[n]) - 4); next }
    { print id "|" $0 }'
} > vitals.psv
wc -l vitals.psv
