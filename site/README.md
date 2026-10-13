# Site public TechLYB / Chabaka

Hébergé sur GitHub Pages depuis ce dépôt, déployé par `.github/workflows/pages.yml` à chaque push sur `main`
touchant `site/`.

- `index.html` : page société TechLYB (exigée par Google Play pour un compte organisation).
- `chabaka/index.html` : page de support de l'app (URL de support App Store).
- `privacy.html` et `chabaka/privacy.html` : politique de confidentialité AR / FR / EN (deux copies identiques,
  l'URL App Store historique `…/chabaka/privacy.html` doit rester valide).

URLs actuelles : https://hsnsalhi.github.io/chabaka/ (racine = page TechLYB), …/chabaka/chabaka/ (support),
…/chabaka/privacy.html (confidentialité).

Domaine personnalisé prévu : `techlyb.com` (fichier `CNAME` à ajouter dans `site/` une fois les DNS Namecheap
pointés vers GitHub Pages ; GitHub redirige alors automatiquement les anciennes URL github.io).
