/// Normalisation arabe — miroir exact de `lib/puzzle/arabic_normalizer.dart`.
///
/// Règles (toutes activées par défaut) :
///   • ا أ إ آ ٱ → ا
///   • ة → ه
///   • ى → ي
///   • Diacritiques (تشكيل) → supprimés
///   • ZWNJ / ZWJ / NBSP / BOM / espaces → supprimés
///
/// Tests parité : 1 000 mots passés dans les deux normalizers doivent donner
/// le même résultat char-à-char (CI gate, spec R9).

// ---------------------------------------------------------------------------
// Tables Unicode (codepoints en hex pour lisibilité arabe)
// ---------------------------------------------------------------------------

/// Diacritiques arabes (تشكيل) à supprimer.
/// Miroir de `_diacritics` dans arabic_normalizer.dart.
const DIACRITICS: &[char] = &[
    '\u{064B}', // fathatan   ً
    '\u{064C}', // dammatan   ٌ
    '\u{064D}', // kasratan   ٍ
    '\u{064E}', // fatha      َ
    '\u{064F}', // damma      ُ
    '\u{0650}', // kasra      ِ
    '\u{0651}', // shadda     ّ
    '\u{0652}', // sukun      ْ
    '\u{0653}', // maddah above ٓ
    '\u{0654}', // hamza above  ٔ
    '\u{0655}', // hamza below  ٕ
    '\u{0656}', // subscript alef ٖ
    '\u{0657}', // inverted damma ٗ
    '\u{0658}', // mark noon ghunna ٘
    '\u{0670}', // superscript alef ٰ
];

/// Caractères zéro-largeur et espaces à supprimer.
/// Miroir de `_zeroWidthChars` dans arabic_normalizer.dart.
const ZERO_WIDTH: &[char] = &[
    '\u{200C}', // ZWNJ  ‌
    '\u{200D}', // ZWJ   ‍
    '\u{00A0}', // NBSP
    '\u{FEFF}', // BOM
];

/// Variantes de alef à normaliser vers ا (\u{0627}).
const ALEF_VARIANTS: &[char] = &[
    '\u{0623}', // أ (alef with hamza above)
    '\u{0625}', // إ (alef with hamza below)
    '\u{0622}', // آ (alef with madda above)
    '\u{0671}', // ٱ (alef wasla)
];

const ALEF_CANONICAL: char = '\u{0627}'; // ا
const TA_MARBUTA: char = '\u{0629}';     // ة
const HA: char = '\u{0647}';             // ه
const ALEF_MAQSURA: char = '\u{0649}';  // ى
const YA: char = '\u{064A}';             // ي

// ---------------------------------------------------------------------------
// Options de normalisation
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
pub struct NormalizerOptions {
    /// ا أ إ آ ٱ → ا  (défaut : true)
    pub normalize_alef: bool,
    /// ة → ه          (défaut : true)
    pub normalize_ta_marbuta: bool,
    /// ى → ي          (défaut : true)
    pub normalize_yaa: bool,
}

impl Default for NormalizerOptions {
    fn default() -> Self {
        NormalizerOptions {
            normalize_alef: true,
            normalize_ta_marbuta: true,
            normalize_yaa: true,
        }
    }
}

// ---------------------------------------------------------------------------
// Fonction principale
// ---------------------------------------------------------------------------

/// Normalise un mot arabe selon les règles Chabaka.
///
/// # Arguments
/// * `input`   – texte arabe brut (peut contenir diacritiques, variantes alef, etc.)
/// * `options` – options de normalisation (défaut : tout activé)
///
/// # Returns
/// Vecteur de chars normalisés (un char = un graphème arabe de base).
/// Identique à la sortie de `ArabicNormalizer.normalize()` côté Dart.
pub fn normalize(input: &str, options: NormalizerOptions) -> String {
    let mut result = String::with_capacity(input.len());

    for ch in input.chars() {
        // 1. Supprimer diacritiques
        if DIACRITICS.contains(&ch) {
            continue;
        }

        // 2. Supprimer caractères zéro-largeur et espaces
        if ZERO_WIDTH.contains(&ch) || ch.is_whitespace() {
            continue;
        }

        // 3. Normaliser alef
        let mut c = ch;
        if options.normalize_alef && ALEF_VARIANTS.contains(&c) {
            c = ALEF_CANONICAL;
        }

        // 4. Normaliser ta marbuta
        if options.normalize_ta_marbuta && c == TA_MARBUTA {
            c = HA;
        }

        // 5. Normaliser ya (alef maqsura)
        if options.normalize_yaa && c == ALEF_MAQSURA {
            c = YA;
        }

        result.push(c);
    }

    result
}

/// Normalise avec les options par défaut (raccourci).
pub fn normalize_default(input: &str) -> String {
    normalize(input, NormalizerOptions::default())
}

