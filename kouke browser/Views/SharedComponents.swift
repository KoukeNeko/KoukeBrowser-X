//
//  SharedComponents.swift
//  kouke browser
//
//  Reusable UI components with consistent styling across the app.
//

import SwiftUI

// MARK: - Sheet Container

/// A consistent container for popup sheets matching Safari-style design
struct SheetContainer<Content: View>: View {
    let title: String
    let showBackButton: Bool
    let onBack: (() -> Void)?
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        showBackButton: Bool = false,
        onBack: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.onBack = onBack
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: title,
                showBackButton: showBackButton,
                onBack: onBack,
                onDismiss: onDismiss
            )

            Divider()

            content
        }
        .background(Color("Bg"))
    }
}

// MARK: - Sheet Header

struct SheetHeader: View {
    let title: String
    var showBackButton: Bool = false
    var onBack: (() -> Void)?
    let onDismiss: () -> Void
    var trailingButton: AnyView? = nil

    var body: some View {
        HStack {
            if showBackButton {
                Button(action: { onBack?() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            if let trailing = trailingButton {
                trailing
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color("TextMuted"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Search Bar

struct SheetSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color("TextMuted"))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color("TextMuted"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color("CardBg"))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Section Header

struct SheetSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color("TextMuted"))
            .textCase(.uppercase)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Bg"))
    }
}

// MARK: - List Row

struct SheetListRow<Leading: View, Trailing: View>: View {
    let onTap: () -> Void
    @ViewBuilder let leading: Leading
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onTap = onTap
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                leading

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(Color("Text"))
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color("TextMuted"))
                            .lineLimit(1)
                    }
                }

                Spacer()

                trailing
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isHovering ? Color("CardBg") : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Empty State

struct SheetEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color("TextMuted").opacity(0.5))

            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color("TextMuted").opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Input Field

struct SheetInputField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("TextMuted"))
                .textCase(.uppercase)

            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color("CardBg"))
            .cornerRadius(6)
        }
    }
}

// MARK: - Bottom Button Bar

struct SheetButtonBar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                leading
                Spacer()
                trailing
            }
            .padding(16)
        }
    }
}
