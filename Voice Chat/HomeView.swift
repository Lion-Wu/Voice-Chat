//
//  HomeView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI

struct HomeView: View {
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            #if os(iOS)
            NavigationLink(destination: ChatView()) {
                Text("Enter Chat Interface")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(15)
            }
            .padding(.horizontal)

            NavigationLink(destination: VoiceView()) {
                Text("Enter Voice Generator")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.teal]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(15)
            }
            .padding(.horizontal)
            #else
            Text("Welcome to Voice Chat")
                .font(.largeTitle)
                .padding()
            #endif
            Spacer()
            Text("Voice Chat By Lion in 2024")
                .foregroundColor(.gray)
                .padding()
        }
        .padding()
        .navigationTitle("Home")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings.toggle()
                }) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(SettingsManager.shared)
        }
        #endif
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
