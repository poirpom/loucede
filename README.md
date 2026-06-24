<p align="center">
  <img src="https://res.cloudinary.com/poirpom/image/upload/v1780859210/loucede/logo-1024_dsuue5.png" width="128" alt="loucedé">
</p>

# loucedé — Une IA au bout de tes doigts

🌐 [loucede.app](https://loucede.app)

Une application macOS effectuant des actions IA sur du texte sélectionné. Sans copier-coller, sans ouvrir un chat, sans attendre. Beaucoup plus rapide donc, mais surtout beaucoup moins chiant.


https://github.com/user-attachments/assets/46196d13-9102-4bb6-b52d-12a1771bbd47

---

## Fonctionnalités

- Raccourci clavier configurable (par défaut ⌥&)
- Multi-providers : Anthropic, OpenAI, Mistral — au choix avec ta clé API
- Générateur d'actions à la volée : crée une action IA personnalisée depuis le popup
- Streaming des réponses dans une fenêtre de résultat dédiée (live-grow pendant la génération)
- Tutoriel interactif au premier lancement
- Light/dark mode système
- Mises à jour automatiques
- Fonctionne partout : navigateur, mail, traitement de texte, PDF…

### Actions prédéfinies

loucedé est livré avec une vingtaine d'actions prédéfinies organisées par catégorie : traduire, analyser, transformer, structurer, proposer. Quelques exemples emblématiques :

- 🤏 Résume ce texte
- 🌍 Traduire en anglais
- ✍️ Corrige les fautes
- 🍳 Extrais la recette de cuisine
- 🏷️ Extrais les noms propres

Tu peux modifier ces actions, en désactiver, en créer de nouvelles à la volée via le générateur d'action.

---

## Pourquoi pas un chat IA classique ?

**Sans loucedé**, pour résumer un article web :
sélectionner le texte → copier → ouvrir un onglet → attendre que ça charge → écrire un prompt → coller → entrée → attendre la réponse → la lire.

**Avec loucedé** :
sélectionner le texte → ⌥& → choisir 🤏 Résume ce texte → c'est fait.

Beaucoup plus rapide. Et surtout beaucoup moins chiant.

---

## Installation

### Prérequis

- macOS 15 (Sequoia) minimum
- Xcode 16 minimum pour compiler depuis les sources

### Installer le binaire

Un binaire notarisé est disponible sur les [Releases GitHub](https://github.com/poirpom/loucede/releases). Télécharge le `.dmg`, ouvre-le, glisse loucedé dans `Applications`. C'est tout.

### Compiler depuis les sources

```bash
git clone https://github.com/poirpom/loucede.git
cd loucede
open loucede.xcodeproj
```

Lance avec `⌘R` depuis Xcode.

### Modèle économique

12 utilisations gratuites pour tester, puis 10€ en paiement unique (pas d'abonnement) sur [polar.sh](https://buy.polar.sh/polar_cl_NyddnsIaqM7gVRKFinwyIhM8iHqzoRrJaZfDi2HN0SO).

Le coût d'utilisation des IA dépend ensuite du fournisseur que tu choisis (Mistral, Anthropic ou OpenAI), du modèle et de ton usage. En pratique : quelques euros par an grand max, payés directement au fournisseur — aucun rapport avec loucedé.

---

## Configuration

1. **Permission Accessibilité** — au premier lancement, loucedé demande l'accès à l'API Accessibilité macOS pour lire le texte sélectionné. Autorise-le dans Réglages Système → Confidentialité et sécurité → Accessibilité.

2. **Raccourci global** — par défaut `⌥&`. Modifiable dans Réglages → Général.

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
- Mises à jour : **[Sparkle](https://sparkle-project.org)**
- Rendu Markdown : **[MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)**
