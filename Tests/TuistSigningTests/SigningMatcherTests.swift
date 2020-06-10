import TSCBasic
import TuistCore
import XCTest
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SigningMatcherTests: TuistUnitTestCase {
    var subject: SigningMatcher!
    var signingFilesLocator: MockSigningFilesLocator!
    var provisioningProfileParser: MockProvisioningProfileParser!
    var certificateParser: MockCertificateParser!

    override func setUp() {
        super.setUp()

        signingFilesLocator = MockSigningFilesLocator()
        provisioningProfileParser = MockProvisioningProfileParser()
        certificateParser = MockCertificateParser()

        subject = SigningMatcher(
            signingFilesLocator: signingFilesLocator,
            provisioningProfileParser: provisioningProfileParser,
            certificateParser: certificateParser
        )
    }

    override func tearDown() {
        super.tearDown()

        subject = nil
        signingFilesLocator = nil
        provisioningProfileParser = nil
        certificateParser = nil
    }

    func test_locates_certificates_from_entry_path() throws {
        // Given
        let entryPath = try temporaryPath()
        var locatePath: AbsolutePath?
        signingFilesLocator.locateUnencryptedCertificatesStub = {
            locatePath = $0
            return []
        }

        // When
        _ = try subject.match(from: entryPath)

        // Then
        XCTAssertEqual(entryPath, locatePath)
    }

    func test_match_returns_pairs() throws {
        // Given
        let debugConfiguration = "debug"
        let releaseConfiguration = "release"
        let publicKeyPath = AbsolutePath("/\(debugConfiguration).cer")
        let privateKeyPath = AbsolutePath("/\(debugConfiguration).p12")
        let releasePublicKeyPath = AbsolutePath("/\(releaseConfiguration).cer")
        let releasePrivateKeyPath = AbsolutePath("/\(releaseConfiguration).p12")
        signingFilesLocator.locateUnencryptedCertificatesStub = { _ in
            [
                publicKeyPath,
                releasePublicKeyPath,
            ]
        }
        signingFilesLocator.locateUnencryptedPrivateKeysStub = { _ in
            [
                privateKeyPath,
                releasePrivateKeyPath,
            ]
        }
        certificateParser.parseStub = { publicKey, privateKey in
            Certificate.test(publicKey: publicKey, privateKey: privateKey)
        }
        let expectedCertificates: [String: Certificate] = [
            debugConfiguration: Certificate.test(publicKey: publicKeyPath, privateKey: privateKeyPath),
            releaseConfiguration: Certificate.test(publicKey: releasePublicKeyPath, privateKey: releasePrivateKeyPath),
        ]

        let debugProvisioningProfilePath = AbsolutePath("/\(debugConfiguration).mobileprovision")
        let releaseProvisioningProfilePath = AbsolutePath("/\(releaseConfiguration).mobileprovision")
        signingFilesLocator.locateProvisioningProfilesStub = { _ in
            [
                debugProvisioningProfilePath,
                releaseProvisioningProfilePath,
            ]
        }
        let date = Date()
        let targetName = "TargetOne"
        provisioningProfileParser.parseStub = { profilePath in
            let configurationName: String
            if profilePath == debugProvisioningProfilePath {
                configurationName = debugConfiguration
            } else {
                configurationName = releaseConfiguration
            }
            return ProvisioningProfile.test(
                path: profilePath,
                targetName: targetName,
                configurationName: configurationName,
                expirationDate: date
            )
        }
        let expectedProvisioningProfiles: [String: [String: ProvisioningProfile]] = [
            targetName: [
                debugConfiguration: ProvisioningProfile.test(
                    path: debugProvisioningProfilePath,
                    targetName: targetName,
                    configurationName: debugConfiguration,
                    expirationDate: date
                ),
                releaseConfiguration: ProvisioningProfile.test(
                    path: releaseProvisioningProfilePath,
                    targetName: targetName,
                    configurationName: releaseConfiguration,
                    expirationDate: date
                ),
            ],
        ]

        // When
        let (certificates, provisioningProfiles) = try subject.match(from: try temporaryPath())

        // Then
        XCTAssertEqual(certificates, expectedCertificates)
        XCTAssertEqual(provisioningProfiles, expectedProvisioningProfiles)
    }
}
