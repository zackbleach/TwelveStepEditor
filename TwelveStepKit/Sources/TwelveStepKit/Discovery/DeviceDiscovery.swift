// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

/// Role of a 12 Step port, derived from the names in `KMI_DevData.h`.
public enum TwelveStepPortRole: String, Sendable {
    case control     // "Control Surface" / "Port 1": configuration traffic
    case secondary   // "Expander", "Port 2", "TRS MIDI OUT", "CV Out"
    case bootloader
    case unknown     // name says 12 Step but role is unclear
}

public struct TwelveStepPortMatch: Equatable, Sendable {
    public let endpoint: EndpointInfo
    public let role: TwelveStepPortRole
    /// Generation inferred from the name only; the identity reply is authoritative.
    public let looksLikeGen2: Bool
}

public enum DeviceDiscovery {
    /// Lowercased, with spaces/punctuation removed, so "12 Step2 Control Surface" -> "12step2controlsurface".
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Candidate names for matching: display name, plain name, and device + endpoint combined
    /// (iOS may expose the device name and endpoint name separately).
    static func candidateNames(_ endpoint: EndpointInfo) -> [String] {
        var names = [endpoint.displayName, endpoint.name]
        if let device = endpoint.deviceName { names.append("\(device) \(endpoint.name)") }
        return names.map(normalize)
    }

    public static func match(_ endpoint: EndpointInfo) -> TwelveStepPortMatch? {
        let names = candidateNames(endpoint)
        guard names.contains(where: { $0.contains("12step") }) else { return nil }

        let role: TwelveStepPortRole
        if names.contains(where: { $0.contains("bootloader") }) {
            role = .bootloader
        } else if names.contains(where: { $0.contains("controlsurface") || $0.hasSuffix("port1") }) {
            role = .control
        } else if names.contains(where: { $0.contains("expander") || $0.hasSuffix("port2") || $0.contains("trs") || $0.contains("cvout") }) {
            role = .secondary
        } else {
            role = .unknown
        }
        return TwelveStepPortMatch(endpoint: endpoint, role: role,
                                   looksLikeGen2: names.contains { $0.contains("12step2") })
    }

    public static func matches(in endpoints: [EndpointInfo]) -> [TwelveStepPortMatch] {
        endpoints.compactMap(match)
    }

    /// Best endpoint for configuration traffic: the control port, else the bootloader port,
    /// else an unrecognised-role 12 Step port. Never a secondary port.
    public static func preferredControlEndpoint(in endpoints: [EndpointInfo]) -> EndpointInfo? {
        let found = matches(in: endpoints).filter { !$0.endpoint.isOffline }
        for role in [TwelveStepPortRole.control, .bootloader, .unknown] {
            if let match = found.first(where: { $0.role == role }) { return match.endpoint }
        }
        return nil
    }
}
