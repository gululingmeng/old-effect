
import UIKit
import BNBSdkApi
import BNBEffectPlayer
import BNBSdkCore
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Banuba SDK initialization.
        // Provide app-bundle paths where Banuba should search for resources (effects, modules, etc.)
        let main = Bundle.main.bundlePath
        let effects = main + "/effects"

        // 把相关 framework bundlePath 也给进去，避免“模型在 framework 里但找不到”
        let sdkApi = Bundle(for: BanubaSdkManager.self).bundlePath
        let effectPlayer = Bundle(for: Player.self).bundlePath
        let effectPlayerUI = Bundle(for: EffectPlayerView.self).bundlePath

        // Try to auto-detect FaceTracker resources (BNBFaceTracker.bundle / face_tracker.zip) in the app.
        // If these resources are missing, face detector will stay 0.
        var resourcePaths = [effects, main, sdkApi, effectPlayer, effectPlayerUI]

        if let subpaths = FileManager.default.subpaths(atPath: main) {
            let hits = subpaths.filter {
                let s = $0.lowercased()
                return s.contains("bnbfacetracker") || s.contains("face_tracker") || s.contains("facetracker")
            }
            if !hits.isEmpty {
                print("🔍 FaceTracker-related files in app bundle (first 20):", Array(hits.prefix(20)))
            } else {
                print("🔍 No FaceTracker resources found under app bundle. You likely need to add BNBFaceTracker dependency.")
            }

            // Add any discovered resource bundles to Banuba resourcePath.
            for rel in hits where rel.hasSuffix(".bundle") {
                resourcePaths.append(main + "/" + rel)
            }
        }

        BanubaSdkManager.initialize(
            resourcePath: resourcePaths,
            clientTokenString: banubaClientToken
        )
        if let lm = BNBLicenseManager.instance() ?? BNBLicenseManager.create(banubaClientToken) {
            print("🔑 Banuba checksum:", lm.getChecksum())
            print("🔑 Banuba isExpired:", lm.isExpired())
            print("🔑 Banuba license json:", lm.getJson())
        } else {
            print("🔑 BNBLicenseManager is nil (initialize 未生效或资源/模块缺失)")
        }

        return true
    }

    // UISceneSession Lifecycle
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
