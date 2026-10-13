# Page Facebook « الإعراب » — outils de publication

Pipeline automatique (option 2) : une routine quotidienne génère le contenu du jour
et le publie sur la page via l'API Graph, avec le jeton de page stocké en secret
d'environnement (`FB_PAGE_TOKEN`, `FB_PAGE_ID`). Jamais de jeton dans le dépôt.

## Grille → image

1. Export d'une grille depuis le générateur de l'app (même moteur que « لعبة سريعة ») :

   ```
   flutter test test/tools/export_grid_test.dart --tags tool \
     --dart-define=ROWS=10 --dart-define=COLS=7 --dart-define=MAX_DIFF=2 \
     --dart-define=SEED=4242 --dart-define=OUT=build/fb/grid.json
   ```

   `SEED` absent = graine tirée de l'heure. `MAX_DIFF=2` = mots courants (niveau débutant
   de l'app), recommandé pour la page. Le JSON contient la solution. `COUNT=N` avec `OUT=dossier`
   génère une série ; ajouter `--timeout 30m` à `flutter test` au-delà de quelques grilles.

2. Rendu en deux PNG 1080×1080 (grille vide + solution) :

   ```
   NODE_PATH=$(npm root -g) node tools/facebook/render_grid.js build/fb/grid.json build/fb/out "شبكة اليوم ١"
   ```

## Journal

Chaque publication est consignée dans `docs/facebook/journal.md` (date, type, id du post,
lien) par la routine, pour relecture.
