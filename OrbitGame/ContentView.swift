import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .background(Color.black)
            .onAppear {
                scene.setAppActive(scenePhase == .active)
                // Installs the handler and silently restores an existing Game Center
                // session. It does not force the sign-in UI; that only happens when
                // the player taps RANKING.
                GameCenterService.shared.prepareAuthentication()
            }
            .onChange(of: scenePhase) { _, newPhase in
                scene.setAppActive(newPhase == .active)
            }
    }
}

#Preview {
    ContentView()
}
