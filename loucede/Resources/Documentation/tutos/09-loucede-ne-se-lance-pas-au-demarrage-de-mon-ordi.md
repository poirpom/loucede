# loucedé ne se lance pas au démarrage de mon ordi

Tu as activé "Lancer au démarrage" dans loucedé pour ne plus avoir à te taper le double-clic matinal, mais à chaque redémarrage de ton Mac : nada. Pas d'icône loucedé dans la barre des menus. Tu pleures.

C'est pas le moment de craquer, c'est le moment de vérifier 2 trucs. Suis le guide.

---

## 1. Vérifier que "Lancer au démarrage" est bien activé dans loucedé

**Ouvre loucedé → Réglages → Général, et regarde la section *Préférences*.** Le toggle *Lancer au démarrage* doit être en bleu (activé).

![lancer-demarrage.png](bundle://images/09-loucede-ne-se-lance-pas-au-demarrage-de-mon-ordi-lancer-demarrage.png)

S'il était désactivé, active-le. Redémarre ton Mac. Test.

---

## 2. Vérifier que loucedé est bien dans la liste système macOS

macOS a sa propre liste d'apps qui démarrent à l'ouverture de la session. Possible que loucedé ait été retiré de cette liste sans que le toggle interne soit touché.

1. **Va dans *Réglages système* → *Général* → *Ouverture et extensions***.
2. Sous *Ouvrir avec la session*, **cherche loucedé dans la liste**.

![ouverture-macos-comment.png](bundle://images/09-loucede-ne-se-lance-pas-au-demarrage-de-mon-ordi-ouverture-macos-comment.png)

Si loucedé est absent de la liste, deux options pour le remettre :

- **Option simple** : retourne dans loucedé → Réglages → Général, désactive puis réactive le toggle *Lancer au démarrage*. loucedé se ré-enregistre auprès de macOS.
- **Option manuelle** : clique sur le `+` sous la liste système et ajoute loucedé depuis le dossier *Applications*.

Redémarre ton Mac. Test.