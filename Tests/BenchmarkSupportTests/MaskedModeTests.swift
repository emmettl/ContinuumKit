import BenchmarkSupport
import Foundation
import Testing

@Suite("Independent masked box contracts") struct MaskedModeTests {
 let env = BenchmarkEnvironment(repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test", operatingSystem: "test")
 func setup(_ index: Int = 0) throws -> (MaskedModeCase, MaskedModeResolution, MaskedGrid, MaskedModeHistory) {
  let c = try MaskedModeCase.standard()[index]
  let r = MaskedModeResolution(axis: "time", nx: 16, ny: 8, nz: 8, steps: 256)
  let g = try MaskedGrid(c,r)
  return (c,r,g,MaskedModeHistory(fields: try MaskedModeOracle.history(c,r), inside: g.inside, faces: g.faces))
 }
 func result(_ c: MaskedModeCase,_ r: MaskedModeResolution,_ h: MaskedModeHistory) throws -> MaskedModeResult {
  try MaskedModeResult.evaluate(model: "test", c: c, r: r, environment: env, runtime: 0, h: h)
 }
 @Test("Integer occupancy agrees with independent physical volumes and closes the gap") func occupancy() throws {
  for index in 0...1 {
   let (c,_,g,_) = try setup(index)
   #expect(g.labels.filter{$0>=0}.count == (index == 0 ? 432 : 360))
   let volume = Double(g.labels.filter{$0>=0}.count)*g.spacing.reduce(1,*)
   #expect(abs(volume-c.boxes.reduce(0){$0+$1.lengths.reduce(1,*)})<1e-15)
   #expect(g.label([7,3,3]) == (index == 0 ? 0 : -1))
   #expect(g.faces[1024+6+16*(3+8*3)] == (index == 0 ? -1 : 0))
  }
 }
 @Test("Off-origin pressure uses local centre coordinates") func pressureGolden() throws {
  let (c,r,_,h) = try setup()
  let i=2+16*(1+8*1)
  let golden=cos(Double.pi/12)*pow(cos(Double.pi/12),2)
  #expect(abs(h.fields.frames[0].p[i]-golden)<1e-14)
  #expect(h.fields.frames[0].p[0]==100)
  #expect(try MaskedGrid(c,r).openFields[3].count==16*8*9)
 }
 @Test("Discrete quarter-cycle oscillator has independently computed frequency") func discreteGolden() throws {
  let (c,r,g,_) = try setup()
  let omega=320*sqrt(3)*2*sin(Double.pi/12)/g.spacing[0]
  let h=try MaskedModeOracle.history(c,r,dt:Double.pi/(2*omega),captures:[1])
  #expect(abs(h.frames[0].p[2+16*(1+8*1)])<1e-14)
  // z faces use their native half-step time and local coordinate.
  let i=2+16*(1+8*2)
  let golden=cos(Double.pi/12)*cos(Double.pi/12)*sin(Double.pi/6)/(400*sqrt(3))*sin(Double.pi/4)
  #expect(abs(h.frames[0].w[i]-golden)<1e-14)
 }
 @Test("Volume integration excludes padding and undriven chamber") func energyGolden() throws {
  for index in 0...1 {
   let (c,_,g,h)=try setup(index)
   let p=h.fields.frames[0].p
   let integrated=g.labels.indices.filter{g.labels[$0]>=0}.reduce(0.0){$0+p[$1]*p[$1]}*g.spacing.reduce(1,*)/(2*c.density*c.speed*c.speed)
   #expect(abs(integrated/c.energy-1)<1e-14)
  }
 }
 @Test("Inactive corruption is detected without diluting active field error") func poison() throws {
  let (c,r,g,h)=try setup()
  let f=h.fields
  let corrupt=RigidModeHistory(spacing:f.spacing,dt:f.dt,frames:f.frames.map{ frame in
   var p=frame.p;p[0]+=1
   return RigidModeFrame(step:frame.step,p:p,u:frame.u,v:frame.v,w:frame.w)
  })
  let good=try result(c,r,h)
  let bad=try result(c,r,MaskedModeHistory(fields:corrupt,inside:g.inside,faces:g.faces))
  #expect(good.errors!.fieldL2 == bad.errors!.fieldL2)
  #expect(good.errors!.initialEnergyError == bad.errors!.initialEnergyError)
  #expect(bad.errors!.inactivePreservationError==1)
  #expect(throws:BenchmarkFailure.self){try MaskedModeCommand.bounds(bad)}
 }
 @Test("Wrong occupancy and a falsely open wall cannot pass") func geometryRejection() throws {
  let (c,r,g,h)=try setup()
  var inside=g.inside;inside[0]=1
  #expect(throws:BenchmarkFailure.self){try result(c,r,MaskedModeHistory(fields:h.fields,inside:inside,faces:g.faces))}
  var faces=g.faces;faces[2+16*(1+8*1)] = -1
  #expect(throws:BenchmarkFailure.self){try result(c,r,MaskedModeHistory(fields:h.fields,inside:g.inside,faces:faces))}
 }
 @Test("Leakage and reversed z velocity have separate rejection evidence") func fieldRejection() throws {
  let (c,r,g,h)=try setup(1)
  let f=h.fields
  let broken=RigidModeHistory(spacing:f.spacing,dt:f.dt,frames:f.frames.map{ frame in
   var p=frame.p;p[9+16*(1+8*1)]=0.1
   return RigidModeFrame(step:frame.step,p:p,u:frame.u,v:frame.v,w:frame.w.map{-$0})
  })
  let bad=try result(c,r,MaskedModeHistory(fields:broken,inside:g.inside,faces:g.faces))
  #expect(bad.errors!.disconnectedLeakage==0.1)
  #expect(bad.errors!.fieldL2[3]>1.99)
  #expect(throws:BenchmarkFailure.self){try MaskedModeCommand.bounds(bad)}
 }
 @Test("Misaligned geometry, missing fields and malformed metrics fail explicitly") func invalid() throws {
  let (c,r,g,h)=try setup()
  #expect(throws:BenchmarkFailure.self){try MaskedGrid(c,MaskedModeResolution(axis:"space",nx:18,ny:9,nz:9,steps:64))}
  let f=h.fields
  let missing=RigidModeHistory(spacing:f.spacing,dt:f.dt,frames:f.frames.map{RigidModeFrame(step:$0.step,p:$0.p,u:$0.u,v:$0.v,w:[])})
  #expect(throws:BenchmarkFailure.self){try result(c,r,MaskedModeHistory(fields:missing,inside:g.inside,faces:g.faces))}
  var dict=try JSONSerialization.jsonObject(with:JSONEncoder().encode(result(c,r,h))) as! [String:Any]
  var errors=dict["errors"] as! [String:Any];errors["fieldL2"]=[];dict["errors"]=errors
  let bad=try JSONDecoder().decode(MaskedModeResult.self,from:JSONSerialization.data(withJSONObject:dict))
  #expect(throws:BenchmarkFailure.self){try MaskedModeCommand.check([bad,bad,bad])}
 }
}
