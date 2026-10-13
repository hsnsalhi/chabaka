# Chabaka sur Google Play — guide de publication

## 1. Compte développeur Google Play

- https://play.google.com/console → créer un compte développeur (25 USD, paiement unique).
- Compte **personnel** ou **organisation** (TechLYB). Pour une organisation, Google demande un numéro
  D-U-N-S et une vérification d'identité ; pour un compte personnel, une pièce d'identité et un numéro de
  téléphone. Compter 1 à 3 jours de vérification.
- **Règle importante pour un compte personnel créé après novembre 2023** : avant toute publication en
  production, l'app doit passer par un **test fermé avec au moins 12 testeurs inscrits pendant 14 jours
  consécutifs**, puis une demande d'accès à la production. Les comptes organisation n'y sont pas soumis.
  Prévoir donc 2 à 3 semaines entre le premier AAB et la mise en ligne publique.

## 2. Clé d'upload (faite)

Keystore `chabaka-upload.jks` généré le 13 octobre 2026 (RSA 2048, alias `upload`, valide jusqu'en 2054).
Conservé hors du dépôt. Quatre secrets GitHub à créer : `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (valeurs dans le fichier
`chabaka_android_secrets.txt` remis au PO). Play App Signing gardera la clé de signature finale chez
Google ; cette clé ne sert qu'à l'upload.

## 3. Produire l'App Bundle

GitHub → Actions → « Android → Play Store » → Run workflow → `build_number` = versionCode (1, puis 2…).
Le run dépose `app-release.aab` (à envoyer dans Play Console) et `app-release.apk` (installable
directement sur un téléphone Android pour tester, sources inconnues autorisées).

## 4. Créer l'app dans Play Console

- « Créer une application » : nom `شبكة — كلمات مسهمة`, langue par défaut arabe, type Application,
  gratuite. Accepter les règles.
- **Tableau de bord → Configurer votre application** (tout est obligatoire avant la mise en ligne) :
  - Politique de confidentialité : https://hsnsalhi.github.io/chabaka/privacy.html
  - Accès à l'application : « Toutes les fonctionnalités sont accessibles sans conditions particulières ».
  - Annonces : Non.
  - Classification du contenu : questionnaire IARC, catégorie Jeu, tout à Non → PEGI 3 / Everyone.
  - Audience cible : 13 ans et plus (choisir aussi « enfants » impose des règles famille : éviter).
  - Application d'actualités : Non. Application de suivi des contacts COVID : Non.
  - Sécurité des données : « Aucune donnée collectée ni partagée », données non chiffrées en transit
    sans objet (pas de réseau), pas de suppression de compte (pas de compte).
  - Applications gouvernementales : Non. Fonctionnalités financières : Non. Santé : Non.
  - Catégorie : Jeux → Mots. Coordonnées : contact@techlyb.com.
  - Fiche Google Play : textes et visuels dans `fiche.md`.
- **Tests → Tests internes** : créer une release, importer l'AAB, ajouter une liste de testeurs par
  e-mail (jusqu'à 100), publier. Lien d'opt-in à partager. Disponible en quelques minutes, sans revue.
- **Tests → Tests fermés** (obligatoire pour un compte personnel récent) : même AAB, 12 testeurs
  minimum, 14 jours.
- **Production** : créer la release, choisir les pays, envoyer en revue. Première revue Google :
  quelques heures à 7 jours.

## 5. Visuels requis par la fiche Play

| Élément | Taille | Source |
|---|---|---|
| Icône | 512 × 512 PNG, sans transparence | `docs/play-store/icon_512.png` |
| Image de présentation (feature graphic) | 1024 × 500 PNG/JPG | `docs/play-store/feature_1024x500.png` |
| Captures téléphone | 2 à 8, ratio 16:9 à 9:16, 320 à 3840 px | les captures iPhone 1206×2622 conviennent (`docs/app-store/screenshots/iphone_6.3_1206x2622/`) |
| Captures tablette 7" et 10" | facultatives | — |

## 6. Différences avec iOS à vérifier sur un Android réel

- Clavier arabe Gboard : saisie d'une lettre par case, retour arrière, suggestion désactivée dans les cases.
- Bouton Retour système : doit revenir à l'écran précédent sans quitter brutalement une partie.
- Police Cairo embarquée : rendu identique (pas de police système arabe Android, qui varie selon le constructeur).
- Thème sombre et barre système.
