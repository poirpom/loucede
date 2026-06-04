# Le raccourci ne fonctionne pas

Tu sélectionnes du texte, tu presses `⌥&` (ou ton raccourci personnalisé), et… rien. Pas de popup. Pas de loucedé. Le néant.

Trois pistes à vérifier dans l'ordre. Tu trouveras le coupable dans les 30 secondes.

---

## 1. Premier réflexe : la permission Accessibilité

C'est le coupable n°1, statistiquement. Sans la permission Accessibilité, **aucun raccourci global ne peut être capté par loucedé**. C'est macOS qui décide.

**Va dans loucedé → Réglages → Général → section *Autorisations***. La ligne *Accessibilité* doit indiquer que la permission est accordée.

Si elle est rouge / manquante :

1. Clique sur **Ouvrir les réglages**.
2. Dans *Réglages système → Confidentialité et sécurité → Accessibilité*, **active la coche en face de loucedé**.
3. Redémarre loucedé (clic droit sur l'icône menu → Quitter → relance via Applications).

---

## 2. Tu as personnalisé le raccourci ? Cherche un conflit

Si tu as remplacé le raccourci par défaut `⌥&` par autre chose, il y a peut-être un conflit avec un raccourci système ou un raccourci d'une autre app.

**Test rapide** : retourne dans loucedé → Réglages → Général → *Raccourci global* et **reconfigure temporairement à `⌥&`** (clique sur le champ, presse `⌥&`).

![raccourci.png](bundle://images/10-le-raccourci-ne-fonctionne-pas-raccourci.png)

Si `⌥&` fonctionne et que ton raccourci perso ne marche pas → c'est un conflit. Quelques zones à éviter quand tu choisis un raccourci :

- Raccourcis système macOS (⌘Espace, ⌥Espace, ⌘Tab, ⌘⇧3/4/5, ⌃↑/↓)
- Raccourcis globaux d'apps actives en arrière-plan (Spotlight, Alfred, Raycast, gestionnaires de fenêtres…)