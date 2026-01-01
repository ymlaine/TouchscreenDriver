#!/usr/bin/env swift

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import AppKit

// ============================================
// Configuration pour Corsair Xeneon Edge
// À AJUSTER après analyse des rapports HID
// ============================================
let TOUCHSCREEN_VENDOR_ID: Int = 0x27c0
let TOUCHSCREEN_PRODUCT_ID: Int = 0x0859

// Plages de coordonnées du touchscreen (à déterminer via HIDAnalyzer)
// Ces valeurs sont des estimations, à ajuster!
var touchscreenMaxX: CGFloat = 4095
var touchscreenMaxY: CGFloat = 4095
var touchscreenMinX: CGFloat = 0
var touchscreenMinY: CGFloat = 0

// ============================================
// Configuration écran cible
// ============================================
var targetScreen: NSScreen?
var screenOffsetX: CGFloat = 0
var screenOffsetY: CGFloat = 0
var screenWidth: CGFloat = 1920
var screenHeight: CGFloat = 1080

// ============================================
// État du toucher
// ============================================
var currentX: CGFloat = 0
var currentY: CGFloat = 0
var isTouching: Bool = false
var lastClickTime: Date = Date.distantPast
let debounceInterval: TimeInterval = 0.05 // 50ms debounce

// ============================================
// Mode de fonctionnement
// ============================================
enum ClickMode {
    case moveCursorAndClick  // Téléporte le curseur puis clique
    case clickInPlace        // Clique sans bouger le curseur (peut ne pas marcher avec toutes les apps)
}
var clickMode: ClickMode = .moveCursorAndClick

// ============================================
// Mode de capture HID
// ============================================
enum CaptureMode {
    case shared      // Écoute les événements sans les bloquer (peut causer des doubles clics)
    case exclusive   // Capture exclusive - bloque les événements système (recommandé)
}
var captureMode: CaptureMode = .exclusive

// ============================================
// Fonctions utilitaires
// ============================================

func convertToScreenCoordinates(rawX: Int, rawY: Int) -> CGPoint {
    // Normaliser les coordonnées brutes en 0.0 - 1.0
    let normalizedX = (CGFloat(rawX) - touchscreenMinX) / (touchscreenMaxX - touchscreenMinX)
    let normalizedY = (CGFloat(rawY) - touchscreenMinY) / (touchscreenMaxY - touchscreenMinY)
    
    // Convertir en coordonnées écran
    let screenX = screenOffsetX + (normalizedX * screenWidth)
    let screenY = screenOffsetY + (normalizedY * screenHeight)
    
    return CGPoint(x: screenX, y: screenY)
}

func injectClick(at point: CGPoint) {
    // Vérifier le debounce
    let now = Date()
    guard now.timeIntervalSince(lastClickTime) > debounceInterval else { return }
    lastClickTime = now
    
    switch clickMode {
    case .moveCursorAndClick:
        // Téléporter le curseur
        CGWarpMouseCursorPosition(point)
        
        // Petit délai pour que le système enregistre la position
        usleep(10000) // 10ms
        
    case .clickInPlace:
        break // Ne pas bouger le curseur
    }
    
    // Créer et poster les événements souris
    guard let mouseDown = CGEvent(mouseEventSource: nil,
                                   mouseType: .leftMouseDown,
                                   mouseCursorPosition: point,
                                   mouseButton: .left) else {
        print("❌ Erreur création événement mouseDown")
        return
    }
    
    guard let mouseUp = CGEvent(mouseEventSource: nil,
                                 mouseType: .leftMouseUp,
                                 mouseCursorPosition: point,
                                 mouseButton: .left) else {
        print("❌ Erreur création événement mouseUp")
        return
    }
    
    // Poster les événements
    mouseDown.post(tap: .cghidEventTap)
    usleep(20000) // 20ms entre down et up
    mouseUp.post(tap: .cghidEventTap)
    
    print("🖱️  Clic injecté à (\(Int(point.x)), \(Int(point.y)))")
}

func injectDrag(to point: CGPoint) {
    guard let dragEvent = CGEvent(mouseEventSource: nil,
                                   mouseType: .leftMouseDragged,
                                   mouseCursorPosition: point,
                                   mouseButton: .left) else {
        return
    }
    
    if clickMode == .moveCursorAndClick {
        CGWarpMouseCursorPosition(point)
    }
    
    dragEvent.post(tap: .cghidEventTap)
}

// ============================================
// Callback HID
// ============================================

func hidInputCallback(context: UnsafeMutableRawPointer?,
                      result: IOReturn,
                      sender: UnsafeMutableRawPointer?,
                      value: IOHIDValue) {
    
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    
    // Mettre à jour les coordonnées
    if usagePage == 0x01 { // Generic Desktop
        switch usage {
        case 0x30: // X
            currentX = CGFloat(intValue)
        case 0x31: // Y
            currentY = CGFloat(intValue)
        default:
            break
        }
    }
    
    // Détecter le toucher (Tip Switch)
    if usagePage == 0x0D && usage == 0x42 {
        let wasTouching = isTouching
        isTouching = intValue != 0
        
        if isTouching && !wasTouching {
            // Nouveau toucher → clic
            let screenPoint = convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY))
            injectClick(at: screenPoint)
        } else if isTouching && wasTouching {
            // Glissement → drag
            let screenPoint = convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY))
            injectDrag(to: screenPoint)
        }
        // Si relâché, on ne fait rien (le mouseUp a déjà été envoyé)
    }
}

// ============================================
// Configuration de l'écran
// ============================================

