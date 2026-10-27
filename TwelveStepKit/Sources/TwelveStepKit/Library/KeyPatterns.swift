// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

/// Generates notes for all 13 keys at once.
///
/// The 12 Step's keys are one chromatic octave, C to C, and they stay that way: key 1 is always a
/// C, key 2 a C♯, … key 13 the next C. The scale's key (`tonic`) only decides which keys are in
/// the scale and which chord each plays: in F major with 7th chords, key 1 (C) plays C7 and
/// key 3 (D) plays Dm7. Keys outside the scale follow `outOfScale`.
public struct KeyPattern: Equatable, Sendable {
    public enum Layout: String, CaseIterable, Identifiable, Sendable {
        case chromatic = "Chromatic"
        case major = "Major"
        case minor = "Natural minor"
        case harmonicMinor = "Harmonic minor"
        case dorian = "Dorian"
        case mixolydian = "Mixolydian"
        case majorPentatonic = "Major pentatonic"
        case minorPentatonic = "Minor pentatonic"
        case blues = "Blues"

        public var id: String { rawValue }

        /// Semitone offsets of one octave of the scale.
        public var steps: [Int] {
            switch self {
            case .chromatic: Array(0..<12)
            case .major: [0, 2, 4, 5, 7, 9, 11]
            case .minor: [0, 2, 3, 5, 7, 8, 10]
            case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
            case .dorian: [0, 2, 3, 5, 7, 9, 10]
            case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
            case .majorPentatonic: [0, 2, 4, 7, 9]
            case .minorPentatonic: [0, 3, 5, 7, 10]
            case .blues: [0, 3, 5, 6, 7, 10]
            }
        }

        /// Semitones above the root for scale degree `degree` (0-based, may exceed one octave).
        public func offset(ofDegree degree: Int) -> Int {
            let steps = self.steps
            let octave = Int((Double(degree) / Double(steps.count)).rounded(.down))
            return steps[((degree % steps.count) + steps.count) % steps.count] + 12 * octave
        }

        /// The degree number for a semitone above the root, or nil if it isn't in the scale.
        public func degree(ofSemitone semitone: Int) -> Int? {
            let octave = Int((Double(semitone) / 12).rounded(.down))
            return steps.firstIndex(of: ((semitone % 12) + 12) % 12).map { $0 + steps.count * octave }
        }
    }

    public enum Voicing: String, CaseIterable, Identifiable, Sendable {
        case single = "Single note"
        case octaves = "Octaves"
        case fifths = "Fifths (power)"
        case triads = "Triads"
        case sevenths = "7th chords"
        case custom = "Custom intervals"

        public var id: String { rawValue }
    }

    /// What keys outside the scale play.
    public enum OutOfScale: String, CaseIterable, Identifiable, Sendable {
        case silent = "Silent"
        case nearest = "Nearest scale note"
        case leadingDiminished = "Diminished 7th"
        case secondaryDominant = "Secondary dominant"

        public var id: String { rawValue }

        public var explanation: String {
            switch self {
            case .silent: "Keys outside the scale play nothing."
            case .nearest: "Keys outside the scale play the nearest scale note (the one below when it's a tie), with the same voicing."
            case .leadingDiminished: "Keys outside the scale play a diminished 7th built on that key, leading up to the next scale chord."
            case .secondaryDominant: "Keys outside the scale play the dominant 7th of the next scale note up, with that key's note in the bass."
            }
        }
    }

    /// Octave of key 1, which always plays a C (2 → C2 = 48, as in the factory presets; C3 = 60).
    public var octave: Int
    /// The scale's key as a pitch class (0 = C … 11 = B). Key 1 stays C whatever the key.
    public var tonic: Int
    public var layout: Layout
    public var voicing: Voicing
    public var outOfScale: OutOfScale
    /// Semitones added above each key's note when the voicing is `.custom` (e.g. [7, 12]).
    public var customIntervals: [Int]

