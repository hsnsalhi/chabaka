# Fiche App Store — Chabaka (شبكة)

Textes prêts à coller dans App Store Connect. Les limites de caractères sont celles d'Apple. La langue principale de la fiche est l'**arabe** ; le français est fourni en localisation secondaire.

## Identité

| Champ | Valeur |
|---|---|
| Bundle ID | `com.mainlyb.chabaka` |
| SKU | `chabaka-ios` |
| Catégorie principale | Jeux → Mots |
| Catégorie secondaire | Jeux → Puzzle |
| Classification d'âge | 4+ (aucun contenu à signaler dans le questionnaire) |
| Prix | Gratuit |
| Confidentialité | « Data Not Collected » (aucune donnée collectée) |
| Chiffrement | Non exempt : non (déjà déclaré dans Info.plist) |

## Arabe (langue principale)

**Nom** (30 car. max)
```
شبكة — كلمات مسهمة
```

**Sous-titre** (30 car. max)
```
شبكة مسهمة جديدة كل يوم
```

**Texte promotionnel** (170 car. max, modifiable sans nouvelle version)
```
كلمات مسهمة عربية أصيلة على طريقة أبو سلمى: شبكة اليوم، لعبة سريعة بأربعة مستويات، وبدون إنترنت.
```

**Description** (4000 car. max)
```
شبكة هي لعبة الكلمات المسهمة العربية التي تعيد إليك متعة شبكات الجرائد، مستوحاة من مسهمات أبو سلمى.

كل يوم شبكة جديدة
تنتظرك شبكة مسهمة جديدة كل يوم، تُولَّد على جهازك من قاعدة معرفة تضم آلاف الكلمات والتعريفات: مفردات عامة، أعلام، جغرافيا، علوم، فنون، أمثال، وأكثر.

على طريقة الجرائد الحقيقية
لا مربعات سوداء: خانات التعريف بأسهمها هي التي تحدّد اتجاه الكلمات، تماماً كما في المسهمات المطبوعة. كل حرف في خانة، وكل خانة لها معنى.

لعبة سريعة على مقاسك
أربعة مستويات من مبتدئ إلى أستاذ، مع اختيار المواضيع التي تحبها. مؤقت، تلميحات محدودة، ومضاعف نقاط للتحدي.

تقدّمك بين يديك
نقاط، سلسلة أيام متتالية، إنجازات، إحصائيات، وتقويم لشبكات الأيام الماضية. كل شيء يُحفظ على جهازك.

بدون إنترنت، بدون حساب، بدون إعلانات
شبكة تعمل بالكامل دون اتصال. لا تسجيل، لا تتبّع، لا إزعاج.

مظهر يليق بالعربية
خطوط عربية واضحة، واجهة من اليمين إلى اليسار، وثلاثة مظاهر: فاتح، داكن، وسيبيا.
```

**Mots-clés** (100 car. max, séparés par des virgules, sans espaces)
```
كلمات,مسهمة,متقاطعة,شبكة,ألغاز,عربي,ثقافة,أبو سلمى,لعبة,ذكاء
```

**Nouveautés de cette version**
```
الإصدار الأول من شبكة: شبكة اليوم، لعبة سريعة، إنجازات وإحصائيات.
```

## Français (localisation secondaire)

**Nom**
```
Chabaka — Mots fléchés arabes
```

**Sous-titre**
```
Une grille arabe chaque jour
```

**Texte promotionnel**
```
Des mots fléchés arabes authentiques, façon Abou Salma : grille du jour, partie rapide à quatre niveaux, et tout hors ligne.
```

**Description**
```
Chabaka fait revivre le plaisir des mots fléchés arabes des journaux, dans l'esprit des grilles d'Abou Salma.

Une grille chaque jour
Chaque jour, une nouvelle grille générée sur votre appareil à partir d'une base de milliers de mots et de définitions : vocabulaire courant, personnalités, géographie, sciences, arts, proverbes et plus encore.

Comme dans les vrais journaux
Pas de case noire : ce sont les cases-définition et leurs flèches qui donnent le sens des mots, exactement comme dans les grilles imprimées.

Une partie rapide à votre mesure
Quatre niveaux, du débutant au maître, avec le choix des thèmes. Chronomètre, indices limités et multiplicateur de score pour le défi.

Votre progression, chez vous
Scores, série de jours consécutifs, succès, statistiques et calendrier des grilles passées. Tout reste sur votre appareil.

Sans internet, sans compte, sans publicité
Chabaka fonctionne entièrement hors ligne. Aucune inscription, aucun traceur.

Une interface pensée pour l'arabe
Polices arabes lisibles, lecture de droite à gauche, trois thèmes : clair, sombre et sépia.
```

**Mots-clés**
```
mots fléchés,arabe,mots croisés,grille,puzzle,culture,abou salma,jeu,lettres
```

## Captures d'écran à fournir

Portrait uniquement. Apple accepte une seule taille par famille et l'adapte aux autres.

| Appareil | Taille (px) | Obligatoire |
|---|---|---|
| iPhone 6,9" / 6,7" | 1320 × 2868 ou 1290 × 2796 | Oui |
| iPhone 6,5" | 1284 × 2778 ou 1242 × 2688 | Oui si pas de 6,9" fournie |
| iPad 13" | 2064 × 2752 ou 2048 × 2732 | Oui tant que l'iPad reste activé (`TARGETED_DEVICE_FAMILY = "1,2"`) |

Suggestion de série (3 à 5 captures) : grille du jour en cours, barre d'indice avec un mot actif, résultat avec score, écran partie rapide, statistiques. Prises depuis le simulateur avec `flutter run` puis ⌘S, ou depuis l'iPhone.

Si vous ne voulez pas gérer l'iPad, passer `TARGETED_DEVICE_FAMILY` à `"1"` dans `ios/Runner.xcodeproj/project.pbxproj` avant le build.

## URLs

| Champ | Valeur |
|---|---|
| Politique de confidentialité | URL publique de `site/privacy.html` (voir `site/README.md`) |
| Support | Même page, ou une adresse e-mail `mailto:` n'est pas acceptée : prévoir une page ou l'URL du dépôt public |
| Marketing (optionnel) | — |

## Notes pour la revue Apple (App Review Information)

```
Chabaka is a fully offline Arabic arrow-crossword game. No account or login is needed: open the app, tap "شبكة اليوم" (Today's grid) on the home screen and type Arabic letters with the system keyboard. An Arabic keyboard must be enabled in iOS Settings to enter letters. The app collects no data and makes no network requests.
```

## Checklist avant soumission

- [ ] Compte Apple Developer Program actif
- [ ] App créée dans App Store Connect avec le bundle ID ci-dessus
- [ ] `CONTACT_EMAIL` remplacé dans `site/privacy.html` et page hébergée
- [ ] Build uploadé via `flutter build ipa` puis Transporter, testé en TestFlight
- [ ] Captures d'écran importées
- [ ] Questionnaire confidentialité : « Data Not Collected »
- [ ] Questionnaire classification d'âge rempli (tout à « Non »)
