# Touchscreen Driver pour Corsair Xeneon Edge

Driver macOS pour transformer les touches sur l'écran tactile en clics à la position absolue.

## Comment ça fonctionne

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Écran tactile  │────▶│  Notre Driver    │────▶│  macOS          │
│  (USB HID)      │     │  (capture excl.) │     │  (clic injecté) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
     Données brutes         Conversion            Clic à la bonne
     X, Y, TouchDown        coordonnées           position absolue
```

### Mode de capture EXCLUSIF (par défaut)

Le driver "capture" le périphérique tactile :
- macOS ne reçoit plus les événements originaux
- Seuls nos clics convertis sont envoyés
- **Pas de double clic**

### Mode PARTAGÉ (fallback)

Si le mode exclusif échoue :
- Le driver lit les événements en parallèle du système
- Risque de double clic (système + notre injection)
- À utiliser uniquement pour le debug

## Gestion multi-écrans

Le driver détecte automatiquement la position de l'écran Xeneon Edge dans l'espace global macOS :

```
┌───────────────────────────────────────────────────────┐
│              Espace coordonnées macOS                 │
│                                                       │
│  ┌─────────────┐     ┌─────────────────┐             │
│  │ Principal   │     │ Xeneon Edge     │             │
│  │ (0, 0)      │     │ (1920, 0)       │             │
│  │ 1920x1080   │     │ 2560x1440       │             │
│  └─────────────┘     └─────────────────┘             │
│                                                       │
│  Touch à 50% X, 50% Y sur Xeneon                     │
│  = Position globale (1920 + 1280, 720)               │
│  = (3200, 720)                                       │
└───────────────────────────────────────────────────────┘
```

**Si tu réorganises tes écrans**, le driver se met à jour automatiquement !

## Prérequis

- macOS 10.15+ (Catalina ou plus récent)
- Xcode Command Line Tools : `xcode-select --install`
- Écran Corsair Xeneon Edge branché en USB-C

## Configuration de ton écran

```
TouchScreen:
  VendorID:  0x27c0
  ProductID: 0x0859
  Fabricant: wch.cn
```

## Étape 1 : Analyser les rapports HID

Avant de pouvoir créer le driver, on doit comprendre le format des données tactiles.

### Compiler l'analyseur

```bash
cd TouchscreenDriver
swiftc HIDAnalyzer.swift -o HIDAnalyzer -framework IOKit -framework CoreFoundation
```

### Exécuter l'analyseur

```bash
./HIDAnalyzer
```

### Ce que tu verras

Quand tu touches l'écran, tu devrais voir quelque chose comme :

```
============================================================
🖐️  TOUCH #1 DÉTECTÉ!
============================================================
  Digitizer / Tip Switch (toucher): 1 [min:0, max:1]
  Generic Desktop / X: 2048 [min:0, max:4095]
  Generic Desktop / Y: 1536 [min:0, max:4095]
  Digitizer / Contact ID: 0
👆 RELÂCHÉ à X=2048, Y=1536
------------------------------------------------------------
```

**Note les valeurs `max` pour X et Y** — on en aura besoin pour la calibration.

## Étape 2 : Driver complet (à venir)

Une fois qu'on connaît le format des données, je créerai le driver complet qui :
1. Capture les touches
2. Convertit en coordonnées écran
3. Injecte des clics macOS à la bonne position

## Permissions requises

### Accès aux périphériques d'entrée

Si l'outil ne détecte pas l'écran, tu devras peut-être autoriser l'accès :

1. **Préférences Système** → **Confidentialité et sécurité** → **Confidentialité**
2. Section **Surveillance de l'entrée** (Input Monitoring)
3. Ajouter Terminal ou ton app

### Accès Accessibilité (pour le driver final)

Pour injecter des clics, il faudra aussi :

1. **Préférences Système** → **Confidentialité et sécurité** → **Confidentialité**
2. Section **Accessibilité**
3. Ajouter l'app du driver

## Troubleshooting

### "Écran tactile non trouvé"

- Vérifie que l'écran est bien branché
- Vérifie les VendorID/ProductID dans **Informations Système** → **USB**
- Modifie les constantes dans le code si nécessaire

### "Impossible d'ouvrir IOHIDManager"

- Ajoute Terminal dans les permissions "Surveillance de l'entrée"
- Redémarre Terminal après avoir ajouté les permissions

### Aucun événement affiché

- Certains écrans nécessitent d'être l'écran principal
- Essaie de toucher différentes zones de l'écran
- Vérifie que le tactile est activé dans les paramètres de l'écran

### Le mode exclusif échoue

Si tu vois l'erreur "Impossible d'ouvrir IOHIDManager" en mode exclusif :

1. Vérifie qu'aucun autre programme n'utilise le tactile (iCUE, etc.)
2. Tu peux passer en mode partagé temporairement :

```swift
// Dans TouchscreenDriver.swift, ligne ~50
var captureMode: CaptureMode = .shared  // au lieu de .exclusive
```

⚠️ En mode partagé, tu auras peut-être des doubles clics.

### Clics décalés / mauvaise position

1. Lance d'abord `HIDAnalyzer` et note les valeurs max de X et Y
2. Modifie `TouchscreenDriver.swift` :

```swift
var touchscreenMaxX: CGFloat = 4095  // ← Ta valeur
var touchscreenMaxY: CGFloat = 4095  // ← Ta valeur
```

3. Si l'écran n'est pas détecté par son nom, force l'index :

```swift
// Dans setupScreen(), remplace la détection automatique par :
targetScreen = NSScreen.screens[1]  // ou l'index de ton Xeneon
```
