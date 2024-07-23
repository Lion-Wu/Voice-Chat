//
//  ContentView.swift
//  Voice Chat
//
//  Created by 吴子宸 on 2023/12/25.
//

import SwiftUI

struct HomeView: View {
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()
                NavigationLink(destination: ChatView()) {
                    Text("进入聊天界面")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                NavigationLink(destination: VoiceView()) {
                    Text("进入语音生成器")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }
                Spacer()
                Text("Voice Chat By Lion in 2024")
                    .foregroundColor(.gray)
                    .padding()
            }
            .padding()
            .navigationTitle("主页")
            .navigationBarItems(trailing: Button(action: {
                showingSettings.toggle()
            }) {
                Image(systemName: "gear")
                    .imageScale(.large)
            })
            .sheet(isPresented: $showingSettings) {
                SettingsView(isPresented: $showingSettings)
            }
        }
    }
}

#Preview {
    HomeView()
}
