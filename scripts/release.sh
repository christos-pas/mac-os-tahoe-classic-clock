#!/bin/sh
# Create a dist zip, commit the version bump, push, and publish a GitHub release.
# Usage:
#   make release
#   make release NOTES="What changed"
#   ./scripts/release.sh --notes "What changed"
#
# The working tree must be clean before release (aside from what this script writes).
# After `make dist` bumps Version.xcconfig, that file is committed and pushed so the
# tag and the version in git stay aligned.
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

notes="${NOTES-}"
while [ $# -gt 0 ]; do
	case "$1" in
		--notes)
			if [ $# -lt 2 ]; then
				echo "error: --notes requires a value" >&2
				exit 1
			fi
			notes="$2"
			shift 2
			;;
		--notes=*)
			notes="${1#--notes=}"
			shift
			;;
		-h|--help)
			echo "usage: make release NOTES=\"...\""
			echo "       ./scripts/release.sh --notes \"...\""
			echo
			echo "GNU make cannot take a --notes flag. Use NOTES= with make, or this script."
			echo "Requires a clean working tree. Commits and pushes Version.xcconfig after the bump."
			exit 0
			;;
		*)
			echo "error: unknown option: $1" >&2
			echo "usage: make release NOTES=\"...\"  or  ./scripts/release.sh --notes \"...\"" >&2
			exit 1
			;;
	esac
done

if [ ! -f "$root/Makefile" ] || [ ! -f "$root/Version.xcconfig" ]; then
	echo "error: run this from the Lock Clock repo" >&2
	exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
	echo "error: gh is not installed (brew install gh)" >&2
	exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "error: not a git repository. Commit and create the GitHub repo first." >&2
	exit 1
fi

if ! git rev-parse HEAD >/dev/null 2>&1; then
	echo "error: no commits yet. Commit and push before releasing." >&2
	exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
	echo "error: no origin remote. Create the GitHub repo and push first." >&2
	exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
	echo "error: gh is not logged in. Run: gh auth refresh -h github.com" >&2
	exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
	echo "error: working tree is dirty. Commit or stash your changes, then run release again." >&2
	echo "The release script commits only the Version.xcconfig bump." >&2
	git status --short >&2
	exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "HEAD" ]; then
	echo "error: detached HEAD. Check out a branch before releasing." >&2
	exit 1
fi

echo "Checking GitHub access..."
gh repo view >/dev/null

echo "Building dist zip..."
make dist

major="$(awk '/^MAJOR = / { print $3; exit }' Version.xcconfig)"
minor="$(awk '/^MINOR = / { print $3; exit }' Version.xcconfig)"
build="$(awk '/^BUILD = / { print $3; exit }' Version.xcconfig)"
version="${major}.${minor}.${build}"
zip_path="$root/dist/LockClock-${version}.zip"
tag="v${version}"

if [ ! -f "$zip_path" ]; then
	echo "error: expected zip not found: $zip_path" >&2
	exit 1
fi

if git diff --quiet -- Version.xcconfig; then
	echo "error: Version.xcconfig was not changed by make dist" >&2
	exit 1
fi

# Only the version file should be dirty after a clean-tree dist.
if [ -n "$(git status --porcelain | grep -v ' Version.xcconfig$' || true)" ]; then
	echo "error: unexpected dirty files after dist (expected only Version.xcconfig):" >&2
	git status --short >&2
	exit 1
fi

echo "Committing version bump ${version}..."
git add Version.xcconfig
git commit -m "Bump version to ${version}"
echo "Pushing ${branch}..."
git push -u origin HEAD

if [ -z "$notes" ]; then
	notes="Lock Clock ${version}

Ad-hoc signed and not notarized. macOS Gatekeeper will warn on open; Control-click → Open. If it says the app is damaged:

xattr -d com.apple.quarantine /Applications/LockClock.app"
fi

echo "Creating GitHub release ${tag}..."
url="$(gh release create "$tag" "$zip_path" --title "Lock Clock ${version}" --notes "$notes" --target "$(git rev-parse HEAD)")"
echo "$url"
