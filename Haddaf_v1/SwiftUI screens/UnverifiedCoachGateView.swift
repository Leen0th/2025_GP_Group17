//
//  Untitled.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 16/02/2026.
//

import SwiftUI

struct UnverifiedCoachGateView: View {
    @Binding var isPresented: Bool
    private let primary = BrandColors.darkTeal
    
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
                    
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                        .padding(.top, 10)
                    
                    Text("Verification Required")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(primary)
                    
                    Text("Your coaching profile is under review. Social features will be unlocked once your account is verified.")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                    
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
