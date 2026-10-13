# Page Facebook « الإعراب » — ligne éditoriale

Validée par le PO le 13 octobre 2026. La routine de publication automatique applique ce document
à la lettre ; toute modification passe par ce fichier.

## 1. Objectif

Réveiller une page de 14 000 abonnés en sommeil depuis un an, en lui rendant sa vocation
(la grammaire arabe) et en y greffant le jeu : des grilles de mots fléchés à résoudre en
commentaires. Chabaka est présenté comme le prolongement naturel de la page, jamais comme une
publicité envahissante.

## 2. Public et langue

- Arabophones du Maghreb et de la diaspora, lycéens, étudiants, enseignants, amateurs de langue.
- **Tout en arabe standard (الفصحى)**, vocalisation (تشكيل) seulement là où elle lève une ambiguïté.
- Pas de dialecte, pas de français dans les posts (le pied de page des images porte seulement
  l'adresse techlyb.com/chabaka).
- Ton : chaleureux, pédagogue, jamais condescendant. On vouvoie le groupe (« أعزاءنا »، « تفضلوا »).
- Émojis : au plus deux par post, jamais dans les explications grammaticales.
- Hashtags fixes en fin de post : `#الإعراب #كلمات_مسهمة #شبكة`. Pas d'autres.

## 3. Formats

| Code | Format | Contenu | Image |
|---|---|---|---|
| G | **شبكة اليوم** | Grille 10×7, mots courants (difficulté ≤ 2), numérotée (شبكة اليوم ١، ٢…). Texte court : invitation à répondre en commentaire, règle « كلمة واحدة تكفي للمشاركة ». Rappel discret en dernière ligne : « من تطبيق شبكة ». | grille.png |
| GF | **تحدي الجمعة** | Même chose, grille 13×9 toutes difficultés, le vendredi. | grille.png |
| S | **الحل** | Commentaire sous le post G/GF, pas un post. Image solution + félicitations nominatives aux trois premiers commentaires corrects (prénom tel qu'affiché par Facebook). | solution.png |
| I1 | **جملة للإعراب** | Une phrase courte à analyser, choisie pour illustrer une règle. Réponse détaillée le lendemain en commentaire (format : كل كلمة ثم إعرابها). | aucune |
| I2 | **قاعدة** | Une règle expliquée en 6 à 10 lignes avec deux exemples et une erreur fréquente. Sujets tournants : المبتدأ والخبر، كان وأخواتها، إن وأخواتها، الفاعل، المفعول به، الحال، التمييز، الممنوع من الصرف، الأفعال الخمسة، إعراب الأسماء الخمسة، البدل، النعت، الاستثناء، العدد والمعدود، همزة الوصل والقطع… | aucune |
| C | **كلمة ومعنى** | Un mot rare ou un proverbe de la base Chabaka, sa signification, une phrase d'usage. | aucune |
| P | **Promotion** | Annonce, nouvelle version, arrivée sur Android, témoignage. Badge App Store. | capture ou visuel |

Longueur : 40 à 120 mots pour G/GF/C, 80 à 180 pour I1/I2, 120 à 200 pour P.

## 4. Rythme et horaires

Heure du Maroc (Africa/Casablanca). Un post par jour, pas plus.

| Jour | 09:00 | 20:00 |
|---|---|---|
| Samedi | G | commentaire S |
| Dimanche | I1 | — |
| Lundi | G | commentaire S + réponse de I1 en commentaire sous le post de dimanche |
| Mardi | I2 | — |
| Mercredi | G | commentaire S |
| Jeudi | C | — |
| Vendredi | GF | commentaire S (le samedi 09:00, juste avant la nouvelle grille) |

Promotion (P) : un post toutes les deux semaines, le jeudi à la place de C, et jamais deux P
d'affilée. Exceptions planifiées : annonce de lancement, sortie Android.

## 5. Lancement

1. **Avant la disponibilité en France** (statut de commerçant Apple en cours) : posts I1, I2, C et
   une première grille G, sans lien de téléchargement, mention « من تطبيق شبكة » seulement.
2. **Dès que l'app est visible en France** : post P d'annonce (texte validé le 13 octobre) à 09:00,
   puis le calendrier normal reprend le lendemain.
3. **Sortie Android** : post P avec les deux badges.

## 6. Grilles : règles de production

- Générées par le moteur de l'app (`test/tools/export_grid_test.dart`), rendues par
  `tools/facebook/render_grid.js`. Graine = numéro du jour, jamais la grille du jour de l'app
  (celle-là reste réservée aux utilisateurs).
- Rejeter et régénérer si : un indice dépasse 28 caractères, un mot apparaît déjà dans les
  30 dernières grilles publiées, ou un mot figure dans la liste d'exclusion
  (`docs/facebook/exclusions.txt`, à alimenter par le PO).
- Vérification humaine : aucune au quotidien. Le PO reçoit chaque dimanche un bilan de la semaine
  (posts, portée, commentaires, solutions) et peut à tout moment ajouter une exclusion.

## 7. Interaction avec les membres

- **Aucune réponse automatique aux commentaires pendant le premier mois.** La routine lit les
  commentaires uniquement pour désigner les premiers à avoir trouvé.
- Après ce mois, et sur décision du PO, réponses limitées à : remercier, confirmer ou corriger une
  réponse d'إعراب, orienter vers l'app. Jamais de débat.
- Commentaires insultants, politiques ou religieux polémiques : non traités, signalés au PO dans le
  bilan. Jamais de suppression automatique.
- Jamais de message privé, jamais de collecte d'adresses.

## 8. Lignes rouges

- Pas de politique, pas de polémique religieuse. Les exemples coraniques ou poétiques classiques
  sont bienvenus comme matière grammaticale, sans commentaire religieux.
- Pas de contenu généré sans vérification pour I1/I2 : chaque analyse grammaticale est relue par la
  routine contre une règle citée (référence : النحو الواضح، جامع الدروس العربية).
- Pas de visuel tiers, pas de citation de source non vérifiée, pas de données personnelles.
- Promotion plafonnée (section 4). Le texte des grilles ne dit jamais « téléchargez », il dit
  « من تطبيق شبكة ».

## 9. Traçabilité et arrêt

- Chaque publication et chaque commentaire sont consignés dans `docs/facebook/journal.md`
  (date, type, texte, id Facebook, lien) et poussés dans le dépôt.
- Arrêt immédiat : désactiver la routine dans claude.ai (Routines) ou révoquer l'app « Chabaka
  Publisher » dans Facebook → Paramètres → Intégrations professionnelles. Les deux suffisent.

## 10. Modèles de texte

**G — شبكة اليوم**
```
شبكة اليوم {n} 🧩
كلمات مسهمة من إعداد تطبيق شبكة. اقرؤوا التعريفات، واكتبوا الكلمات التي وجدتموها في التعليقات، كلمة واحدة تكفي للمشاركة.
الحل مساء اليوم، مع أسماء أول من يحلّها.
#الإعراب #كلمات_مسهمة #شبكة
```

**S — commentaire solution**
```
حل شبكة اليوم {n} ✅
أول من وجد الحل : {أسماء}. أحسنتم!
الشبكة القادمة يوم {jour}. وللمزيد من الشبكات في أي وقت : تطبيق شبكة.
```

**I1 — جملة للإعراب**
```
جملة للإعراب ✍️
« {phrase} »
أعربوا الجملة كاملة في التعليقات. الإعراب التفصيلي غداً في التعليقات.
#الإعراب #كلمات_مسهمة #شبكة
```

**I2 — قاعدة**
```
قاعدة اليوم : {titre}
{explication en 6 à 10 lignes}
مثال : {ex1}
مثال : {ex2}
خطأ شائع : {erreur} ← الصواب : {correction}
#الإعراب #كلمات_مسهمة #شبكة
```

**C — كلمة ومعنى**
```
كلمة ومعنى 📖
{mot} : {sens}.
في جملة : {phrase}.
من قاعدة كلمات تطبيق شبكة.
#الإعراب #كلمات_مسهمة #شبكة
```
