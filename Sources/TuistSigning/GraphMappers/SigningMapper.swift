import Foundation
import TSCBasic
import TuistCore
import TuistSupport

enum SigningMapperError: FatalError, Equatable {
    case appIdMismatch(String, String, String)

    var type: ErrorType {
        switch self {
        case .appIdMismatch:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .appIdMismatch(appId, developmentTeamId, bundleId):
            return "App id \(appId) does not correspond to \(developmentTeamId).\(bundleId). Make sure the provisioning profile has been added to the right target."
        }
    }
}

public class SigningMapper: ProjectMapping {
    private let signingFilesLocator: SigningFilesLocating
    private let signingMatcher: SigningMatching
    private let signingCipher: SigningCiphering

    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingMatcher: SigningMatcher(),
                  signingCipher: SigningCipher())
    }

    init(signingFilesLocator: SigningFilesLocating,
         signingMatcher: SigningMatching,
         signingCipher: SigningCiphering) {
        self.signingFilesLocator = signingFilesLocator
        self.signingMatcher = signingMatcher
        self.signingCipher = signingCipher
    }

    // MARK: - GraphMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let path = project.path
        guard
            try signingFilesLocator.locateSigningDirectory(from: path) != nil
        else {
            logger.debug("No signing artifacts found")
            return (project, [])
        }

        try signingCipher.decryptSigning(at: path, keepFiles: true)
        defer { try? signingCipher.encryptSigning(at: path, keepFiles: false) }

        let derivedDirectory = project.path.appending(component: Constants.derivedFolderName)
        let keychainPath = derivedDirectory.appending(component: Constants.signingKeychain)

        let (certificates, provisioningProfiles) = try signingMatcher.match(from: project.path)

        project.targets = try project.targets.map {
            try map(target: $0,
                    project: project,
                    keychainPath: keychainPath,
                    certificates: certificates,
                    provisioningProfiles: provisioningProfiles)
        }

        return (project, [])
    }

    // MARK: - Helpers

    private func map(target: Target,
                     project: Project,
                     keychainPath: AbsolutePath,
                     certificates: [TargetName: [ConfigurationName: Certificate]],
                     provisioningProfiles: [TargetName: [ConfigurationName: ProvisioningProfile]]) throws -> Target {
        var target = target
        let targetConfigurations = target.settings?.configurations ?? [:]
        let configurations: [BuildConfiguration: Configuration?] = try targetConfigurations
            .merging(project.settings.configurations,
                     uniquingKeysWith: { config, _ in config })
            .reduce(into: [:]) { dict, configurationPair in
                guard
                    let provisioningProfile = provisioningProfiles[target.name]?[configurationPair.key.name],
                    let certificate = certificates[target.name]?[configurationPair.key.name]
                else {
                    dict[configurationPair.key] = configurationPair.value
                    return
                }
                guard
                    provisioningProfile.appId == provisioningProfile.teamId + "." + target.bundleId
                else {
                    throw SigningMapperError.appIdMismatch(
                        provisioningProfile.appId,
                        provisioningProfile.teamId,
                        target.bundleId
                    )
                }
                let configuration = configurationPair.value ?? Configuration()
                var settings = configuration.settings
                settings["CODE_SIGN_STYLE"] = "Manual"
                settings["CODE_SIGN_IDENTITY"] = SettingValue(stringLiteral: certificate.name)
                settings["OTHER_CODE_SIGN_FLAGS"] = SettingValue(stringLiteral: "--keychain \(keychainPath.pathString)")
                settings["DEVELOPMENT_TEAM"] = SettingValue(stringLiteral: provisioningProfile.teamId)
                settings["PROVISIONING_PROFILE_SPECIFIER"] = SettingValue(stringLiteral: provisioningProfile.uuid)
                dict[configurationPair.key] = configuration.with(settings: settings)
            }

        target.settings = Settings(
            base: target.settings?.base ?? [:],
            configurations: configurations,
            defaultSettings: target.settings?.defaultSettings ?? .recommended
        )
        return target
    }
}
