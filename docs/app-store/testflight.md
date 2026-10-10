# TestFlight — Informations de test

Textes à coller dans App Store Connect → Chabaka → onglet TestFlight.
Deux endroits : « Informations de test » (une fois, pour l'app) et « Que tester » (par build).

## 1. Informations de test (section de l'app)

**Description bêta de l'app** (max 4 000 caractères)

> شبكة — لعبة كلمات مسهمة عربية تعمل بالكامل دون اتصال بالإنترنت.
> شبكة جديدة كل يوم، ولعبة سريعة بأربعة مستويات (مبتدئ، متوسط، خبير، أستاذ) مع اختيار الفئات.
> قاعدة تضم أكثر من 15 000 كلمة : مفردات عامة، أعلام، بلدان وعواصم، تاريخ، علوم، فنون ورياضة.
> تلميحات، تحقق فوري، مؤقت، نقاط، إنجازات وإحصائيات.
>
> Chabaka est une application de mots fléchés en arabe, entièrement hors ligne. Grille quotidienne, partie rapide à quatre niveaux, plus de 15 000 mots. Cette version bêta sert à valider la jouabilité, la lisibilité des grilles et la qualité des indices avant publication.

**E-mail de commentaires** : contact@techlyb.com

**URL marketing** : https://hsnsalhi.github.io/chabaka/

**URL de la politique de confidentialité** : https://hsnsalhi.github.io/chabaka/privacy.html

## 2. Informations de révision bêta (demandées à la première soumission externe)

- Prénom / Nom : vos nom et prénom
- Téléphone : votre numéro, format international
- E-mail : contact@techlyb.com
- Compte de démonstration : **Non requis** (aucune connexion, aucun compte)
- Notes pour la révision :

> The app is a fully offline Arabic arrow-crossword game. No account, no login, no network access, no data collection. The interface is in Arabic (right-to-left). To test: open the app, tap the red card « شبكة اليوم » for today's grid, or « لعبة سريعة » to pick a level and start a quick game. Tap a cell and type Arabic letters; the lightbulb reveals a letter, the check mark validates the grid. Long-press a clue cell to read its full text. Export compliance: the app uses no encryption beyond what iOS provides.

## 3. Que tester (texte par build, max 4 000 caractères)

**Build 6** — version arabe

> مرحباً بكم في النسخة التجريبية من شبكة.
>
> ما الجديد في هذا الإصدار :
> • قاعدة كلمات موسعة : أكثر من 15 000 كلمة تشمل البلدان والعواصم والأعلام والمعالم والتاريخ.
> • تعريفات أقصر وأوضح : ثلاث كلمات على الأكثر، بالعربية الفصحى.
> • شبكات أطول من عرضها بنسبة ثابتة : 10×7، 13×9، 16×11، 17×12 حسب المستوى.
> • مستوى المبتدئ يقتصر على الكلمات المألوفة.
> • الأسهم تخرج من الجهة التي تبدأ منها الكلمة.
>
> نرجو التركيز على :
> 1. وضوح التعريفات داخل الخانات التي تضم ثلاثة منها (الشبكة 13×9 فأكثر). هل الخط صغير جداً ؟
> 2. صعوبة الكلمات في مستوى المبتدئ : هل بقيت كلمات غامضة ؟
> 3. التعريفات الغامضة أو الخاطئة : اذكروا الكلمة والتعريف.
> 4. أي كلمة عامية أو مغربية في التعريفات (المطلوب فصحى فقط).
> 5. سرعة إنشاء الشبكة عند الضغط على « بدء اللعبة » في المستويين خبير وأستاذ.
>
> للإبلاغ : لقطة شاشة من داخل TestFlight (هز الهاتف أو زر المشاركة) أو رسالة إلى contact@techlyb.com.

**Build 6** — version française (si vous ajoutez une localisation française)

> Bienvenue dans la bêta de Chabaka.
>
> Nouveautés de ce build :
> • Base de mots élargie : plus de 15 000 mots, dont pays, capitales, personnalités, monuments et histoire.
> • Indices plus courts et plus clairs : trois mots maximum, en arabe standard.
> • Grilles toujours plus hautes que larges : 10×7, 13×9, 16×11, 17×12 selon le niveau.
> • Le niveau débutant se limite aux mots courants.
> • Les flèches partent du côté où commence le mot.
>
> Points à tester en priorité :
> 1. Lisibilité des indices dans les cases à trois définitions (grilles 13×9 et plus). Trop petit ?
> 2. Difficulté des mots en niveau débutant : reste-t-il des mots obscurs ?
> 3. Indices ambigus ou faux : notez le mot et l'indice.
> 4. Tout mot dialectal ou marocain dans un indice (arabe standard attendu).
> 5. Temps de génération au clic sur « بدء اللعبة » en niveaux expert et maître.
>
> Pour signaler : capture d'écran depuis TestFlight (secouer le téléphone ou bouton Partager), ou e-mail à contact@techlyb.com.

## 4. Lien public TestFlight

Groupe externe, build 6 approuvé le 10 octobre 2026 :
**https://testflight.apple.com/join/S163wBh1**

Message type à envoyer avec le lien :

> سلام، هذه النسخة التجريبية من لعبة « شبكة » (كلمات مسهمة عربية).
> 1. ثبّت تطبيق TestFlight من App Store.
> 2. افتح هذا الرابط من الآيفون : https://testflight.apple.com/join/S163wBh1
> 3. اضغط « قبول » ثم « تثبيت ».
> ملاحظاتك تهمّني : لقطة شاشة من TestFlight أو رسالة على contact@techlyb.com. شكراً !

## 5. Rappels

- Le premier build envoyé à un groupe externe passe une revue Apple allégée (24 à 48 h).
- Question « chiffrement » à la soumission : répondre **Non** (ou cocher « exempt »). Pour éviter la question à chaque build, la clé `ITSAppUsesNonExemptEncryption = NO` est déjà présente dans `ios/Runner/Info.plist`, donc la question ne devrait pas être posée.
- Un build expire 90 jours après son envoi.
