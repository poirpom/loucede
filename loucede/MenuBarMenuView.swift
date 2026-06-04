//
//  MenuBarMenuView.swift
//  loucede
//
//  Created by content manager on 27/01/26.
//

import SwiftUI
import AppKit

struct MenuBarMenuView: View {
    @State private var isVisible = false
    @State private var hoveredItem: String? = nil

    var onSettings: () -> Void
    var onQuit: () -> Void
    var onDismiss: () -> Void

    /// Observe l'état licence pour afficher/masquer dynamiquement l'item
    /// d'achat (réactif : si l'utilisateur active une licence pendant que
    /// le menu est ouvert, l'item disparaît live).
    @StateObject private var license = LicenseManager.shared

    // Phase 6.7b revertée (2026-04-29) : isDarkMode retiré, les sous-vues
    // lisent colorScheme via @Environment directement.
    @Environment(\.colorScheme) var colorScheme

    var backgroundColor: Color {
        Color(NSColor.windowBackgroundColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Menu items
            VStack(spacing: 2) {
                // Trial épuisé sans licence → item d'achat en haut (l'emoji
                // 🎉 occupe la gouttière d'icône, exception au pattern SF
                // Symbol). Disparaît dès que canRunAction redevient true.
                if !license.canRunAction {
                    MenuBarMenuItem(
                        emoji: "🎉",
                        title: "Acheter loucedé",
                        isHovered: hoveredItem == "purchase",
                        delay: 0.05
                    ) {
                        onDismiss()                                 // ferme le menu
                        PurchaseWindowController.presentCheckout()  // ouvre la fenêtre Polar
                    }
                    .onHover { hovering in
                        hoveredItem = hovering ? "purchase" : nil
                    }

                    // Separator
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.1), value: isVisible)
                }

                MenuBarMenuItem(
                    icon: "gearshape",
                    title: "Réglages",
                    isHovered: hoveredItem == "settings",
                    delay: 0.1
                ) {
                    onSettings()
                }
                .onHover { hovering in
                    hoveredItem = hovering ? "settings" : nil
                }

                // Separator
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(0.15), value: isVisible)

                MenuBarMenuItem(
                    icon: "power",
                    title: "Quitter",
                    isHovered: hoveredItem == "quit",
                    isDestructive: true,
                    delay: 0.15
                ) {
                    onQuit()
                }
                .onHover { hovering in
                    hoveredItem = hovering ? "quit" : nil
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 170)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .scaleEffect(isVisible ? 1 : 0.8, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isVisible = true
            }
        }
    }

    func dismiss() {
        withAnimation(.easeIn(duration: 0.15)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDismiss()
        }
    }
}

struct MenuBarMenuItem: View {
    /// SF Symbol affiché dans la gouttière. `nil` si on utilise `emoji`.
    var icon: String? = nil
    /// Emoji affiché dans la gouttière à la place du SF Symbol (item
    /// d'achat). Prioritaire sur `icon`.
    var emoji: String? = nil
    let title: String
    let isHovered: Bool
    var isDestructive: Bool = false
    let delay: Double
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var isVisible = false

    var textColor: Color {
        if isDestructive && isHovered { return .white }
        return colorScheme == .dark ? .white : Color(white: 0.15)
    }

    var iconColor: Color {
        if isDestructive && isHovered { return .white }
        return colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.4)
    }

    var hoverBackground: Color {
        if isDestructive { return Color.red.opacity(0.85) }
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let emoji {
                        Text(emoji)
                            .font(.system(size: 14))
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                }
                .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? hoverBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: isVisible ? 0 : -8)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(delay)) {
                isVisible = true
            }
        }
    }
}

// Window controller for the menu
class MenuBarMenuWindowController: NSObject {
    private var menuWindow: NSWindow?
    private var eventMonitor: Any?

    func showMenu(relativeTo statusItem: NSStatusItem, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        guard let button = statusItem.button else { return }

        // Close existing menu if any
        closeMenu()

        // Get button frame in screen coordinates
        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        // Create the menu view
        let menuView = MenuBarMenuView(
            onSettings: { [weak self] in
                self?.closeMenu()
                onSettings()
            },
            onQuit: { [weak self] in
                self?.closeMenu()
                onQuit()
            },
            onDismiss: { [weak self] in
                self?.closeMenu()
            }
        )

        let hostingView = NSHostingView(rootView: menuView)
        hostingView.setFrameSize(hostingView.fittingSize)

        // Create borderless window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false // We handle shadow in SwiftUI

        // Position below the status item, centered
        let menuX = buttonFrameOnScreen.midX - (hostingView.fittingSize.width / 2)
        let menuY = buttonFrameOnScreen.minY - hostingView.fittingSize.height - 4
        window.setFrameOrigin(NSPoint(x: menuX, y: menuY))

        window.orderFront(nil)
        menuWindow = window

        // Monitor for clicks outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeMenu()
        }

        // Also monitor local events
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let menuWindow = self?.menuWindow,
               !NSPointInRect(NSEvent.mouseLocation, menuWindow.frame) {
                self?.closeMenu()
            }
            return event
        }
    }

    func closeMenu() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        menuWindow?.orderOut(nil)
        menuWindow = nil
    }

    var isMenuVisible: Bool {
        menuWindow != nil
    }
}
