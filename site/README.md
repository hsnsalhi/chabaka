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

## Migration vers Firebase Hosting (octobre 2026)

Le même dossier `site/` est publié sur Firebase Hosting par `.github/workflows/firebase-hosting.yml`
(configuration dans `firebase.json` et `.firebaserc`). Une fois le domaine techlyb.com rattaché au projet
Firebase (console → Hosting → Ajouter un domaine personnalisé, puis enregistrements A fournis par Firebase
chez Namecheap à la place des quatre adresses GitHub), GitHub Pages peut être désactivé et le dépôt passé
en privé. Le fichier `CNAME` est ignoré par Firebase.
