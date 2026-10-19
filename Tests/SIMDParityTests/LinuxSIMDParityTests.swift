import Foundation
import Testing

/// Whether the Linux stand-in for simd (Sources/LinuxSIMD) gives Apple's results bit for bit.
/// `SIMDParity` digests each function's results over fixed inputs, and `recorded` holds the
/// stand-in's digests. On Linux this guards the stand-in; on the Mac the same calls reach Apple's
/// simd, so a difference there means Linux's results differ from the Mac's in that function.
@Suite struct LinuxSIMDParityTests {
  /// The stand-in's digests. `CONTINUUMKIT_RECORD_SIMD=1 swift test --filter
  /// LinuxSIMDParityTests` prints them on Linux. These were taken on 19 October 2026 on a Mac
  /// Studio (macOS 27 SDK, debug build) with Sources/LinuxSIMD compiled in place of simd, where
  /// 69 of the 70 matched Apple's simd and only `inverse.double3x3` did not. For a function that
  /// calls no C maths library, that is also the stand-in's result on Linux. The three rows that
  /// go through Glibc's sine, cosine or arc tangent (`quatd.angle`, `quatd.angle_axis`,
  /// `quatf.angle_axis`) are instead the Linux digests (x86_64, Swift 6.4) that BombCAD recorded
  /// for the same arithmetic in its Tests/BlastModelTests/LinuxSIMDParityTests.swift. Its other
  /// 36 rows are the same as these, except `inverse.double3x3`, whose cross products the
  /// stand-in now fuses.
  static let recorded: [String: UInt64] = [
    "abs.float3": 0x4685_72cb_a753_d04f,
    "ceil_trunc_floor.double3": 0x700f_16e8_7fa2_2b4d,
    "clamp.double": 0x5a6c_a1b0_649c_0658,
    "clamp.float3": 0x434a_aad4_99c0_c5d7,
    "cross.double3": 0xe2d5_55fd_d87d_d4d2,
    "cross.float3": 0x4645_4d9f_16ca_8615,
    "determinant.double3x3": 0x6e3c_a638_7c63_9e5b,
    "determinant.float3x3": 0x26d0_9418_34c2_d001,
    "distance.double3": 0x13b1_eaef_5644_eab7,
    "distance.float3": 0x2f24_3510_af12_04ce,
    "distance_squared.float3": 0x2b76_831f_87e3_6c6f,
    "dot.double3": 0xa95f_1148_a0a6_43f5,
    "dot.double4": 0x737f_cf22_6ff9_d96f,
    "dot.float2": 0x1b43_029c_9e02_f949,
    "dot.float3": 0x30c5_4bf9_c304_d76e,
    "equal.double3x3": 0xccc9_b7a4_f654_e105,
    "floor.float3": 0x3d1a_bfdf_1377_461b,
    "inverse.double3x3": 0xc82b_bf96_ee84_618d,
    "length.double3": 0x599a_39b3_72ff_9344,
    "length.float2": 0x8601_cb4c_575d_5a26,
    "length.float3": 0x7b94_c09a_b3b6_cea4,
    "length_squared.double3": 0x6c25_47be_3f57_1834,
    "matrix.matrix.double3x3": 0x758a_7b04_484a_d512,
    "matrix.matrix.float3x3": 0xa804_8b2d_314b_356a,
    "matrix.quatd.double3x3": 0xaf04_b555_1147_b817,
    "matrix.vector.double3x3": 0x8fce_0181_f450_4c90,
    "matrix.vector.float3x3": 0x66f0_9342_b21b_0e12,
    "max.double": 0x2d25_ad9c_85bf_86d8,
    "max.double3": 0x92a7_b951_f94d_6026,
    "min.float": 0xd592_8736_b934_8eaf,
    "min.float3": 0xbd2a_3fa6_f1be_6835,
    "min_max_clamp.int3": 0x5afc_8d9d_0671_2144,
    "negate.double3x3": 0xf595_06bf_17f5_e383,
    "normalize.double3": 0x6369_bce9_1ce5_ff3d,
    "normalize.float2": 0x7f40_637b_5b43_f271,
    "normalize.float3": 0x7eaf_55a8_914d_87b4,
    "overlay.abs.double3": 0x6ea2_479e_3159_6276,
    "overlay.cross_dot.double3": 0xa912_2e01_fbcd_e08a,
    "product.assign.double3x3": 0x758a_7b04_484a_d512,
    "quatd.act": 0xa120_1eed_b98e_57e7,
    "quatd.angle": 0xffee_9c7a_2e21_163b,
    "quatd.angle_axis": 0x4117_d6a4_cf6f_0ef9,
    "quatd.axis": 0x6369_bce9_1ce5_ff3d,
    "quatd.conjugate_length": 0x5160_75af_b064_3ded,
    "quatd.from_to": 0x61b_50cf_dd64_49b0,
    "quatd.from_to.opposite": 0xc70a_5cde_be92_d72e,
    "quatd.inverse": 0x3017_0e8a_ac40_9f3f,
    "quatd.normalized": 0xcd7e_ddaa_1eb7_8a12,
    "quatd.product": 0x2e79_1a95_b477_6825,
    "quatd.simd_act": 0xa120_1eed_b98e_57e7,
    "quatd.simd_inverse": 0x3017_0e8a_ac40_9f3f,
    "quatd.simd_mul": 0x2e79_1a95_b477_6825,
    "quatd.simd_normalize": 0xcd7e_ddaa_1eb7_8a12,
    "quatd.sum_scaled": 0x1baa_44b1_e27e_6ecb,
    "quatf.act": 0xfd37_5e3f_b7ba_a2fc,
    "quatf.angle_axis": 0xb902_84c8_0329_8bd0,
    "quatf.product": 0x7d82_6410_4f63_907f,
    "reduce_max.double3": 0xdb37_52ac_8690_d495,
    "reduce_min.float3": 0xe48_db39_113c_961a,
    "rows.diagonal.double3x3": 0x37d5_636e_fcc0_aeef,
    "scaled.double3x3": 0xdb86_d0c6_4382_40b5,
    "scaled.sum.float3x3": 0xf2e_3f61_e1e6_39a0,
    "simd_mul.matrix.double3x3": 0x758a_7b04_484a_d512,
    "simd_mul.vector.double3x3": 0x8fce_0181_f450_4c90,
    "subscript.double3x3": 0x5fff_4aba_0457_8598,
    "sum.difference.float3x3": 0x22c1_3f7e_83c6_f232,
    "sum.double3x3": 0xb7c_93fa_cd5a_5b31,
    "transpose.double3x3": 0x4580_c24c_c6e5_3b01,
    "transpose.float3x3": 0x2484_eb51_c7ff_be21,
    "vector.matrix.double3x3": 0xb30e_b3b4_5c18_c125,
  ]

