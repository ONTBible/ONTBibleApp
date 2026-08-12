import Foundation

/// Le port de remontée d'erreurs.
///
/// Un protocole, pour que ni le domaine ni les features ne dépendent de
/// Sentry — seul le point d'assemblage le connaît. C'est la même règle que
/// pour le corpus et le stockage : les modules déclarent ce dont ils ont
/// besoin, pas comment c'est fait.
///
/// **Ce qu'on ne remonte jamais.** Les annotations d'un lecteur de Bible
/// révèlent des convictions religieuses — catégorie particulière au sens de
/// l'article 9 du RGPD. Le texte d'une note, le contenu d'un verset et la
/// liste des passages surlignés ne doivent jamais quitter l'appareil par ce
/// canal. Les implémentations expurgent ; les appelants n'ont pas à y penser,
/// mais ne doivent pas non plus glisser ces valeurs dans un message.
public protocol Reporter: Sendable {
    /// Remonte une erreur, avec le contexte de l'endroit où elle s'est produite.
    func report(_ error: any Error, context: String)

    /// Dépose une miette de contexte, rattachée au prochain événement.
    ///
    /// Bon marché — pas de pile d'appels, pas d'envoi immédiat. À préférer
    /// pour tracer un enchaînement.
    func breadcrumb(_ message: String)
}

/// Le rapporteur par défaut : il ne fait rien.
///
/// Sert aux tests, aux aperçus, et à toute construction où l'observabilité
/// n'a pas de sens. Un module qui n'a pas reçu de rapporteur ne doit jamais
/// planter pour autant.
public struct SilentReporter: Reporter {
    public init() {}
    public func report(_ error: any Error, context: String) {}
    public func breadcrumb(_ message: String) {}
}
