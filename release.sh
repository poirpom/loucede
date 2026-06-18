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
PBXPROJ="$REPO_ROOT/loucede.xcodeproj/project.pbxproj"

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
NEW_BUILD=""          # CURRENT_PROJECT_VERSION après bump
PBXPROJ_BACKUP=""     # copie de sauvegarde du pbxproj (restore éventuel)
RESTORE_PBXPROJ=0     # 1 ⇒ cleanup restaure le pbxproj depuis le backup
APP_PATH=""           # .app signé Developer ID exporté
DMG_PATH=""           # DMG final (sous build/, gitignoré)
STAGING_DIR=""        # dossier temporaire de montage du DMG

# --- Cleanup / trap ---------------------------------------------------------
# Étoffé aux étapes suivantes (build dir, staging DMG, worktree appcast).
# Idempotent : sans danger si une ressource est absente.
cleanup() {
  # Restauration du pbxproj : toujours en mode TEST ; en mode PROD seulement
  # si le bump n'a pas été commité (échec avant C5 → on ne laisse pas l'arbre sale).
  if [ "$RESTORE_PBXPROJ" -eq 1 ] && [ -n "$PBXPROJ_BACKUP" ] && [ -f "$PBXPROJ_BACKUP" ]; then
    cp "$PBXPROJ_BACKUP" "$PBXPROJ"
    rm -f "$PBXPROJ_BACKUP"
    warn "pbxproj restauré (bump non conservé)"
  fi
  # Dossier de montage temporaire du DMG (mktemp). Les autres artefacts
  # vivent sous build/ (gitignoré, écrasé au run suivant) → laissés pour debug.
  [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ] && rm -rf "$STAGING_DIR"
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

# --- Versionning ------------------------------------------------------------
# Versions portées par le pbxproj (GENERATE_INFOPLIST_FILE=YES : pas de
# CFBundle*Version dans l'Info.plist statique). On édite le pbxproj au sed.
read_current_build() {
  # Premier CURRENT_PROJECT_VERSION rencontré (toutes les cibles sont alignées)
  local b
  b="$(grep -m1 -E 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ" \
       | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')"
  [[ "$b" =~ ^[0-9]+$ ]] || die "CURRENT_PROJECT_VERSION introuvable/illisible dans le pbxproj"
  printf '%s' "$b"
}

bump_version() {
  info "Versionning…"
  local cur
  cur="$(read_current_build)"
  NEW_BUILD=$((cur + 1))

  # Sauvegarde avant édition (restore en mode test, ou si échec avant commit)
  PBXPROJ_BACKUP="$(mktemp -t loucede-pbxproj-backup)"
  cp "$PBXPROJ" "$PBXPROJ_BACKUP"
  RESTORE_PBXPROJ=1

  # MARKETING_VERSION (3 cibles alignées) + CURRENT_PROJECT_VERSION (bump)
  sed -i '' -E "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

  ok "Version posée : MARKETING_VERSION=$VERSION · CURRENT_PROJECT_VERSION=$cur→$NEW_BUILD"
}

# --- Build + export Developer ID + DMG --------------------------------------
build_app() {
  info "Build + archive (Release)…"
  rm -rf "$BUILD_DIR"

  xcodebuild archive \
    -project "$REPO_ROOT/loucede.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    -archivePath "$BUILD_DIR/loucede.xcarchive" \
    >/dev/null \
    || die "échec de l'archive xcodebuild"

  # Options d'export Developer ID (signature de distribution hors App Store).
  # Notarisation NON déclenchée ici : faite manuellement sur le DMG (C4).
  cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

  info "Export Developer ID…"
  xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/loucede.xcarchive" \
    -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    >/dev/null \
    || die "échec de l'export Developer ID"

  APP_PATH="$(find "$BUILD_DIR/export" -maxdepth 1 -name '*.app' | head -1)"
  [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ] || die "app exportée introuvable sous build/export"
  ok "App signée : $APP_PATH"
}

make_dmg() {
  info "Création du DMG…"
  STAGING_DIR="$(mktemp -d -t loucede-dmg)"
  cp -R "$APP_PATH" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"

  DMG_PATH="$BUILD_DIR/$DMG_NAME"
  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "loucedé" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" \
    >/dev/null \
    || die "échec de la création du DMG"

  rm -rf "$STAGING_DIR"; STAGING_DIR=""
  ok "DMG créé : $DMG_PATH"
}

# --- main -------------------------------------------------------------------
main() {
  parse_args "$@"
  preflight
  bump_version
  build_app
  make_dmg
  # Étapes notarize / release / appcast ajoutées aux commits C4→C6.
  ok "release.sh — build + DMG OK"
}

main "$@"
