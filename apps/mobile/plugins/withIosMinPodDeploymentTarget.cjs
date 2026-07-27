const fs = require("node:fs");
const path = require("node:path");

const { withDangerousMod } = require("expo/config-plugins");

const MARKER = "# t3code: raise pod deployment targets below the SDK-supported minimum";
const MIN_TARGET_BUMP = `${MARKER}
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |build_configuration|
        current_target = build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
        if current_target && current_target.to_f < 15.0
          build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        end
      end
    end
`;

// Some transitive pods (RNSVG resource bundles, GoogleUtilities privacy
// bundles, ReachabilitySwift) pin IPHONEOS_DEPLOYMENT_TARGET below iOS 15,
// which recent Xcode SDKs reject outright at build time.
module.exports = function withIosMinPodDeploymentTarget(config) {
  return withDangerousMod(config, [
    "ios",
    (nextConfig) => {
      const podfilePath = path.join(nextConfig.modRequest.platformProjectRoot, "Podfile");
      const podfile = fs.readFileSync(podfilePath, "utf8");

      if (podfile.includes(MARKER)) {
        return nextConfig;
      }

      const postInstallStart = "post_install do |installer|\n";
      if (!podfile.includes(postInstallStart)) {
        throw new Error("Unable to raise pod deployment targets: post_install is missing.");
      }

      fs.writeFileSync(
        podfilePath,
        podfile.replace(postInstallStart, `${postInstallStart}${MIN_TARGET_BUMP}`),
        "utf8",
      );
      return nextConfig;
    },
  ]);
};
