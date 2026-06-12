# Obtenir et fournir une clé API

Tu as installé loucedé, tu l’as lancé mais l'app refuse de fonctionner sans qu'une clé API soit renseignée. 

Normal ma gueule : loucedé a besoin de cette clé pour parler à l'IA. Ce tuto t'explique comment l'obtenir et la configurer.

On va pas se mytho : ça, c’est l’étape la plus chiante. Mais franchement : c’est plié en 3 minutes chrono.

> ℹ️ Il te faudra une CB en cours de validité pour utiliser une clé API. 
>
> Bonne nouvelle : c’est facturé à l’usage, en pré-paiement, et pas cher.

---

## Pourquoi ai-je besoin d'une clé API ?

loucedé ne paye pas l'IA pour toi. Tu choisis ton fournisseur (Mistral, Anthropic, ou OpenAI), tu crées un compte chez eux, tu obtiens une clé API, et tu la colles dans loucedé. À chaque action, loucedé envoie ta requête au fournisseur via cette clé, récupère la réponse, et l'affiche.

Côté finances :

- loucedé : 10€ à l'achat de l'app.
- Fournisseur IA : payé directement, à l'usage. Quelques euros par an pour un usage classique.

Côté données : loucedé sert de courroie de transmission. Le contenu sélectionné est envoyé au fournisseur (forcément, c'est lui qui fait le travail), mais loucedé ne stocke ni tes requêtes ni les réponses de l'IA. Aucune trace côté loucedé.

---

## Choisir ton fournisseur

**Trois fournisseurs sont supportés.** Ils sont équivalents en termes de capacités générales mais différents par leur pays d'origine, leurs tarifs, et leurs particularités d'inscription.

### Mistral 🇫🇷

Fournisseur français. Modèles principalement développés à Paris.

> ℹ️ Particularité : Mistral propose un plan Experiment gratuit (sans carte bancaire) pour tester l'API avant de passer en payant. 
>
> Pratique pour démarrer si tu veux d'abord essayer. Une API c’est comme un repas : c’est meilleur quand c’est gratuit. Ne te prive pas.

### Anthropic 🇺🇸

Fournisseur américain. Modèles Claude.

### OpenAI 🇺🇸

Fournisseur américain. Modèles GPT.

---

## Comparatif des modèles recommandés

| Fournisseur | Modèle recommandé | Coût indicatif |
| --- | --- | --- |
| Mistral 🇫🇷 | Mistral Small | ~10 000 actions/€ |
| OpenAI 🇺🇸 | GPT-4o Mini | ~5 000 actions/€ |
| Anthropic 🇺🇸 | Claude Haiku | ~800 actions/€ |

**Ces modèles offrent le meilleur rapport vitesse/qualité/coût pour les actions courantes de loucedé (corriger, traduire, résumer, reformuler).**

Si tu veux la qualité maximale (créativité, traduction nuancée, résumé long), bascule sur les modèles plus haut de gamme du fournisseur (Mistral Medium / Large, GPT-4o, Claude Sonnet ou Opus). Ils sont plus chers mais plus performants sur les tâches complexes.

> ℹ️ Tu peux changer de fournisseur à tout moment dans les *Réglages*. Pas d'engagement. 
>
> Par contre, tu devras créer une clé API chez chaque fournisseur que tu souhaites utiliser

---

## La procédure (commune aux 3 fournisseurs)

Le parcours est globalement le même chez les trois fournisseurs. Quatre étapes.

### 1. Créer un compte

Va sur le site du fournisseur que tu as choisi :

- Mistral : [console.mistral.ai](https://console.mistral.ai)
- Anthropic : [console.anthropic.com](https://console.anthropic.com)
- OpenAI : [platform.openai.com](https://platform.openai.com)

Tu peux t’inscrire avec ton email ou ton compte Google.

### 2. Ajouter un moyen de paiement

**Les trois fournisseurs demandent une carte bancaire avant de pouvoir générer une clé API valide.** C'est dans la section `Billing` (ou `Plans & Billing` ou `Facturation`) de leur console.

Tu peux fixer un plafond de dépense (Mets pas plus de 5 balles pour commencer).

> ℹ️ Exception : Mistral propose le plan Experiment gratuit qui te permet de tester l'API sans CB. Si tu veux essayer Mistral avant de t'engager, c'est l'option à choisir.

### 3. Générer une clé API

Dans la console, va dans la section *API Keys*. Clique sur *Create new key* (ou équivalent), donne un nom à la clé (par exemple "loucedé"), valide.

> ℹ️ **La clé s'affiche une seule fois. Copie-la immédiatement. Si tu la perds, tu devras en générer une nouvelle.**
>
> C’est pas compliqué à faire, hein. Mais si tu peux le faire qu’une fois, c’est bien aussi.

### 4. La coller dans loucedé

1. **Dans loucedé, ouvre les *Réglages.*** 
2. **Dans l’onglet *Général*, sélectionne ton fournisseur dans le menu déroulant, puis colle ta clé dans le champ *Clé API*.** 
3. **Pas besoin de valider, pas de bouton "tester". Tu colles, c'est bon. La première utilisation confirmera que tout marche.**
    
    Sauf si tu copies n’importe quoi dans le champ *Clé API*, hein. RESTE FOCUS STEUPLÉ C CHO LÀ
    

![CleanShot 2026-05-10_20-10-36.png](bundle://images/03-obtenir-et-fournir-une-cle-api-cleanshot-2026-05-10-20-10-36.png)

---

## Spécificités par fournisseur

### Mistral

Au moment de la création de compte, Mistral te demande de créer un Workspace. Une fois dedans, va dans Admin → Subscriptions pour activer ton plan (*Experiment gratuit* ou *Pay-as-you-go* avec CB). Les API keys sont accessibles dans la barre latérale gauche, sous *API Keys*.

### Anthropic

*Settings* → *Billing* pour ajouter ta carte et acheter des crédits prépayés. *Settings* → *API Keys* pour générer la clé. Anthropic fonctionne par crédits prépayés (tu achètes 5€, 10€, etc. à l'avance, puis ils sont consommés à mesure).

### OpenAI

OpenAI demande une vérification par téléphone (un code SMS) avant de pouvoir générer une clé. Le projet par défaut convient pour la plupart des usages. *Billing* → A*dd payment method* pour ajouter ta carte. *API Keys* → *Create new secret key* pour générer la clé.

---

---

## Et après ?

**Une fois ta clé configurée, loucedé est prêt. Tu peux refermer les *Réglages* et tester ta première action.**

Et là, c’est bonheur. Ça marche tout seul. Tu fais ce que tu veux. *Make it rain*.

Pour rappel : loucedé ne stocke ni tes requêtes ni les réponses de l'IA. Tout transite chez le fournisseur que tu as choisi, qui applique sa propre politique de données. À toi de la consulter chez le fournisseur si ce point t'importe. 

A priori, tu as déjà donné à l’IA : ta déclaration d’impôts, les problèmes de cœur de ta sœur et ton profil Tinder à remplir. Alors minaude pas trop passque tu vas lui refiler 2 trads à faire en douce et un mail bourré de fautes à corriger avec loucedé. C’est foutu, déjà. Le jour où tu as ouvert GPT pour la première fois, t’avais déjà perdu.