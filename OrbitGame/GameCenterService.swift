import GameKit
import UIKit

final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterService()

    enum IDs {
        static let bestScoreLeaderboard = "com.marcustitton.orbitgame.leaderboard.best"
        static let dailyLeaderboard = "com.marcustitton.orbitgame.leaderboard.daily"

        static let firstOrbit = "com.marcustitton.orbitgame.achievement.first_orbit"
        static let gettingSerious = "com.marcustitton.orbitgame.achievement.getting_serious"
        static let orbitMaster = "com.marcustitton.orbitgame.achievement.orbit_master"
        static let untouchable = "com.marcustitton.orbitgame.achievement.untouchable"
        static let comboMaster = "com.marcustitton.orbitgame.achievement.combo_master"
        static let addicted = "com.marcustitton.orbitgame.achievement.addicted"
    }

    private var authenticationConfigured = false
    private var authenticationViewController: UIViewController?
    private var wantsToOpenRanking = false
    private var didSyncThisSession = false
    private var isPresentingGameCenter = false
    private var presentationRetryWorkItem: DispatchWorkItem?

    var isAuthenticated: Bool {
        GKLocalPlayer.local.isAuthenticated
    }

    private override init() {
        super.init()
    }

    // Install Game Center authentication once when the app launches. The handler may
    // silently restore an existing account or provide Apple's sign-in controller.
    // We only present that controller after the player explicitly taps RANKING.
    func prepareAuthentication() {
        guard !authenticationConfigured else { return }
        authenticationConfigured = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let viewController {
                    self.authenticationViewController = viewController

                    if self.wantsToOpenRanking {
                        self.presentAuthenticationIfNeeded()
                    }
                    return
                }

                self.authenticationViewController = nil

                if GKLocalPlayer.local.isAuthenticated {
                    if !self.didSyncThisSession {
                        self.didSyncThisSession = true
                        self.syncStoredProgress()
                    }

                    if self.wantsToOpenRanking {
                        // The Game Center login sheet can report authentication before
                        // its dismissal animation is fully complete. Wait until the app's
                        // root controller is free, then present the leaderboard.
                        self.scheduleRankingPresentation()
                    }
                    return
                }

                if error != nil {
                    self.wantsToOpenRanking = false
                    self.cancelPendingPresentation()
                }
            }
        }
    }

    func showRanking() {
        wantsToOpenRanking = true
        prepareAuthentication()

        if isAuthenticated {
            scheduleRankingPresentation()
        } else {
            presentAuthenticationIfNeeded()
        }
    }

    // Kept as an alias so older GameScene code remains source-compatible.
    func showDashboard() {
        showRanking()
    }

    func submitNormalScore(_ score: Int) {
        guard isAuthenticated, score > 0 else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [IDs.bestScoreLeaderboard]
        ) { _ in }
    }

    func submitDailyScore(_ score: Int) {
        guard isAuthenticated, score > 0 else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [IDs.dailyLeaderboard]
        ) { _ in }
    }

    func reportAchievements(
        score: Int,
        totalRuns: Int,
        totalNearMisses: Int,
        bestCombo: Int
    ) {
        guard isAuthenticated else { return }

        let achievements = [
            achievement(IDs.firstOrbit, progress: progress(score, target: 10)),
            achievement(IDs.gettingSerious, progress: progress(score, target: 50)),
            achievement(IDs.orbitMaster, progress: progress(score, target: 100)),
            achievement(IDs.untouchable, progress: progress(totalNearMisses, target: 10)),
            achievement(IDs.comboMaster, progress: progress(bestCombo, target: 4)),
            achievement(IDs.addicted, progress: progress(totalRuns, target: 100))
        ]

        // If achievements are not configured in App Store Connect yet, GameKit simply
        // returns an error here. It does not affect leaderboards or gameplay.
        GKAchievement.report(achievements) { _ in }
    }

    // MARK: - Authentication UI

    private func presentAuthenticationIfNeeded() {
        guard wantsToOpenRanking,
              !isAuthenticated,
              let controller = authenticationViewController else { return }

        Task { @MainActor in
            if controller.presentingViewController != nil {
                return
            }

            guard let presenter = AppPresenter.topViewController() else { return }
            presenter.present(controller, animated: true)
        }
    }

    // MARK: - Ranking UI

    private func scheduleRankingPresentation(attempt: Int = 0) {
        guard wantsToOpenRanking, isAuthenticated else { return }

        cancelPendingPresentation()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                guard self.wantsToOpenRanking,
                      self.isAuthenticated,
                      !self.isPresentingGameCenter else { return }

                guard let root = AppPresenter.rootViewController() else {
                    self.retryRankingPresentation(after: attempt)
                    return
                }

                // Authentication and other system sheets are presented from the root.
                // Do not stack the Game Center controller on top of one of them.
                if root.presentedViewController != nil {
                    self.retryRankingPresentation(after: attempt)
                    return
                }

                self.presentRanking(from: root)
            }
        }

        presentationRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.20 : 0.30), execute: workItem)
    }

    @MainActor
    private func retryRankingPresentation(after attempt: Int) {
        guard attempt < 12 else {
            wantsToOpenRanking = false
            cancelPendingPresentation()
            return
        }

        scheduleRankingPresentation(attempt: attempt + 1)
    }

    @MainActor
    private func presentRanking(from presenter: UIViewController) {
        guard wantsToOpenRanking, isAuthenticated, !isPresentingGameCenter else { return }

        // Use GKGameCenterViewController instead of the iOS 18-specific
        // GKAccessPoint leaderboard trigger. This path works with our iOS 17
        // deployment target and opens the exact leaderboard configured in
        // App Store Connect.
        let controller = GKGameCenterViewController(
            leaderboardID: IDs.bestScoreLeaderboard,
            playerScope: .global,
            timeScope: .allTime
        )
        controller.gameCenterDelegate = self

        isPresentingGameCenter = true
        wantsToOpenRanking = false
        cancelPendingPresentation()
        presenter.present(controller, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true) { [weak self] in
            self?.isPresentingGameCenter = false
            NotificationCenter.default.post(name: .orbitGameCenterDidDismiss, object: nil)
        }
    }

    private func cancelPendingPresentation() {
        presentationRetryWorkItem?.cancel()
        presentationRetryWorkItem = nil
    }

    // MARK: - Progress sync

    private func achievement(_ identifier: String, progress: Double) -> GKAchievement {
        let achievement = GKAchievement(identifier: identifier)
        achievement.percentComplete = min(100, max(0, progress))
        achievement.showsCompletionBanner = true
        return achievement
    }

    private func progress(_ value: Int, target: Int) -> Double {
        guard target > 0 else { return 100 }
        return min(100, Double(value) / Double(target) * 100)
    }

    private func syncStoredProgress() {
        let defaults = UserDefaults.standard
        let bestScore = defaults.integer(forKey: "orbit.bestScore")
        let totalRuns = defaults.integer(forKey: "orbit.stats.totalRuns")
        let totalNearMisses = defaults.integer(forKey: "orbit.stats.totalNearMisses")
        let bestCombo = max(1, defaults.integer(forKey: "orbit.stats.bestCombo"))

        submitNormalScore(bestScore)

        if defaults.string(forKey: "orbit.daily.day") == utcDayString() {
            submitDailyScore(defaults.integer(forKey: "orbit.daily.best"))
        }

        reportAchievements(
            score: bestScore,
            totalRuns: totalRuns,
            totalNearMisses: totalNearMisses,
            bestCombo: bestCombo
        )
    }

    private func utcDayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: Date())

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}


extension Notification.Name {
    static let orbitGameCenterDidDismiss = Notification.Name("orbit.gameCenter.didDismiss")
}
