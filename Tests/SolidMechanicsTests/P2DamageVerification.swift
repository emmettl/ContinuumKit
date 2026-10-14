import SolidMechanics
import Foundation

enum P2DamageVerification {
    static func run(_ args: [String]) throws {
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
        func value(_ d: [String: Any], _ k: String) -> Double { (d[k] as! NSNumber).doubleValue }
        let L = value(input,"length_m"), A = value(input,"width_m") * value(input,"thickness_m")
        let tol = value(input,"relative_tolerance")
        var checks = 0, maxError = 0.0, cases = 0
        func require(_ condition: Bool, _ label: String) throws {
            checks += 1; if !condition { throw NSError(domain:label,code:1) }
        }
        func compare(_ a: Double, _ b: Double, _ scale: Double, _ label: String) throws {
            let error = abs(a-b)/scale; maxError = max(maxError,error)
            try require(a.isFinite && error <= tol,"\(label): \(a) vs \(b), scaled error \(error)")
        }
        let lines = try String(contentsOfFile:args[2],encoding:.utf8).split(whereSeparator:{$0.isNewline})
        var csv = String(lines[0])+"\n"
        var nodesCSV = "mode,orientation,cells,increments,sign,step,node,x_m,displacement_m,reaction_N\n"
        var cellsCSV = "mode,orientation,cells,increments,sign,step,cell,band,strain,stress_Pa,stored_J,loss_J\n"
        var law: VeneerDamage!
        var accepted: VeneerDamage.State!
        var oldNodes = [Double](), oldForces = [Double](), externalWork = 0.0
        var lastKey = "", lastTarget = 0.0
        var endLoss: [String:Double] = [:]
        var peaks: [[String:Any]] = []
        let p1 = try OrthotropicPlaneStress(youngAlong:1e10,youngAcross:1e9,shear:5e8,poissonAlongAcross:0.25)
        let frame = try OrthotropicPlaneStress.Frame()
        for line in lines.dropFirst() {
            let c = line.split(separator:",").map(String.init)
            let mode = c[0], orientation = Int(c[1])!, n = Int(c[2])!, increments = Int(c[3])!, step = Int(c[5])!
            let h = L/Double(n), band = n/2-1
            let p = mode == "tension" ? (input["tension"] as! [[String:Any]]).first{value($0,"grain_deg")==Double(orientation)}! : input["shear"] as! [String:Any]
            let K = value(p,"K_Pa"), S = value(p,"strength_Pa"), G = value(p,"Gf_J_m2")
            let key = c.prefix(5).joined(separator:"/")
            if key != lastKey {
                law = try VeneerDamage(mode:mode == "tension" ? .tension : .shear,
                          modulus:K,strength:S,fractureEnergy:G,bandLength:h,maximumStrain:value(input,"maximum_strain"))
                accepted = law.zeroState; oldNodes = Array(repeating:0,count:n+1)
                oldForces = oldNodes; externalWork = 0; lastTarget = 0; lastKey = key; cases += 1
                let e = 0.0001
                let p1Strain: SIMD3<Double>
                if mode == "shear" { p1Strain = SIMD3(0,0,e) }
                else if orientation == 0 { p1Strain = SIMD3(e,-p1.poissonAlongAcross*e,0) }
                else { p1Strain = SIMD3(-p1.poissonAcrossAlong*e,e,0) }
                let elastic = try p1.evaluate(strain:p1Strain,grainAngleRadians:0,frame:frame)
                let result = try law.evaluate(strain:e,from:law.zeroState)
                try compare(result.stress,mode == "shear" ? elastic.stress.z : (orientation == 0 ? elastic.stress.x : elastic.stress.y),S,"P1 elastic limit")
                let other = try VeneerDamage(mode:law.mode,modulus:K,strength:S,fractureEnergy:G,bandLength:h*0.9)
                var rejected = false
                do { _ = try other.evaluate(strain:0,from:accepted) } catch { rejected = true }
                try require(rejected,"history transfer across band lengths")
            }
            let target = Double(c[6])!
            // Split prescribed band control at constitutive events so assembled
            // nodal work is exact even with one increment per leg or shear reversal.
            var cuts = [target]
            for point in [-law.failureStrain,-law.initiationStrain,-accepted.maximumEquivalentStrain,
                          0,accepted.maximumEquivalentStrain,law.initiationStrain,law.failureStrain] {
                if point > min(lastTarget,target) && point < max(lastTarget,target) { cuts.append(point) }
            }
            cuts.sort(); if target < lastTarget { cuts.reverse() }
            var finalStored = 0.0, finalLoss = 0.0
            var strains = [Double](), stresses = [Double](), energies = [Double]()
            for control in cuts {
                let old = accepted!
                let predicted = try law.evaluate(strain:control,from:old)
                var nodes = [0.0]
                for cell in 0..<n {
                    nodes.append(nodes.last! + h * (cell == band ? control : predicted.stress/K))
                }
                let bandStrain = (nodes[band+1]-nodes[band])/h
                let state = try law.evaluate(strain:bandStrain,from:old)
                var forces = Array(repeating:0.0,count:n+1)
                var stored = 0.0
                strains = []; stresses = []; energies = []
                for cell in 0..<n {
                    let e = (nodes[cell+1]-nodes[cell])/h
                    let stress = cell == band ? state.stress : K*e
                    let energy = cell == band ? state.energyDensity : 0.5*K*e*e
                    forces[cell] -= A*stress; forces[cell+1] += A*stress
                    stored += A*h*energy
                    strains.append(e); stresses.append(stress); energies.append(A*h*energy)
                }
                for i in 1..<n { try compare(forces[i],0,A*S,"interior equilibrium") }
                try compare(forces.reduce(0,+),0,A*S,"net reaction")
                try compare(forces.last!,A*state.stress,A*S,"assembled end traction")
                for i in nodes.indices { externalWork += 0.5*(oldForces[i]+forces[i])*(nodes[i]-oldNodes[i]) }
                let loss = A*h*state.dissipationDensity
                try compare(externalWork,stored+loss,A*G,"assembled external-work ledger")
                try compare(state.workDensity,state.energyDensity+state.dissipationDensity,G/h,"material work ledger")
                try require(state.damage >= old.damage-1e-14 && state.maximumEquivalentStrain >= old.maximumEquivalentStrain,"irreversible history")
                try require(state.dissipationDensity >= old.dissipationDensity-1e-10,"monotone loss")
                if state.maximumEquivalentStrain == old.maximumEquivalentStrain && bandStrain != old.strain {
                    try compare(state.stress-old.stress,(1-old.damage)*K*(bandStrain-old.strain),S,"damaged elastic unloading/reload")
                }
                if state.damage > 0 {
                    // Valid abandoned failure and invalid trial must leave history intact.
                    _ = try law.evaluate(strain:law.failureStrain,from:state)
                    for invalid in [Double.nan,Double.infinity,0.101] {
                        var rejected = false
                        do { _ = try law.evaluate(strain:invalid,from:state) } catch { rejected = true }
                        try require(rejected,"invalid trial")
                    }
                    let unchanged = try law.evaluate(strain:state.strain,from:state)
                    try compare(unchanged.damage,state.damage,1,"abandoned/rejected damage rollback")
                    try compare(unchanged.workDensity,state.workDensity,G/h,"abandoned/rejected work rollback")
                }
                accepted = state; oldNodes = nodes; oldForces = forces
                finalStored = stored; finalLoss = loss
            }
            let state = accepted!
            let actual = [state.strain,state.stress,state.damage,state.maximumEquivalentStrain,oldNodes.last!,oldForces.last!,finalStored,finalLoss,externalWork]
            let scales = [law.failureStrain,S,1,law.failureStrain,2*G/S,A*S,A*G,A*G,A*G]
            for i in actual.indices { try compare(actual[i],Double(c[i+6])!,scales[i],"reference \(key) step \(step) field \(i)") }
            csv += (Array(c.prefix(6))+actual.map{String(format:"%.17g",$0)}).joined(separator:",")+"\n"
            for i in oldNodes.indices { nodesCSV += (Array(c.prefix(6))+[String(i),String(Double(i)*h),String(oldNodes[i]),String(oldForces[i])]).joined(separator:",")+"\n" }
            for i in 0..<n { cellsCSV += (Array(c.prefix(6))+[String(i),String(i==band),String(strains[i]),String(stresses[i]),String(energies[i]),String(i == band ? finalLoss : 0)]).joined(separator:",")+"\n" }
            if step == 5*increments {
                // Fixed-history potential gradients audit the nodal force assembly
                // independently of the softening update, on a partially reloaded state.
                func fixedEnergy(_ u: [Double]) -> Double {
                    var energy = 0.0
                    for i in 0..<n {
                        let e = (u[i+1]-u[i])/h
                        energy += 0.5*A*h*K*(i == band ? 1-state.damage : 1)*e*e
                    }
                    return energy
                }
                let delta = 1e-7*L
                for i in oldNodes.indices {
                    var plus = oldNodes, minus = oldNodes
                    plus[i] += delta; minus[i] -= delta
                    try compare((fixedEnergy(plus)-fixedEnergy(minus))/(2*delta),oldForces[i],A*S,"fixed-history energy gradient")
                }
            }
            if step == 11*increments {
                try compare(state.damage,1,1,"complete failure")
                try compare(finalLoss,A*G,A*G,"declared fracture energy")
                try compare(finalStored,0,A*G,"final zero storage")
                let group = "\(mode)/\(orientation)"
                if let first = endLoss[group] { try compare(finalLoss,first,A*G,"mesh/partition/sign energy invariance") }
                else { endLoss[group] = finalLoss }
                peaks.append(["case":key,"fracture_energy_J_m2":finalLoss/A,"loss_J":finalLoss,"band_length_m":h])
            }
            lastTarget = target
        }
        for params in [(0.0,2e6,150.0,0.005),(5e8,0,150,0.005),(5e8,2e6,0,0.005),(5e8,2e6,150,0),(5e8,2e6,1,0.005),(Double.nan,2e6,150,0.005)] {
            var rejected = false
            do { _ = try VeneerDamage(mode:.shear,modulus:params.0,strength:params.1,fractureEnergy:params.2,bandLength:params.3) } catch { rejected = true }
            try require(rejected,"invalid parameters / brittle band domain")
        }
        var wrongLengthControls: [[String:Any]] = []
        for mode in ["tension", "shear"] {
            for orientation in [0,90] {
                let p = mode == "tension" ? (input["tension"] as! [[String:Any]]).first{value($0,"grain_deg")==Double(orientation)}! : input["shear"] as! [String:Any]
                let coarseH = L/4, fineH = L/8, G = value(p,"Gf_J_m2")
                // Deliberately keep the coarse softening strain on the fine mesh:
                // actual band volume halves, so the independent energy gate must fail.
                let wrong = try VeneerDamage(mode:mode == "tension" ? .tension : .shear,
                    modulus:value(p,"K_Pa"),strength:value(p,"strength_Pa"),fractureEnergy:G,bandLength:coarseH)
                let failed = try wrong.evaluate(strain:wrong.failureStrain,from:wrong.zeroState)
                let actualLoss = A*fineH*failed.dissipationDensity
                try compare(actualLoss,0.5*A*G,A*G,"wrong-length negative control halves loss")
                try require(abs(actualLoss-A*G)/(A*G) > tol,"wrong-length fracture gate must reject")
                wrongLengthControls.append(["mode":mode,"orientation":orientation,"observed_J_m2":actualLoss/A,"required_J_m2":G,"rejected_by_energy_gate":true])
            }
        }
        let tensile = try VeneerDamage(mode:.tension,modulus:1e9,strength:2e6,fractureEnergy:100,bandLength:0.005)
        var rejected = false
        do { _ = try tensile.evaluate(strain:-0.001,from:tensile.zeroState) } catch { rejected = true }
        try require(rejected,"tension branch excludes compression")
        for (name,content) in [("actual.csv",csv),("nodes.csv",nodesCSV),("cells.csv",cellsCSV)] { try content.write(toFile:args[3]+"/"+name,atomically:true,encoding:.utf8) }
        let report: [String:Any] = ["fixture_id":input["fixture_id"]!,"passed":true,"cases":cases,"samples":lines.count-1,"checks":checks,"maximum_scaled_error":maxError,"relative_tolerance":tol,"completed_fracture_cases":peaks,"wrong_band_length_controls":wrongLengthControls,"scope":input["scope"]!]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[3]+"/verification.json"))
        print("PASS \(cases) cases, \(lines.count-1) samples, \(checks) checks; max scaled error \(maxError)")
    }
}
