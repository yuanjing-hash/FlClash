#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
cd "$root"

mode=""
want_version=""
do_push=0
assume_yes=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: tool/release.sh <pre|stable> [options]

  pre                Tag the next vX.Y.Z[-root.N]-pre.N prerelease.
  stable             Write the changelog, commit it, and tag vX.Y.Z[-root.N].

Options:
  --version VERSION  Target X.Y.Z or X.Y.Z-root.N. Defaults to pubspec,
                     bumping the patch or root revision if already tagged.
  --push             Push the branch and the tag once the local steps pass.
  --yes              Skip the confirmation prompt.
  --dry-run          Report the plan and exit without changing anything.
  -h, --help         Show this help.

Examples:
  tool/release.sh pre --push          # v0.8.97-pre.1, notes rendered by CI
  tool/release.sh stable --push       # v0.8.97 with a chore(release) commit
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    pre | stable)
      [[ -z "$mode" ]] || die "mode given twice: $mode and $1"
      mode="$1"
      ;;
    --version)
      shift || die "--version needs a value"
      want_version="$1"
      ;;
    --version=*) want_version="${1#*=}" ;;
    --push) do_push=1 ;;
    --yes | -y) assume_yes=1 ;;
    --dry-run) dry_run=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$mode" ]] || {
  usage >&2
  exit 64
}

if [[ -n "$want_version" && ! "$want_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-root\.[0-9]+)?$ ]]; then
  die "--version must look like 0.9.1-root.1 or 0.9.1, got: $want_version"
fi

pubspec_version() {
  sed -n 's/^version: \([^+]*\)+.*/\1/p' pubspec.yaml
}

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree has uncommitted changes; commit or stash them first"
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" != "HEAD" ]] || die "detached HEAD; check out a branch first"
if [[ "$branch" != "main" ]]; then
  echo "note: releasing from '$branch', not main. CI triggers on the tag, so"
  echo "      this publishes '$branch' while main stays behind."
fi

current="$(pubspec_version)"
[[ -n "$current" ]] || die "could not read the version from pubspec.yaml"

bumped=0
if [[ -n "$want_version" ]]; then
  version="$want_version"
elif git rev-parse -q --verify "refs/tags/v$current" >/dev/null; then
  if [[ "$current" == *-root.* ]]; then
    root_revision="${current##*-root.}"
    version="${current%-root.*}-root.$((root_revision + 1))"
  else
    IFS='.' read -r vmaj vmin vpat <<<"$current"
    version="$vmaj.$vmin.$((vpat + 1))"
  fi
  echo "pubspec is at $current, which is already tagged; targeting $version"
else
  version="$current"
fi

git rev-parse -q --verify "refs/tags/v$version" >/dev/null &&
  die "v$version is already tagged; pass --version with the next one"

if [[ "$version" != "$current" ]]; then
  bumped=1
fi

if [[ "$mode" == "pre" ]]; then
  last="$(git tag --list "v$version-pre.*" |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-root\.[0-9]+)?-pre\.[0-9]+$' |
    sed 's/.*-pre\.//' | sort -n | tail -1 || true)"
  tag="v$version-pre.$(((${last:-0}) + 1))"
else
  tag="v$version"
fi

echo
echo "mode      : $mode"
echo "branch    : $branch"
echo "version   : $current -> $version$([[ $bumped == 1 ]] && echo ' (pubspec will be rewritten)')"
echo "tag       : $tag"
if [[ "$mode" == "pre" ]]; then
  echo "changelog : rendered by CI from build --unreleased; nothing committed"
  echo "publishes : signed Android APKs + SHA256SUMS as a GitHub prerelease"
else
  echo "changelog : CHANGELOG.md + changelog.json regenerated and committed"
  echo "publishes : signed Android APKs + SHA256SUMS as a GitHub release"
fi
echo "repository: https://github.com/yuanjing-hash/FlClash"
echo "signing   : without signing secrets, debug APKs stay workflow artifacts"
echo "push      : $([[ $do_push == 1 ]] && echo yes || echo 'no (printed at the end)')"
echo

committed=0
restore() {
  ((committed)) && return 0
  git checkout -- pubspec.yaml changelog.json CHANGELOG.md 2>/dev/null || true
}
trap restore EXIT

if ((bumped)); then
  sed -i.bak "s/^version: [^+]*/version: $version/" pubspec.yaml
  rm -f pubspec.yaml.bak
fi
tool/bump_version.sh minor

echo "--- release notes for $tag ---"
if dart run tool/changelog.dart build --unreleased >/dev/null 2>&1; then
  dart run tool/changelog.dart render release 2>/dev/null |
    sed -n '/changelog:begin/,/changelog:end/p' | sed '1d;$d'
else
  echo "(preview unavailable: 'build --unreleased' found nothing to collect)"
fi
git checkout -- changelog.json 2>/dev/null || true
echo "--- end of notes ---"
echo

if ((dry_run)); then
  echo "dry run: nothing was changed."
  exit 0
fi

if ((assume_yes == 0)); then
  if [[ ! -r /dev/tty ]]; then
    die "no terminal to confirm on; pass --yes to run unattended"
  fi
  while true; do
    read -r -p "Proceed with $tag? [y/n] " reply </dev/tty ||
      die "no answer read; pass --yes to run unattended"
    case "$reply" in
      [yY] | [yY][eE][sS]) break ;;
      [nN] | [nN][oO])
        echo "Cancelled. Nothing was changed."
        exit 0
        ;;
      *) echo "Please answer y or n." ;;
    esac
  done
fi

if [[ "$mode" == "stable" ]]; then
  dart run tool/changelog.dart release --version "$version"
  echo
  git --no-pager diff --stat -- CHANGELOG.md changelog.json pubspec.yaml
  echo
  git add CHANGELOG.md changelog.json pubspec.yaml
  git commit -m "chore(release): v$version"
  committed=1
  dart run tool/changelog.dart verify
elif ! git diff --quiet -- pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "chore: bump version to $(sed -n 's/^version: //p' pubspec.yaml)"
  committed=1
else
  committed=1
fi

git tag "$tag"
echo "tagged $tag at $(git rev-parse --short HEAD)"

if ((do_push)); then
  git push origin "$branch"
  git push origin "$tag"
  echo "pushed $branch and $tag"
else
  echo
  echo "Nothing was pushed. To publish:"
  echo "  git push origin $branch && git push origin $tag"
fi