func setupScreen() {
    // Trouver l'écran Corsair Xeneon Edge
    // Par défaut on prend l'écran principal, mais tu peux ajuster
    
    let screens = NSScreen.screens
    print("📺 Écrans détectés:")
    
    for (index, screen) in screens.enumerated() {
        let frame = screen.frame
        let name = screen.localizedName
        print("   [\(index)] \(name): \(Int(frame.width))x\(Int(frame.height)) @ (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
    }
    
    // Chercher l'écran Corsair (ou prendre le principal)
    // Tu peux ajuster cette logique selon ta configuration
    if let xeneonScreen = screens.first(where: { $0.localizedName.contains("XENEON") || $0.localizedName.contains("Corsair") }) {
        targetScreen = xeneonScreen
        print("✅ Écran Xeneon Edge trouvé!")
    } else if screens.count > 1 {
        // Prendre le deuxième écran (souvent l'externe)
        targetScreen = screens[1]
        print("⚠️  Xeneon non identifié par nom, utilisation de l'écran secondaire")
    } else {
        targetScreen = NSScreen.main
        print("⚠️  Un seul écran détecté, utilisation de l'écran principal")
    }
    
    updateScreenGeometry()
}

func updateScreenGeometry() {
    if let screen = targetScreen {
        let frame = screen.frame
        screenOffsetX = frame.origin.x
        screenOffsetY = frame.origin.y
        screenWidth = frame.width
        screenHeight = frame.height
        print("📐 Écran cible: \(Int(screenWidth))x\(Int(screenHeight)) @ (\(Int(screenOffsetX)), \(Int(screenOffsetY)))")
    }
}

// ============================================
// Observer pour les changements d'écran
// ============================================

class ScreenChangeObserver {
    init() {
        // Observer les changements de configuration d'écran
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("\n🔄 Configuration d'écran modifiée! Mise à jour...")
            setupScreen()
        }
    }
}

var screenObserver: ScreenChangeObserver?

// ============================================
// Vérification des permissions
// ============================================

func checkAccessibilityPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// ============================================
// Programme principal
// ============================================

func main() {
    print("""
    ╔════════════════════════════════════════════════════════════╗
    ║   Touchscreen Driver - Corsair Xeneon Edge                 ║
    ║   Convertit les touches en clics absolus                   ║
    ╚════════════════════════════════════════════════════════════╝
    
    """)
    
    // Vérifier les permissions Accessibilité
    print("🔐 Vérification des permissions Accessibilité...")
    if !checkAccessibilityPermission() {
        print("""
        
        ⚠️  PERMISSION REQUISE
        
        Pour injecter des clics, cette app doit être ajoutée à:
        Préférences Système → Confidentialité → Accessibilité
        
        Une fenêtre de demande devrait s'être ouverte.
        Après avoir accordé la permission, relance le programme.
        
        """)
        exit(1)
    }
    print("✅ Permission Accessibilité accordée")
    
    // Configurer l'écran cible
    setupScreen()
    
    // Initialiser l'observer pour les changements d'écran
    screenObserver = ScreenChangeObserver()
    
    print("""
    
    📊 Configuration actuelle:
       Touchscreen: X=[0, \(Int(touchscreenMaxX))], Y=[0, \(Int(touchscreenMaxY))]
       Mode clic: \(clickMode == .moveCursorAndClick ? "Déplacer curseur + clic" : "Clic sans déplacer")
       Mode capture: \(captureMode == .exclusive ? "EXCLUSIF (bloque événements système)" : "PARTAGÉ (peut causer des doubles clics)")
    
    ⚠️  Si les clics ne sont pas à la bonne position, ajuste les valeurs
       touchscreenMaxX/Y dans le code source après avoir utilisé HIDAnalyzer.
    
    """)
    
    // Créer le HID Manager
    guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) else {
        print("❌ Erreur: Impossible de créer IOHIDManager")
        exit(1)
    }
    
    // Filtrer pour notre écran tactile
    let deviceMatch: [String: Any] = [
        kIOHIDVendorIDKey as String: TOUCHSCREEN_VENDOR_ID,
        kIOHIDProductIDKey as String: TOUCHSCREEN_PRODUCT_ID
    ]
    
    IOHIDManagerSetDeviceMatching(manager, deviceMatch as CFDictionary)
    
    // Ouvrir le manager avec le mode approprié
    // kIOHIDOptionsTypeSeizeDevice = 0x01 - prend le contrôle exclusif du périphérique
    let openOptions: IOOptionBits
    if captureMode == .exclusive {
        openOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        print("🔒 Ouverture en mode EXCLUSIF (seize device)...")
    } else {
        openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
        print("🔓 Ouverture en mode PARTAGÉ...")
    }
    
    let openResult = IOHIDManagerOpen(manager, openOptions)
    if openResult != kIOReturnSuccess {
        print("❌ Erreur: Impossible d'ouvrir IOHIDManager (code: \(openResult))")
        if captureMode == .exclusive {
            print("""
            
            💡 Le mode exclusif peut échouer si:
               - Un autre programme utilise déjà le périphérique
               - Les permissions sont insuffisantes
               
            Tu peux essayer le mode PARTAGÉ en changeant:
               var captureMode: CaptureMode = .shared
               
            """)
        }
        exit(1)
    }
    
    // Vérifier le périphérique
    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
        print("❌ Erreur: Écran tactile non trouvé!")
        exit(1)
    }
    
    print("✅ Écran tactile connecté!")
    
    // Enregistrer le callback
    IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    
    print("""
    
    🎯 Driver actif! Touche l'écran pour cliquer.
       (Ctrl+C pour quitter)
    
    """)
    
    // Lancer le RunLoop
    CFRunLoopRun()
}

// Point d'entrée
main()
