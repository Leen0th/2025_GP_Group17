//
//  DeactivatedAccountGateView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 14/02/2026.
//

import SwiftUI

struct DeactivatedAccountGateView: View {
    @EnvironmentObject var session: AppSession
    @Binding var isPresented: Bool
    private let primary = BrandColors.darkTeal
    
    @State private var showDetails = false
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            // Popup card
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Handle bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                    
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .padding(.top, 10)
                    
                    Text("Account Deactivated")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(primary)
                    
                    Text("Your account has been deactivated and you cannot perform this action.")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                    
                    // Show reason button
                    if session.deactivationReason != nil {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDetails.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 15))
                                Text(showDetails ? "Hide Details" : "Why was my account deactivated?")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(primary.opacity(0.6), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        if showDetails, let reason = session.deactivationReason {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "quote.opening")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("Admin's Reason:")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(reason)
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 11))
                                    Text("Think this is a mistake?")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                }
                                .foregroundColor(.secondary)
                                
                                Button {
                                    if let url = URL(string: "mailto:support@haddaf.com") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Text("Contact support@haddaf.com")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(primary)
                                        .underline()
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.red.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    
                    // Dismiss button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    } label: {
                        Text("OK")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(primary)
                            .clipShape(Capsule())
                            .shadow(color: primary.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
                )
                .padding(.horizontal, 0)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea()
    }
}
