//
//  NavButton.swift
//  kouke browser
//
//  Navigation button with optional right-click history menu support.
//

import SwiftUI
import AppKit

struct NavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true
    var menuItems: [NavigationHistoryItem]? = nil
    var onMenuItemSelected: ((Int) -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        NavButtonRepresentable(
            icon: icon,
            action: action,
            isEnabled: isEnabled,
            isHovering: $isHovering,
            menuItems: menuItems,
            onMenuItemSelected: onMenuItemSelected
        )
        .frame(width: 28, height: 28)
        .background(isHovering && isEnabled ? Color("AccentHover") : Color.clear)
        .cornerRadius(2)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// NSViewRepresentable for NavButton with right-click menu support
struct NavButtonRepresentable: NSViewRepresentable {
    let icon: String
    let action: () -> Void
    let isEnabled: Bool
    @Binding var isHovering: Bool
    var menuItems: [NavigationHistoryItem]?
    var onMenuItemSelected: ((Int) -> Void)?

    func makeNSView(context: Context) -> NavButtonNSView {
        let view = NavButtonNSView()
        view.icon = icon
        view.action = action
        view.isEnabled = isEnabled
        view.menuItems = menuItems
        view.onMenuItemSelected = onMenuItemSelected
        return view
    }

    func updateNSView(_ nsView: NavButtonNSView, context: Context) {
        nsView.icon = icon
        nsView.action = action
        nsView.isEnabled = isEnabled
        nsView.menuItems = menuItems
        nsView.onMenuItemSelected = onMenuItemSelected
        nsView.updateIcon()
    }
}

/// Custom NSView that handles left-click action and right-click menu
class NavButtonNSView: NSView {
    var icon: String = ""
    var action: (() -> Void)?
    var isEnabled: Bool = true
    var menuItems: [NavigationHistoryItem]?
    var onMenuItemSelected: ((Int) -> Void)?

    private var iconImageView: NSImageView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14)
        ])

        iconImageView = imageView
    }

    func updateIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconImageView?.image = image
        iconImageView?.contentTintColor = isEnabled
            ? NSColor(named: "TextMuted")
            : NSColor(named: "TextMuted")?.withAlphaComponent(0.4)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        action?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled, let items = menuItems, !items.isEmpty else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuItemClicked(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = item.index
            menuItem.isEnabled = true

            // Load favicon asynchronously
            loadFavicon(for: item.url) { [weak menuItem] image in
                DispatchQueue.main.async {
                    menuItem?.image = image
                }
            }

            menu.addItem(menuItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        onMenuItemSelected?(sender.tag)
    }

    private func loadFavicon(for urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString),
              let host = url.host else {
            completion(defaultGlobeIcon())
            return
        }

        // Use Google's favicon service for quick loading
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")

        guard let faviconURL = faviconURL else {
            completion(defaultGlobeIcon())
            return
        }

        URLSession.shared.dataTask(with: faviconURL) { data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                image.size = NSSize(width: 16, height: 16)
                completion(image)
            } else {
                completion(self.defaultGlobeIcon())
            }
        }.resume()
    }

    private func defaultGlobeIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
