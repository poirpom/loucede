# Sécurité & signalement de bugs

## Signaler un bug

Un comportement anormal ? [Ouvre une issue](https://github.com/poirpom/loucede/issues) avec :

- Ce qui s'est passé et ce que tu attendais
- Les étapes pour reproduire
- Ta version de macOS (loucedé cible macOS 15.0+)
- Le provider et le modèle utilisés le cas échéant

## Signaler une vulnérabilité de sécurité

Si tu découvres un problème de sécurité (clés API mal protégées, données
envoyées vers un endpoint inattendu, exécution non sollicitée…),
**n'ouvre pas d'issue publique**.

Contacte directement l'auteur par email : **fabrice@poirpom.com**

- Réponse sous quelques jours.
- Le signalement reste confidentiel jusqu'à la publication du correctif.
- Tu seras crédité·e dans le correctif si tu le souhaites.

## Comment loucedé gère tes données

- **Clés API** : stockées localement dans le Keychain macOS (service
  `app.loucede.loucede.apikey`). Jamais envoyées ailleurs que vers le
  provider correspondant (OpenAI, Anthropic, Mistral).
- **Texte sélectionné** : envoyé uniquement au provider que tu as choisi,
  pour exécuter l'action sélectionnée.
- **Aucune télémétrie** : aucun suivi, aucun analytics, aucune connexion
  réseau vers des serveurs tiers autres que le provider choisi.
- **Aucun compte** : loucedé fonctionne sans authentification, sans OAuth,
  sans backend.
- **Mises à jour** : l'app vérifie périodiquement les [GitHub Releases](https://github.com/poirpom/loucede/releases)
  du dépôt officiel (connexion HTTPS à api.github.com, aucune donnée envoyée).
