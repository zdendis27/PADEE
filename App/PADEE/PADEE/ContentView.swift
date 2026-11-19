//
//  ContentView.swift
//  PADEE
//
//  Kořenová obrazovka: podle stavu přihlášení ukáže přihlášení, nebo aplikaci.
//

import SwiftUI

struct ContentView: View {
    /// `@State` drží ViewModel naživu po celou dobu, co je ContentView na obrazovce.
    @State private var auth = AuthViewModel()

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView(auth: auth)
            case .signedIn(let profile):
                SignedInView(auth: auth, profile: profile)
            }
        }
        // Spustí se při zobrazení a běží, dokud View existuje.
        .task { await auth.observeAuthChanges() }
    }
}

/// Dočasná obrazovka po přihlášení: ukáže PADEE ID a jde se odhlásit.
/// Skutečné záložky (Domů, Zápasy, Žebříčky, Profil) přijdou v dalších týdnech.
private struct SignedInView: View {
    let auth: AuthViewModel
    let profile: Profile?

    var body: some View {
        VStack(spacing: 16) {
            if let profile {
                Text("Ahoj, \(profile.displayName ?? "hráči")!")
                    .font(.title2.bold())
                Text("Tvoje PADEE ID")
                    .foregroundStyle(.secondary)
                Text(profile.padeeId)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .textSelection(.enabled)
            } else {
                ProgressView("Načítám profil…")
            }

            if let message = auth.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            Button("Odhlásit se", role: .destructive) {
                Task { await auth.signOut() }
            }
            .padding(.top, 32)
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
