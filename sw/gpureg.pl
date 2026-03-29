#!/usr/bin/perl -w
use lib "/usr/local/netfpga/lib/Perl5";
use strict;

# --- Register Definitions ---
my $GPU_GPU_CMD_REG         = 0x2000300;
my $GPU_HOST_THREAD_ID_REG  = 0x2000304;
my $GPU_GPU_RESULT_LOW_REG  = 0x2000308;
my $GPU_GPU_RESULT_HIGH_REG = 0x200030c;

# --- Helper Functions ---

sub regwrite {
   my( $addr, $value ) = @_;
   my $cmd = sprintf( "regwrite 0x%x 0x%08x", $addr, $value );
   my $result = `$cmd`;
}

sub regread {
   my( $addr ) = @_;
   my $cmd = sprintf( "regread 0x%x", $addr );
   my @out = `$cmd`;
   my $result = $out[0];
   if ( defined $result && $result =~ m/Reg (0x[0-9a-f]+) \((\d+)\):\s+(0x[0-9a-f]+) \((\d+)\)/i ) {
      $result = $3;
   }
   return $result;
}

sub usage {
   print "Usage: ./gpureg.pl <cmd> <options>\n";
   print "  Commands:\n";
   print "    reset <0|1>   : Set GPU Reset (1=Reset, 0=Run)\n";
   print "    thread <id>   : Set Host Thread ID (e.g., 0, 1, 2...)\n";
   print "    result        : Read the 64-bit GPU result\n";
   print "    status        : Read all GPU registers\n";
}

# --- Main Script Logic ---

my $numargs = $#ARGV + 1;
if( $numargs < 1 ) {
   usage();
   exit(1);
}

my $cmd = $ARGV[0];

if ($cmd eq "reset") {
   if ($numargs < 2) {
      print "Error: Reset requires a value (0 or 1)\n";
      usage();
      exit(1);
   }
   my $val = $ARGV[1];
   regwrite($GPU_GPU_CMD_REG, $val);
   print "GPU Reset set to: $val\n";

} elsif ($cmd eq "thread") {
   if ($numargs < 2) {
      print "Error: Thread requires an ID\n";
      usage();
      exit(1);
   }
   my $val = $ARGV[1];
   # Support both decimal and hex inputs
   my $int_val = ($val =~ /^0x/i) ? hex($val) : int($val);
   regwrite($GPU_HOST_THREAD_ID_REG, $int_val);
   print "GPU Host Thread ID set to: $int_val\n";

} elsif ($cmd eq "result") {
   my $hi = regread($GPU_GPU_RESULT_HIGH_REG);
   my $lo = regread($GPU_GPU_RESULT_LOW_REG);
   
   my $hi_val = hex($hi);
   my $lo_val = hex($lo);
   
   # Stitch the two 32-bit registers into one 64-bit hex output
   printf("GPU Result: 0x%08x%08x\n", $hi_val, $lo_val);

} elsif ($cmd eq "status") {
   print "--- GPU Status ---\n";
   print "Reset State : ", regread($GPU_GPU_CMD_REG), "\n";
   print "Thread ID   : ", regread($GPU_HOST_THREAD_ID_REG), "\n";
   
   my $hi = regread($GPU_GPU_RESULT_HIGH_REG);
   my $lo = regread($GPU_GPU_RESULT_LOW_REG);
   printf("GPU Result  : 0x%08x%08x\n", hex($hi), hex($lo));

} else {
   print "Unrecognized command '$cmd'\n";
   usage();
   exit(1);
}
