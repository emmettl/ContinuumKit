#!/usr/bin/env python3
"""Make a private alpha.10 profiling module with explicit source/patch provenance."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--core',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
baseline='da7cb5f5ac642edc57e8433c6150dceca6b9edd9'
shutil.copytree(a.core/'Fixtures/MetalWaveThroughput',a.output)
folder=a.output/'Sources/ProfiledMetal';folder.mkdir(parents=True)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',baseline,'Sources/LinearAcousticsMetal'],cwd=a.core,text=True).splitlines()
provenance={}
for path in paths:
 raw=subprocess.check_output(['git','show',baseline+':'+path],cwd=a.core)
 text=raw.decode();patches=[]
 if path.endswith('MetalWaveStepper.swift'):
  def replace(old,new):
   global text
   assert text.count(old)==1,old
   patches.append({'old':old,'new':new});text=text.replace(old,new)
  replace('  private var invalidated = false', '''  private var invalidated = false
  var profileGroup = SIMD3<Int>(32,1,1)
  var profileCommands: [ProfileCommand] = []
  var profileDecodeSeconds = 0.0
  var profileMaximumThreads: Int { min(velocity.maxTotalThreadsPerThreadgroup, pressure.maxTotalThreadsPerThreadgroup) }''')
  replace('    var frames: [WaveObservationFrame] = []', '''    let profileStart = ContinuousClock().now
    defer { profileDecodeSeconds += profileSeconds(profileStart) }
    var frames: [WaveObservationFrame] = []''')
  replace('    let group = MTLSize(width: width, height: 1, depth: 1)', '''    guard profileGroup.x > 0, profileGroup.y > 0, profileGroup.z > 0,
      profileGroup.x * profileGroup.y * profileGroup.z <= profileMaximumThreads,
      profileGroup.x >= width else { throw MetalWaveError.commandEncodingFailed }
    let group = MTLSize(width: profileGroup.x, height: profileGroup.y, depth: profileGroup.z)''')
  replace('      let batch = min(remaining, 128)', '''      let profileEncodingStart = ContinuousClock().now
      let batch = min(remaining, 128)''')
  replace('''      encoder.endEncoding()
      do { try complete(commands) } catch {''','''      encoder.endEncoding()
      let profileEncoding = profileSeconds(profileEncodingStart)
      let profileWaitStart = ContinuousClock().now
      do { try complete(commands) } catch {''')
  replace('      pressureStepIndex += batch', '''      profileCommands.append(ProfileCommand(steps: batch, encodingSeconds: profileEncoding,
        commitWaitSeconds: profileSeconds(profileWaitStart),
        gpuStartSeconds: commands.gpuStartTime, gpuEndSeconds: commands.gpuEndTime))
      pressureStepIndex += batch''')
 target=folder/Path(path).relative_to('Sources/LinearAcousticsMetal');target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)
 provenance[path]={'originalSHA256':hashlib.sha256(raw).hexdigest(),'profiledSHA256':hashlib.sha256(text.encode()).hexdigest(),'patches':patches}
(folder/'Profile.swift').write_text('''import Foundation
struct ProfileCommand: Encodable {
 let steps: Int
 let encodingSeconds, commitWaitSeconds, gpuStartSeconds, gpuEndSeconds: Double
}
func profileSeconds(_ start: ContinuousClock.Instant) -> Double {
 let d = start.duration(to: ContinuousClock().now).components
 return Double(d.seconds) + Double(d.attoseconds)/1e18
}
''')
(a.output/'profile-source-provenance.json').write_text(json.dumps({'baseline':baseline,'files':provenance,'scope':'timing instrumentation and explicitly selected threadgroup only; all kernels, barriers, arithmetic, bounds, plans and clocks retained'},indent=2,sort_keys=True)+'\n')
