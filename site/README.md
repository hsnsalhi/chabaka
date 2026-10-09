# Site public Chabaka

Deux pages statiques exigées par l'App Store :

- `index.html` : page de support (URL de support dans App Store Connect).
- `privacy.html` : politique de confidentialité AR / FR / EN (URL de confidentialité).

Hébergement : dépôt public `hsnsalhi/chabaka-site` avec GitHub Pages (Settings → Pages → Deploy from a branch → `main`, dossier `/`). Les deux fichiers y sont copiés à la racine. URLs :

- https://hsnsalhi.github.io/chabaka-site/
- https://hsnsalhi.github.io/chabaka-site/privacy.html

Pour republier après une modification ici :

```bash
cp site/index.html site/privacy.html ../chabaka-site/ && cd ../chabaka-site && git add . && git commit -m "Mise à jour site" && git push
```