/// Normalise en retournant un Vec<char> (pour O(1) access par position dans le solver).
pub fn normalize_to_chars(input: &str, options: NormalizerOptions) -> Vec<char> {
    normalize(input, options).chars().collect()
}

// ---------------------------------------------------------------------------
// Validation de lettre (miroir de matchesLetter)
// ---------------------------------------------------------------------------

/// Vérifie qu'un char utilisateur correspond à la lettre solution après normalisation.
pub fn matches_letter(user_input: char, solution: char, options: NormalizerOptions) -> bool {
    let user_str = user_input.to_string();
    let sol_str = solution.to_string();
    let norm_user = normalize(&user_str, options);
    let norm_sol = normalize(&sol_str, options);
    !norm_user.is_empty() && !norm_sol.is_empty() && norm_user == norm_sol
}

// ---------------------------------------------------------------------------
// Tests unitaires
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn opts() -> NormalizerOptions {
        NormalizerOptions::default()
    }

    #[test]
    fn test_alef_variants_normalized() {
        // أ إ آ ٱ → ا
        assert_eq!(normalize("أهلا", opts()), "اهلا");
        assert_eq!(normalize("إسلام", opts()), "اسلام");
        assert_eq!(normalize("آداب", opts()), "اداب");
        assert_eq!(normalize("ٱلله", opts()), "الله");
    }

    #[test]
    fn test_ta_marbuta_normalized() {
        // ة → ه
        assert_eq!(normalize("مدرسة", opts()), "مدرسه");
        assert_eq!(normalize("فاطمة", opts()), "فاطمه");
    }

    #[test]
    fn test_yaa_normalized() {
        // ى → ي
        assert_eq!(normalize("موسى", opts()), "موسي");
        assert_eq!(normalize("عيسى", opts()), "عيسي");
    }

    #[test]
    fn test_diacritics_removed() {
        // diacritiques supprimés
        assert_eq!(normalize("كَتَبَ", opts()), "كتب");
        assert_eq!(normalize("مُحَمَّدٌ", opts()), "محمد");
    }

    #[test]
    fn test_zero_width_removed() {
        let with_zwnj = "ع\u{200C}ر\u{200D}ب";
        assert_eq!(normalize(with_zwnj, opts()), "عرب");
    }

    #[test]
    fn test_plain_arabic_unchanged() {
        // Un mot déjà normalisé reste identique
        let word = "كتاب";
        assert_eq!(normalize(word, opts()), word);
    }

    #[test]
    fn test_mixed_complex() {
        // Combinaison de variantes alef + diacritiques + ta marbuta
        let input = "أُمَّةٌ";  // أمّة avec diacritiques
        // أ → ا, ّ et ً supprimés, ة → ه → "امه"
        assert_eq!(normalize(input, opts()), "امه");
    }

    #[test]
    fn test_matches_letter() {
        // أ doit matcher ا
        assert!(matches_letter('أ', 'ا', opts()));
        // ة doit matcher ه
        assert!(matches_letter('ة', 'ه', opts()));
        // ى doit matcher ي
        assert!(matches_letter('ى', 'ي', opts()));
        // ع ne doit pas matcher ب
        assert!(!matches_letter('ع', 'ب', opts()));
    }

    #[test]
    fn test_empty_string() {
        assert_eq!(normalize("", opts()), "");
    }

    #[test]
    fn test_option_alef_disabled() {
        let opts_no_alef = NormalizerOptions {
            normalize_alef: false,
            ..NormalizerOptions::default()
        };
        // أ reste أ si option désactivée
        assert_eq!(normalize("أهل", opts_no_alef), "أهل");
    }

    #[test]
    fn test_option_ta_marbuta_disabled() {
        let opts_no_ta = NormalizerOptions {
            normalize_ta_marbuta: false,
            ..NormalizerOptions::default()
        };
        // Avec ta_marbuta désactivé, ة reste ة (non convertie en ه)
        // alef et yaa sont toujours normalisés (options default)
        let result = normalize("مدرسة", opts_no_ta);
        // "مدرسة" : م د ر س ة  → ة doit rester ة
        assert_eq!(result, "مدرسة", "ta marbuta should stay as ة when option disabled");
        // Vérifier qu'alef est toujours normalisé même avec ta_marbuta désactivé
        let result2 = normalize("أمة", opts_no_ta);
        assert_eq!(result2, "امة", "alef should still be normalized, ta marbuta preserved");
    }

    #[test]
    fn test_normalize_to_chars_length() {
        // "كتاب" = 4 chars arabes
        let chars = normalize_to_chars("كتاب", opts());
        assert_eq!(chars.len(), 4);
        assert_eq!(chars[0], 'ك');
        assert_eq!(chars[3], 'ب');
    }
}
