# Chabaka 1.1 — préparation de la version

## Fait
- [x] `pubspec.yaml` : version 1.1.0 (le numéro de build est donné par le workflow CI à chaque envoi).
- [x] Textes de version dans l'app (accueil, réglages) : 1.1.
- [x] Toutes les adresses passent sur techlyb.com (fiches App Store et Play, TestFlight, site).
- [x] Déjà dans la branche depuis le build 6 : base de 15 287 mots, indices courts en arabe standard, grilles
      10×7 / 13×9 / 16×11 / 17×12, niveau débutant limité aux mots courants, indices réduits plutôt que tronqués,
      sous-titre de fin de partie selon le mode, base SQLite rafraîchie à chaque mise à jour.

## À faire avant le build (demandes du PO à venir)
- [x] Palettes de couleurs : 5 palettes (classique, zmurrudi/lagune, layli/nuit bleue, zaafarani/safran, nili/indigo)
      sélectionnables dans Réglages → « الألوان », combinées aux 3 modes clair / sépia / sombre. Persisté (Hive).
- [ ] Autres modifications à préciser.
- [ ] Mettre à jour le texte « Nouveautés » 1.1 dans `docs/app-store/fiche.md` selon ce qui est retenu.

## Publication iOS (après validation du PO)
1. Workflow « iOS → TestFlight » avec `build_number` = 7 (puis 8…). Tester sur l'iPhone.
2. App Store Connect → Distribution → bouton « + » à côté de « iOS App » → nouvelle version **1.1.0**.
3. Dans la version : « Nouveautés », captures (reprendre les mêmes ou les refaire si les couleurs changent),
   **Support URL = https://techlyb.com/chabaka/**, build 1.1.0 (7), notes de revue inchangées.
4. App Information → **Privacy Policy URL = https://techlyb.com/chabaka/privacy.html** (s'il n'est pas sur la page
   version, il est sur la page App Privacy). Marketing URL = https://techlyb.com/.
5. « Add for Review » → « Submit ». Revue en général sous 24 h pour une mise à jour.

## Après publication de 1.1
- [ ] Vérifier sur la fiche App Store que les liens pointent vers techlyb.com.
- [ ] GitHub → Settings → Pages → retirer le domaine personnalisé, puis Settings → General → passer le dépôt en privé.
- [ ] Réduire la rétention des artefacts Actions (workflows) si besoin.

## Android
- Même code ; `flutter build appbundle` par le workflow « Android → Play Store ». versionName = 1.1.0.
- Dépend de l'approbation du compte Play Console organisation (identité TechLYB).
