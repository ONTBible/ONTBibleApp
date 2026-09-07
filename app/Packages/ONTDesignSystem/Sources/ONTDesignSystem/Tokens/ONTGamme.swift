import SwiftUI

/// Les gammes de la palette — chaque teinte déclinée de 50 à 950.
///
/// ## D'où viennent les valeurs
///
/// **Des ancres relevées, pas d'un nuancier importé.** Le bordeaux `#421B26`
/// du logo, l'or `#CDBE83`, la nuit `#18090D` du site sont des crans de leurs
/// gammes — `aubergine800`, `or300`, `aubergine950`, au bit près. Le reste est
/// interpolé en OKLCH autour d'eux : même clarté perçue à chaque cran d'une
/// gamme à l'autre, chroma en cloche, teinte suivie entre les ancres. Le
/// générateur est consigné dans SYNCHRONISATION.md (3 septembre 2026).
///
/// ## Comment on s'en sert
///
/// Comme chez Tailwind : `ONTGamme.or300`, `ONTGamme.braise600`. **Mais un
/// écran ne pioche pas ici directement** — il passe par les rôles du thème
/// (`theme.danger`, `theme.accent`…), qui choisissent le cran selon le mode.
/// La gamme est le clavier ; le rôle est la partition.
///
/// Contrastes vérifiés à la génération : les rôles clairs tiennent 4,5:1 sur
/// parchemin, les rôles sombres dépassent 10:1 sur la nuit.
public enum ONTGamme {

    // MARK: - Aubergine

    /// La gamme de la marque — la nuit du site en 950, sa surface en 900,
    /// le bordeaux du logo en **800**, exacts au relevé.
    public static let aubergine50 = Color(red: 0.9998, green: 0.9491, blue: 0.9589)
    public static let aubergine100 = Color(red: 0.9721, green: 0.9053, blue: 0.9183)
    public static let aubergine200 = Color(red: 0.9165, green: 0.8242, blue: 0.8426)
    public static let aubergine300 = Color(red: 0.8386, green: 0.7215, blue: 0.7455)
    public static let aubergine400 = Color(red: 0.743, green: 0.6027, blue: 0.6324)
    public static let aubergine500 = Color(red: 0.6488, green: 0.4871, blue: 0.5228)
    public static let aubergine600 = Color(red: 0.5619, green: 0.3805, blue: 0.4228)
    public static let aubergine700 = Color(red: 0.4815, green: 0.2822, blue: 0.3321)
    public static let aubergine800 = Color(red: 0.2588, green: 0.1059, blue: 0.149)
    public static let aubergine900 = Color(red: 0.149, green: 0.0627, blue: 0.0863)
    public static let aubergine950 = Color(red: 0.0941, green: 0.0353, blue: 0.051)

    // MARK: - Or

    /// L'or du logo en **300**, l'or assombri en **500** — exacts au relevé.
    public static let or50 = Color(red: 1.0, green: 0.966, blue: 0.8287)
    public static let or100 = Color(red: 0.9684, green: 0.9269, blue: 0.7615)
    public static let or200 = Color(red: 0.9032, green: 0.8531, blue: 0.655)
    public static let or300 = Color(red: 0.8039, green: 0.7451, blue: 0.5137)
    public static let or400 = Color(red: 0.7369, green: 0.6343, blue: 0.3741)
    public static let or500 = Color(red: 0.65, green: 0.53, blue: 0.31)
    public static let or600 = Color(red: 0.5217, green: 0.4235, blue: 0.2434)
    public static let or700 = Color(red: 0.4162, green: 0.3378, blue: 0.1947)
    public static let or800 = Color(red: 0.3157, green: 0.2557, blue: 0.1466)
    public static let or900 = Color(red: 0.2157, green: 0.1726, blue: 0.0945)
    public static let or950 = Color(red: 0.142, green: 0.1075, blue: 0.0439)

    // MARK: - Parchemin

    /// Le neutre chaud — le fond parchemin en **50**, son encre en **900**.
    public static let parchemin50 = Color(red: 0.98, green: 0.96, blue: 0.92)
    public static let parchemin100 = Color(red: 0.9452, green: 0.9219, blue: 0.8791)
    public static let parchemin200 = Color(red: 0.8775, green: 0.847, blue: 0.7988)
    public static let parchemin300 = Color(red: 0.7886, green: 0.7504, blue: 0.6978)
    public static let parchemin400 = Color(red: 0.6746, green: 0.6393, blue: 0.5966)
    public static let parchemin500 = Color(red: 0.6041, green: 0.5219, blue: 0.4327)
    public static let parchemin600 = Color(red: 0.4959, green: 0.4252, blue: 0.3574)
    public static let parchemin700 = Color(red: 0.3963, green: 0.3383, blue: 0.289)
    public static let parchemin800 = Color(red: 0.3003, green: 0.2555, blue: 0.2219)
    public static let parchemin900 = Color(red: 0.16, green: 0.13, blue: 0.11)
    public static let parchemin950 = Color(red: 0.1315, green: 0.1079, blue: 0.0923)

    // MARK: - Braise

