//
//  SplashView.swift
//  ChineseLawsSearch
//

import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.88
    var onFinish: () -> Void

    // 仿古纸色背景
    private let paperColor = Color(red: 0.949, green: 0.929, blue: 0.878)
    // 朱红印章色
    private let sealRed = Color(red: 0.78, green: 0.12, blue: 0.10)

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            sealView
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                opacity = 1
                scale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeIn(duration: 0.35)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinish()
                }
            }
        }
    }

    private var sealView: some View {
        ZStack {
            // 外框
            RoundedRectangle(cornerRadius: 6)
                .stroke(sealRed, lineWidth: 4)
                .frame(width: 140, height: 140)
            // 内框
            RoundedRectangle(cornerRadius: 3)
                .stroke(sealRed, lineWidth: 2)
                .frame(width: 124, height: 124)
            // 篆字
            VStack(spacing: -6) {
                Text("律")
                Text("疏")
            }
            .font(.custom("STKaiti", size: 62).bold())
            .foregroundStyle(sealRed)
            .frame(width: 108, height: 108)
        }
    }
}

#Preview {
    SplashView(onFinish: {})
}
