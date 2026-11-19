//
//  AuthViewModel.swift
//  PADEE
//
//  ViewModel (MVVM) pro přihlášení. View jen zobrazuje `state` a volá metody,
//  veškerá logika přihlášení je tady.
//

import AuthenticationServices
import Foundation
import Observation
import Supabase

/// `@Observable`: když se změní `state` nebo `errorMessage`, SwiftUI samo
/// překreslí obrazovky, které je používají.
/// Třída běží na hlavním vlákně (výchozí izolace projektu je MainActor),
/// takže změny stavu jsou pro UI bezpečné.
@Observable
final class AuthViewModel {

    /// V jakém stavu přihlášení aplikace je.
    enum State: Equatable {
        case loading                 // zjišťujeme, jestli je uložené přihlášení
        case signedOut               // ukaž přihlašovací obrazovku
        case signedIn(Profile?)      // přihlášený; profil se může ještě načítat
    }

    private(set) var state: State = .loading
    var errorMessage: String?

    private let client = SupabaseManager.client
    /// Nonce aktuálního pokusu o přihlášení (viz AppleSignInNonce.swift).
    private var currentNonce: String?

    // MARK: - Sledování přihlášení

    /// Poslouchá změny přihlášení po celou dobu běhu aplikace.
    /// Volá se z `.task { }` ve View, takže skončí, až View zmizí.
    func observeAuthChanges() async {
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .initialSession, .signedIn:
                if let session = change.session {
                    state = .signedIn(nil)
                    await loadProfile(userId: session.user.id)
                } else {
                    state = .signedOut
                }
            case .signedOut, .userDeleted:
                state = .signedOut
            default:
                break // obnovení tokenu apod. stav nemění
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Volá se těsně před zobrazením okna „Pokračovat s Applem“.
    /// Vrací otisk nonce, který se vloží do požadavku na Apple.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.random()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    /// Zpracuje výsledek od Applu a přihlásí uživatele do Supabase.
    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil

        let authorization: ASAuthorization
        switch result {
        case .success(let value):
            authorization = value
        case .failure(let error):
            // Zavření okna uživatelem není chyba, nic nehlásíme.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Přihlášení přes Apple se nepovedlo: \(error.localizedDescription)"
            return
        }

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            errorMessage = "Apple nevrátil přihlašovací token. Zkus to znovu."
            return
        }

        do {
            // Supabase ověří token u Applu. Při prvním přihlášení založí účet
            // a databázový trigger k němu vytvoří profil s PADEE ID.
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )

            // Jméno pošle Apple jen při úplně prvním přihlášení, a ne v tokenu.
            // Proto si ho hned uložíme do profilu.
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
                if !name.isEmpty {
                    try await saveDisplayName(name, userId: session.user.id)
                }
            }
            await loadProfile(userId: session.user.id)
        } catch {
            errorMessage = "Přihlášení do PADEE se nepovedlo: \(error.localizedDescription)"
        }
        currentNonce = nil
    }

    // MARK: - Přihlášení kódem z e-mailu
    //
    // Náhradní přihlášení, dokud není aktivní placený Apple Developer Program
    // (Sign in with Apple s bezplatným „Personal Team“ nejde).
    // Postup: 1) pošleme na e-mail 6místný kód, 2) uživatel ho opíše, 3) ověříme.

    /// E-mail, na který odešel kód. Když není nil, View ukáže pole pro kód.
    private(set) var emailWaitingForCode: String?

    /// Krok 1: Supabase pošle na e-mail jednorázový kód.
    /// Pokud účet s tímto e-mailem ještě neexistuje, Supabase ho založí.
    func sendEmailCode(to email: String) async {
        errorMessage = nil
        let cleaned = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard cleaned.contains("@") else {
            errorMessage = "Zadej platný e-mail."
            return
        }
        do {
            try await client.auth.signInWithOTP(email: cleaned)
            emailWaitingForCode = cleaned
        } catch {
            errorMessage = "Kód se nepodařilo odeslat: \(error.localizedDescription)"
        }
    }

    /// Krok 2: ověří kód z e-mailu. Po úspěchu přijde událost `.signedIn`
    /// do `observeAuthChanges()` a ta načte profil.
    func verifyEmailCode(_ code: String) async {
        errorMessage = nil
        guard let email = emailWaitingForCode else { return }
        do {
            try await client.auth.verifyOTP(
                email: email,
                token: code.trimmingCharacters(in: .whitespaces),
                type: .email
            )
            emailWaitingForCode = nil
        } catch {
            errorMessage = "Kód nesouhlasí nebo vypršel. Zkus to znovu."
        }
    }

    /// Zpět na zadání e-mailu (např. při překlepu v adrese).
    func cancelEmailCode() {
        emailWaitingForCode = nil
        errorMessage = nil
    }

    // MARK: - Odhlášení

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = "Odhlášení se nepovedlo: \(error.localizedDescription)"
        }
    }

    // MARK: - Profil

    /// Načte profil přihlášeného hráče z tabulky `profiles`.
    /// RLS v databázi zaručí, že upravovat jde jen vlastní profil.
    private func loadProfile(userId: UUID) async {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            state = .signedIn(profile)
        } catch {
            errorMessage = "Nepodařilo se načíst profil: \(error.localizedDescription)"
        }
    }

    private func saveDisplayName(_ name: String, userId: UUID) async throws {
        try await client
            .from("profiles")
            .update(["display_name": name])
            .eq("id", value: userId)
            .execute()
    }
}
