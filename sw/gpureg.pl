#!/usr/bin/perl -w
use lib "/usr/local/netfpga/lib/Perl5";
use strict;

# =========================================================
#  REGISTER MAP (matches ids.xml after update)
#
#  Software registers (host writes):
#   0x2000300  GPU_CMD_REG         bit[0]=reset, bit[1]=prog_en,
#                                   bit[2]=dmem_sel, bit[3]=prog_we
#   0x2000304  HOST_THREAD_ID_REG
#   0x2000308  PROG_ADDR_REG       byte address for IMEM/DMEM access
#   0x200030c  PROG_WDATA_LO_REG   lower 32 bits of write data
#   0x2000310  PROG_WDATA_HI_REG   upper 32 bits of write data (DMEM only)
#
#  Hardware registers (GPU writes):
#   0x2000314  GPU_RESULT_LOW_REG  bits [31:0]  of 64-bit result
#   0x2000318  GPU_RESULT_HIGH_REG bits [63:32] of 64-bit result
#   0x200031c  GPU_PC_REG          bit[31]=gpu_done, bit[7:0]=current PC
#
#  CMD values used in gpu_test.sh:
#   0x0  GPU running
#   0x2  IMEM prog idle    (prog_en=1, dmem_sel=0, prog_we=0)
#   0xA  IMEM write pulse  (prog_en=1, dmem_sel=0, prog_we=1)
#   0x6  DMEM prog idle    (prog_en=1, dmem_sel=1, prog_we=0)
#   0xE  DMEM write pulse  (prog_en=1, dmem_sel=1, prog_we=1)
# =========================================================

my $GPU_CMD_REG          = 0x2000300;
my $HOST_THREAD_ID_REG   = 0x2000304;
my $PROG_ADDR_REG        = 0x2000308;
my $PROG_WDATA_LO_REG    = 0x200030c;
my $PROG_WDATA_HI_REG    = 0x2000310;
my $GPU_RESULT_LOW_REG   = 0x2000314;
my $GPU_RESULT_HIGH_REG  = 0x2000318;
my $GPU_PC_REG           = 0x200031c;

# ── Helpers ──────────────────────────────────────────────────────────────

sub regwrite {
    my ($addr, $value) = @_;
    system(sprintf("regwrite 0x%x 0x%08x", $addr, $value));
}

sub regread {
    my ($addr) = @_;
    my $cmd = sprintf("regread 0x%x", $addr);
    my @out = `$cmd`;
    my $result = $out[0];
    if (defined $result &&
        $result =~ m/Reg (0x[0-9a-f]+) \((\d+)\):\s+(0x[0-9a-f]+) \((\d+)\)/i) {
        $result = $3;
    }
    chomp $result if defined $result;
    return $result;
}

sub usage {
    print "Usage: ./gpureg.pl <cmd> [options]\n\n";
    print "Commands:\n";
    print "  write <addr> <val>    Write a value to any register address\n";
    print "  read  <addr>          Read a value from any register address\n";
    print "  reset <0|1>           Set GPU reset (1=hold, 0=run)\n";
    print "  thread <id>           Set host thread ID\n";
    print "  result                Read the 64-bit GPU result\n";
    print "  pc                    Read current PC and done flag\n";
    print "  status                Dump all GPU registers\n";
}

# ── Main ─────────────────────────────────────────────────────────────────

my $numargs = $#ARGV + 1;
if ($numargs < 1) { usage(); exit(1); }

my $cmd = $ARGV[0];

if ($cmd eq "write") {
    die "Error: write requires address and value\n" if $numargs < 3;
    regwrite($ARGV[1], $ARGV[2]);

} elsif ($cmd eq "read") {
    die "Error: read requires address\n" if $numargs < 2;
    print regread($ARGV[1]), "\n";

} elsif ($cmd eq "reset") {
    die "Error: reset requires 0 or 1\n" if $numargs < 2;
    # Preserve prog_en/dmem_sel/prog_we bits — only toggle bit[0]
    my $cur = hex(regread($GPU_CMD_REG));
    my $new = ($ARGV[1]) ? ($cur | 0x1) : ($cur & ~0x1);
    regwrite($GPU_CMD_REG, $new);
    print "GPU Reset set to: $ARGV[1]\n";

} elsif ($cmd eq "thread") {
    die "Error: thread requires an ID\n" if $numargs < 2;
    my $val = ($ARGV[1] =~ /^0x/i) ? hex($ARGV[1]) : int($ARGV[1]);
    regwrite($HOST_THREAD_ID_REG, $val);
    print "GPU Host Thread ID set to: $val\n";

} elsif ($cmd eq "result") {
    my $hi = hex(regread($GPU_RESULT_HIGH_REG));
    my $lo = hex(regread($GPU_RESULT_LOW_REG));
    printf("GPU Result: 0x%08x%08x\n", $hi, $lo);

} elsif ($cmd eq "pc") {
    my $raw     = hex(regread($GPU_PC_REG));
    my $done    = ($raw >> 31) & 1;
    my $pc_val  = $raw & 0xFF;
    printf("GPU PC = 0x%02x  gpu_done = %d\n", $pc_val, $done);

} elsif ($cmd eq "status") {
    print "── GPU Status ──────────────────────\n";
    printf("  CMD reg      : %s\n", regread($GPU_CMD_REG));
    printf("  Thread ID    : %s\n", regread($HOST_THREAD_ID_REG));
    printf("  Prog Addr    : %s\n", regread($PROG_ADDR_REG));
    my $raw  = hex(regread($GPU_PC_REG));
    my $done = ($raw >> 31) & 1;
    printf("  PC           : 0x%02x  (gpu_done=%d)\n", $raw & 0xFF, $done);
    my $hi = hex(regread($GPU_RESULT_HIGH_REG));
    my $lo = hex(regread($GPU_RESULT_LOW_REG));
    printf("  GPU Result   : 0x%08x%08x\n", $hi, $lo);

} else {
    print "Unrecognized command '$cmd'\n";
    usage();
    exit(1);
}