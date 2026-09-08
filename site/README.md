# Site public Chabaka

`privacy.html` est la politique de confidentialité exigée par l'App Store (URL publique obligatoire, même sans collecte de données).

Avant publication : remplacer `CONTACT_EMAIL` (3 occurrences) par l'adresse de contact.

## Hébergement

Ce dépôt est privé ; GitHub Pages n'est disponible pour un dépôt privé qu'avec un compte payant. Deux options gratuites :

1. **Dépôt public dédié** `hsnsalhi/chabaka-site` avec GitHub Pages activé (Settings → Pages → branche `main`, dossier `/`). Y copier `privacy.html` en `index.html` ou garder le nom. URL obtenue : `https://hsnsalhi.github.io/chabaka-site/privacy.html`.
2. **Page utilisateur** `hsnsalhi/hsnsalhi.github.io` : même principe, URL `https://hsnsalhi.github.io/chabaka/privacy.html` si le fichier est placé dans un dossier `chabaka/`.

Commandes pour l'option 1, une fois le dépôt public créé sur GitHub :

```bash
git clone https://github.com/hsnsalhi/chabaka-site.git
cp ~/Repos/chabaka/site/privacy.html chabaka-site/
cd chabaka-site && git add . && git commit -m "Politique de confidentialité Chabaka" && git push
```

L'URL finale se renseigne dans App Store Connect → App Information → Privacy Policy URL.
