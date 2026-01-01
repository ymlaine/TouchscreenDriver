# Projet Driver Tactile - Corsair Xeneon Edge

## Contexte

Discussion avec Claude pour créer un driver macOS permettant d'utiliser l'écran tactile Corsair Xeneon Edge avec des clics à la **position absolue** (là où on touche) plutôt qu'à la position du curseur.

---

## Matériel

### Écran
| Propriété | Valeur |
|-----------|--------|
| Modèle | Corsair Xeneon Edge |
| Type | Barre tactile 14.5" |
| Résolution native | 2560 × 720 |
| Ratio | 32:9 (super ultrawide) |
| Position actuelle | Origin (-2560, 720) |
| Écran principal | Studio Display 5K |

### Contrôleur tactile USB
| Propriété | Valeur |
|-----------|--------|
| VendorID | `0x27c0` |
| ProductID | `0x0859` |
| Fabricant | wch.cn |
| Vitesse | USB 2.0 (12 Mb/s) |

### Autres périphériques USB de l'écran
- Hub USB 2.0 : VendorID `0x1a40`, ProductID `0x0801`
- Interface Corsair iCUE : VendorID `0x1b1c`, ProductID `0x1d0d`

---

## Architecture du driver

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Écran tactile  │────▶│  Notre Driver    │────▶│  macOS          │
│  (USB HID)      │     │  (capture excl.) │     │  (clic injecté) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
     Données brutes         Conversion            Clic à la bonne
     X, Y, TouchDown        coordonnées           position absolue
```

### Fonctionnement
1. **Capture exclusive** du périphérique HID (`kIOHIDOptionsTypeSeizeDevice`)
   - macOS ne reçoit plus les événements bruts
   - Évite les doubles clics
   
2. **Lecture des rapports HID**
   - Usage Page `0x0D` (Digitizer) : état du toucher
   - Usage Page `0x01` (Generic Desktop) : coordonnées X/Y
   
3. **Conversion des coordonnées**
   ```
   screenX = screenOffsetX + (rawX / maxRawX) * screenWidth
   screenY = screenOffsetY + (rawY / maxRawY) * screenHeight
   ```
   
4. **Injection CGEvent**
   - `CGWarpMouseCursorPosition()` pour déplacer le curseur
   - `CGEvent` mouseDown/mouseUp pour le clic

5. **Détection dynamique des écrans**
   - Observer sur `NSApplication.didChangeScreenParametersNotification`
   - Se reconfigure si on réorganise les écrans

---

## Fichiers du projet

### HIDAnalyzer.swift
Outil de diagnostic pour capturer et afficher les rapports HID bruts.

**Usage :**
```bash
swiftc HIDAnalyzer.swift -o HIDAnalyzer -framework IOKit -framework CoreFoundation
./HIDAnalyzer
```

**Objectif :** Déterminer les valeurs min/max des coordonnées X et Y envoyées par le contrôleur tactile.

### TouchscreenDriver.swift
Driver complet avec capture exclusive et injection de clics.

**Usage :**
```bash
swiftc TouchscreenDriver.swift -o TouchscreenDriver \
    -framework IOKit -framework CoreFoundation \
    -framework CoreGraphics -framework AppKit
./TouchscreenDriver
```

**Paramètres à ajuster (lignes ~15-18) :**
```swift
var touchscreenMaxX: CGFloat = 4095  // À déterminer via HIDAnalyzer
var touchscreenMaxY: CGFloat = 4095  // À déterminer via HIDAnalyzer
```

**Modes disponibles :**
```swift
var captureMode: CaptureMode = .exclusive  // ou .shared
var clickMode: ClickMode = .moveCursorAndClick  // ou .clickInPlace
```

### Scripts
- `run_analyzer.sh` : Compile et lance HIDAnalyzer
- `run_driver.sh` : Compile et lance TouchscreenDriver

---

## Étapes restantes

### 1. Analyser les rapports HID
```bash
./run_analyzer.sh
```
Toucher l'écran et noter les valeurs `[min:X, max:Y]` affichées pour X et Y.

### 2. Configurer le driver
Éditer `TouchscreenDriver.swift` avec les bonnes valeurs :
```swift
var touchscreenMaxX: CGFloat = VALEUR_TROUVÉE
var touchscreenMaxY: CGFloat = VALEUR_TROUVÉE
```

### 3. Accorder les permissions
- **Préférences Système → Confidentialité → Accessibilité** : ajouter l'exécutable
- **Préférences Système → Confidentialité → Surveillance de l'entrée** : si nécessaire

### 4. Tester
```bash
./run_driver.sh
```

---

## Problème secondaire : Résolution HiDPI

### Problème
Le texte et la barre de menu sont illisibles en 2560×720 sans HiDPI.

### Solution idéale
Résolution **1280×360 HiDPI** (texte 2× plus grand et net).

### Tentatives effectuées
1. **displayplacer** : La résolution existe (mode 70) mais la commande ne l'applique pas
   ```bash
   displayplacer "id:C281DDEC-C0ED-4FCE-AE2E-6BC5990102E7 mode:70"
   ```

2. **Préférences Système + Option** : Résolution non listée

### Piste à explorer
Utiliser **BetterDisplay** (https://github.com/waydabber/BetterDisplay) pour créer une résolution HiDPI custom 1280×360.

---

## Informations displayplacer

```
Persistent screen id: C281DDEC-C0ED-4FCE-AE2E-6BC5990102E7
Contextual screen id: 6
Serial screen id: s16843009
Resolution actuelle: 2560x720
Origin: (-2560, 720)
Mode HiDPI souhaité: mode 70 (res:1280x360 hz:60 color_depth:8 scaling:on)
```

---

## Permissions requises

| Permission | Raison |
|------------|--------|
| Accessibilité | Injection de clics CGEvent |
| Surveillance de l'entrée | Capture des événements HID |

---

## Commandes utiles

### Lister les périphériques USB
```bash
system_profiler SPUSBDataType
```

### Lister les écrans
```bash
displayplacer list
system_profiler SPDisplaysDataType
```

### Chercher les Display IDs (pour override EDID)
```bash
ioreg -l | grep -i "DisplayVendorID\|DisplayProductID"
```

---

## Prérequis

- macOS 10.15+ (Catalina ou plus récent)
- Xcode Command Line Tools : `xcode-select --install`
- Homebrew + displayplacer : `brew install displayplacer`
- Optionnel : BetterDisplay pour le HiDPI
