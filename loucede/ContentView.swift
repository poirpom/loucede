//
//  ContentView.swift
//  typo
//
//  Created by content manager on 23/01/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.cursor")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("loucedé est actif")
                .font(.title2.bold())

            Text("Appuie sur ⇧ + ⌥ + A pour ouvrir")
                .foregroundColor(.secondary)

            Text("Ou clique sur l'icône dans la barre des menus")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(width: 300, height: 200)
        .padding()
    }
}

#Preview {
    ContentView()
}