  /// Functions whose results go through the C library's sine, cosine or arc tangent, or through
  /// Apple's matrix inverse, whose method is not published: Glibc and Apple may round these
  /// differently in the last place, so a difference is printed, not failed.
  static let unmatchable: Set<String> = [
    "inverse.double3x3", "quatd.angle_axis", "quatd.angle", "quatf.angle_axis",
  ]

  @Test func digestsMatchTheRecord() {
    let found = SIMDParity.digests()
    #expect(Set(found.keys) == Set(Self.recorded.keys))
    for (name, digest) in Self.recorded.sorted(by: { $0.key < $1.key }) {
      if Self.unmatchable.contains(name) {
        if found[name] != digest { print("LinuxSIMDParityTests: \(name) differs from the stand-in's record") }
        continue
      }
      #expect(found[name] == digest, "\(name) differs from the stand-in's record\(Self.hint(name, found[name]))")
    }
  }

  /// For the cross product, which of clang's two ways of compiling it this platform's is.
  static func hint(_ name: String, _ digest: UInt64?) -> String {
    guard name == "cross.float3" else { return "" }
    let variants = SIMDParity.crossVariants()
    if digest == variants.fused { return "; this platform fuses a*b - c*d, as the stand-in does" }
    if digest == variants.rounded { return "; this platform rounds each product, which the stand-in does not" }
    return "; it matches neither way of compiling it"
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["CONTINUUMKIT_RECORD_SIMD"] != nil))
  func record() {
    for (name, digest) in SIMDParity.digests().sorted(by: { $0.key < $1.key }) {
      // Grouped by four hexadecimal digits.
      let hex = String(String(digest, radix: 16).reversed())
      let groups = stride(from: 0, to: hex.count, by: 4).map { start in
        String(hex.dropFirst(start).prefix(4).reversed())
      }
      print("    \"\(name)\": 0x\(groups.reversed().joined(separator: "_")),")
    }
  }
}
