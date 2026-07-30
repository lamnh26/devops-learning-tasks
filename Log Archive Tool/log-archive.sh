#!/usr/bin/env bash
#
# log-archive.sh - Archive a log directory into a timestamped tar.gz
#
# Compresses the contents of <log-directory> into a .tar.gz stored in an
# archive directory, and appends a record of each run to a manifest log.
#
# Usage:
#   log-archive <log-directory> [-o <output-dir>] [-r <days>] [-h]
#
# Options:
#   -o <output-dir>  Where archives are stored   (default: <log-directory>/archives)
#   -r <days>        Delete archives older than N days after a successful run
#   -h               Show this help
#
# Examples:
#   log-archive /var/log
#   log-archive /var/log -o /backups/logs -r 30

set -euo pipefail

prog=${0##*/}

usage() {
    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- parse arguments --------------------------------------------------------

log_dir=""
out_dir=""
retention_days=""

[[ $# -eq 0 ]] && usage 1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out_dir=${2:?"-o needs a directory"}; shift 2 ;;
        -r) retention_days=${2:?"-r needs a number of days"}; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "$prog: unknown option '$1'" >&2; usage 1 ;;
        *)  if [[ -z "$log_dir" ]]; then log_dir=$1; shift
            else echo "$prog: unexpected argument '$1'" >&2; usage 1; fi ;;
    esac
done

# ---- validate ---------------------------------------------------------------

if [[ -z "$log_dir" ]]; then
    echo "$prog: missing <log-directory>" >&2; usage 1
fi
if [[ ! -d "$log_dir" ]]; then
    echo "$prog: '$log_dir' is not a directory" >&2; exit 1
fi
if [[ ! -r "$log_dir" ]]; then
    echo "$prog: '$log_dir' is not readable (try sudo for /var/log)" >&2; exit 1
fi

# Default archive dir lives under the log dir; override with -o
out_dir=${out_dir:-"$log_dir/archives"}
mkdir -p "$out_dir"

if [[ -n "$retention_days" && ! "$retention_days" =~ ^[0-9]+$ ]]; then
    echo "$prog: -r expects a positive integer, got '$retention_days'" >&2; exit 1
fi

# ---- archive ----------------------------------------------------------------

ts=$(date '+%Y%m%d_%H%M%S')
archive_name="logs_archive_${ts}.tar.gz"
archive_path="$out_dir/$archive_name"
manifest="$out_dir/archive.log"

echo "Archiving '$log_dir' -> $archive_path"

# --exclude the archive dir so we never tar our own output.
# -C into the parent and tar the basename so paths in the archive stay relative.
parent=$(cd "$log_dir" && pwd)
base=$(basename "$parent")
tar --exclude="$base/archives" \
    --warning=no-file-changed \
    -czf "$archive_path" \
    -C "$(dirname "$parent")" "$base" 2>/dev/null \
  || { rc=$?; # tar returns 1 for "file changed as we read it" - tolerate that
       if [[ $rc -ne 1 ]]; then echo "$prog: tar failed (exit $rc)" >&2; exit "$rc"; fi; }

size=$(du -h "$archive_path" | cut -f1)

# ---- manifest ---------------------------------------------------------------

printf '%s | source=%s | archive=%s | size=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$log_dir" "$archive_name" "$size" \
    >> "$manifest"

echo "Done. Size: $size"
echo "Logged to: $manifest"

# ---- optional retention -----------------------------------------------------

if [[ -n "$retention_days" ]]; then
    old=$(find "$out_dir" -maxdepth 1 -name 'logs_archive_*.tar.gz' \
              -type f -mtime +"$retention_days" -print -delete | wc -l)
    (( old > 0 )) && echo "Pruned $old archive(s) older than $retention_days days."
fi