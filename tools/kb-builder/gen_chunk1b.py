#!/usr/bin/env python3
"""
Complément chunk 1 : ~130 entrées supplémentaires pour atteindre 500 nouvelles.
"""
from __future__ import annotations
import csv
from pathlib import Path

SEED_PATH = Path(__file__).resolve().parent / "seed" / "chabaka_seed.csv"

existing: set[str] = set()
with open(SEED_PATH, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        existing.add(row["word_display"].strip())

print(f"Mots existants dans le CSV : {len(existing)}")

NEW_ENTRIES: list[tuple[str, str, str, str]] = [

    # =========================================================================
    # VERBES SUPPLÉMENTAIRES — len 3
    # =========================================================================
    ("بدأ", "common", "ابتدأ وشرع في فعل", "synonym"),
    ("أبى", "common", "رفض وامتنع عن فعل", "definition"),
    ("ثنى", "common", "عطف وانعطف", "definition"),
    ("جنى", "common", "كسب أو قطر الثمر", "definition"),
    ("خبأ", "common", "أخفى وخزّن", "definition"),
    ("دعا", "common", "طلب ونادى", "synonym"),
    ("ذوى", "common", "ذبل ويبس النبات", "definition"),
    ("ربح", "common", "كسب أرباحاً من تجارة", "definition"),
    ("زها", "common", "تكبّر وافتخر", "definition"),
    ("سها", "common", "غفل ونسي", "definition"),
    ("شقى", "common", "تعب وكدح", "definition"),
    ("طغى", "common", "تجاوز الحدّ وبغى", "definition"),
    ("عفا", "common", "صفح وغفر", "synonym"),
    ("فدى", "common", "ضحّى بنفسه أو ماله", "definition"),
    ("قضى", "common", "حكم وانتهى من أمر", "definition"),
    ("كلى", "common", "عضو إخراج السوائل في الجسم", "definition"),
    ("لهى", "common", "انصرف عن الجدّ إلى اللهو", "definition"),
    ("مضى", "common", "ذهب ومرّ وانتهى", "definition"),
    ("نضى", "common", "خلع وانتزع", "definition"),
    ("وشى", "common", "نمّ وأخبر بالسرّ", "definition"),
    ("أذعن", "common", "خضع وسلّم بالأمر", "definition"),
    ("آمن", "common", "صدّق وأعطى الأمان", "definition"),
    ("ابتهج", "common", "فرح وسُرّ سروراً شديداً", "definition"),
    ("ابتكر", "common", "استحدث شيئاً لم يُسبق إليه", "definition"),
    ("اجتهد", "common", "بذل الجهد والعناية", "definition"),
    ("احتضن", "common", "ضمّ إلى الصدر", "definition"),
    ("ادّخر", "common", "وفّر وحفظ للمستقبل", "definition"),
    ("اشتاق", "common", "حنّ وتوق إلى شيء", "definition"),
    ("اطمأن", "common", "سكن وهدأ القلق", "definition"),
    ("انبثق", "common", "ظهر فجأة من مكان ما", "definition"),

    # =========================================================================
    # ADJECTIFS — len 3-6
    # =========================================================================
    ("ذكي", "common", "سريع الفهم حادّ الذكاء", "definition"),
    ("كريم", "common", "سخيّ ومحسن", "synonym"),
    ("شجاع", "common", "مقدام لا يخشى الخطر", "synonym"),
    ("لطيف", "common", "رقيق المشاعر ودود", "definition"),
    ("صبور", "common", "يتحمّل المشاق بهدوء", "definition"),
    ("حازم", "common", "قاطع في قراراته قوي الإرادة", "definition"),
    ("بارع", "common", "ماهر جداً في مجاله", "definition"),
    ("نشيط", "common", "مجدّ لا يكلّ من العمل", "definition"),
    ("ودود", "common", "محبّ ودافئ في تعامله", "definition"),
    ("أمين", "common", "حافظ للأمانة موثوق", "definition"),
    ("رزين", "common", "هادئ وقور متأنٍ", "definition"),
    ("فصيح", "common", "واضح الكلام جيد البيان", "definition"),
    ("ظريف", "common", "خفيف الروح ممتع الصحبة", "definition"),
    ("رشيد", "common", "سديد الرأي حسن التصرف", "definition"),
    ("حليم", "common", "يتحلّى بالحلم ولا يغضب بسرعة", "synonym"),
    ("وفيّ", "common", "يفي بعهوده وصداقاته", "definition"),
    ("مخلص", "common", "صادق في تفانيه لغيره", "definition"),
    ("أصيل", "common", "ذو أصالة وعراقة في نسبه", "definition"),
    ("فطن", "common", "يدرك الأمور بسرعة وذكاء", "definition"),
    ("حذق", "common", "ماهر متقن لعمله", "definition"),
    ("واثق", "common", "متأكد من نفسه وأفعاله", "definition"),
    ("عادل", "common", "يعطي كل ذي حق حقه", "definition"),
    ("متسامح", "common", "يقبل الآخر ولا يتشدد", "definition"),
    ("قادر", "common", "يملك القدرة على الفعل", "definition"),
    ("ماهر", "common", "متمكّن وبارع في صنعته", "definition"),

    # =========================================================================
    # MÉTIERS — len 4-7
    # =========================================================================
    ("بنّاء", "common", "من يبني البيوت والمنشآت", "definition"),
    ("خيّاط", "common", "من يحيك الثياب ويرقعها", "definition"),
    ("حدّاد", "common", "من يصنع الأدوات من الحديد", "definition"),
    ("نجّار", "common", "من يصنع الأثاث من الخشب", "definition"),
    ("خبّاز", "common", "من يصنع الخبز في المخبز", "definition"),
    ("جزّار", "common", "من يذبح ويبيع اللحوم", "definition"),
    ("صيدلاني", "common", "من يرتّب ويصرف الأدوية", "definition"),
    ("مهندس", "common", "من يصمم الإنشاءات والمشاريع", "synonym"),
    ("محامي", "common", "من يدافع عن الآخرين قانونياً", "synonym"),
    ("صحفي", "common", "من يكتب في الصحف والإعلام", "definition"),
    ("ممثل", "common", "من يؤدي أدواراً في المسرح والسينما", "definition"),
    ("موسيقار", "common", "من يؤلف ويعزف الموسيقى", "definition"),
    ("رسّام", "common", "من يبدع اللوحات التشكيلية", "definition"),
    ("نحّات", "common", "من ينحت التماثيل والأشكال", "definition"),
    ("مؤرخ", "common", "من يبحث في التاريخ ويكتبه", "definition"),
    ("فيلسوف", "common", "من يتأمل ويبحث في أسئلة الوجود", "definition"),
    ("فلكي", "common", "من يدرس الأجرام السماوية", "definition"),
    ("كيميائي", "common", "من يبحث في خصائص المواد", "definition"),
    ("طبيب", "common", "من يعالج الأمراض ويداوي", "synonym"),
    ("معلم", "common", "من يُعلّم ويرشد الطلاب", "synonym"),
    ("أستاذ", "common", "معلم جامعي متخصص", "definition"),
    ("كاتب", "common", "من يؤلف الكتب والمقالات", "definition"),
    ("مصوّر", "common", "من يلتقط الصور بالكاميرا", "definition"),
    ("ملحّن", "common", "من يضع ألحان الأغاني", "definition"),
    ("مذيع", "common", "من يقدّم برامج في الراديو والتلفزيون", "definition"),

    # =========================================================================
    # TERMES SCIENCES HUMAINES — len 5-9
    # =========================================================================
    ("الأنثروبولوجيا", "science", "علم دراسة الإنسان وحضاراته", "definition"),
    ("الأثريون", "science", "علماء يبحثون في المواقع الأثرية", "definition"),
    ("علم التاريخ", "science", "دراسة أحداث الماضي وتفسيرها", "definition"),
    ("الديموغرافيا", "science", "علم دراسة خصائص السكان", "definition"),
    ("الاقتصاد", "science", "علم إنتاج وتوزيع الثروة", "definition"),
    ("التسويق", "science", "دراسة تروج للسلع وتصل للمستهلك", "definition"),
    ("المحاسبة", "science", "تسجيل ومراقبة الحسابات المالية", "definition"),
    ("القانون", "science", "منظومة قواعد تنظّم السلوك في المجتمع", "synonym"),
    ("التشريع", "science", "إصدار القوانين من الجهة المختصة", "definition"),
    ("الحوكمة", "science", "إدارة المنظمات بشفافية ومساءلة", "definition"),
    ("التنمية", "science", "تحسين الأوضاع الاقتصادية والاجتماعية", "definition"),
    ("الإحصاء", "science", "جمع البيانات وتحليلها إحصائياً", "synonym"),
    ("الجيولوجيا", "science", "علم دراسة تركيب الأرض وطبقاتها", "definition"),
    ("علم البيئة", "science", "دراسة علاقة الكائنات ببيئتها", "definition"),
    ("الأوبئة", "science", "علم انتشار الأمراض في المجتمعات", "definition"),

    # =========================================================================
    # PERSONNALITÉS SUPPLÉMENTAIRES — savants arabes
    # =========================================================================
    ("ابن قتيبة", "person", "أديب وناقد عربي من القرن التاسع", "synonym"),
    ("المبرّد", "person", "نحوي بصري كبير كتب المقتضب", "definition"),
    ("الفرّاء", "person", "نحوي كوفي شيخ الكوفيين", "definition"),
    ("ابن جنّي", "person", "نحوي ولغوي كتب الخصائص", "definition"),
    ("الخليل بن أحمد", "person", "مؤسس علم العروض العربي", "definition"),
    ("سيبويه", "person", "إمام النحاة صاحب الكتاب الكبير", "synonym"),
    ("عمرو بن بحر الجاحظ", "person", "أديب معتزلي صاحب كتاب الحيوان", "definition"),
    ("ابن المقفع", "person", "كاتب عربي ترجم كليلة ودمنة", "definition"),
    ("اليعقوبي", "person", "مؤرخ وجغرافي عربي من القرن التاسع", "definition"),
    ("الطبري", "person", "مؤرخ مفسر صاحب تفسير شهير", "synonym"),
    ("المسعودي", "person", "مؤرخ وجغرافي صاحب مروج الذهب", "synonym"),
    ("ياقوت الحموي", "person", "جغرافي صاحب معجم البلدان", "synonym"),
    ("البيروني", "person", "عالم موسوعي فارسي كتب باللغة العربية", "synonym"),
    ("الإدريسي", "person", "جغرافي مغربي رسم أول خريطة دقيقة", "synonym"),
    ("ابن يونس", "person", "فلكي مصري صاحب الزيج الكبير الحاكمي", "synonym"),
    ("القلقشندي", "person", "مؤرخ ومنشئ مصري صاحب صبح الأعشى", "definition"),
    ("النويري", "person", "موسوعي مصري صاحب نهاية الأرب", "definition"),
    ("المقريزي", "person", "مؤرخ مصري كتب عن تاريخ مصر", "synonym"),
    ("ابن حجر العسقلاني", "person", "محدّث مصري صاحب فتح الباري", "definition"),
    ("جلال الدين الرومي", "person", "شاعر متصوف فارسي كتب المثنوي", "definition"),

    # =========================================================================
    # ARTS ET MUSIQUE
    # =========================================================================
    ("ربابة", "art", "آلة وترية شعبية تقليدية", "definition"),
    ("عود", "art", "آلة موسيقية وترية عربية أصيلة", "synonym"),
    ("ناي", "art", "آلة نفخ خشبية عربية شعرية", "synonym"),
    ("قانون", "art", "آلة موسيقية وترية يُعزف عليها بأنامل خاصة", "definition"),
    ("كمان", "art", "آلة وترية تُعزف بالقوس", "synonym"),
    ("طبلة", "art", "آلة إيقاعية جلدية شرقية", "definition"),
    ("بنجو", "art", "آلة وترية ذات صندوق دائري", "definition"),
    ("أكورديون", "art", "آلة موسيقية بمفاتيح وضاغط هواء", "definition"),
    ("الأوركسترا", "art", "فرقة موسيقية كلاسيكية كبيرة", "definition"),
    ("اللحن", "art", "تتابع النغمات المتناسقة في الموسيقى", "definition"),
    ("الإيقاع", "art", "تنظيم الزمن في الموسيقى", "definition"),
    ("الطقطوقة", "art", "أغنية مصرية شعبية قصيرة مرحة", "definition"),
    ("المقام", "art", "سلّم موسيقي في الموسيقى العربية", "synonym"),
    ("النغمة", "art", "وحدة صوتية في السلّم الموسيقي", "definition"),
    ("الكورال", "art", "غناء جماعي منسجم الأصوات", "definition"),

    # =========================================================================
    # TERMES GÉOGRAPHIQUES SUPPLÉMENTAIRES
    # =========================================================================
    ("المناخ", "science", "متوسط الأحوال الجوية على مدى سنوات", "definition"),
    ("الطقس", "common", "حالة الجو في يوم بعينه", "synonym"),
    ("الأعاصير", "science", "عواصف دوارة شديدة تنشأ في البحار", "definition"),
    ("الفيضانات", "common", "فيضان الأنهار وتسرب المياه للأراضي", "definition"),
    ("الجفاف", "common", "قلة الأمطار لفترة طويلة", "synonym"),
    ("التصحّر", "science", "تحوّل الأراضي الخصبة إلى صحراء", "definition"),
    ("التنوع البيولوجي", "science", "تعدد الأنواع الحية في منطقة ما", "definition"),
    ("النظام البيئي", "science", "مجموع الكائنات وبيئتها المترابطة", "definition"),
    ("السلسلة الغذائية", "science", "تسلسل كائنات تأكل بعضها", "definition"),
    ("الدورة الحيوية", "science", "مسار الحياة من الميلاد حتى الموت", "definition"),
    ("التوازن البيئي", "science", "حالة الاستقرار في النظام البيئي", "definition"),
    ("الغلاف الجوي", "science", "طبقة الهواء المحيطة بالأرض", "definition"),
    ("الغلاف المائي", "science", "مجموع المياه على سطح الأرض", "definition"),
    ("طبقة الأوزون", "science", "طبقة تحمي الأرض من أشعة الشمس", "definition"),
    ("الاحترار العالمي", "science", "ارتفاع درجة حرارة الأرض تدريجياً", "definition"),

    # =========================================================================
    # MOTS DIVERS len=3-4 pour combler les quotas
    # =========================================================================
    ("غصن", "common", "فرع الشجرة الصغير", "definition"),
    ("جذع", "common", "ساق الشجرة الرئيسية", "definition"),
    ("لحاء", "common", "قشرة الشجرة الخارجية", "definition"),
    ("طحن", "common", "تحويل الحبوب إلى دقيق", "definition"),
    ("سكب", "common", "صبّ سائل من وعاء", "definition"),
    ("نقع", "common", "غمر في الماء لفترة", "definition"),
    ("شوى", "common", "طبخ على نار مباشرة", "definition"),
    ("قلى", "common", "طبخ في الزيت الساخن", "definition"),
    ("عجن", "common", "خلط الدقيق بالماء للخبز", "definition"),
    ("فطر", "common", "مملكة حيّة بين النبات والحيوان", "definition"),
    ("طحالب", "common", "نباتات بحرية صغيرة خضراء", "definition"),
    ("حشائش", "common", "نباتات عشبية صغيرة تغطي الأرض", "definition"),
    ("أعشاب", "common", "نباتات طبيعية بريّة متنوعة", "synonym"),
    ("بذرة", "common", "أصل النبتة قبل إنباتها", "definition"),
    ("غراس", "common", "شتلات صغيرة تُزرع في الأرض", "definition"),
    ("فسيل", "common", "صغير النخلة الصالح للزراعة", "definition"),
    ("حقل", "common", "أرض مزروعة بالمحاصيل", "synonym"),
    ("حديقة", "common", "مساحة خضراء لزراعة الزهور", "synonym"),
    ("بستان", "common", "أرض مزروعة بأشجار الفاكهة", "synonym"),
    ("كرم", "common", "مزرعة عنب أو جود وسخاء", "definition"),
]

# Filtre doublons
final_entries = []
skipped = []
seen_new: set[str] = set()

for word, cat, clue, kind in NEW_ENTRIES:
    if word in existing:
        skipped.append(f"DOUBLON: {word}")
        continue
    if word in seen_new:
        skipped.append(f"DOUBLON INTERNE: {word}")
        continue
    seen_new.add(word)
    final_entries.append((word, cat, clue, kind))

print(f"Nouvelles entrées après filtre : {len(final_entries)}")
if skipped:
    print(f"Ignorées ({len(skipped)}) :")
    for s in skipped:
        print(f"  {s}")

# Append
with open(SEED_PATH, "a", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    for word, cat, clue, kind in final_entries:
        writer.writerow([word, cat, clue, kind, 2, "curated"])

print(f"\nAppend terminé. {len(final_entries)} nouvelles entrées ajoutées.")
total = 0
with open(SEED_PATH, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for _ in reader:
        total += 1
print(f"Total lignes CSV après append : {total}")
