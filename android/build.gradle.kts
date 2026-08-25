// La racine du build — elle ne construit rien.
//
// `apply false` déclare les greffons et fixe leur version pour tout le monde,
// sans les appliquer ici. Chaque module choisit ensuite ceux qui le concernent.
// C'est ce qui permet à `ontkit` de n'avoir aucun greffon Android : s'ils
// étaient appliqués à la racine, il en hériterait, et sa pureté ne serait plus
// vérifiable.
//
// `org.jetbrains.kotlin.android` ne paraît nulle part : depuis AGP 9.0, le
// support Kotlin est intégré aux greffons Android, et le déclarer en plus fait
// échouer la configuration avec un message net. `kotlin.jvm` reste, pour le
// seul module qui n'est pas Android.

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
