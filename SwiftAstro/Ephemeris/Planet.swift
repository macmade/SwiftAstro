/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Foundation

/// A planet whose position this library can compute.
///
/// Every planet observable from Earth is covered (all but Earth itself). Their
/// low-precision orbital elements (after Schlyter) are good to roughly an
/// arc-minute for the inner planets and a fraction of a degree for the outer
/// ones, whose larger mutual perturbations are not modelled — ample for deciding
/// whether a planet is above the horizon.
public enum Planet: String, CaseIterable, Sendable
{
    /// Mercury.
    case mercury

    /// Venus.
    case venus

    /// Mars.
    case mars

    /// Jupiter.
    case jupiter

    /// Saturn.
    case saturn

    /// Uranus.
    case uranus

    /// Neptune.
    case neptune

    /// A human-readable name, e.g. `"Jupiter"`.
    public var name: String
    {
        self.rawValue.capitalized
    }

    /// The planet's astronomical symbol, e.g. `♂` for Mars.
    ///
    /// Uranus uses its astronomical symbol `⛢` (U+26E2) rather than the
    /// astrological `♅`; the other six are the same in both conventions.
    public var symbol: String
    {
        switch self
        {
            case .mercury: return "☿"
            case .venus:   return "♀"
            case .mars:    return "♂"
            case .jupiter: return "♃"
            case .saturn:  return "♄"
            case .uranus:  return "⛢"
            case .neptune: return "♆"
        }
    }

    /// The planet's heliocentric orbital elements at a day number.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The planet's elements.
    func elements( dayNumber d: Double ) -> OrbitalElements
    {
        switch self
        {
            case .mercury:
                return OrbitalElements(
                    longitudeOfAscendingNode: 48.3313  + 3.24587e-5   * d,
                    inclination:              7.0047   + 5.00e-8      * d,
                    argumentOfPerihelion:     29.1241  + 1.01444e-5   * d,
                    semiMajorAxis:            0.387098,
                    eccentricity:             0.205635 + 5.59e-10     * d,
                    meanAnomaly:              168.6562 + 4.0923344368 * d
                )

            case .venus:
                return OrbitalElements(
                    longitudeOfAscendingNode: 76.6799  + 2.46590e-5   * d,
                    inclination:              3.3946   + 2.75e-8      * d,
                    argumentOfPerihelion:     54.8910  + 1.38374e-5   * d,
                    semiMajorAxis:            0.723330,
                    eccentricity:             0.006773 - 1.302e-9     * d,
                    meanAnomaly:              48.0052  + 1.6021302244 * d
                )

            case .mars:
                return OrbitalElements(
                    longitudeOfAscendingNode: 49.5574  + 2.11081e-5   * d,
                    inclination:              1.8497   - 1.78e-8      * d,
                    argumentOfPerihelion:     286.5016 + 2.92961e-5   * d,
                    semiMajorAxis:            1.523688,
                    eccentricity:             0.093405 + 2.516e-9     * d,
                    meanAnomaly:              18.6021  + 0.5240207766 * d
                )

            case .jupiter:
                return OrbitalElements(
                    longitudeOfAscendingNode: 100.4542 + 2.76854e-5   * d,
                    inclination:              1.3030   - 1.557e-7     * d,
                    argumentOfPerihelion:     273.8777 + 1.64505e-5   * d,
                    semiMajorAxis:            5.20256,
                    eccentricity:             0.048498 + 4.469e-9     * d,
                    meanAnomaly:              19.8950  + 0.0830853001 * d
                )

            case .saturn:
                return OrbitalElements(
                    longitudeOfAscendingNode: 113.6634 + 2.38980e-5   * d,
                    inclination:              2.4886   - 1.081e-7     * d,
                    argumentOfPerihelion:     339.3939 + 2.97661e-5   * d,
                    semiMajorAxis:            9.55475,
                    eccentricity:             0.055546 - 9.499e-9     * d,
                    meanAnomaly:              316.9670 + 0.0334442282 * d
                )

            case .uranus:
                return OrbitalElements(
                    longitudeOfAscendingNode: 74.0005  + 1.3978e-5    * d,
                    inclination:              0.7733   + 1.9e-8       * d,
                    argumentOfPerihelion:     96.6612  + 3.0565e-5    * d,
                    semiMajorAxis:            19.18171 - 1.55e-8      * d,
                    eccentricity:             0.047318 + 7.45e-9      * d,
                    meanAnomaly:              142.5905 + 0.011725806  * d
                )

            case .neptune:
                return OrbitalElements(
                    longitudeOfAscendingNode: 131.7806 + 3.0173e-5    * d,
                    inclination:              1.7700   - 2.55e-7      * d,
                    argumentOfPerihelion:     272.8461 - 6.027e-6     * d,
                    semiMajorAxis:            30.05826 + 3.313e-8     * d,
                    eccentricity:             0.008606 + 2.15e-9      * d,
                    meanAnomaly:              260.2471 + 0.005995147  * d
                )
        }
    }
}
