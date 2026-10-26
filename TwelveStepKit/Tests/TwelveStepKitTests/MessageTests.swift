import Testing
@testable import TwelveStepKit

struct SafetyPolicyTests {
    @Test func allowsOnlyReadOnlyQueries() {
        for command in SafeCommand.allCases {
            #expect(SendPolicy.isAllowed(command.bytes))
        }
    }

    @Test func rejectsKnownWriteAndModeMessages() {
        #expect(!SendPolicy.isAllowed(TwelveStepMessages.enterBootloader))
        #expect(!SendPolicy.isAllowed(TwelveStepMessages.tetherOn))
        #expect(!SendPolicy.isAllowed(TwelveStepMessages.tetherOff))
        #expect(!SendPolicy.isAllowed(TwelveStepMessages.standaloneOn))
        let resetCV = KMIFraming.encode(KMIPacket(pid: 22, category: 1, type: KMICalibrationType.resetCVCalToFactory))
        #expect(!SendPolicy.isAllowed(resetCV))
        #expect(!SendPolicy.isAllowed([0xC0, 0x05]))
    }

    @Test func legacyQueryMatchesSource() {
        let query = TwelveStepMessages.legacyFirmwareQuery
        #expect(query.count == 67)
        #expect(Array(query.prefix(6)) == [0xF0, 0x00, 0x01, 0x55, 0x7A, 0x14])
        #expect(Array(query.suffix(10)) == [0x01, 0x00, 0x00, 0x00, 0x00, 0x04, 0x40, 0x00, 0x30, 0xF7])
    }
}

struct IdentityReplyTests {
    let sample: [UInt8] = [0xF0, 0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x5F, 22, 0x00,
                           0x00, 0x00, 1, 0, 2, 1, 0, 9, 0xF7]

    @Test func parsesEditorOffsets() throws {
        let reply = try #require(IdentityReply(sample))
        #expect(reply.isKMI)
        #expect(reply.product == .twelveStep2)
        #expect(reply.bootloaderMode == false)
        #expect(reply.bootloaderString == "1.0.2")
        #expect(reply.firmwareString == "1.0.9")
    }

    @Test func toleratesShortReplies() throws {
        let reply = try #require(IdentityReply([0xF0, 0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x5F, 20, 0xF7]))
        #expect(reply.product == .twelveStep1)
        #expect(reply.firmwareVersion == nil)
    }

    @Test func rejectsRequestAndOtherSysEx() {
        #expect(IdentityReply(TwelveStepMessages.identityRequest) == nil)
        #expect(IdentityReply(TwelveStepMessages.tetherOn) == nil)
        #expect(!SafeCommand.identityRequest.isReply(TwelveStepMessages.identityRequest))
        #expect(SafeCommand.identityRequest.isReply(sample))
    }

    @Test func detectsBootloaderMode() throws {
        var bytes = sample
        bytes[9] = 1
        #expect(try #require(IdentityReply(bytes)).bootloaderMode == true)
    }
}

struct ClassifierTests {
    @Test func classifiesPerformanceMessages() {
        #expect(MessageClassifier.classify([0x90, 60, 100]).summary == "Note On ch1 C4 (60) vel 100")
        #expect(MessageClassifier.classify([0x91, 60, 0]).summary.hasPrefix("Note Off ch2"))
        #expect(MessageClassifier.classify([0xB0, 7, 64]).kind == .performance)
        #expect(MessageClassifier.classify([0xC9, 0]).summary.contains("ch10 0"))
    }

    @Test func classifiesConfigurationTraffic() {
        #expect(MessageClassifier.classify(TwelveStepMessages.identityRequest).kind == .configuration)
        #expect(MessageClassifier.classify(TwelveStepMessages.tetherOn).summary.contains("tether on/off"))
        #expect(MessageClassifier.classify(TwelveStepMessages.cvCalibrationRequest).summary.contains("CV calibration request"))
        #expect(MessageClassifier.classify([0xF0, 0x43, 0x10, 0xF7]).kind == .sysex)
        #expect(MessageClassifier.classify([0xF8]).kind == .realtime)
    }
}

struct DiscoveryTests {
    func endpoint(_ display: String, name: String? = nil, device: String? = nil, offline: Bool = false) -> EndpointInfo {
        EndpointInfo(id: Int32(display.hashValue & 0x7FFF_FFFF), direction: .destination, name: name ?? display,
                     displayName: display, deviceName: device, isOffline: offline)
    }

    @Test(arguments: [
        ("12Step Control Surface", TwelveStepPortRole.control),
        ("12 Step2 Control Surface", .control),
        ("12Step Port 1", .control),
        ("12Step Expander", .secondary),
        ("12 Step2 TRS MIDI OUT", .secondary),
        ("12Step Port 2", .secondary),
        ("12 Step Bootloader", .bootloader),
        ("12Step", .unknown),
    ])
    func matchesKnownPortNames(name: String, role: TwelveStepPortRole) throws {
        #expect(try #require(DeviceDiscovery.match(endpoint(name))).role == role)
    }

    @Test func matchesWhenDeviceAndEndpointNamesAreSeparate() throws {
        let match = try #require(DeviceDiscovery.match(endpoint("Control Surface", device: "12Step")))
        #expect(match.role == .control)
    }

    @Test func ignoresOtherDevices() {
        #expect(DeviceDiscovery.match(endpoint("SoftStep Control Surface")) == nil)
        #expect(DeviceDiscovery.match(endpoint("Network Session 1")) == nil)
    }

    @Test func prefersControlPortAndSkipsOffline() {
        let endpoints = [endpoint("12Step Expander"), endpoint("12Step Control Surface", offline: true),
                         endpoint("12 Step2 Control Surface")]
        #expect(DeviceDiscovery.preferredControlEndpoint(in: endpoints)?.displayName == "12 Step2 Control Surface")
    }
}