    public init(octave: Int = 2, tonic: Int = 0, layout: Layout = .chromatic, voicing: Voicing = .single,
                outOfScale: OutOfScale = .silent, customIntervals: [Int] = [7]) {
        self.octave = octave
        self.tonic = tonic
        self.layout = layout
        self.voicing = voicing
        self.outOfScale = outOfScale
        self.customIntervals = customIntervals
    }

    /// MIDI note of key 1 (the C).
    public var keyOneNote: Int { NoteNames.c(inOctave: octave) }
    /// MIDI note of the tonic in key 1's octave; scale degrees are measured from here.
    private var root: Int { keyOneNote + tonic }

    /// Notes for each key, index 0 = key 1 (C). Each key holds at most 5 notes within 0...127.
    public func notesForKeys() -> [[Int]] {
        (0..<Preset.keyCount).map { keyIndex in
            let semitone = keyIndex - tonic // relative to the tonic; negative below it
            let notes: [Int]
            if let degree = layout.degree(ofSemitone: semitone) {
                notes = voiced(degree: degree)
            } else {
                notes = outOfScaleNotes(semitone: semitone)
            }
            var seen = Set<Int>()
            let unique = notes.filter { (0...127).contains($0) && seen.insert($0).inserted }
            return Array(unique.prefix(Preset.notesPerKey))
        }
    }

    /// True if key `index` (0-based) is outside the scale.
    public func isOutOfScale(keyIndex index: Int) -> Bool {
        layout.degree(ofSemitone: index - tonic) == nil
    }

    // MARK: Voicing

    private func voiced(degree: Int) -> [Int] {
        let base = root + layout.offset(ofDegree: degree)
        switch voicing {
        case .single: return [base]
        case .octaves: return [base, base + 12]
        case .fifths: return [base, base + 7]
        case .custom: return [base] + customIntervals.map { base + $0 }
        case .triads: return stacked(degree: degree, count: 3)
        case .sevenths: return stacked(degree: degree, count: 4)
        }
    }

    /// Stacks scale thirds on a degree. For the chromatic layout, a major triad / dominant 7th.
    private func stacked(degree: Int, count: Int) -> [Int] {
        if layout == .chromatic {
            let base = root + degree
            return Array([base, base + 4, base + 7, base + 10].prefix(count))
        }
        return (0..<count).map { root + layout.offset(ofDegree: degree + 2 * $0) }
    }

    // MARK: Out-of-scale keys

    private func outOfScaleNotes(semitone: Int) -> [Int] {
        let base = root + semitone
        switch outOfScale {
        case .silent:
            return []
        case .nearest:
            var below = semitone - 1
            while layout.degree(ofSemitone: below) == nil { below -= 1 }
            var above = semitone + 1
            while layout.degree(ofSemitone: above) == nil { above += 1 }
            let nearest = above - semitone < semitone - below ? above : below // ties go down
            return voiced(degree: layout.degree(ofSemitone: nearest)!)
        case .leadingDiminished:
            return [base, base + 3, base + 6, base + 9]
        case .secondaryDominant:
            var target = semitone + 1
            while layout.degree(ofSemitone: target) == nil { target += 1 }
            // V7 of the target: root a fifth above it; tones 0, 4, 7, 10.
            let dominantRoot = root + target + 7
            let pitchClasses = [0, 4, 7, 10].map { (dominantRoot + $0) % 12 }
            // Put the chord tone closest above (or on) the key's note in the bass.
            let bass = pitchClasses.map { base + ((($0 - base) % 12) + 12) % 12 }.min()!
            return pitchClasses.map { bass + ((($0 - bass) % 12) + 12) % 12 }.sorted()
        }
    }

    /// Parses "+7 +12" or "7, 12" into intervals; ignores anything that isn't a number.
    public static func parseIntervals(_ text: String) -> [Int] {
        text.split(whereSeparator: { " ,;".contains($0) }).compactMap { Int($0.replacingOccurrences(of: "+", with: "")) }
    }
}

extension Preset {
    public mutating func apply(_ pattern: KeyPattern) {
        for (index, notes) in pattern.notesForKeys().enumerated() {
            setNotes(notes, forKey: index + 1)
        }
    }
}
