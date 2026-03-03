//
//  LoginView.swift
//  SipBuddy
//
//  Firebase Login Screen
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthStateManager
    @FocusState private var focusedField: Field?
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSignUp = false
    @State private var showingPasswordReset = false
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 20) {
                    // Logo or App Name
                    VStack(spacing: 8) {
                        Image("SipBuddyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .colorScheme(.light)
                    
                    Text("SipBuddy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your sip companion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 40)
                
                // Login Form
                VStack(spacing: 16) {
                    TextField("", text: $email, prompt: Text("Email").foregroundColor(.white.opacity(0.5)))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(10)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                    
                    SecureField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.5)))
                        .textContentType(.password)
                        .padding()
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(10)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            if !email.isEmpty && !password.isEmpty {
                                Task { await signIn() }
                            }
                        }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(email.isEmpty || password.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                    
                    Button {
                        showingPasswordReset = true
                    } label: {
                        Text("Forgot Password?")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Sign Up Link
                HStack {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    Button {
                        showingSignUp = true
                    } label: {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .padding(.bottom, 30)
            }
            }
            .navigationBarHidden(true)
            .onAppear {
                PostHogService.shared.screen("Login")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onTapGesture {
                focusedField = nil
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showingPasswordReset) {
                PasswordResetView()
            }
        }
    }
    
    private func signIn() async {
        errorMessage = nil
        isLoading = true
        
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthStateManager
    @FocusState private var isEmailFocused: Bool
    
    @State private var email = ""
    @State private var isLoading = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 20) {
                    Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .focused($isEmailFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !email.isEmpty {
                            Task { await resetPassword() }
                        }
                    }
                
                if let success = successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button {
                    Task { await resetPassword() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(email.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(email.isEmpty || isLoading)
                
                Spacer()
            }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEmailFocused = false
                    }
                }
            }
        }
    }
    
    private func resetPassword() async {
        errorMessage = nil
        successMessage = nil
        isLoading = true
        
        do {
            try await authManager.resetPassword(email: email)
            successMessage = "Password reset link sent! Check your email."
            
            // Auto dismiss after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
