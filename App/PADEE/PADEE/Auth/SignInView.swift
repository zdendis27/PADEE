//
//  SignInView.swift
//  PADEE
//
//  Úvodní obrazovka s přihlášením (cesta A, krok 1).
//  Hlavní cesta je Sign in with Apple; přihlášení kódem z e-mailu je náhradní,
//  dokud není aktivní placený Apple Developer Program.
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    /// ViewModel dostáváme zvenku (z ContentView), aby existoval jen jeden.
    let auth: AuthViewModel

    /// Světlý / tmavý režim telefonu. Podle něj zvolíme barvu tlačítka Apple.
    @Environment(\.colorScheme) private var colorScheme

    /// Co uživatel píše do textových polí. `@State` = View si to pamatuje.
    @State private var email = ""
    @State private var code = ""
    /// Běží zrovna síťový požadavek? Tlačítka se mezitím zablokují.
    @State private var isWorking = false

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

            Text("nebo")
                .font(.footnote)
                .foregroundStyle(.secondary)

            emailSection

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .disabled(isWorking)
    }

    /// Přihlášení kódem z e-mailu: nejdřív e-mail, pak pole pro kód.
    @ViewBuilder
    private var emailSection: some View {
        if let sentTo = auth.emailWaitingForCode {
            VStack(spacing: 12) {
                Text("Kód jsme poslali na \(sentTo)")
                    .font(.footnote)
                TextField("Kód z e-mailu", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode) // iOS nabídne kód z Mailu sám
                    .multilineTextAlignment(.center)
                    .font(.title2.monospaced())
                    .textFieldStyle(.roundedBorder)
                Button("Přihlásit se") {
                    run { await auth.verifyEmailCode(code) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 6)
                Button("Změnit e-mail") {
                    code = ""
                    auth.cancelEmailCode()
                }
                .font(.footnote)
            }
        } else {
            VStack(spacing: 12) {
                TextField("E-mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Poslat kód na e-mail") {
                    run { await auth.sendEmailCode(to: email) }
                }
                .buttonStyle(.bordered)
                .disabled(email.isEmpty)
            }
        }
    }

    /// Spustí asynchronní akci a po dobu jejího běhu zablokuje tlačítka.
    private func run(_ action: @escaping () async -> Void) {
        Task {
            isWorking = true
            await action()
            isWorking = false
        }
    }
}

#Preview {
    SignInView(auth: AuthViewModel())
}
