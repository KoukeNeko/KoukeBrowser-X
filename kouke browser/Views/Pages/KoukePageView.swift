//
//  KoukePageView.swift
//  kouke browser
//
//  Router view for kouke: internal pages.
//

import SwiftUI

struct KoukePageView: View {
    let url: String
    let onNavigate: (String) -> Void

    var body: some View {
        switch url {
        case KoukeScheme.blank:
            StartPage(onNavigate: onNavigate)

        case KoukeScheme.about:
            AboutPageView()

        case KoukeScheme.settings:
            SettingsPageView()

        case KoukeScheme.help:
            HelpPageView()

        default:
            // Handle kouke:// URLs (like view-source) - let WebView handle them
            if url.hasPrefix("kouke://") {
                Color.clear
            } else {
                unknownPageView
            }
        }
    }

    private var unknownPageView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color("TextMuted").opacity(0.5))

            Text("Unknown Page")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color("Text"))

            Text("The page \"\(url)\" is not recognized.")
                .font(.system(size: 14))
                .foregroundColor(Color("TextMuted"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Bg"))
    }
}

#Preview {
    KoukePageView(url: KoukeScheme.blank, onNavigate: { _ in })
        .frame(width: 800, height: 600)
}
