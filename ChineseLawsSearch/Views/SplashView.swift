//
//  SplashView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.92
    var onFinish: () -> Void

    private let paperColor = Color(red: 0.949, green: 0.929, blue: 0.878)

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            Image("SealGlyph")
                .resizable()
                .frame(width: 200, height: 200)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                opacity = 1
                scale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeIn(duration: 0.35)) { opacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onFinish() }
            }
        }
    }
}

#Preview {
    SplashView(onFinish: {})
}
