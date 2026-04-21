<h1 align="center">loucedé</h1>

<p align="center">L'IA en loucedé, directement depuis votre barre des menus.</p>

<p align="center">
  <a href="https://loucede.app">Site</a> · <a href="https://github.com/poirpom/loucede/issues">Signaler un bug</a>
</p>

<br />

## À propos

**loucedé** est une application macOS qui vit dans la barre des menus et déclenche des actions IA sur le texte sélectionné, partout dans le système. Sélectionnez du texte dans n'importe quelle app, appuyez sur `⇧ + ⌥ + A`, choisissez une action — c'est fait.

Votre clé API, votre modèle. Pas d'abonnement, pas d'intermédiaire, les requêtes partent directement chez le fournisseur.

<br />

## Fonctionnalités

- **Actions personnalisées** — créez autant de prompts que vous voulez, chacun avec son emoji
- **Sélection rapide** — touches 1-9, 0, - et = depuis le popup (compatible AZERTY/QWERTY)
- **Trois fournisseurs** — OpenAI, Anthropic (Claude), Mistral
- **Streaming** — la réponse s'affiche au fur et à mesure
- **Confidentialité** — votre clé API parle directement au fournisseur, rien ne passe par nos serveurs
- **Partout** — fonctionne dans toutes les apps, tous les champs de texte

<br />

## Installation

Téléchargez la dernière version sur la [page des releases](https://github.com/poirpom/loucede/releases/latest), ou compilez depuis les sources :

```bash
git clone https://github.com/poirpom/loucede.git
cd loucede
open loucede.xcodeproj
```

Puis compilez et lancez (`⌘R`).

### Configuration minimale

- macOS 15 (Sequoia) ou plus récent
- Xcode 26 ou plus récent pour compiler
- Une clé API chez au moins un fournisseur : [OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://console.anthropic.com/settings/keys), ou [Mistral](https://console.mistral.ai/api-keys/)

<br />

## Contribuer

Les PR sont les bienvenues. Ouvrez une issue avant les gros changements pour qu'on discute de la direction.

<br />

## Licence et attribution

loucedé est distribué sous **GPL v3** — voir [LICENSE](LICENSE).

Il s'agit d'un fork francophone de **[TexTab](https://github.com/ELPROFUG0/TexTab)** par [ELPROFUG0](https://github.com/ELPROFUG0), lui aussi sous GPL v3. Merci à l'auteur original pour le travail de base.

Les modifications apportées par loucedé — localisation française, restriction aux trois fournisseurs OpenAI / Anthropic / Mistral, sélection des prompts par touches du haut du clavier, import/export JSON, changements d'architecture de licence, suppression des plugins — s'ajoutent au projet original en respectant la GPL v3. Le code reste libre et toute redistribution doit rester sous la même licence.
