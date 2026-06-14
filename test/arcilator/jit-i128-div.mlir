// RUN: arcilator %s --run --jit-entry=entry 2>&1 | FileCheck %s
// REQUIRES: host-arch-x86_64

// Verify that 128-bit integer division and modulo are correctly handled by the
// JIT on all platforms, including Windows where the compiler-rt helpers
// (__divti3 et al.) are not available from the system runtime.
//
// Test: (3 << 64) / 3 == 2^64
//   udiv: lo=0, hi=1  (checks lane ordering; a swap gives lo=1, hi=0)
//   umod: (3<<64) mod 3 == 0
//   sdiv / smod: same values, positive operands, so signed == unsigned

module {
  hw.module @DivHarness(in %clk : !seq.clock, in %rst : i1,
                        in %a : i128, in %b : i128,
                        out qu : i128, out ru : i128,
                        out qs : i128, out rs : i128) {
    %qu = comb.divu %a, %b : i128
    %ru = comb.modu %a, %b : i128
    %qs = comb.divs %a, %b : i128
    %rs = comb.mods %a, %b : i128
    hw.output %qu, %ru, %qs, %rs : i128, i128, i128, i128
  }

  func.func @entry() {
    %c1  = hw.constant 1 : i128
    %c3  = hw.constant 3 : i128
    %c64 = hw.constant 64 : i128
    %a   = comb.shl %c3, %c64 : i128   // dividend = 3 << 64
    %exp = comb.shl %c1, %c64 : i128   // expected quotient = 2^64
    %false = hw.constant false
    %low   = seq.const_clock low
    %high  = seq.const_clock high

    arc.sim.instantiate @DivHarness as %m {
      arc.sim.set_input %m, "b" = %c3 : i128, !arc.sim.instance<@DivHarness>
      arc.sim.set_input %m, "a" = %a  : i128, !arc.sim.instance<@DivHarness>
      arc.sim.set_input %m, "rst" = %false : i1, !arc.sim.instance<@DivHarness>
      arc.sim.set_input %m, "clk" = %low : !seq.clock, !arc.sim.instance<@DivHarness>
      arc.sim.step %m : !arc.sim.instance<@DivHarness>
      arc.sim.set_input %m, "clk" = %high : !seq.clock, !arc.sim.instance<@DivHarness>
      arc.sim.step %m : !arc.sim.instance<@DivHarness>

      %qu = arc.sim.get_port %m, "qu" : i128, !arc.sim.instance<@DivHarness>
      %ru = arc.sim.get_port %m, "ru" : i128, !arc.sim.instance<@DivHarness>
      %qs = arc.sim.get_port %m, "qs" : i128, !arc.sim.instance<@DivHarness>
      %rs = arc.sim.get_port %m, "rs" : i128, !arc.sim.instance<@DivHarness>

      %qu_lo = comb.extract %qu from 0  : (i128) -> i64
      %qu_hi = comb.extract %qu from 64 : (i128) -> i64
      arc.sim.emit "udiv_lo", %qu_lo : i64
      arc.sim.emit "udiv_hi", %qu_hi : i64

      %qs_lo = comb.extract %qs from 0  : (i128) -> i64
      %qs_hi = comb.extract %qs from 64 : (i128) -> i64
      arc.sim.emit "sdiv_lo", %qs_lo : i64
      arc.sim.emit "sdiv_hi", %qs_hi : i64

      %ru_lo = comb.extract %ru from 0  : (i128) -> i64
      arc.sim.emit "umod_lo", %ru_lo : i64
      %rs_lo = comb.extract %rs from 0  : (i128) -> i64
      arc.sim.emit "smod_lo", %rs_lo : i64

      %c0 = hw.constant 0 : i128
      %udiv_ok = comb.icmp eq %qu, %exp : i128
      %sdiv_ok = comb.icmp eq %qs, %exp : i128
      %umod_ok = comb.icmp eq %ru, %c0  : i128
      %smod_ok = comb.icmp eq %rs, %c0  : i128
      arc.sim.emit "{\22type\22: \22assert\22, \22op\22: \22udiv\22}", %udiv_ok : i1
      arc.sim.emit "{\22type\22: \22assert\22, \22op\22: \22sdiv\22}", %sdiv_ok : i1
      arc.sim.emit "{\22type\22: \22assert\22, \22op\22: \22umod\22}", %umod_ok : i1
      arc.sim.emit "{\22type\22: \22assert\22, \22op\22: \22smod\22}", %smod_ok : i1
    }
    return
  }
}

// CHECK: udiv_lo = 0000000000000000
// CHECK: udiv_hi = 0000000000000001
// CHECK: sdiv_lo = 0000000000000000
// CHECK: sdiv_hi = 0000000000000001
// CHECK: umod_lo = 0000000000000000
// CHECK: smod_lo = 0000000000000000
// CHECK: {"type": "assert", "op": "udiv"} = 1
// CHECK: {"type": "assert", "op": "sdiv"} = 1
// CHECK: {"type": "assert", "op": "umod"} = 1
// CHECK: {"type": "assert", "op": "smod"} = 1
