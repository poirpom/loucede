#!/usr/bin/env bash
#
# release.sh — cycle de release loucedé
#
# Pipeline (ajouté incrémentalement, C1→C6) :
#   parse+validate → pré-checks (garde-fous) → versionning →
#   build/archive → export Developer ID → DMG → notarize → staple →
#   sign_update (Sparkle) → tag + GitHub Release + upload asset →
#   appcast.xml (worktree gh-pages éphémère)
#
# Usage : ./release.sh <version>
#   <version>  SemVer SANS préfixe v (ex: 1.0.0, 1.0.1-test)
#              Un suffixe -test / -rc / -beta ⇒ MODE TEST :
#                · GitHub pre-release (jamais "latest")
#                · bump pbxproj NON commité (restauré en fin de run)
#                · enclosure appcast = URL directe du tag (préserve "latest")
#
set -euo pipefail
IFS=$'\n\t'

# --- Paramètres figés -------------------------------------------------------
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="app.loucede.loucede"
TEAM_ID="LAUYMPKAS2"
NOTARY_PROFILE="loucede-notary"
SCHEME="loucede"
REPO="poirpom/loucede"
CODE_BRANCH="main"
APPCAST_BRANCH="gh-pages"
DMG_NAME="loucede.dmg"
PERMALINK="https://github.com/poirpom/loucede/releases/latest/download/loucede.dmg"

# Chemins de travail
BUILD_DIR="$REPO_ROOT/build"
RELEASE_NOTES_DIR="$REPO_ROOT/release-notes"

# --- Logging ----------------------------------------------------------------
info() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./release.sh <version>
  <version>  SemVer sans préfixe v (ex: 1.0.0, 1.0.1-test)
             Un suffixe -test / -rc / -beta déclenche le MODE TEST
             (GitHub pre-release · bump pbxproj non commité · enclosure tag-direct).
EOF
}

# --- État global (rempli au parsing) ---------------------------------------
VERSION=""
TAG=""
IS_TEST=0

# --- Cleanup / trap ---------------------------------------------------------
# Étoffé aux étapes suivantes (build dir, staging DMG, worktree appcast,
# restauration pbxproj). Idempotent : sans danger si une ressource est absente.
cleanup() {
  :
}
trap cleanup EXIT

# --- Parsing des arguments --------------------------------------------------
parse_args() {
  [ "$#" -eq 1 ] || { usage; die "exactement 1 argument attendu (version)"; }
  VERSION="$1"
  # SemVer : MAJOR.MINOR.PATCH + pré-release optionnel (ex: -test, -rc.1)
  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    die "version invalide « $VERSION » — attendu SemVer sans v (ex: 1.0.0, 1.0.1-test)"
  fi
  TAG="v$VERSION"
  if [[ "$VERSION" =~ -(test|rc|beta) ]]; then
    IS_TEST=1
  fi
}

# --- Pré-checks (garde-fous) ------------------------------------------------
preflight() {
  info "Pré-checks…"

  # Outils requis
  local tool
  for tool in gh xcodebuild codesign hdiutil stapler python3 git; do
    command -v "$tool" >/dev/null 2>&1 || die "outil requis absent : $tool"
  done
  xcrun --find notarytool >/dev/null 2>&1 || die "notarytool introuvable (xcrun)"

  # Auth GitHub
  gh auth status >/dev/null 2>&1 || die "gh non authentifié — lance « gh auth login »"

  # Profil notarytool disponible dans le Keychain
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "profil notarytool « $NOTARY_PROFILE » indisponible dans le Keychain"

  # Branche courante
  local branch
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$branch" = "$CODE_BRANCH" ] || die "branche courante « $branch » ≠ « $CODE_BRANCH »"

  # Arbre de travail propre (la mécanique de versionning/commit l'exige)
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
    || die "arbre de travail non propre — commit ou stash avant de release"

  # Garde-fou release-notes (décision #41 : pas de release sans notes)
  local notes="$RELEASE_NOTES_DIR/v$VERSION.md"
  [ -f "$notes" ] || die "release-notes absentes : $notes — pas de release silencieuse"

  # Tag inexistant (local + remote)
  if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "tag $TAG déjà existant en local"
  fi
  if git -C "$REPO_ROOT" ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    die "tag $TAG déjà existant sur origin"
  fi

  ok "Pré-checks OK — version=$VERSION · tag=$TAG · mode=$([ "$IS_TEST" -eq 1 ] && echo TEST || echo PROD)"
}

# --- main -------------------------------------------------------------------
main() {
  parse_args "$@"
  preflight
  # Étapes build / notarize / release / appcast ajoutées aux commits C2→C6.
  ok "release.sh — squelette OK"
}

main "$@"
