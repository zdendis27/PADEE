//
//  SignInView.swift
//  PADEE
//
//  Úvodní obrazovka s tlačítkem Sign in with Apple (cesta A, krok 1).
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    /// ViewModel dostáváme zvenku (z ContentView), aby existoval jen jeden.
    let auth: AuthViewModel

    /// Světlý / tmavý režim telefonu. Podle něj zvolíme barvu tlačítka Apple.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("PADEE")
                .font(.largeTitle.bold())
            Text("Skóre na hodinkách, rozbor od AI trenéra a bilance s kamarády.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            // Hotové tlačítko od Applu. Vzhled a text řeší systém sám.
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}

#Preview {
    SignInView(auth: AuthViewModel())
}
