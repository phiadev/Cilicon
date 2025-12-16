import Foundation

struct Config: Decodable {
    init(
        provisioner: ProvisionerConfig,
        hardware: HardwareConfig,
        directoryMounts: [DirectoryMountConfig],
        source: VMSource,
        vmClonePath: String,
        numberOfRunsUntilHostReboot: Int? = nil,
        runnerName: String? = nil,
        autoTransferImageVolume: String? = nil,
        instanceID: String? = nil,
        retryDelay: Int,
        sshCredentials: SSHCredentials,
        sshConnectMaxRetries: Int,
        preRun: String? = nil,
        postRun: String? = nil,
        consoleDevices: [String] = []
    ) {
        self.provisioner = provisioner
        self.hardware = hardware
        self.directoryMounts = directoryMounts
        self.source = source
        self.vmClonePath = vmClonePath
        self.numberOfRunsUntilHostReboot = numberOfRunsUntilHostReboot
        self.runnerName = runnerName
        self.autoTransferImageVolume = autoTransferImageVolume
        self.instanceID = instanceID
        self.retryDelay = retryDelay
        self.sshCredentials = sshCredentials
        self.sshConnectMaxRetries = sshConnectMaxRetries
        self.preRun = preRun
        self.postRun = postRun
        self.consoleDevices = consoleDevices
    }

    /// Provisioner Configuration.
    let provisioner: ProvisionerConfig
    /// Hardware Configuration.
    let hardware: HardwareConfig
    /// Directories to mount on the Guest OS.
    let directoryMounts: [DirectoryMountConfig]
    /// The path where the VM bundle is located.
    let source: VMSource
    /// The path where the cloned VM bundle for each run is located.
    /// This should be on the same APFS volume as `vmBundlePath`.
    /// Can be omitted, in which case it defaults to `~/vmclone`.
    let vmClonePath: String
    /// Number of runs until the Host machine reboots.
    let numberOfRunsUntilHostReboot: Int?
    /// Overrides the runner name chosen by the provisioner.
    let runnerName: String?
    /// The name of the volume to which the image should be transferred before provisioning.
    let autoTransferImageVolume: String?
    /// Optional identifier for the Cilicon instance when running multiple hosts concurrently.
    /// When set, this value is appended to clone paths and runner names to avoid collisions.
    let instanceID: String?
    /// Delay in seconds before retrying to provision the image a failed cycle.
    let retryDelay: Int
    /// Credentials to be used when connecting via SSH.
    let sshCredentials: SSHCredentials
    /// Maximum number of retries for SSH connection attempts.
    let sshConnectMaxRetries: Int
    /// A command to run before the provisioning commands are run.
    let preRun: String?
    /// A command to run after the provisioning commands are run.
    let postRun: String?
    /// A list of console device names that are going to be injected into the VM.
    let consoleDevices: [String]

    enum CodingKeys: CodingKey {
        case provisioner
        case hardware
        case directoryMounts
        case source
        case vmClonePath
        case numberOfRunsUntilHostReboot
        case runnerName
        case autoTransferImageVolume
        case instanceID
        case retryDelay
        case sshCredentials
        case sshConnectMaxRetries
        case preRun
        case postRun
        case consoleDevices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provisioner = try container.decode(ProvisionerConfig.self, forKey: .provisioner)
        self.hardware = try container.decodeIfPresent(HardwareConfig.self, forKey: .hardware) ?? .default
        self.directoryMounts = try container.decodeIfPresent([DirectoryMountConfig].self, forKey: .directoryMounts) ?? []
        self.source = try container.decode(VMSource.self, forKey: .source)
        self.vmClonePath = try (
            container.decodeIfPresent(String.self, forKey: .vmClonePath).map { ($0 as NSString).standardizingPath }
        ) ?? URL(filePath: NSHomeDirectory()).appending(component: "vmclone").path
        self.numberOfRunsUntilHostReboot = try container.decodeIfPresent(Int.self, forKey: .numberOfRunsUntilHostReboot)
        self.runnerName = try container.decodeIfPresent(String.self, forKey: .runnerName)
        self.autoTransferImageVolume = try container.decodeIfPresent(String.self, forKey: .autoTransferImageVolume)
        self.instanceID = try container.decodeIfPresent(String.self, forKey: .instanceID)
        self.retryDelay = try container.decodeIfPresent(Int.self, forKey: .retryDelay) ?? 5
        self.sshCredentials = try container.decodeIfPresent(SSHCredentials.self, forKey: .sshCredentials) ?? .default
        self.sshConnectMaxRetries = try container.decodeIfPresent(Int.self, forKey: .sshConnectMaxRetries) ?? 10
        self.preRun = try container.decodeIfPresent(String.self, forKey: .preRun)
        self.postRun = try container.decodeIfPresent(String.self, forKey: .postRun)
        self.consoleDevices = try container.decodeIfPresent([String].self, forKey: .consoleDevices) ?? []
    }

    /// Returns the effective instance identifier, trimmed and empty-string safe.
    var resolvedInstanceID: String? {
        guard let instanceID = instanceID?.trimmingCharacters(in: .whitespacesAndNewlines), !instanceID.isEmpty else {
            return nil
        }
        return instanceID
    }

    /// Computes a VM clone path that is unique for the current instance, if an instance ID is set.
    var instanceScopedVMClonePath: String {
        guard let resolvedInstanceID else { return vmClonePath }
        return URL(filePath: vmClonePath).appending(component: resolvedInstanceID).path
    }

    /// Returns the runner name with the instance ID appended to avoid collisions.
    /// - Parameter defaultName: The default name to fall back to when no runnerName is provided.
    func resolvedRunnerName(defaultName: String?) -> String {
        let baseName = runnerName ?? defaultName ?? "no-name"
        guard let resolvedInstanceID else { return baseName }
        return "\(baseName)-\(resolvedInstanceID)"
    }

    /// Returns a new config with the provided instance ID overriding the existing value if present.
    func withResolvedInstanceID(_ overrideID: String?) -> Config {
        let resolvedID = overrideID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Config(
            provisioner: provisioner,
            hardware: hardware,
            directoryMounts: directoryMounts,
            source: source,
            vmClonePath: vmClonePath,
            numberOfRunsUntilHostReboot: numberOfRunsUntilHostReboot,
            runnerName: runnerName,
            autoTransferImageVolume: autoTransferImageVolume,
            instanceID: resolvedID?.isEmpty == false ? resolvedID : instanceID,
            retryDelay: retryDelay,
            sshCredentials: sshCredentials,
            sshConnectMaxRetries: sshConnectMaxRetries,
            preRun: preRun,
            postRun: postRun,
            consoleDevices: consoleDevices
        )
    }
}

struct SSHCredentials: Codable {
    static let `default` = Self(username: "admin", password: "admin")
    let username: String
    let password: String
}
