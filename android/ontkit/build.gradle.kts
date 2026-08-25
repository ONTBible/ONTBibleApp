// Le domaine — et la seule ligne qui compte est celle qui manque.
//
// ## Pourquoi un module JVM et non une bibliothèque Android
//
// `ontkit` n'applique **pas** les greffons Android. Il n'a donc pas le SDK sur
// son chemin de classes : écrire `import android.content.Context` ici ne
// compile pas. Pas par convention — parce que la classe n'existe pas.
//
// C'est la seule chose que le Swift ne pouvait pas garantir. `ONTKit` n'importe
// que `Foundation`, mais rien n'empêchait quelqu'un d'y ajouter `import UIKit`
// un mardi après-midi ; on ne l'aurait vu qu'en revue, ou jamais. Ici la
// tentative s'arrête au compilateur.
//
// Ce que ça protège : le domaine décrit ce qu'est une lecture, un verset, une
// sélection. Le jour où il saurait ce qu'est un `Context`, il ne serait plus
// testable sans émulateur, et les 125 tests de la liseuse iOS n'auraient pas
// d'équivalent ici.
//
// ## Ce qu'il contient
//
// Les entités, les cas d'usage, et les **ports** — une interface par
// responsabilité, jamais un objet qui saurait tout faire. Un écran déclare
// exactement ce dont il a besoin, un test fournit une doublure de trois lignes.

plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    // 21 — l'LTS. La version doit être **la même** dans les cinq modules :
    // du bytecode compilé pour 21 ne s'inline pas dans du bytecode visant 17,
    // et Gradle le refuse au lieu de produire un artefact douteux.
    //
    // Une chaîne d'outils, pas une version de JVM : Gradle va chercher le JDK
    // 21 où qu'il soit sur le poste, quelle que soit la JVM qui l'exécute.
    // Android Studio tourne sur sa propre JBR, et ça ne change rien ici.
    jvmToolchain(21)
    // Le domaine n'expose que ce qu'il a décidé d'exposer : `explicitApi`
    // impose de dire `public` et de typer les retours. Sur une frontière que
    // quatre modules traversent, l'oubli d'un modificateur est une fuite.
    explicitApi()
}

dependencies {
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
