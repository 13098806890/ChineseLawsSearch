//
//  SplashView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.92
    var onFinish: () -> Void

    private let sealRed    = Color(red: 0.78, green: 0.12, blue: 0.10)
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
            // 纸色印面
            RoundedRectangle(cornerRadius: 10)
                .fill(paperColor)
                .frame(width: 210, height: 210)
            // 外边框
            RoundedRectangle(cornerRadius: 10)
                .stroke(sealRed, lineWidth: 4)
                .frame(width: 210, height: 210)
            // 内边框
            RoundedRectangle(cornerRadius: 6)
                .stroke(sealRed, lineWidth: 2)
                .frame(width: 194, height: 194)
            // 阳刻字形
            Image("SealGlyph")
                .resizable()
                .frame(width: 152, height: 152)
        }
    }
}

#Preview {
    SplashView(onFinish: {})
}
