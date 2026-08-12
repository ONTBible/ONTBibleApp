#!/usr/bin/env bash
#
# Téléverse les symboles de débogage (dSYM) vers Sentry.
#
# Appelé par une phase de build Xcode — jamais à la main, sauf pour un
# rattrapage. Sans ces symboles, une pile d'appels d'un build Release arrive
# en adresses hexadécimales : `0x0000000102a4c1f8` au lieu de
# `ONTData.BundleCorpusRepository.book(_:)`. Illisible, donc inutile.
#
# Le dSYM est apparié au binaire par UUID : celui d'un autre build ne sert à
# rien. C'est pourquoi le téléversement vit dans le build lui-même.

set -euo pipefail

# Homebrew n'est pas dans le PATH d'une phase de build Xcode.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

export SENTRY_ORG="${SENTRY_ORG:-pinkha-app}"
export SENTRY_PROJECT="${SENTRY_PROJECT:-ont-ios}"
# Pas de SENTRY_URL : un jeton d'organisation porte sa région, et l'imposer à
# la main ne fait qu'entrer en conflit avec elle.

# ── Ce qui ne concerne pas ce build ──────────────────────────────────────────

# Un build Debug ne produit pas de dSYM, et ses piles sont déjà lisibles.
if [ "${CONFIGURATION:-Debug}" = "Debug" ]; then
  echo "note: Sentry — build Debug, pas de symboles à téléverser."
  exit 0
fi

# Un aperçu SwiftUI ou une compilation d'index n'est pas un vrai build.
if [ "${ENABLE_PREVIEWS:-NO}" = "YES" ]; then
  exit 0
fi

# ── Ce qui doit être présent ─────────────────────────────────────────────────
#
# Ici on échoue bruyamment. Une phase qui « saute silencieusement » livre un
# build dont les rapports d'erreur seront illisibles, et personne ne s'en
# aperçoit avant le premier vrai plantage — c'est-à-dire trop tard.

if ! command -v sentry-cli >/dev/null; then
  echo "error: sentry-cli introuvable. Installez-le : brew install getsentry/tools/sentry-cli"
  exit 1
fi

# Le jeton, par ordre de préférence :
#   1. la variable d'environnement (CI),
#   2. `app/sentry.properties` (gitignoré, chmod 600),
#   3. `~/.sentryclirc`, écrit par `sentry-cli login` — que sentry-cli lit seul.
#
# Le troisième est le meilleur sur une machine de développement : le secret
# vit hors du dépôt, il ne peut donc pas y entrer par accident.
PROPRIETES="${SRCROOT:-$(cd "$(dirname "$0")/../app" && pwd)}/sentry.properties"
if [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
  :
elif [ -f "$PROPRIETES" ]; then
  export SENTRY_PROPERTIES="$PROPRIETES"
elif [ -f "$HOME/.sentryclirc" ]; then
  :
else
  cat >&2 <<'TXT'
error: Sentry — aucun jeton d'authentification.

  Le DSN (déjà dans Info.plist) laisse *écrire des événements* ; téléverser
  des symboles demande un jeton d'organisation, qui est un secret.

  Une fois, sur cette machine :

      sentry-cli login

  Le navigateur s'ouvre, le jeton est rangé dans ~/.sentryclirc — hors du
  dépôt. Ne le collez nulle part dans le projet.
TXT
  exit 1
fi

# ── Le téléversement ─────────────────────────────────────────────────────────
#
# `--include-sources` joint les extraits de code source aux images de débogage,
# pour que Sentry affiche la ligne fautive à côté de la trame native. Ce sont
# nos sources Swift : elles ne disent rien du lecteur.
# Accolades obligatoires : sans elles, bash agrège le premier octet du « … »
# au nom de la variable et `set -u` fait échouer le build.
echo "note: Sentry — téléversement des symboles de ${SENTRY_PROJECT}…"
sentry-cli debug-files upload \
  --include-sources \
  --force-foreground \
  "${DWARF_DSYM_FOLDER_PATH:?DWARF_DSYM_FOLDER_PATH absent — cette phase doit tourner dans Xcode}"