    /// Le rouge de la maison — terre cuite qui penche bordeaux, jamais un
    /// rouge d'alerte industriel. Rôle : danger, suppression, échec.
    public static let braise50 = Color(red: 0.9997, green: 0.9512, blue: 0.9444)
    public static let braise100 = Color(red: 0.9985, green: 0.8986, blue: 0.8849)
    public static let braise200 = Color(red: 0.9981, green: 0.7954, blue: 0.7687)
    public static let braise300 = Color(red: 0.9944, green: 0.6531, blue: 0.6126)
    public static let braise400 = Color(red: 0.9106, green: 0.5188, blue: 0.477)
    public static let braise500 = Color(red: 0.8246, green: 0.382, blue: 0.3435)
    public static let braise600 = Color(red: 0.7103, green: 0.279, blue: 0.2482)
    public static let braise700 = Color(red: 0.5742, green: 0.2171, blue: 0.192)
    public static let braise800 = Color(red: 0.4445, green: 0.1571, blue: 0.1375)
    public static let braise900 = Color(red: 0.3162, green: 0.0939, blue: 0.0803)
    public static let braise950 = Color(red: 0.2246, green: 0.0332, blue: 0.028)

    // MARK: - Cedre

    /// Le vert de la maison — sauge boisée, sourde. Rôle : succès, validé.
    public static let cedre50 = Color(red: 0.91, green: 0.9892, blue: 0.9173)
    public static let cedre100 = Color(red: 0.8629, green: 0.9536, blue: 0.8715)
    public static let cedre200 = Color(red: 0.7729, green: 0.8872, blue: 0.7844)
    public static let cedre300 = Color(red: 0.6611, green: 0.7988, blue: 0.6759)
    public static let cedre400 = Color(red: 0.5326, green: 0.6935, blue: 0.5517)
    public static let cedre500 = Color(red: 0.4061, green: 0.5908, blue: 0.4309)
    public static let cedre600 = Color(red: 0.309, green: 0.49, blue: 0.3354)
    public static let cedre700 = Color(red: 0.2424, green: 0.3922, blue: 0.2643)
    public static let cedre800 = Color(red: 0.178, green: 0.2987, blue: 0.1959)
    public static let cedre900 = Color(red: 0.1116, green: 0.2051, blue: 0.1259)
    public static let cedre950 = Color(red: 0.054, green: 0.1342, blue: 0.0678)

    // MARK: - Ambre

    /// L'ambre — entre l'or et la braise. Rôle : avertissement, en attente.
    public static let ambre50 = Color(red: 0.9999, green: 0.9571, blue: 0.9007)
    public static let ambre100 = Color(red: 0.9992, green: 0.9103, blue: 0.792)
    public static let ambre200 = Color(red: 0.9749, green: 0.8245, blue: 0.6197)
    public static let ambre300 = Color(red: 0.8995, green: 0.7228, blue: 0.4761)
    public static let ambre400 = Color(red: 0.8056, green: 0.6038, blue: 0.3056)
    public static let ambre500 = Color(red: 0.7042, green: 0.4901, blue: 0.1296)
    public static let ambre600 = Color(red: 0.5784, green: 0.3998, blue: 0.0989)
    public static let ambre700 = Color(red: 0.4638, green: 0.3182, blue: 0.0746)
    public static let ambre800 = Color(red: 0.3546, green: 0.2398, blue: 0.0483)
    public static let ambre900 = Color(red: 0.2462, green: 0.1602, blue: 0.0178)
    public static let ambre950 = Color(red: 0.1665, green: 0.0969, blue: 0.0)

    /// Toutes les valeurs, par nom — pour les épreuves de contraste et le
    /// nuancier du catalogue. Une gamme qui n'est pas ici n'est pas éprouvée.
    public static let nuancier: [String: Color] = [
        "aubergine50": aubergine50,
        "aubergine100": aubergine100,
        "aubergine200": aubergine200,
        "aubergine300": aubergine300,
        "aubergine400": aubergine400,
        "aubergine500": aubergine500,
        "aubergine600": aubergine600,
        "aubergine700": aubergine700,
        "aubergine800": aubergine800,
        "aubergine900": aubergine900,
        "aubergine950": aubergine950,
        "or50": or50,
        "or100": or100,
        "or200": or200,
        "or300": or300,
        "or400": or400,
        "or500": or500,
        "or600": or600,
        "or700": or700,
        "or800": or800,
        "or900": or900,
        "or950": or950,
        "parchemin50": parchemin50,
        "parchemin100": parchemin100,
        "parchemin200": parchemin200,
        "parchemin300": parchemin300,
        "parchemin400": parchemin400,
        "parchemin500": parchemin500,
        "parchemin600": parchemin600,
        "parchemin700": parchemin700,
        "parchemin800": parchemin800,
        "parchemin900": parchemin900,
        "parchemin950": parchemin950,
        "braise50": braise50,
        "braise100": braise100,
        "braise200": braise200,
        "braise300": braise300,
        "braise400": braise400,
        "braise500": braise500,
        "braise600": braise600,
        "braise700": braise700,
        "braise800": braise800,
        "braise900": braise900,
        "braise950": braise950,
        "cedre50": cedre50,
        "cedre100": cedre100,
        "cedre200": cedre200,
        "cedre300": cedre300,
        "cedre400": cedre400,
        "cedre500": cedre500,
        "cedre600": cedre600,
        "cedre700": cedre700,
        "cedre800": cedre800,
        "cedre900": cedre900,
        "cedre950": cedre950,
        "ambre50": ambre50,
        "ambre100": ambre100,
        "ambre200": ambre200,
        "ambre300": ambre300,
        "ambre400": ambre400,
        "ambre500": ambre500,
        "ambre600": ambre600,
        "ambre700": ambre700,
        "ambre800": ambre800,
        "ambre900": ambre900,
        "ambre950": ambre950,
    ]
}
