# Site public Chabaka

Deux pages statiques exigées par l'App Store :

- `index.html` : page de support (URL de support dans App Store Connect).
- `privacy.html` : politique de confidentialité AR / FR / EN (URL de confidentialité).

Hébergement : GitHub Pages sur ce dépôt (public), déployé par `.github/workflows/pages.yml` à chaque push sur `main` touchant `site/`. Activation unique dans Settings → Pages → Source : **GitHub Actions**. URLs :

- https://hsnsalhi.github.io/chabaka/
- https://hsnsalhi.github.io/chabaka/privacy.html

Pour republier : modifier les fichiers de `site/` et pousser sur `main`.
