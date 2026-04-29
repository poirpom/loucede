# loucedé — Une IA au bout de tes doigts

🌐 [loucede.app](https://loucede.app)

Une application macOS effectuant des actions IA sur du texte sélectionné. Sans copier-coller, sans ouvrir un chat, sans attendre. Beaucoup plus rapide donc, mais surtout beaucoup moins chiant.

![loucedé](https://res.cloudinary.com/poirpom/image/upload/v1777481584/loucede/motto-home-CD_aqbzpz.png)

---

## Fonctionnalités

- Raccourci clavier configurable (par défaut ⌃+⌥+W)
- Multi-providers : Anthropic, OpenAI, Mistral — au choix avec ta clé API
- Streaming des réponses
- Light/dark mode système
- Mises à jour automatiques
- Fonctionne partout : navigateur, mail, traitement de texte, PDF…

### 🌍 Traduire
Français, anglais, espagnol, portugais, emojis.

### 🔬 Analyser
Détection d'incohérences, extraction d'arguments, analyse de biais, génération de questions.

### ⚡ Transformer
Résumé, correction de fautes, simplification, optimisation SEO, ton professionnel, concision, amélioration du style.

### 🗂️ Structurer
Extraction de recettes de cuisine, réorganisation logique, conversion en tableau Markdown, génération de todo lists.

### 💡 Proposer
Titres accrocheurs, plans structurés.

Tu peux modifier ces actions, en désactiver, en créer de nouvelles ou exporter ta config depuis Réglages → Actions.

---

## Pourquoi pas un chat IA classique ?

**Sans loucedé**, pour résumer un article web :
sélectionner le texte → copier → ouvrir un onglet → attendre que ça charge → écrire un prompt → coller → entrée → attendre la réponse → la lire.

**Avec loucedé** :
sélectionner le texte → ⌃+⌥+W → choisir 🤏 Résume ce texte → c'est fait.

Beaucoup plus rapide. Et surtout beaucoup moins chiant.

---

## Installation

### Prérequis

- macOS 15 (Sequoia) minimum
- Xcode 16 minimum pour compiler depuis les sources

### Compiler depuis les sources

```bash
git clone https://github.com/poirpom/loucede.git
cd loucede
open loucede.xcodeproj
```

Lance avec `⌘R` depuis Xcode.

> Un binaire notarisé sera disponible sur les [Releases GitHub](https://github.com/poirpom/loucede/releases) dès la sortie de la v1.0.

### Modèle économique

12 utilisations gratuites pour tester, puis 8€ en paiement unique (pas d'abonnement) sur [polar.sh](https://buy.polar.sh/polar_cl_NyddnsIaqM7gVRKFinwyIhM8iHqzoRrJaZfDi2HN0SO).

Le coût d'utilisation des IA dépend ensuite du fournisseur que tu choisis (Mistral, Anthropic ou OpenAI), du modèle et de ton usage. En pratique : quelques euros par an grand max, payés directement au fournisseur — aucun rapport avec loucedé.

---

## Configuration

1. **Permission Accessibilité** — au premier lancement, loucedé demande l'accès à l'API Accessibilité macOS pour lire le texte sélectionné. Autorise-le dans Réglages Système → Confidentialité et sécurité → Accessibilité.

2. **Raccourci global** — par défaut `⌃⌥W`. Modifiable dans Réglages → Général.

3. **Clé API** — dans Réglages → Général, colle ta clé API et choisis ton fournisseur :
   - Anthropic : [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
   - OpenAI : [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
   - Mistral : [console.mistral.ai/api-keys](https://console.mistral.ai/api-keys)

---

## Contribuer

Consulte [CONTRIBUTING.md](CONTRIBUTING.md) pour le guide de contribution, le style de code et comment soumettre une PR.

---

## Licence

Distribué sous **[GPL v3](LICENSE)**.

---

## Crédits

- Fork de **[TexTab](https://github.com/ELPROFUG0/TexTab)** par [ELPROFUG0](https://github.com/ELPROFUG0) — merci pour le travail de base
- Gestion de licence : **[Polar.sh](https://polar.sh)**
- APIs IA : **[Anthropic](https://anthropic.com)**, **[OpenAI](https://openai.com)**, **[Mistral](https://mistral.ai)**
