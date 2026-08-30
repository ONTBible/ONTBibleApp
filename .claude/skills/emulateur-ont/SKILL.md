---
name: emulateur-ont
description: Lancer l'app Android sur l'émulateur, la piloter et la capturer — et les quatre pièges qui font conclure juste sur une mesure qui n'a pas eu lieu. À employer dès qu'on veut voir l'app Android tourner.
---

# Voir l'app Android tourner

Une modification non relancée ne sert à rien, et c'est une règle de ce projet.

Gloire a **un Galaxy S20+**, branché quand il l'est. Ce texte disait le
contraire — il a été écrit avant, et l'affirmation a survécu à l'appareil. Quand
le téléphone est là, c'est lui qui tranche : l'émulateur ne dit rien de la
lenteur réelle ni des gestes du système. `adb devices -l` montre qui répond.

## L'environnement, qui n'est jamais exporté tout seul

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
adb=$ANDROID_HOME/platform-tools/adb
```

**`jenv` peut pointer vers un JDK que la machine n'a plus.** Le 30 août 2026,
`./gradlew` répondait `jenv: version 'temurin64-25.0.2' is not installed` — le
Temurin de la machine était passé à 26, et le réglage global de `jenv` désignait
toujours l'ancien. Rien dans le dépôt n'épingle de version : le défaut est dans
l'outil, pas dans le projet.

`/usr/libexec/java_home -V` liste ce qui est réellement installé ; exporter
`JAVA_HOME` explicitement contourne `jenv` entièrement.

**`JAVA_HOME` non exporté fait échouer `avdmanager`** d'une façon qui ressemble
à une absence de définitions d'appareils. J'ai affirmé à Gloire que la ligne de
commande n'en avait pas — c'était faux, il manquait la variable.

L'AVD est **`ONT-Pixel9`**. Le paquet Homebrew n'a pas les habillages : la voie
fiable pour en créer un est le Device Manager d'Android Studio, qui télécharge
et rattache le bon habillage tout seul.

## La boucle complète

```sh
cd android
./gradlew :app:assembleDebug --console=plain 2>&1 | grep -E "^e: |FAILED|BUILD "
$adb install -r app/build/outputs/apk/debug/app-debug.apk
$adb logcat -c                                    # ← avant, toujours
$adb shell am start -W -n com.labibleont.ont/.MainActivity
$adb shell sleep 6                                # le corpus se décode en fond
$adb exec-out screencap -p > capture.png
$adb logcat -d | grep -cE "FATAL EXCEPTION"
```

Le paquet est **`com.labibleont.ont`**, sans suffixe `.debug` — `am start` sur
`com.labibleont.ONT.debug` répond « Activity class does not exist ».

`am start -W` attend l'affichage. Sans lui, la capture prend l'écran d'avant :
le processus tourne déjà, l'app n'est pas encore dessinée.

## Les quatre pièges

Ils ont un air de famille : **chacun rend un résultat vraisemblable sur une
mesure qui n'a pas eu lieu.** C'est ce qui les rend coûteux — on ne doute pas
d'un chiffre plausible.

### 1. Le journal non vidé

`logcat -d | head -30` sur un journal qui traîne depuis une heure rend trente
lignes anciennes. J'y ai lu « zéro plantage » et je l'ai annoncé à Gloire
pendant que le système affichait « l'app ne cesse de s'arrêter ».

**Vider avant de lancer, compter sur le journal entier.** `grep -c` sur tout,
jamais `head` sur un extrait.

### 2. `KEYCODE_BACK` depuis l'écran racine sort de l'app

Le lanceur reprend la main, et il peut ouvrir un dialogue système par-dessus.
J'ai capturé un écran de stylet Google en croyant capturer la liseuse.

**Vérifier ce qui est au premier plan avant de conclure sur une capture :**

```sh
$adb shell dumpsys activity activities | grep -m1 topResumedActivity
```

### 3. L'habillage qui ne correspond pas à l'appareil

`device-art-resources` d'Android Studio sert à **encadrer des captures**, pas à
habiller l'émulateur. Le détourner donne un cadre gris et **une encoche en
double** — celle du masque plus celle du système. L'AVD et l'habillage doivent
décrire le même appareil, sinon il vaut mieux aucun habillage.

### 4. Un `sleep` de l'hôte est bloqué

Employer `$adb shell sleep N` — il tourne sur l'appareil. Sans attente, la
capture précède le rendu et on décrit un écran qui n'existait pas encore.

## Piloter

Les coordonnées sont celles de l'appareil (1280 × 2856 sur `ONT-Pixel9`). Une
capture rendue à 896 × 2000 se multiplie par **1,43**.

```sh
$adb shell input tap X Y
$adb shell input swipe 640 2000 640 700 300      # descendre
$adb shell input swipe 640 700 640 2000 300      # remonter
```

Les onglets, en bas : Qahal 152, Bible 476, Lexique 800, Vous 1128, à Y = 2660.

**Une réinstallation remet la navigation au départ.** `install -r` conserve les
données mais l'app repart de l'onglet d'accueil : une chaîne de gestes calée sur
l'écran d'avant frappe alors dans le vide. Refaire le chemin depuis l'accueil
après chaque `install`.

**Capturer après chaque geste plutôt qu'en chaîner cinq à l'aveugle.** Une
chaîne de gestes dont le troisième rate laisse les deux derniers frapper un
écran imprévu — et le résultat ressemble à un défaut de l'app.

## Lire l'état réel plutôt que l'écran

L'écran montre ce qui est composé ; le fichier montre ce qui est enregistré. Les
deux se contredisent quand une écriture manque, et c'est précisément le défaut
qu'on cherche.

```sh
$adb shell run-as com.labibleont.ont cat /data/data/com.labibleont.ont/files/lecteur.json
```

Attention à la forme : les réglages sont sous la clé `preferences`, pas à la
racine. J'ai conclu « le champ ne s'écrit pas » en lisant au mauvais niveau —
c'était mon contrôle qui était faux, pas le code.

## Ce qui n'est pas dans le dépôt

`Schema.kt` est **engendré** depuis `pipeline/src/schema.rs`
(`cargo run --bin engendrer`) et ignoré par git. Le corpus embarqué est copié
par une tâche Gradle `Sync` depuis `app/Resources/data` — la même source
qu'iOS. Corriger l'un ou l'autre à la main est du travail perdu au prochain
build.
