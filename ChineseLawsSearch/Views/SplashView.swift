//
//  SplashView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.92
    var onFinish: () -> Void

    private let sealRed   = Color(red: 0.78, green: 0.12, blue: 0.10)
    private let paperColor = Color(red: 0.949, green: 0.929, blue: 0.878)

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            sealStamp
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

    private var sealStamp: some View {
        ZStack {
            // 印章红底
            RoundedRectangle(cornerRadius: 12)
                .fill(sealRed)
                .frame(width: 200, height: 200)
            // 双边框
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.35), lineWidth: 3)
                .frame(width: 200, height: 200)
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 184, height: 184)
            // 从图标抠出的篆刻字形
            Image("SealGlyph")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white)
                .frame(width: 148, height: 148)
        }
        // 轻微旋转，印章感
        .rotationEffect(.degrees(-3))
        // 印章压纸阴影
        .shadow(color: sealRed.opacity(0.4), radius: 18, x: 4, y: 6)
    }
}

#Preview {
    SplashView(onFinish: {})
}
