import SolidMechanics
import Foundation

enum P2CompressionVerification {
    static func run(_ args: [String]) throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
        let materials = input["materials"] as! [[String: Any]]
        func number(_ m: [String: Any], _ key: String) -> Double { (m[key] as! NSNumber).doubleValue }
        let tolerance = number(input, "relative_tolerance")
        var checks = 0, maximumError = 0.0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw NSError(domain: message, code: 1) }
        }
        func compare(_ actual: Double, _ expected: Double, _ scale: Double, _ label: String) throws {
            let error = abs(actual - expected) / scale
            maximumError = max(maximumError, error)
            try require(actual.isFinite && error <= tolerance, label)
        }
        let p1 = try OrthotropicPlaneStress(youngAlong: 1e10, youngAcross: 1e9, shear: 5e8, poissonAlongAcross: 0.25)
        let frame = try OrthotropicPlaneStress.Frame()
        let text = try String(contentsOfFile: args[2], encoding: .utf8)
        let lines = text.split(whereSeparator: { $0.isNewline })
        var output = String(lines[0]) + "\n"
        var previous: VeneerCompression.State?
        var law: VeneerCompression?
        var lastKey = ""
        var endpoints: [String: [Double]] = [:]
        var caseCount = 0
        for line in lines.dropFirst() {
            let cells = line.split(separator: ",").map(String.init)
            let axis = cells[0], control = cells[1], increments = cells[2], step = Int(cells[3])!
            let m = materials.first { $0["axis"] as! String == axis }!
            let E = number(m,"E_Pa"), Y = number(m,"Y_Pa")
            let H = control == "linear" ? number(m,"H_Pa") : 0
            let key = "\(axis)/\(control)/\(increments)"
            if key != lastKey {
                law = try VeneerCompression(young:E, yieldStress:Y, hardening:H,
                      minimumStrain:number(input,"minimum_strain"), maximumStrain:number(input,"maximum_strain"))
                previous = law!.zeroState; lastKey = key; caseCount += 1
            }
            let model = law!, old = previous!, strain = Double(cells[4])!
            let state = try model.evaluate(strain:strain, from:old)
            let L = number(input,"gauge_length_m"), A = number(input,"width_m")*number(input,"thickness_m")
            let actual = [state.strain,state.stress,state.alpha,state.elasticEnergyDensity,
                          state.hardeningEnergyDensity,state.dissipationDensity,state.workDensity,
                          L*state.strain,A*state.stress,A*L*state.workDensity]
            let scales = [0.03,Y,0.03,Y*0.03,Y*0.03,Y*0.03,Y*0.03,L*0.03,A*Y,A*L*Y*0.03]
            for i in actual.indices { try compare(actual[i],Double(cells[i+4])!,scales[i],"reference \(key) step \(step) column \(i)") }
            try require(state.alpha >= old.alpha && state.dissipationDensity >= old.dissipationDensity,"monotone history")
            try require(-state.stress <= Y+H*state.alpha+tolerance*Y,"yield consistency")
            try compare(state.workDensity,state.elasticEnergyDensity+state.hardeningEnergyDensity+state.dissipationDensity,Y*0.03,"work ledger")
            if state.alpha == old.alpha && strain != old.strain {
                try compare((state.stress-old.stress)/(strain-old.strain),E,E,"elastic loading/unloading slope")
            }
            if step == 8*Int(increments)! {
                try compare(state.stress,0,Y,"zero stress after unloading")
                try compare(state.strain,-state.alpha,0.03,"permanent strain")
                try require(state.alpha > 0 && state.dissipationDensity > 0,"irreversibility")
                let endKey = "\(axis)/\(control)"
                if let baseline = endpoints[endKey] {
                    for i in actual.indices { try compare(actual[i],baseline[i],scales[i],"partition independence") }
                } else { endpoints[endKey] = actual }
            }
            // P1 elastic reduction at a small admissible compressive strain.
            if step == 0 {
                let e = -0.0001
                let tensor = axis == "along" ? SIMD3(e,-p1.poissonAlongAcross*e,0) : SIMD3(-p1.poissonAcrossAlong*e,e,0)
                let p1Result = try p1.evaluate(strain:tensor,grainAngleRadians:0,frame:frame)
                let small = try model.evaluate(strain:e,from:model.zeroState)
                try compare(small.stress,axis == "along" ? p1Result.stress.x : p1Result.stress.y,Y,"P1 uniaxial elastic reduction")
                for invalid in [Double.nan,Double.infinity,-Double.infinity,-0.031,0.002] {
                    var rejected = false
                    do { _ = try model.evaluate(strain:invalid,from:state) } catch { rejected = true }
                    try require(rejected,"invalid strain rejection")
                }
                let other = try VeneerCompression(young:E*2,yieldStress:Y,hardening:H)
                var rejected = false
                do { _ = try other.evaluate(strain:0,from:state) } catch { rejected = true }
                try require(rejected,"incompatible state rejection")
            }
            // Abandon a valid deep trial and reject invalid ones from plastic history.
            // Re-evaluating the accepted strain must return the unchanged state.
            if state.alpha > 0 {
                _ = try model.evaluate(strain:-0.03,from:state)
                do { _ = try model.evaluate(strain:-0.04,from:state); throw NSError(domain:"accepted invalid trial",code:1) }
                catch VeneerCompression.MaterialError.invalidTrial { }
                let unchanged = try model.evaluate(strain:strain,from:state)
                try compare(unchanged.alpha,state.alpha,0.03,"trial rollback alpha")
                try compare(unchanged.workDensity,state.workDensity,Y*0.03,"trial rollback work")
            }
            output += ([axis,control,increments,String(step)]+actual.map{String(format:"%.17g",$0)}).joined(separator:",")+"\n"
            previous = state
        }
        for params in [(0.0,1.0,0.0),(1.0,0.0,0.0),(1.0,1.0,-1.0),(Double.nan,1.0,0.0),(Double.greatestFiniteMagnitude,1.0,Double.greatestFiniteMagnitude)] {
            var rejected = false
            do { _ = try VeneerCompression(young:params.0,yieldStress:params.1,hardening:params.2) } catch { rejected = true }
            try require(rejected,"invalid parameters")
        }
        try output.write(toFile:args[3]+"/actual.csv",atomically:true,encoding:.utf8)
        let report: [String:Any] = ["fixture_id":input["fixture_id"]!,"passed":true,"cases":caseCount,"samples":lines.count-1,"checks":checks,"maximum_scaled_error":maximumError,"relative_tolerance":tolerance,"scope":input["scope"]!]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[3]+"/verification.json"))
        print("PASS \(caseCount) cases, \(lines.count-1) samples, \(checks) checks; maximum scaled error \(maximumError)")
    }
}
